param(
    [Parameter(Mandatory = $true)]
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

try {
    Write-Host "Starting AVD Agent Configuration..." -ForegroundColor Cyan

    # -------------------------------------------------------------------------
    # CHECK: Is the Agent already installed? (Avoid Zombie/SxS Issues)
    # -------------------------------------------------------------------------
    $agentService = Get-Service -Name "RDAgentBootLoader" -ErrorAction SilentlyContinue
    
    if ($agentService) {
        Write-Host "⚠️ AVD Agent is already installed (Marketplace Image detected)." -ForegroundColor Yellow
        Write-Host "Skipping Download and Installation to prevent version conflicts." -ForegroundColor Yellow
        # Wir springen direkt zur Token-Injektion
    }
    else {
        # ---------------------------------------------------------------------
        # INSTALLATION (Only if missing)
        # ---------------------------------------------------------------------
        Write-Host "AVD Agent not found. Starting fresh installation..." -ForegroundColor Cyan

        # 1. Create directory
        if (!(Test-Path "C:\AzureData")) {
            New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null
        }

        # 2. Download
        $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
        $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"

        Write-Host "Downloading binaries..."
        (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
        (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

        # 3. Install Agent
        Write-Host "Installing AVD Agent..."
        $p1 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart" -Wait -PassThru
        if ($p1.ExitCode -ne 0 -and $p1.ExitCode -ne 3010) { throw "Agent install failed: $($p1.ExitCode)" }

        # 4. Install Bootloader
        Write-Host "Installing Bootloader..."
        $p2 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait -PassThru
        if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { throw "Bootloader install failed: $($p2.ExitCode)" }

        Write-Host "Installation complete. Waiting for system to settle..."
        Start-Sleep -Seconds 10
    }

    # -------------------------------------------------------------------------
    # TOKEN INJECTION (Always required, even for pre-installed agents)
    # -------------------------------------------------------------------------
    Write-Host "Injecting Registration Token into Registry..."
    $registryPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    
    if (!(Test-Path $registryPath)) { 
        New-Item -Path $registryPath -Force | Out-Null
    }

    # Write Token & Reset State
    New-ItemProperty -Path $registryPath -Name "RegistrationToken" -Value $RegistrationToken -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name "IsRegistered" -Value 0 -PropertyType DWord -Force | Out-Null

    # -------------------------------------------------------------------------
    # RESTART SERVICES (Critical for pre-installed agents too!)
    # -------------------------------------------------------------------------
    Write-Host "Restarting AVD Agent services to pick up the token..." -ForegroundColor Yellow
    
    # Restart forces the pre-installed agent to read the new registry key
    Restart-Service -Name "RDAgentBootLoader" -Force -ErrorAction SilentlyContinue
    Restart-Service -Name "RDAgent" -Force -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 15

    # -------------------------------------------------------------------------
    # VERIFICATION
    # -------------------------------------------------------------------------
    Write-Host "Waiting for registration to complete..."
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
        }
        catch { }

        Write-Host "Checking registration status... ($($retryCount + 1)/$maxRetries)"
        Start-Sleep -Seconds 10
        $retryCount++
    }

    if ($isRegistered -eq 1) {
        Write-Host "✅ SUCCESS: Session Host successfully registered." -ForegroundColor Green
    }
    else {
        # Detailliertere Fehlermeldung
        Write-Error "❌ TIMEOUT: Agent did not register. If this is a pre-installed agent, the version might be incompatible with the token or the environment."
        throw "Timeout waiting for registration."
    }

}
catch {
    Write-Error "CRITICAL ERROR: $($_.Exception.Message)"
    exit 1
}
