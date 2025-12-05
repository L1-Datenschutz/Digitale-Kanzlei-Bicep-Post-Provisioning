<#
.SYNOPSIS
    Installs and registers the AVD Agent.
    HYBRID STRATEGY:
    1. Try fresh install via MSI.
    2. Check if registration happened.
    3. If not registered after 60s, FORCE inject token and restart service (Self-Healing).
#>

param(
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

$ErrorActionPreference = "Stop"

# DEBUG OUTPUT
if ($RegistrationToken -and $RegistrationToken.Length -ge 20) {
    Write-Host "DEBUG: Token Length: $($RegistrationToken.Length)"
    Write-Host "DEBUG: Token Start:  $($RegistrationToken.Substring(0, 10))..."
} else {
    Write-Host "DEBUG: CRITICAL - Token is NULL or too short!"
}

try {
    Write-Host "Starting AVD Session Host Configuration..." -ForegroundColor Cyan
    $registryPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    $needsHardReset = $false

    # -------------------------------------------------------------------------
    # 1. INSTALLATION PHASE
    # -------------------------------------------------------------------------
    $agentService = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
    
    if ($agentService) {
        Write-Host "⚠️ AVD Agent service found. Flagging for Token Injection." -ForegroundColor Yellow
        $needsHardReset = $true
    }
    else {
        Write-Host "AVD Agent not found. Starting fresh installation..." -ForegroundColor Cyan
        if (!(Test-Path "C:\AzureData")) { New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null }

        $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
        $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"

        (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
        (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

        # Try installing WITH Token first
        Write-Host "Installing AVD Agent (attempting MSI token injection)..."
        $agentArgs = "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart REGISTRATION_TOKEN=`"$RegistrationToken`""
        $p1 = Start-Process msiexec.exe -ArgumentList $agentArgs -Wait -PassThru
        if ($p1.ExitCode -ne 0 -and $p1.ExitCode -ne 3010) { throw "Agent install failed: $($p1.ExitCode)" }

        Write-Host "Installing Bootloader..."
        $p2 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait -PassThru
        if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { throw "Bootloader install failed: $($p2.ExitCode)" }
        
        Write-Host "Fresh installation complete. Checking if Agent picks up the token..."
        
        # Give the service 60 seconds to register on its own
        $earlyCheck = 0
        while ($earlyCheck -lt 6) {
            Start-Sleep -Seconds 10
            $val = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
            if ($val.IsRegistered -eq 1) {
                Write-Host "✅ Immediate Success! Agent registered via MSI parameters." -ForegroundColor Green
                exit 0 # We are done!
            }
            $earlyCheck++
        }
        
        Write-Host "⚠️ Agent running but NOT registered. MSI Token injection likely failed." -ForegroundColor Yellow
        Write-Host "Initiating Self-Healing (Hard Reset)..." -ForegroundColor Yellow
        $needsHardReset = $true
    }

    # -------------------------------------------------------------------------
    # 2. SELF-HEALING / HARD RESET
    #    Runs if:
    #    a) Agent was already there (Marketplace)
    #    b) Fresh install failed to register within 60s
    # -------------------------------------------------------------------------
    if ($needsHardReset) {
        # A. DISABLE & KILL (To prevent auto-restart interference)
        Set-Service -Name "RDAgentBootLoader" -StartupType Disabled -ErrorAction SilentlyContinue
        Set-Service -Name "RDAgent" -StartupType Disabled -ErrorAction SilentlyContinue
        
        $processes = Get-Process -Name "RDAgentBootLoader", "RDAgent" -ErrorAction SilentlyContinue
        if ($processes) { $processes | Stop-Process -Force -ErrorAction SilentlyContinue }
        
        Start-Sleep -Seconds 5

        # B. FORCE INJECT TOKEN
        if (!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }
        
        # Always overwrite the token to be sure
        New-ItemProperty -Path $registryPath -Name "RegistrationToken" -Value $RegistrationToken -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name "IsRegistered" -Value 0 -PropertyType DWord -Force | Out-Null

        # C. RE-ENABLE & START
        Set-Service -Name "RDAgentBootLoader" -StartupType Automatic
        Set-Service -Name "RDAgent" -StartupType Automatic
        
        Start-Service -Name "RDAgentBootLoader"
        
        Write-Host "Waiting 15 seconds for BootLoader restart..."
        Start-Sleep -Seconds 15

        # Nudge Agent if needed
        if ((Get-Service "RDAgent").Status -ne 'Running') {
            Start-Service -Name "RDAgent" -ErrorAction SilentlyContinue
        }
    }

    # -------------------------------------------------------------------------
    # 3. FINAL VERIFICATION
    # -------------------------------------------------------------------------
    Write-Host "Waiting 30 seconds for Broker negotiation..."
    Start-Sleep -Seconds 30

    Write-Host "Verifying registration status..." -ForegroundColor Cyan
    $maxRetries = 20
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        try {
            $val = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
            if ($val -and $val.IsRegistered -eq 1) {
                Write-Host "✅ SUCCESS: Session Host is registered." -ForegroundColor Green
                exit 0
            }
             Write-Host "No registration yet. Attempt: $($retryCount + 1)/$maxRetries"
        }
        catch {}
        Start-Sleep -Seconds 10
        $retryCount++
    }

    # FAIL STATE LOGGING
    $bl = Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue
    $ag = Get-Service "RDAgent" -ErrorAction SilentlyContinue
    
    Write-Host "Debug Info: BootLoader=$($bl.Status), Agent=$($ag.Status)"
    
    # Check if Token is actually in registry
    $regCheck = Get-ItemProperty -Path $registryPath -Name "RegistrationToken" -ErrorAction SilentlyContinue
    if ($regCheck.RegistrationToken) {
        Write-Host "Debug Info: Token IS present in registry (First 5 chars: $($regCheck.RegistrationToken.Substring(0,5))...)"
    } else {
        Write-Host "Debug Info: Token is MISSING from registry!"
    }

    Write-Error "❌ TIMEOUT: Agent did not register."
    exit 1
}
catch {
    Write-Error "❌ CRITICAL ERROR: $($_.Exception.Message)"
    exit 1
}
