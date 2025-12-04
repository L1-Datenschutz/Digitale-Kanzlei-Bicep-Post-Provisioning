param(
    [Parameter(Mandatory = $true)]
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

try {
    Write-Host "Installing AVD Agent..."
    Invoke-WebRequest -Uri "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv" -OutFile "AVDAgent.msi"
    Start-Process msiexec.exe -ArgumentList "/i AVDAgent.msi /quiet /norestart REGISTRATIONTOKEN=$RegistrationToken" -Wait

    Write-Host "Installing AVD Bootloader..."
    Invoke-WebRequest -Uri "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH" -OutFile "AVDBootloader.msi"
    Start-Process msiexec.exe -ArgumentList "/i AVDBootloader.msi /quiet /norestart" -Wait

    Write-Host "VM successfully joined to Host Pool."
}
catch {
    Write-Error "Failed to join Host Pool: $_"
    exit 1
}
