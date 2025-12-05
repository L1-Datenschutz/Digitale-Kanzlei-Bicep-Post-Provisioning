<#
.SYNOPSIS
    Installs and registers the AVD Agent.
    DIFFERENTIATED LOGIC:
    - Fresh Install: Installs with Token, does NOT restart services (prevents corruption).
    - Existing Agent: Performs Atomic Reset to inject new token.
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

    # -------------------------------------------------------------------------
    # 1. CHECK: Fresh Install vs. Marketplace Image
    # -------------------------------------------------------------------------
    $agentService = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
    $isFreshInstall = $false

    if ($agentService) {
        # --- SCENARIO: EXISTING AGENT (Marketplace) ---
        Write-Host "⚠️ AVD Agent service found. Using 'Injection Mode'." -ForegroundColor Yellow
        $isFreshInstall = $false
    }
    else {
        # --- SCENARIO: FRESH INSTALL ---
        Write-Host "AVD Agent not found. Using 'Fresh Install Mode'." -ForegroundColor Cyan
        $isFreshInstall = $true

        if (!(Test-Path "C:\AzureData")) { New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null }

        $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
        $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"

        (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
        (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

        # Install Agent WITH TOKEN.
        # CRITICAL: We rely on the MSI to start the service correctly. We do NOT restart it.
        Write-Host "Installing AVD Agent (with Token)..."
        $agentArgs = "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart REGISTRATION_TOKEN=`"$RegistrationToken`""
        $p1 = Start-Process msiexec.exe -ArgumentList $agentArgs -Wait -PassThru
        if ($p1.ExitCode -ne 0 -and $p1.ExitCode -ne 3010) { throw "Agent install failed: $($p1.ExitCode)" }

        Write-Host "Installing Bootloader..."
        $p2 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait -PassThru
        if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { throw "Bootloader install failed: $($p2.ExitCode)" }
        
        Write-Host "Fresh installation complete. Waiting for auto-start..."
        Start-Sleep -Seconds 10
    }

    # -------------------------------------------------------------------------
    # 2. HARD RESET (ONLY FOR EXISTING AGENTS)
    #    We skip this for fresh installs to avoid killing the initializing service.
    # -------------------------------------------------------------------------
    if (-not $isFreshInstall) {
        Write-Host "Performing Atomic Reset on existing Agent..." -ForegroundColor Cyan
        
        # A. DISABLE & KILL
        Set-Service -Name "RDAgentBootLoader" -StartupType Disabled -ErrorAction SilentlyContinue
        Set-Service -Name "RDAgent" -StartupType Disabled -ErrorAction SilentlyContinue
        
        $processes = Get-Process -Name "RDAgentBootLoader", "RDAgent" -ErrorAction SilentlyContinue
        if ($processes) { $processes | Stop-Process -Force -ErrorAction SilentlyContinue }
        
        Start-Sleep -Seconds 5

        # B. INJECT TOKEN
        if (!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }
        New-ItemProperty -Path $registryPath -Name "RegistrationToken" -Value $RegistrationToken -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name "IsRegistered" -Value 0 -PropertyType DWord -Force | Out-Null

        # C. RE-ENABLE & START
        Set-Service -Name "RDAgentBootLoader" -StartupType Automatic
        Set-Service -Name "RDAgent" -StartupType Automatic
        Start-Service -Name "RDAgentBootLoader"
        
        Write-Host "Restarted existing services."
    }

    # -------------------------------------------------------------------------
    # 3. VERIFICATION LOOP (For BOTH Scenarios)
    # -------------------------------------------------------------------------
    Write-Host "Waiting 30 seconds for Broker negotiation..."
    Start-Sleep -Seconds 30

    Write-Host "Verifying registration status..." -ForegroundColor Cyan
    $maxRetries = 20
    $retryCount = 0
    $isRegistered = 0

    while ($retryCount -lt $maxRetries) {
        try {
            $val = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
            if ($val -and $val.IsRegistered -eq 1) {
                $isRegistered = 1
                break
            }
             Write-Host "No registration yet. Attempt: $($retryCount + 1)/$maxRetries"
        }
        catch {}
        Start-Sleep -Seconds 10
        $retryCount++
    }

    if ($isRegistered -eq 1) {
        Write-Host "✅ SUCCESS: Session Host is registered." -ForegroundColor Green
    }
    else {
        # DEBUGGING INFO
        $bl = Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue
        $ag = Get-Service "RDAgent" -ErrorAction SilentlyContinue
        Write-Host "Debug Info: BootLoader=$($bl.Status), Agent=$($ag.Status)"
        
        # Emergency Jumpstart (Last Resort)
        if ($bl.Status -ne 'Running') {
             Write-Host "⚠️ Service not running. Attempting emergency start..."
             Start-Service "RDAgentBootLoader"
             Start-Sleep -Seconds 15
        }

        # Check again
        $valFinal = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
        if ($valFinal.IsRegistered -eq 1) {
            Write-Host "✅ RECOVERY SUCCESS." -ForegroundColor Green
        } else {
            Write-Error "❌ TIMEOUT: Agent did not register."
            exit 1
        }
    }
}
catch {
    Write-Error "❌ CRITICAL ERROR: $($_.Exception.Message)"
    exit 1
}

exit 0
