param(
    [Parameter(Mandatory = $true)]
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

$ErrorActionPreference = "Stop"

function Install-AvdAgent {
    param($Token)
    Write-Host "Agent not found. Proceeding with FRESH installation..." -ForegroundColor Yellow
    
    New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null
    
    # Download
    $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
    (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

    # Install
    Write-Host "Installing AVD Agent..."
    $p1 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart REGISTRATIONTOKEN=$Token" -Wait -PassThru
    if ($p1.ExitCode -ne 0 -and $p1.ExitCode -ne 3010) { throw "Agent install failed: $($p1.ExitCode)" }

    Write-Host "Installing Bootloader..."
    $p2 = Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait -PassThru
    if ($p2.ExitCode -ne 0 -and $p2.ExitCode -ne 3010) { throw "Bootloader install failed: $($p2.ExitCode)" }
}

function Register-ExistingAgent {
    param($Token)
    Write-Host "AVD Agent found. Injecting Token and Restarting..." -ForegroundColor Cyan

    $regPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

    # 1. Stop Service explicitly to ensure it picks up the new token on start
    Write-Host "Stopping RDAgentBootLoader..."
    Stop-Service "RDAgentBootLoader" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 60

    # 2. Inject Token
    New-ItemProperty -Path $regPath -Name "RegistrationToken" -Value $Token -PropertyType String -Force | Out-Null
    
    # 3. Start Service
    Write-Host "Starting RDAgentBootLoader..."
    Start-Service "RDAgentBootLoader"
}

try {
    Write-Host "--- Starting AVD Host Setup ---"
    
    # Initial sleep to let OS settle
    Start-Sleep -Seconds 600

    if (Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue) {
        Register-ExistingAgent -Token $RegistrationToken
    } else {
        Install-AvdAgent -Token $RegistrationToken
    }

    # --- Verification Loop ---
    Write-Host "Verifying Registration Status (Timeout: 120s)..."
    
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 10
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent" -Name "IsRegistered" -ErrorAction SilentlyContinue
        
        if ($reg.IsRegistered -eq 1) {
            Write-Host "SUCCESS: VM is registered to the Host Pool." -ForegroundColor Green
            exit 0
        }
        Write-Host "Waiting for registration... ($(($i+1)*10)s)"
    }

    # If we get here, it failed. Throw error so deployment fails.
    throw "TIMEOUT: VM failed to register after 120 seconds. Token might be invalid or service is stuck. Token value: ${$RegistrationToken.Substring(0, 10)}..."
}
catch {
    Write-Error "Setup failed: $_"
    exit 1
}
