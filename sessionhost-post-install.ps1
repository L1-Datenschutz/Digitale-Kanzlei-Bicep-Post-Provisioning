param(
    [Parameter(Mandatory = $true)]
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

$ErrorActionPreference = "Stop"

function Install-AvdAgent {
    Write-Host "Agent not found. Proceeding with FRESH installation..." -ForegroundColor Yellow
    
    New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null
    
    # Download
    $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
    (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

    # Install - Note: We do NOT pass the token here anymore. We will inject it manually later.
    Write-Host "Installing AVD Agent..."
    $p1 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart" -Wait -PassThru
    if ($p1.ExitCode -ne 0 -and $p1.ExitCode -ne 3010) { throw "Agent install failed: $($p1.ExitCode)" }

    Write-Host "Installing Bootloader..."
    $p2 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait -PassThru
    if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { throw "Bootloader install failed: $($p2.ExitCode)" }
    
    # Give the installer a moment to settle
    Start-Sleep -Seconds 30
}

function Register-Agent {
    param($Token)
    Write-Host "Configuring AVD Agent (Injecting Token and Restarting)..." -ForegroundColor Cyan

    $regPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

    # 1. Stop Service explicitly to ensure it picks up the new token on start
    # We use SilentlyContinue because on a fresh install, it might not be running yet
    Write-Host "Stopping RDAgentBootLoader..."
    Stop-Service "RDAgentBootLoader" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 30

    # 2. Inject Token
    New-ItemProperty -Path $regPath -Name "RegistrationToken" -Value $Token -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "IsRegistered" -Value 0 -PropertyType DWord -Force | Out-Null # Reset status
    
    # 3. Start Service
    Write-Host "Starting RDAgentBootLoader..."
    Start-Service "RDAgentBootLoader"
}

try {
    Write-Host "--- Starting AVD Host Setup ---"
    Start-Sleep -Seconds 30
    
    # 1. Install if missing
    if (-not (Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue)) {
        Install-AvdAgent
    }

    # 2. ALWAYS Register (Fixes race conditions and ensures token is applied)
    Register-Agent -Token $RegistrationToken

    # --- Verification Loop ---
    Write-Host "Verifying Registration Status (Timeout: 180s)..."
    
    for ($i = 0; $i -lt 18; $i++) {
        Start-Sleep -Seconds 10
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent" -Name "IsRegistered" -ErrorAction SilentlyContinue
        
        if ($reg.IsRegistered -eq 1) {
            Write-Host "SUCCESS: VM is registered to the Host Pool." -ForegroundColor Green
            exit 0
        }
        Write-Host "Waiting for registration... ($(($i+1)*10)s)"
    }

    throw "TIMEOUT: VM failed to register after 180 seconds. Token ($($RegistrationToken.Substring(0,10))) might be invalid or service is stuck."
}
catch {
    Write-Error "Setup failed: $_"
