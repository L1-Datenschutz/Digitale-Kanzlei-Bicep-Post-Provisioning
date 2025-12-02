# Example Post-Deployment Configuration Script
# This script runs inside the VM after deployment.

param(
    [string]$Environment,
    [string]$Timestamp
)

Start-Transcript -Path "C:\Windows\Temp\post-install.log"

Write-Output "Starting Post-Deployment Configuration for Environment: $Environment"

# Example: Install Chocolatey
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Output "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

# Example: Install a tool
# choco install notepadplusplus -y

# Example: Create a folder
New-Item -Path "C:\KanzleiData" -ItemType Directory -Force

Write-Output "Configuration Complete."
Stop-Transcript
