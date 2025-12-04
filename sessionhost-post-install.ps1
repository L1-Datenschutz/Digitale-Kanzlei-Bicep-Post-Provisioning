param(
    [Parameter(Mandatory = $true)]
    [string]$RegistrationToken
)

try {
  mkdir "c:\test"
} catch {
  cd "c:\test"
} finally {
  $client = new-object System.Net.WebClient 
  $client.DownloadFile("https://raw.githubusercontent.com/L1-Datenschutz/Digitale-Kanzlei-Bicep-Post-Provisioning/refs/heads/main/sessionhost-post-install.ps1","c:\test\sessionhost-install.ps1")
}

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
