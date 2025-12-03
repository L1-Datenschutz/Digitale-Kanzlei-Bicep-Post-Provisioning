Write-Host "Sessionhost Post Install Done"

try {
  mkdir "c:\test"
} catch {
  cd "c:\test"
} finally {
  $client = new-object System.Net.WebClient 
  $client.DownloadFile("https://raw.githubusercontent.com/L1-Datenschutz/Digitale-Kanzlei-Bicep-Post-Provisioning/refs/heads/main/sessionhost-post-install.ps1","c:\test\sessionhost-install.ps1")
}
