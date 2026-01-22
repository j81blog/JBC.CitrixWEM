## Updating Application Icons

This document outlines the process of retrieving file icons for example to be run on your master vm or session, to gather icon data for your shortcuts.

---

### 1. Gather icon data
In this example we assume you have generated a json file with export from GroupPolicy. In this case we need to gather the icon information to use this to configure the WEM application. It could be for example that you have exported the Group Policy shortcuts, and did not have access tpo all executables or icon files to gather the icon data.

```PowerShell
Import-Module JBC.CitrixWEM
$filename = "C:\path\to\apps.json"
$apps = Get-Content $filename -Raw | ConvertFrom-Json
#A default chosen icon for Web applications, as they may not have an icon
$defaultURLIconStream = Export-FileIcon -FilePath "C:\Windows\system32\imageres.dll" -Index 20 -AsBase64

foreach ($app in $apps) {
    Write-Host "=> Processing application: $($app.Name)"
    if (-Not [string]::IsNullOrEmpty($($app.IconIndex)) -and -Not [string]::IsNullOrEmpty($($app.IconPath))) {
        if (Test-Path $app.IconPath -ErrorAction SilentlyContinue) {
            try {
                $result = Export-FileIcon -FilePath $app.IconPath -Index $app.IconIndex -AsBase64
                if ($result) {
                    $app.WEMApplicationParams.iconStream = $result
                    Write-Host "   - Successfully exported icon for $($app.Name)"
                } else {
                    Write-Warning "No icon data returned for $($app.Name)"
                    continue
                }
            } catch {
                Write-Warning "Failed to export icon for $($app.Name): $_"
                continue
            }
        } else {
            Write-Warning "Icon path does not exist for $($app.Name): $($app.IconPath)"
            continue
        }

        if ([string]::IsNullOrEmpty($($app.WEMApplicationParams.workingDir)) -and $app.WEMApplicationParams.appType -ieq "InstallerApplication") {
            $app.WEMApplicationParams.workingDir = Split-Path -Path $app.WEMApplicationParams.commandLine -Parent
            Write-Host "   - Set working directory for application `"$($app.Name)`" to `"$($app.WEMApplicationParams.workingDir)`""
            $app.WEMApplicationParams.workingDir = "$($app.WEMApplicationParams.workingDir.TrimEnd('\'))\"
        } elseif (-Not [string]::IsNullOrEmpty($($app.WEMApplicationParams.workingDir))) {
            $app.WEMApplicationParams.workingDir = "$($app.WEMApplicationParams.workingDir.TrimEnd('\'))\"
            Write-Host "   - Cleaned workinggDir $($app.WEMApplicationParams.workingDir)"
        }

    } elseif ($app.targetType -eq "URL") {
        $app.WEMApplicationParams.iconStream = $defaultURLIconStream
        Write-Host "   - App is an URL Type, set default icon..."
    } else {
        Write-Warning "IconPath or IconIndex not specified for $($app.Name)"
        continue
    }
}

$apps | ConvertTo-Json -Depth 10 | Set-Content -Path $filename -Encoding UTF8 -Force
```

### 2. Update the WEM application

If you already have added the shortcuts earlier and just want to update the shortcut icons, you can run the following code.

To connect, follow this guide [Connecting to WEM](ConnectToWEMEnvironment.md)

```PowerShell
$filename = "C:\path\to\apps.json"
$apps = Get-Content $filename -Raw | ConvertFrom-Json
foreach ($app in $apps) {
    $wemApp = Get-WEMApplication | Where-Object { $_.Name -ieq $app.Name } -ErrorAction SilentlyContinue
    if (($wemApp | Measure-Object).Count -gt 1) {
        Write-Host "Multiple applications found with name `"$($app.Name)`". Skipping..."
        continue
    } elseif (-not [string]::IsNullOrEmpty($wemApp.id)) {
        try {
            Set-WemApplication -Id $wemApp.Id -IconStream $app.WEMApplicationParams.iconStream -WorkingDirectory $app.WEMApplicationParams.workingDir
            Write-Host "Updated icon for application `"$($app.Name)`""
        } catch {
            Write-Host "Failed to update icon for application `"$($app.Name)`": $_"
        }
    } else {
        Write-Host "Application `"$($app.Name)`" not found in WEM. Skipping... (GPO Action: $($app.Action))"
    }
}
```