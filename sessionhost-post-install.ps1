<#
.SYNOPSIS
    Installs and registers the AVD Agent.
    Optimized for Windows 11 Multi-session images with pre-installed agent.
#>

param(
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

$ErrorActionPreference = "Stop"

# Validate Token
if ([string]::IsNullOrWhiteSpace($RegistrationToken) -or $RegistrationToken.Length -lt 20) {
    Write-Error "[CRITICAL] Registration token is NULL or invalid. Length: $($RegistrationToken.Length)"
    exit 1
}

Write-Host "[INFO] Token Length: $($RegistrationToken.Length)"
Write-Host "[INFO] Token Start: $($RegistrationToken.Substring(0, 10))..."

try {
    Write-Host "[INFO] Starting AVD Session Host Configuration..." -ForegroundColor Cyan
    $registryPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"

    # -------------------------------------------------------------------------
    # PRE-FLIGHT CHECK: Already Registered?
    # -------------------------------------------------------------------------
    Write-Host "[INFO] Checking if already registered..."
    $preCheck = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
    if ($preCheck -and $preCheck.IsRegistered -eq 1) {
        Write-Host "[SUCCESS] Session Host is already registered. Nothing to do." -ForegroundColor Green
        exit 0
    }

    # -------------------------------------------------------------------------
    # PHASE 1: Check for Pre-installed Agent (Marketplace Image)
    # -------------------------------------------------------------------------
    $agentService = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
    
    if ($agentService) {
        Write-Host "[INFO] Pre-installed AVD Agent detected (Marketplace image)." -ForegroundColor Cyan
        Write-Host "[INFO] Waiting 90 seconds for auto-registration..."
        
        # Wait for Marketplace agent to self-register
        $autoRegWait = 0
        while ($autoRegWait -lt 9) {
            Start-Sleep -Seconds 10
            $val = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
            if ($val -and $val.IsRegistered -eq 1) {
                Write-Host "[SUCCESS] Agent auto-registered successfully!" -ForegroundColor Green
                exit 0
            }
            $autoRegWait++
        }
        
        Write-Host "[WARNING] Auto-registration failed. Will inject token manually." -ForegroundColor Yellow
        
        # Token Injection for Pre-installed Agent
        Write-Host "[INFO] Stopping services for token injection..."
        Stop-Service -Name "RDAgentBootLoader" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "RDAgent" -Force -ErrorAction SilentlyContinue
        
        # Wait for services to fully stop
        $stopWait = 0
        while ($stopWait -lt 15) {
            $bl = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
            if ($bl.Status -eq 'Stopped') { break }
            Start-Sleep -Seconds 2
            $stopWait += 2
        }
        
        # Kill processes if still running
        Get-Process -Name "RDAgentBootLoader", "RDAgent" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        
        # Inject Token
        Write-Host "[INFO] Injecting registration token into registry..."
        if (!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }
        New-ItemProperty -Path $registryPath -Name "RegistrationToken" -Value $RegistrationToken -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name "IsRegistered" -Value 0 -PropertyType DWord -Force | Out-Null
        
        # Restart Services
        Write-Host "[INFO] Restarting services..."
        Start-Service -Name "RDAgentBootLoader"
        Start-Sleep -Seconds 10
        
        if ((Get-Service "RDAgent" -ErrorAction SilentlyContinue).Status -ne 'Running') {
            Start-Service -Name "RDAgent" -ErrorAction SilentlyContinue
        }
    }
    else {
        # -------------------------------------------------------------------------
        # PHASE 2: Fresh Installation (No Pre-installed Agent)
        # -------------------------------------------------------------------------
        Write-Host "[INFO] No pre-installed agent found. Starting fresh installation..." -ForegroundColor Cyan
        if (!(Test-Path "C:\AzureData")) { New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null }

        $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
        $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"

        Write-Host "[INFO] Downloading AVD Agent and Bootloader..."
        (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
        (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

        Write-Host "[INFO] Installing AVD Agent with registration token..."
        $agentArgs = "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart REGISTRATION_TOKEN=`"$RegistrationToken`""
        $p1 = Start-Process msiexec.exe -ArgumentList $agentArgs -Wait -PassThru
        if ($p1.ExitCode -ne 0 -and $p1.ExitCode -ne 3010) { 
            throw "Agent installation failed with exit code: $($p1.ExitCode)" 
        }

        Write-Host "[INFO] Installing AVD Bootloader..."
        $p2 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait -PassThru
        if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { 
            throw "Bootloader installation failed with exit code: $($p2.ExitCode)" 
        }
        
        Write-Host "[INFO] Installation complete. Services should start automatically..."
        Start-Sleep -Seconds 15
    }

    # -------------------------------------------------------------------------
    # PHASE 3: SERVICE HEALTH CHECK & INITIALIZATION SOAK
    # -------------------------------------------------------------------------
    Write-Host "[INFO] Allowing services to fully initialize (60 seconds)..." -ForegroundColor Cyan
    Start-Sleep -Seconds 60
    
    Write-Host "[INFO] Checking service health before verification..." -ForegroundColor Cyan
    $serviceCheckRetries = 0
    $maxServiceRetries = 60  # 60 retries * 10 seconds = 10 minutes
    
    while ($serviceCheckRetries -lt $maxServiceRetries) {
        $blService = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
        $agService = Get-Service -Name "RDAgent" -ErrorAction SilentlyContinue
        
        if ($blService -and $blService.Status -eq 'Running' -and $agService -and $agService.Status -eq 'Running') {
            Write-Host "[INFO] Both services are running. Ready for broker negotiation." -ForegroundColor Green
            break
        }
        
        $blStatus = if ($blService) { $blService.Status } else { 'N/A' }
        $agStatus = if ($agService) { $agService.Status } else { 'N/A' }
        Write-Host "[INFO] Waiting for services to be ready... Attempt $($serviceCheckRetries + 1)/$maxServiceRetries (BL: $blStatus, Agent: $agStatus)"
        Start-Sleep -Seconds 10
        $serviceCheckRetries++
    }
    
    if ($serviceCheckRetries -eq $maxServiceRetries) {
        Write-Host "[WARNING] Services not fully healthy after 30 seconds, but continuing verification..." -ForegroundColor Yellow
    }

    # -------------------------------------------------------------------------
    # PHASE 4: VERIFICATION (Extended Wait - 5 Minutes Total)
    # -------------------------------------------------------------------------
    Write-Host "[INFO] Waiting for Azure Broker negotiation (this may take 2-5 minutes)..." -ForegroundColor Cyan

    Write-Host "[INFO] Verifying registration status..." -ForegroundColor Cyan
    $maxRetries = 30  # 30 retries * 10 seconds = 5 minutes
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        $val = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
        if ($val -and $val.IsRegistered -eq 1) {
            Write-Host "[SUCCESS] Session Host registered successfully!" -ForegroundColor Green
            exit 0
        }
        
        Write-Host "[INFO] Registration pending... Attempt $($retryCount + 1)/$maxRetries"
        Start-Sleep -Seconds 10
        $retryCount++
    }

    # -------------------------------------------------------------------------
    # FAILURE LOGGING WITH EVENT VIEWER DIAGNOSTICS
    # -------------------------------------------------------------------------
    Write-Host "[ERROR] Registration timeout after 5 minutes." -ForegroundColor Red
    
    $bl = Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue
    $ag = Get-Service "RDAgent" -ErrorAction SilentlyContinue
    Write-Host "[DEBUG] BootLoader Status: $($bl.Status)"
    Write-Host "[DEBUG] RDAgent Status: $($ag.Status)"
    
    $regCheck = Get-ItemProperty -Path $registryPath -Name "RegistrationToken" -ErrorAction SilentlyContinue
    if ($regCheck.RegistrationToken) {
        Write-Host "[DEBUG] Token present in registry (First 5 chars: $($regCheck.RegistrationToken.Substring(0,5))...)"
    } else {
        Write-Host "[DEBUG] Token MISSING from registry!"
    }

    Write-Error "[CRITICAL ERROR] TIMEOUT: Agent did not register."
    exit 1
}
catch {
    Write-Error "[CRITICAL ERROR] $($_.Exception.Message)"
    exit 1
}
