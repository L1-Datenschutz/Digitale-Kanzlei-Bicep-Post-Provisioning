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
    
    # Create data directory
    New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null

    # --- 1. Install AVD Agent ---
    Write-Host "Downloading AVD Agent..."
    $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    $AgentMsi = "C:\AzureData\AVDAgent.msi"
    Invoke-WebRequest -Uri $AgentUrl -OutFile $AgentMsi

    Write-Host "Installing AVD Agent..."
    # Critical: We pass the token here for a fresh install
    $procAgent = Start-Process msiexec.exe -ArgumentList "/i `"$AgentMsi`" /quiet /norestart REGISTRATIONTOKEN=$Token" -Wait -PassThru
    
    # Exit Code 0 = Success, 3010 = Success (Reboot Required)
    if ($procAgent.ExitCode -ne 0 -and $procAgent.ExitCode -ne 3010) { 
        throw "AVD Agent install failed with exit code: $($procAgent.ExitCode)" 
    }

    # --- 2. Install AVD Bootloader ---
    Write-Host "Downloading AVD Bootloader..."
    $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    $BootMsi = "C:\AzureData\AVDBootloader.msi"
    Invoke-WebRequest -Uri $BootUrl -OutFile $BootMsi

    Write-Host "Installing AVD Bootloader..."
    $procBoot = Start-Process msiexec.exe -ArgumentList "/i `"$BootMsi`" /quiet /norestart" -Wait -PassThru
    
    if ($procBoot.ExitCode -ne 0 -and $procBoot.ExitCode -ne 3010) { 
        throw "AVD Bootloader install failed with exit code: $($procBoot.ExitCode)" 
    }
}

function Register-ExistingAgent {
    param($Token)
    Write-Host "AVD Agent found (Pre-installed). Injecting Registration Token..." -ForegroundColor Cyan

    $regPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

    # Inject Token
    New-ItemProperty -Path $regPath -Name "RegistrationToken" -Value $Token -PropertyType String -Force | Out-Null
    
    # Restart Service
    Write-Host "Restarting RDAgentBootLoader to trigger registration..."
    Restart-Service "RDAgentBootLoader" -Force
}

try {
    Write-Host "--- Starting AVD Host Setup ---"

    # Check for Service
    $bootLoaderService = Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue

    if ($bootLoaderService) {
        Register-ExistingAgent -Token $RegistrationToken
    }
    else {
        Install-AvdAgent -Token $RegistrationToken
    }

    # --- Verification ---
    Write-Host "Verifying Registration Status..."
    # Wait a moment for the agent to process the token
    Start-Sleep -Seconds 20
    
    $isRegistered = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent" -Name "IsRegistered" -ErrorAction SilentlyContinue
    
    if ($isRegistered.IsRegistered -eq 1) {
        Write-Host "SUCCESS: VM is registered to the Host Pool." -ForegroundColor Green
    } else {
        Write-Warning "VM is not yet registered (IsRegistered != 1). It may take a minute to appear in the portal."
        Write-Host "Please check the Host Pool in Azure Portal manually."
    }
}
catch {
    Write-Error "Setup failed: $_"
    exit 1
}param(
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
    
    # Create data directory
    New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null

    # --- 1. Install AVD Agent ---
    Write-Host "Downloading AVD Agent..."
    $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    $AgentMsi = "C:\AzureData\AVDAgent.msi"
    Invoke-WebRequest -Uri $AgentUrl -OutFile $AgentMsi

    Write-Host "Installing AVD Agent..."
    # Critical: We pass the token here for a fresh install
    $procAgent = Start-Process msiexec.exe -ArgumentList "/i `"$AgentMsi`" /quiet /norestart REGISTRATIONTOKEN=$Token" -Wait -PassThru
    
    # Exit Code 0 = Success, 3010 = Success (Reboot Required)
    if ($procAgent.ExitCode -ne 0 -and $procAgent.ExitCode -ne 3010) { 
        throw "AVD Agent install failed with exit code: $($procAgent.ExitCode)" 
    }

    # --- 2. Install AVD Bootloader ---
    Write-Host "Downloading AVD Bootloader..."
    $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    $BootMsi = "C:\AzureData\AVDBootloader.msi"
    Invoke-WebRequest -Uri $BootUrl -OutFile $BootMsi

    Write-Host "Installing AVD Bootloader..."
    $procBoot = Start-Process msiexec.exe -ArgumentList "/i `"$BootMsi`" /quiet /norestart" -Wait -PassThru
    
    if ($procBoot.ExitCode -ne 0 -and $procBoot.ExitCode -ne 3010) { 
        throw "AVD Bootloader install failed with exit code: $($procBoot.ExitCode)" 
    }
}

function Register-ExistingAgent {
    param($Token)
    Write-Host "AVD Agent found (Pre-installed). Injecting Registration Token..." -ForegroundColor Cyan

    $regPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

    # Inject Token
    New-ItemProperty -Path $regPath -Name "RegistrationToken" -Value $Token -PropertyType String -Force | Out-Null
    
    # Restart Service
    Write-Host "Restarting RDAgentBootLoader to trigger registration..."
    Restart-Service "RDAgentBootLoader" -Force
}

try {
    Write-Host "--- Starting AVD Host Setup ---"

    # Check for Service
    $bootLoaderService = Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue

    if ($bootLoaderService) {
        Register-ExistingAgent -Token $RegistrationToken
    }
    else {
        Install-AvdAgent -Token $RegistrationToken
    }

    # --- Verification ---
    Write-Host "Verifying Registration Status..."
    # Wait a moment for the agent to process the token
    Start-Sleep -Seconds 20
    
    $isRegistered = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent" -Name "IsRegistered" -ErrorAction SilentlyContinue
    
    if ($isRegistered.IsRegistered -eq 1) {
        Write-Host "SUCCESS: VM is registered to the Host Pool." -ForegroundColor Green
    } else {
        Write-Warning "VM is not yet registered (IsRegistered != 1). It may take a minute to appear in the portal."
        Write-Host "Please check the Host Pool in Azure Portal manually."
    }
}
catch {
    Write-Error "Setup failed: $_"
    exit 1
}
