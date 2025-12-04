param(
    [Parameter(Mandatory = $true)]
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

$ErrorActionPreference = "Stop"

try {
    # Create data directory if it doesn't exist
    New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null

    # --- 1. Install AVD Agent ---
    Write-Host "Downloading AVD Agent..."
    $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    $AgentMsi = "C:\AzureData\AVDAgent.msi"
    $AgentLog = "C:\AzureData\AVDAgentInstall.log"
    Invoke-WebRequest -Uri $AgentUrl -OutFile $AgentMsi

    Write-Host "Installing AVD Agent..."
    # Added /l*v for logging and -PassThru to capture exit code
    $procAgent = Start-Process msiexec.exe -ArgumentList "/i `"$AgentMsi`" /quiet /norestart /l*v `"$AgentLog`" REGISTRATIONTOKEN=$RegistrationToken" -Wait -PassThru
    
    if ($procAgent.ExitCode -ne 0) {
        throw "AVD Agent installation failed with exit code $($procAgent.ExitCode). Check log at $AgentLog"
    }

    # --- 2. Install AVD Bootloader ---
    Write-Host "Downloading AVD Bootloader..."
    $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    $BootMsi = "C:\AzureData\AVDBootloader.msi"
    $BootLog = "C:\AzureData\AVDBootloaderInstall.log"
    Invoke-WebRequest -Uri $BootUrl -OutFile $BootMsi

    Write-Host "Installing AVD Bootloader..."
    $procBoot = Start-Process msiexec.exe -ArgumentList "/i `"$BootMsi`" /quiet /norestart /l*v `"$BootLog`"" -Wait -PassThru

    if ($procBoot.ExitCode -ne 0) {
        throw "AVD Bootloader installation failed with exit code $($procBoot.ExitCode). Check log at $BootLog"
    }

    # --- 3. Verify Installation ---
    Write-Host "Verifying services..."
    $agentService = Get-Service "RemoteDesktopAgent" -ErrorAction SilentlyContinue
    $bootService = Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue

    if (-not $agentService) { throw "Service 'RemoteDesktopAgent' was not found after installation." }
    if (-not $bootService) { throw "Service 'RDAgentBootLoader' was not found after installation." }

    Write-Host "AVD Agent and Bootloader installed successfully. Services are present."
}
catch {
    Write-Error "Installation failed: $_"
    exit 1
}
