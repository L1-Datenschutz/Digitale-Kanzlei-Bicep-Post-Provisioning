<#
.SYNOPSIS
    Installs and registers the AVD Agent on a Session Host.
    Includes robust error handling and service reset logic to avoid race conditions.
#>

param(
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

# Set error preference to Stop to catch all errors immediately
$ErrorActionPreference = "Stop"

# DEBUG OUTPUT
if ($RegistrationToken -and $RegistrationToken.Length -ge 20) {
    Write-Host "DEBUG: Token Length: $($RegistrationToken.Length)"
    Write-Host "DEBUG: Token Start:  $($RegistrationToken.Substring(0, 10))..."
    Write-Host "DEBUG: Token End:    ...$($RegistrationToken.Substring($RegistrationToken.Length - 10))"
}
else {
    Write-Host "DEBUG: CRITICAL - Token is NULL or too short! Value: '$RegistrationToken'"
}

try {
    Write-Host "Starting AVD Session Host Configuration..." -ForegroundColor Cyan

    # -------------------------------------------------------------------------
    # 1. CHECK & INSTALL
    # -------------------------------------------------------------------------
    $agentService = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
    
    if ($agentService) {
        Write-Host "⚠️ AVD Agent service found (Marketplace Image detected)." -ForegroundColor Yellow
        Write-Host "Skipping download and installation." -ForegroundColor Yellow
    }
    else {
        Write-Host "AVD Agent not found. Starting fresh installation..." -ForegroundColor Cyan
        if (!(Test-Path "C:\AzureData")) { New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null }

        $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
        $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"

        (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
        (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

        # Install Agent (injecting token directly)
        Write-Host "Installing AVD Agent..."
        $agentArgs = "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart REGISTRATION_TOKEN=`"$RegistrationToken`""
        $p1 = Start-Process msiexec.exe -ArgumentList $agentArgs -Wait -PassThru
        if ($p1.ExitCode -ne 0 -and $p1.ExitCode -ne 3010) { throw "Agent install failed: $($p1.ExitCode)" }

        # Install Bootloader
        Write-Host "Installing Bootloader..."
        $p2 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait -PassThru
        if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { throw "Bootloader install failed: $($p2.ExitCode)" }
    }

    # -------------------------------------------------------------------------
    # 3. HARD RESET (ATOMIC MODE)
    #    Wir verhindern, dass Windows den Dienst automatisch neu startet
    # -------------------------------------------------------------------------
    Write-Host "Preparing for Atomic Service Reset..." -ForegroundColor Cyan
    
    # A. DISABLE SERVICES (Prevent Auto-Restart by Windows SCM)
    Write-Host "Disabling services temporarily..."
    Set-Service -Name "RDAgentBootLoader" -StartupType Disabled -ErrorAction SilentlyContinue
    Set-Service -Name "RDAgent" -StartupType Disabled -ErrorAction SilentlyContinue
    
    # B. KILL PROCESSES
    Write-Host "Force-Killing processes..."
    $processes = Get-Process -Name "RDAgentBootLoader", "RDAgent" -ErrorAction SilentlyContinue
    if ($processes) { $processes | Stop-Process -Force -ErrorAction SilentlyContinue }
    
    Start-Sleep -Seconds 5

    # C. INJECT TOKEN
    Write-Host "Injecting Token..."
    $registryPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    if (!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }

    New-ItemProperty -Path $registryPath -Name "RegistrationToken" -Value $RegistrationToken -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name "IsRegistered" -Value 0 -PropertyType DWord -Force | Out-Null

    # D. RE-ENABLE & START SERVICES
    Write-Host "Re-Enabling and Starting services..." -ForegroundColor Yellow
    
    # Set back to Automatic
    Set-Service -Name "RDAgentBootLoader" -StartupType Automatic
    Set-Service -Name "RDAgent" -StartupType Automatic

    # Start BootLoader
    Start-Service -Name "RDAgentBootLoader"
    
    Write-Host "Waiting 15 seconds for BootLoader initialization..."
    Start-Sleep -Seconds 15

    # Check and Nudge
    if ((Get-Service "RDAgentBootLoader").Status -ne 'Running') {
        Write-Host "⚠️ BootLoader not running. Retrying start..." -ForegroundColor Red
        Start-Service -Name "RDAgentBootLoader"
    }
    
    if ((Get-Service "RDAgent").Status -ne 'Running') {
        Write-Host "Starting RDAgent manually..."
        Start-Service -Name "RDAgent"
    }

    # Allow negotiation time
    Write-Host "Waiting 30 seconds for Broker negotiation..."
    Start-Sleep -Seconds 30

    # -------------------------------------------------------------------------
    # 4. VERIFICATION LOOP
    # -------------------------------------------------------------------------
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
             Write-Host "No registration yet (IsRegistered=0). Attempt: $($retryCount + 1)/$maxRetries"
        }
        catch {}
        Start-Sleep -Seconds 10
        $retryCount++
    }

    if ($isRegistered -eq 1) {
        Write-Host "✅ SUCCESS: Session Host is registered and ready." -ForegroundColor Green
    }
    else {
        $blStatus = (Get-Service "RDAgentBootLoader").Status
        $agStatus = (Get-Service "RDAgent").Status
        Write-Host "Debug Info: BootLoader is $blStatus, Agent is $agStatus."
        
        # Soft-Fail damit wir das Log sehen können, aber markieren als Fehler
        Write-Error "❌ TIMEOUT: Agent did not register within time limit."
        exit 0
    }
}
catch {
    Write-Error "❌ CRITICAL ERROR: $($_.Exception.Message)"
    exit 1
}

exit 0
