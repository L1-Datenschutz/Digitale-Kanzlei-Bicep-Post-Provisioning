Write-Host "Server Post Install Done"

Write-Host "Common Post Install Done"

mkdir "c:\test"
$client = new-object System.Net.WebClient 
$client.DownloadFile("https://raw.githubusercontent.com/L1-Datenschutz/Digitale-Kanzlei-Bicep-Post-Provisioning/refs/heads/main/server-post-install.ps1","c:\test\server-install.ps1")
