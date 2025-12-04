param(
    [Parameter(Mandatory = $true)]
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "--- Starting AVD Agent Registration (Pre-installed) ---"

    # 1. Check for Pre-installed Agent Service
    $bootLoaderService = Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue

    if (-not $bootLoaderService) {
        throw "AVD Agent service 'RDAgentBootLoader' not found. Ensure you are using an AVD Marketplace Image."
    }

    Write-Host "AVD Agent found. Injecting Registration Token..."

    # 2. Define Registry Path
    $regPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # 3. Inject Token
    # The agent looks for this specific value to register itself
    New-ItemProperty -Path $regPath -Name "RegistrationToken" -Value $RegistrationToken -PropertyType String -Force | Out-Null
    Write-Host "Token injected successfully."

    # 4. Restart Service to trigger registration
    Write-Host "Restarting RDAgentBootLoader to trigger registration..."
    Restart-Service "RDAgentBootLoader" -Force
    
    # 5. Verification
    Start-Sleep -Seconds 15
    $isRegistered = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\RDInfraAgent" -Name "IsRegistered" -ErrorAction SilentlyContinue
    
    if ($isRegistered.IsRegistered -eq 1) {
        Write-Host "SUCCESS: VM is registered to the Host Pool." -ForegroundColor Green
    } else {
        Write-Warning "VM is not yet registered (IsRegistered != 1). It may take a minute to appear in the portal."
    }
}
catch {
    Write-Error "Registration failed: $_"
    exit 1
}
