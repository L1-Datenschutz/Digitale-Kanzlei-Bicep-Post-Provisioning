param(
    [string]$RegistrationToken,
    [string]$Environment,
    [string]$EnableFslogix,
    [string]$FslogixSharePath
)

$ErrorActionPreference = "Stop"

try {
    Write-Host "Starting AVD Configuration..." -ForegroundColor Cyan

    # 1. INSTALLATION
    $AgentUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
    $BootUrl = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"
    
    if (!(Test-Path "C:\AzureData")) { New-Item -Path "C:\AzureData" -ItemType Directory -Force | Out-Null }
    
    # Check if already installed
    if (-not (Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue)) {
        Write-Host "Downloading & Installing..."
        (New-Object System.Net.WebClient).DownloadFile($AgentUrl, "C:\AzureData\AVDAgent.msi")
        (New-Object System.Net.WebClient).DownloadFile($BootUrl, "C:\AzureData\AVDBootloader.msi")

        # Install Agent WITH Token
        $agentArgs = "/i `"C:\AzureData\AVDAgent.msi`" /quiet /norestart REGISTRATION_TOKEN=`"$RegistrationToken`""
        Start-Process msiexec.exe -ArgumentList $agentArgs -Wait
        
        # Install Bootloader
        Start-Process msiexec.exe -ArgumentList "/i `"C:\AzureData\AVDBootloader.msi`" /quiet /norestart" -Wait
    }

    # 2. ENFORCE RUNNING STATE (The Fix)
    # Das Problem war: Der Dienst geht nach der Installation oft kurz aus. 
    # Wir zwingen ihn jetzt an zu bleiben.
    
    Write-Host "Enforcing Service State..." -ForegroundColor Cyan
    $registryPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent"
    
    # Token zur Sicherheit nochmal schreiben (falls MSI es verhauen hat)
    if (!(Test-Path $registryPath)) { New-Item -Path $registryPath -Force | Out-Null }
    New-ItemProperty -Path $registryPath -Name "RegistrationToken" -Value $RegistrationToken -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name "IsRegistered" -Value 0 -PropertyType DWord -Force | Out-Null

    # Loop: Prüfe 60 Sekunden lang, ob der Dienst läuft. Wenn er ausgeht -> Neustart.
    for ($i = 0; $i -lt 12; $i++) {
        $bl = Get-Service "RDAgentBootLoader" -ErrorAction SilentlyContinue
        
        if ($bl.Status -ne 'Running') {
            Write-Host "⚠️ BootLoader is $($bl.Status). Starting it..." -ForegroundColor Yellow
            Start-Service "RDAgentBootLoader"
        } else {
            Write-Host "✅ BootLoader is Running."
        }
        
        # Prüfe auch den Agent
        $ag = Get-Service "RDAgent" -ErrorAction SilentlyContinue
        if ($ag.Status -ne 'Running') {
            Start-Service "RDAgent" -ErrorAction SilentlyContinue
        }

        Start-Sleep -Seconds 5
    }

    # 3. VERIFICATION
    Write-Host "Verifying Registration..."
    $maxRetries = 20
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        $val = Get-ItemProperty -Path $registryPath -Name "IsRegistered" -ErrorAction SilentlyContinue
        if ($val.IsRegistered -eq 1) {
            Write-Host "✅ SUCCESS: Registered." -ForegroundColor Green
            exit 0
        }
        Write-Host "Waiting... ($($retryCount+1)/$maxRetries)"
        Start-Sleep -Seconds 10
        $retryCount++
    }

    Write-Error "❌ TIMEOUT: Agent did not register."
    exit 1
}
catch {
    Write-Error "❌ CRITICAL: $($_.Exception.Message)"
    exit 1
}
