Write-Host "Server Post Install Done"

try {
  mkdir "c:\test"
} catch {
  cd "c:\test"
} finally {
  $client = new-object System.Net.WebClient 
  $client.DownloadFile("https://raw.githubusercontent.com/L1-Datenschutz/Digitale-Kanzlei-Bicep-Post-Provisioning/refs/heads/main/server-post-install.ps1","c:\test\server-install.ps1")
}

