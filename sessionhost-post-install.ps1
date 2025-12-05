<#
.SYNOPSIS
    Installs and registers the AVD Agent on a Session Host.
    Includes robust error handling and service reset logic to avoid race conditions.

.PARAMETER RegistrationToken
    The valid registration token generated from the Host Pool.

.PARAMETER Environment
    Optional environment tag (e.g., 'dev', 'prod'). Not used for logic, just accepted to avoid errors.

.PARAMETER EnableFslogix
    Optional switch/bool. Not used for logic here, just accepted to avoid errors.

.PARAMETER FslogixSharePath
    Optional path. Not used for logic here, just accepted to avoid errors.
#>

param(
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

# Set error preference to Stop to catch all errors immediately
$ErrorActionPreference = "Stop"

try {
    Write-Host "Starting AVD Session Host Configuration..." -ForegroundColor Cyan

    # -------------------------------------------------------------------------
    # 1. CHECK: Is the Agent already installed? (Marketplace Image Check)
    # -------------------------------------------------------------------------
    $agentService = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
    
    if ($agentService) {
        Write-Host "⚠️ AVD Agent service found (Marketplace Image detected)." -ForegroundColor Yellow
        Write-Host "Skipping download and installation to prevent version conflicts." -ForegroundColor Yellow
        # Logic continues to Step 3 to inject token into the existing agent
    }
    else {
        # ---------------------------------------------------------------------
        # 2. INSTALLATION (Only if missing)
        # ---------------------------------------------------------------------
        Write-Host "AVD Agent not found. Starting fresh installation..." -ForegroundColor Cyan

        # Create directory
        if (!(Test-Path "C:\AzureData")) {
            New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null
        }

        # Define URLs (Production Links)
        $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
        $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"

        Write-Host "Downloading binaries..."
        # Using .NET WebClient for better compatibility
        (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
        (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

        # Install Agent (Silent, No Restart, WITH TOKEN INJECTION)
        Write-Host "Installing AVD Agent (injecting token directly)..."
        
        # CHANGE: Added REGISTRATION_TOKEN parameter to msiexec arguments
        $agentArgs = "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart REGISTRATION_TOKEN=`"$RegistrationToken`""
        
        $p1 = Start-Process msiexec.exe -ArgumentList $agentArgs -Wait -PassThru
        if ($p1.ExitCode -ne 0 -and $p1.ExitCode -ne 3010) { 
            throw "Agent install failed with ExitCode: $($p1.ExitCode)" 
        }

        # Install Bootloader
        Write-Host "Installing Bootloader..."
        $p2 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait -PassThru
        if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { 
            throw "Bootloader install failed with ExitCode: $($p2.ExitCode)" 
        }
    }

    # -------------------------------------------------------------------------
    # 3. HARD RESET & TOKEN INJECTION (Safety Net & Marketplace Fix)
    #    Crucial Step: Stop Services -> Write Token -> Start Services
    #    We do this ALWAYS. If installed fresh, it confirms the token. 
    #    If marketplace, it applies the token.
    # -------------------------------------------------------------------------
    Write-Host "Preparing for Service Reset & Token Verification..." -ForegroundColor Cyan
    
    # A. STOP SERVICES explicitly to release file/registry locks
    Write-Host "Stopping AVD Agent services..." -ForegroundColor Yellow
    Stop-Service -Name "RDAgentBootLoader" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "RDAgent" -Force -ErrorAction SilentlyContinue
    
    # Wait to ensure processes are terminated
    Start-Sleep -Seconds 5

    # B. INJECT TOKEN (Redundant for fresh install, required for Marketplace)
    Write-Host "Injecting/Verifying Registration Token in Registry..."
    $registryPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    
    if (!(Test-Path $registryPath)) { 
        New-Item -Path $registryPath -Force | Out-Null 
    }

    # Write Token
    New-ItemProperty -Path $registryPath -Name "RegistrationToken" -Value $RegistrationToken -PropertyType String -Force | Out-Null
    # Reset 'IsRegistered' flag to ensure a fresh registration attempt
    New-ItemProperty -Path $registryPath -Name "IsRegistered" -Value 0 -PropertyType DWord -Force | Out-Null

    # C. START SERVICES
    Write-Host "Starting AVD Agent services..." -ForegroundColor Yellow
    
    # Start BootLoader (this orchestrates the Agent)
    Start-Service -Name "RDAgentBootLoader"
    
    # Wait and check if RDAgent came up, otherwise start it too
    Start-Sleep -Seconds 10
    $rdAgent = Get-Service -Name "RDAgent" -ErrorAction SilentlyContinue
    if ($rdAgent.Status -ne 'Running') {
        Write-Host "Starting RDAgent manually..."
        Start-Service -Name "RDAgent" -ErrorAction SilentlyContinue
    }
    
    # Allow time for Broker Negotiation
    Write-Host "Waiting 30 seconds for Broker negotiation..."
    Start-Sleep -Seconds 30

    # -------------------------------------------------------------------------
    # 4. VERIFICATION LOOP
    # -------------------------------------------------------------------------
    Write-Host "Verifying registration status..." -ForegroundColor Cyan
    
    $maxRetries = 20 # 20 * 10s = approx 3.5 minutes timeout
    $retryCount = 0
    $isRegistered = 0

    while ($retryCount -lt $maxRetries) {
        try {
            # Check the registry key updated by the Agent upon success
            $val = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
            
            if ($val -and $val.IsRegistered -eq 1) {
                $isRegistered = 1
                break
            }

            Write-Host "No registration detected yet. Current Registry value: $($val.isRegistered)"
        }
        catch {
            # Ignore read errors during loop
        }

        Write-Host "Checking status... ($($retryCount + 1)/$maxRetries) - Waiting for 'IsRegistered = 1'"
        Start-Sleep -Seconds 10
        $retryCount++
    }

    if ($isRegistered -eq 1) {
        Write-Host "✅ SUCCESS: Session Host is registered and ready." -ForegroundColor Green
    }
    else {
        # Fetch Service Status for Debugging
        $blStatus = (Get-Service "RDAgentBootLoader").Status
        $agStatus = (Get-Service "RDAgent").Status

        Write-Host "Debug Info: BootLoader is $blStatus, Agent is $agStatus."
        Write-Host "❌ TIMEOUT: Agent did not register within time limit."
        Write-Host "❌ Registration Timeout. Token might be invalid or Broker unreachable."
    }
    exit 0
}
catch {
    Write-Error "❌ CRITICAL ERROR in Post-Install Script: $($_.Exception.Message)"
    exit 0
    # exit 1 - soft fail logic maintained as requested
}

exit 0 # just to be sure
