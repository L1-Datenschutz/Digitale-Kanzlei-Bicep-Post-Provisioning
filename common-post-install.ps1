Write-Host "Common Post Install Done"

try {
  mkdir "c:\test"
} catch {
  cd "c:\test"
} finally {
  $client = new-object System.Net.WebClient 
  $client.DownloadFile("https://raw.githubusercontent.com/L1-Datenschutz/Digitale-Kanzlei-Bicep-Post-Provisioning/refs/heads/main/common-post-install.ps1","c:\test\common-install.ps1")
}
