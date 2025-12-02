
set-german-language



function set-german-language {
    try {
        Write-Output "🇩🇪 Starting configuration of German language settings..."
    
        # 1. Install German language (downloads automatically from MS servers)
        # -CopyToSettings: Applies this to the Welcome screen and new user accounts!
        $lang = Get-InstalledLanguage | Where-Object { $_.LanguageId -eq 'de-DE' }
        
        if (-not $lang) {
            Write-Output "Installing language pack 'de-DE'. This may take a few minutes..."
            Install-Language -Language de-DE -CopyToSettings
        } else {
            Write-Output "Language pack 'de-DE' is already installed."
        }
    
        # 2. Set regional formats (Date, Currency: 31.12.2025, €)
        Write-Output "Setting regional formats (Culture)..."
        Set-Culture -CultureInfo de-DE
    
        # 3. Set System Locale for non-Unicode programs (important for legacy software!)
        Write-Output "Setting System Locale..."
        Set-WinSystemLocale -SystemLocale de-DE
    
        # 4. Set Location (GeoID) to Germany (GeoID 94 = Germany)
        Write-Output "Setting location to Germany..."
        Set-WinHomeLocation -GeoId 94
    
        # 5. Set Time Zone to Berlin
        Write-Output "Setting time zone to Berlin (W. Europe Standard Time)..."
        Set-TimeZone -Id "W. Europe Standard Time"
    
        # 6. Force keyboard layout (Optional, but recommended for AVD)
        # Removes the US layout from the list so users don't accidentally switch
        Write-Output "Forcing keyboard layout to German..."
        $langList = New-WinUserLanguageList de-DE
        $langList[0].InputMethodTips.Clear()
        $langList[0].InputMethodTips.Add('0407:00000407') # German (Germany)
        Set-WinUserLanguageList $langList -Force
    
        Write-Output "✅ Language settings successfully applied."
        
        # ATTENTION: Changes only take full effect after a REBOOT!
        # In Azure Extensions, reboots should be handled carefully.
    }
    catch {
        Write-Error "ERROR while setting language: $($_.Exception.Message)"
        exit 1
    }
}

