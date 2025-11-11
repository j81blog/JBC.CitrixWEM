function Get-GppShortcut {
    <#
    .SYNOPSIS
        Retrieves Group Policy Preferences shortcuts from specified GPOs.

    .DESCRIPTION
        The Get-GppShortcut function extracts shortcut information from Group Policy Objects (GPOs)
        and converts them into a format suitable for Citrix Workspace Environment Management (WEM)
        or other management systems. It resolves Active Directory security groups, extracts icons,
        normalizes paths, and organizes the data for easy migration or analysis.

        The function processes GPP shortcuts and maps environment variables (%StartMenuDir%,
        %DesktopDir%, etc.) to WEM-compatible paths. It handles duplicate shortcuts intelligently
        and can filter out shortcuts with Delete actions.

    .PARAMETER GpoName
        One or more Group Policy Object names to process. Accepts pipeline input.

    .PARAMETER AsJson
        Returns the output as JSON string instead of PowerShell objects.

    .PARAMETER JsonFilePath
        Exports the results to a JSON file at the specified path.

    .PARAMETER SkipDeleteAction
        Skips shortcuts that have a Delete action configured in the GPO.

    .INPUTS
        System.String[]
        You can pipe GPO names to this function.

    .OUTPUTS
        PSCustomObject or System.String
        Returns custom objects with shortcut details, or JSON string if -AsJson is specified.

    .EXAMPLE
        Get-GppShortcut -GpoName "Desktop Applications"

        Retrieves all GPP shortcuts from the "Desktop Applications" GPO.

    .EXAMPLE
        Get-GppShortcut -GpoName "Desktop Applications" -SkipDeleteAction

        Retrieves GPP shortcuts from the specified GPO, excluding any shortcuts configured with Delete action.

    .EXAMPLE
        "GPO1", "GPO2" | Get-GppShortcut -AsJson

        Processes multiple GPOs via pipeline and returns results as JSON.

    .EXAMPLE
        Get-GppShortcut -GpoName "Desktop Applications" -JsonFilePath "C:\Export\shortcuts.json"

        Exports all shortcuts from the GPO to a JSON file.

    .NOTES
        Function  : Get-GppShortcut
        Author    : John Billekens
        CoAuthor  : Claude (Anthropic)
        Copyright : Copyright (c) John Billekens Consultancy
        Requires  : ActiveDirectory and GroupPolicy PowerShell modules
        Version   : 2025.1111.1630

    .LINK
        https://github.com/j81blog/JBC.CitrixWEM
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            HelpMessage = "Enter the name of the GPO."
        )]
        [ValidateNotNullOrEmpty()]
        [string[]]$GpoName,

        [Parameter(HelpMessage = "Returns the output as JSON string.")]
        [switch]$AsJson,

        [Parameter(HelpMessage = "Path to export the results to a JSON file.")]
        [String]$JsonFilePath,

        [Parameter(HelpMessage = "Skips shortcuts with Delete action.")]
        [switch]$SkipDeleteAction
    )

    begin {
        # Check if the required modules are available
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            Write-Error "The GroupPolicy module is required. Please install it via 'Install-WindowsFeature GPMC'."
            return
        }
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Error "The ActiveDirectory module is required. Please install it via RSAT."
            return
        }
        $ActionMap = @{
            C = "Create"
            R = "Replace"
            U = "Update"
            D = "Delete"
        }
        $IconStreamDefault = "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"

        $ResultOutput = @()
    }

    process {
        $Counter = 0
        foreach ($Name in $GpoName) {
            #Write-Progress -Activity "Processing Applications" -Status "Processing item $($Counter) of $($TotalNumberOfItems)" -CurrentOperation "Application: $($Application.path)" -PercentComplete (($Counter / $TotalNumberOfItems) * 100)
            Write-Progress -Activity "Processing GPOs" -Status "Processing GPO: $Name" -PercentComplete (($Counter / $GpoName.Count) * 100) -Id 0
            try {
                Write-Verbose "Processing GPO: '$Name'"
                $GpoReportXml = Get-GPOReport -Name $Name -ReportType Xml -ErrorAction Stop
                [xml]$XmlData = $GpoReportXml

                $ShortcutNodes = @($XmlData.GPO.User.ExtensionData.Extension.ShortcutSettings.Shortcut)

                $Output = $null

                if ($null -ne $ShortcutNodes -and $ShortcutNodes.Count -gt 0) {
                    Write-Verbose "Found $($ShortcutNodes.Count) GPP Shortcuts in GPO '$Name'."
                    $AppCounter = 0
                    foreach ($Shortcut in $ShortcutNodes) {
                        # Initialize variables for each shortcut
                        $IsAutoStart = $false
                        $IsDesktop = $false
                        $IsQuickLaunch = $false
                        $IsStartMenu = $false
                        $CreateShortcut = $true

                        Write-Progress -Activity "Processing Shortcuts" -Status "Processing shortcut $($AppCounter + 1) of $($ShortcutNodes.Count) in GPO '$Name'" -CurrentOperation "Shortcut: $($Shortcut.name)" -PercentComplete ((($AppCounter + 1) / $ShortcutNodes.Count) * 100) -Id 1 -ParentId 0
                        Write-Verbose "Processing shortcut: '$($Shortcut.name)'"
                        if ($SkipDeleteAction -and $Shortcut.Properties.action -ieq "D") {
                            Write-Verbose "Skipping shortcut: '$($Shortcut.name)' with Delete action as per parameter."
                            continue
                        }
                        $TargetedGroup = @()
                        $FilterNodes = $Shortcut.Filters.FilterGroup
                        if ($null -ne $Shortcut.Filters.FilterCollection) {
                            $FilterNodes += $Shortcut.Filters.FilterCollection.FilterGroup
                        }
                        if ($Shortcut.disabled -eq "1") {
                            $Enabled = $false
                            $State = "Disabled"
                        } else {
                            $Enabled = $true
                            $State = "Enabled"
                        }
                        $FailedSIDResolves = 0
                        $SIDCounter = 0
                        if ($null -ne $FilterNodes) {
                            $GroupSids = $FilterNodes | Where-Object { $_.sid } | Select-Object -ExpandProperty sid
                            foreach ($Sid in $GroupSids) {
                                $SIDCounter++
                                $ResolvedObject = Resolve-GppSid -Sid $Sid -ItemName $Shortcut.name
                                if ($null -ne $ResolvedObject) {
                                    $TargetedGroup += $ResolvedObject
                                } else {
                                    $FailedSIDResolves++
                                }
                            }
                        }
                        if ($SIDCounter -gt 0 -and $FailedSIDResolves -ge $SIDCounter) {
                            Write-Warning "Shortcut: `"$($Shortcut.name)`", All SIDs ($SIDCounter) in the filters could not be resolved to an AD Group or User name. Disabling shortcut."
                            $Enabled = $false
                            $CreateShortcut = $false
                            $State = "Enabled - No valid target groups"
                        } elseif ($TargetedGroup.Count -eq 0) {
                            $TargetedGroup += [PSCustomObject]@{ Sid = "S-1-1-0"; Name = "Everyone"; Type = "group" }
                        }
                        $Action = $ActionMap[$Shortcut.Properties.action]
                        if (-not $Action) {
                            $Action = $Shortcut.Properties.action
                        }

                        # Convert shortcut path using helper function
                        $PathResult = Convert-ShortcutPath -ShortcutPath $Shortcut.Properties.shortcutPath `
                            -ShortcutName $Shortcut.name `
                            -IsAutoStart ([ref]$IsAutoStart) `
                            -IsDesktop ([ref]$IsDesktop) `
                            -IsStartMenu ([ref]$IsStartMenu)

                        $StartMenuPath = $PathResult.StartMenuPath
                        if (-not $PathResult.CreateShortcut) {
                            $CreateShortcut = $false
                        }
                        switch ($Shortcut.Properties.targetType) {
                            "FILESYSTEM" {
                                $ActionType = "CreateAppShortcut"
                                $AppType = "InstallerApplication"
                                $URL = $null
                                $CommandLine = $Shortcut.Properties.targetPath
                            }
                            "URL" {
                                $ActionType = "CreateAppShortcut"
                                $AppType = "Url"
                                $URL = $Shortcut.Properties.targetPath -replace '"', '' -replace "'", ''
                                $CommandLine = $null
                                # Validate and normalize URL
                                $knownProtocols = @('http://', 'https://', 'ftp://', 'ftps://', 'jnlps://', 'file://', 'mailto:', 'tel:')
                                $hasKnownProtocol = $false
                                foreach ($protocol in $knownProtocols) {
                                    if ($URL -like "$protocol*") {
                                        $hasKnownProtocol = $true
                                        break
                                    }
                                }
                                if (-not $hasKnownProtocol) {
                                    $URL = "https://$URL"
                                    Write-Warning "Shortcut: `"$($Shortcut.name)`", URL '$($Shortcut.Properties.targetPath)' `r`n         does not start with a known protocol. Prepending https://"
                                }
                            }
                            "SHELL" {
                                Write-Warning "Shortcut: `"$($Shortcut.name)`", Shell shortcuts are currently not supported."
                            }
                            default {
                                $ActionType = "CreateAppShortcut"
                                $AppType = "InstallerApplication"
                            }
                        }
                        # Map GPP window style to WEM window style (valid values: Normal, Maximized, Minimized)
                        switch ($Shortcut.Properties.window) {
                            "MAX" { $WindowStyle = "Maximized" }
                            "MIN" { $WindowStyle = "Minimized" }
                            default { $WindowStyle = "Normal" }
                        }
                        Write-Verbose "Creating output object for shortcut: '$($Shortcut.name)'"
                        $IconPath = "$IconStreamDefault"
                        try {

                            try {
                                $IconPath = Convert-BatchVarToPowerShell -Path $Shortcut.properties.IconPath -Resolve -ErrorAction Stop
                            } catch {
                                $IconPath = $Shortcut.properties.IconPath
                            }
                            switch ($IconPath) {
                                "C:\Windows\System32\explorer.exe" { $IconPath = "C:\Windows\explorer.exe" }
                            }
                            if ([string]::IsNullOrEmpty($($Shortcut.properties.iconIndex))) {
                                if ($AppType -eq "Url") {
                                    $IconPath = "C:\Windows\System32\shell32.dll"
                                    $IconIndex = 13
                                } else {
                                    $IconIndex = 0
                                }
                            } else {
                                try {
                                    $IconIndex = [Int]$Shortcut.properties.iconIndex
                                } catch {
                                    $IconIndex = 0
                                }
                            }
                            if (-Not [string]::IsNullOrEmpty($IconPath) -and (Test-Path -Path $IconPath -ErrorAction SilentlyContinue)) {
                                try {
                                    $IconStream = Export-FileIcon -FilePath $IconPath -Index $IconIndex -Size 32 -AsBase64 -ErrorAction Stop
                                } catch {
                                    Write-Warning "Shortcut: `"$($Shortcut.name)`", Failed to export icon from path:`r`n         '$IconPath'`r`n         With index: $IconIndex.`r`n         Error: $($_.Exception.Message)`r`n         Using default icon stream."
                                    $IconStream = "$IconStreamDefault"
                                }
                            } else {
                                if ($IconPath) {
                                    Write-Warning "Shortcut: `"$($Shortcut.name)`", Icon path does not exists:`r`n         '$IconPath'"
                                }
                            }
                        } catch {
                            Write-Warning "Shortcut: `"$($Shortcut.name)`", Failed to retrieve icon from path:`r`n         '$IconPath'`r`n         With index: $IconIndex.`r`n         Error: $($_.Exception.Message)"
                        }
                        if ([String]::IsNullOrEmpty($IconStream)) {
                            $IconPath = "$IconStreamDefault"
                        }
                        $CreateShortcut = $true
                        if ($Action -eq "Delete") {
                            $CreateShortcut = $false
                            $Enabled = $false
                        }
                        $workingDir = $Shortcut.Properties.startIn
                        if ([string]::IsNullOrEmpty($workingDir) -and $ActionType -eq "CreateAppShortcut") {
                            $workingDir = Split-Path -Path $CommandLine -Parent
                        }
                        $Output = [PSCustomObject]@{
                            GpoName              = $Name
                            Action               = $Action
                            Name                 = $Shortcut.name
                            TargetType           = $Shortcut.Properties.targetType
                            TargetPath           = $Shortcut.Properties.targetPath
                            Comment              = $Shortcut.Properties.comment
                            IconIndex            = $IconIndex
                            IconPath             = $IconPath
                            ShortcutKey          = $Shortcut.properties.shortcutKey
                            Status               = $Shortcut.status
                            CommandLine          = $CommandLine
                            ShortcutPath         = $Shortcut.Properties.shortcutPath
                            StartIn              = $Shortcut.Properties.startIn
                            WindowStyle          = $WindowStyle
                            Arguments            = $Shortcut.Properties.arguments
                            WEMAssignments       = @($TargetedGroup)
                            Enabled              = $Enabled
                            State                = $State
                            CreateShortcut       = $CreateShortcut
                            WEMAssignmentParams  = [PSCustomObject]@{
                                isAutoStart   = $IsAutoStart
                                isDesktop     = $IsDesktop
                                isQuickLaunch = $IsQuickLaunch
                                isStartMenu   = $IsStartMenu
                            }
                            WEMApplicationParams = [PSCustomObject]@{
                                startMenuPath = $StartMenuPath
                                appType       = $AppType
                                state         = $State
                                iconStream    = $IconStream
                                parameter     = $Shortcut.Properties.arguments
                                name          = $Shortcut.name
                                commandLine   = $CommandLine
                                workingDir    = $workingDir
                                url           = $URL
                                displayName   = $Shortcut.name
                                windowStyle   = $WindowStyle
                                actionType    = $ActionType
                            }
                        }
                        if ($Duplicate = $ResultOutput | Where-Object { $_.Name -eq $Shortcut.name }) {
                            if ($Duplicate.TargetPath -eq $Output.TargetPath -and $Duplicate.Arguments -eq $Output.Arguments -and $Output.WEMAssignmentParams.isAutoStart -eq $true) {
                                $Output.Name = "$($Shortcut.name) (AutoStart)"
                                Write-Warning "Shortcut: `"$($Shortcut.name)`", Duplicate shortcut found in GPO '$Name', but with the same CommandLine and Arguments. Appending '(AutoStart)' to the name."
                                $ResultOutput += $Output
                            } elseif ($Duplicate.TargetPath -eq $Output.TargetPath -and $Duplicate.Arguments -eq $Output.Arguments) {
                                Write-Verbose "Shortcut: `"$($Shortcut.name)`", Duplicate shortcut found in GPO '$Name', but with the same CommandLine and Arguments. Checking assignment parameters."
                                if ($Output.WEMAssignmentParams.isAutoStart -eq $true) {
                                    $Duplicate.WEMAssignmentParams.isAutoStart = $true
                                }
                                if ($Output.WEMAssignmentParams.isDesktop -eq $true) {
                                    $Duplicate.WEMAssignmentParams.isDesktop = $true
                                }
                                if ($Output.WEMAssignmentParams.isQuickLaunch -eq $true) {
                                    $Duplicate.WEMAssignmentParams.isQuickLaunch = $true
                                }
                                if ($Output.WEMAssignmentParams.isStartMenu -eq $true) {
                                    $Duplicate.WEMAssignmentParams.isStartMenu = $true
                                }
                            } else {
                                for ($i = 1; $i -lt 100; $i++) {
                                    $NewName = "$($Shortcut.name) ($i)"
                                    if (-not ($ResultOutput | Where-Object { $_.Name -eq $NewName })) {
                                        $Output.Name = $NewName
                                        Write-Warning "Shortcut: `"$($Shortcut.name)`", Duplicate shortcut name found in GPO '$Name'. Appending '($i)' to the name."
                                        $Output.CreateShortcut = $false
                                        $ResultOutput += $Output
                                        break
                                    }
                                }
                            }
                        } else {
                            $ResultOutput += $Output
                        }
                        $AppCounter++
                    }
                    Write-Progress -Activity "Processing Shortcuts" -Status "Processed $($AppCounter) shortcuts in GPO '$Name'" -Completed -Id 1 -ParentId 0
                } else {
                    Write-Verbose "No GPP Shortcuts found in GPO '$Name'."
                }
            } catch {
                Write-Warning "Could not retrieve or parse GPO '$Name'. Error: $($_.Exception.Message)"
            }
            $Counter++
        }
        Write-Progress -Activity "Processing GPOs" -Status "Processed GPO: $Name" -Completed -Id 0
    }
    end {
        if ($JsonFilePath -and $ResultOutput.Count -gt 0) {
            Write-Verbose "Exporting $($ResultOutput.Count) GPP Shortcuts to JSON file at path: $JsonFilePath"
            $ResultOutput | ConvertTo-Json -Depth 5 | Set-Content -Path $JsonFilePath -Force
        } elseif ($AsJson -and $ResultOutput.Count -gt 0) {
            Write-Verbose "Converting $($ResultOutput.Count) GPP Shortcuts output to JSON."
            Write-Output ($ResultOutput | ConvertTo-Json -Depth 5)
        } elseif ($ResultOutput.Count -gt 0) {
            Write-Output $ResultOutput
        } else {
            Write-Output "No GPP Shortcuts found."
        }
    }
}

# SIG # Begin signature block
# MIImdwYJKoZIhvcNAQcCoIImaDCCJmQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCATVUhAakQagnEw
# m+S8/IJyXqPUMG/h4YiuYPPD3DyVk6CCIAowggYUMIID/KADAgECAhB6I67aU2mW
# D5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRpbWUg
# U3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYD
# VQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIwDQYJ
# KoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPvIhKA
# VD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlBnwDE
# JuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv2eNm
# GiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7CQKf
# OUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLgzb1g
# bL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ1AzC
# s1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwUtrYE
# 2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYadtn03
# 4ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0jBBgw
# FoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1SgLqz
# YZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBDMEGg
# P6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3Rh
# bXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKGO2h0
# dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jv
# b3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVUacah
# RoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQUn73
# 3qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M/SFj
# eCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7KyUJ
# Go1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/mSiSU
# ice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ1c6F
# ibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALOz1Uj
# b0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7HpNi/
# KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUufrV64
# EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ7l93
# 9bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5vVye
# fQIwggZFMIIELaADAgECAhAIMk+dt9qRb2Pk8qM8Xl1RMA0GCSqGSIb3DQEBCwUA
# MFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMu
# QS4xJDAiBgNVBAMTG0NlcnR1bSBDb2RlIFNpZ25pbmcgMjAyMSBDQTAeFw0yNDA0
# MDQxNDA0MjRaFw0yNzA0MDQxNDA0MjNaMGsxCzAJBgNVBAYTAk5MMRIwEAYDVQQH
# DAlTY2hpam5kZWwxIzAhBgNVBAoMGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5
# MSMwIQYDVQQDDBpKb2huIEJpbGxla2VucyBDb25zdWx0YW5jeTCCAaIwDQYJKoZI
# hvcNAQEBBQADggGPADCCAYoCggGBAMslntDbSQwHZXwFhmibivbnd0Qfn6sqe/6f
# os3pKzKxEsR907RkDMet2x6RRg3eJkiIr3TFPwqBooyXXgK3zxxpyhGOcuIqyM9J
# 28DVf4kUyZHsjGO/8HFjrr3K1hABNUszP0o7H3o6J31eqV1UmCXYhQlNoW9FOmRC
# 1amlquBmh7w4EKYEytqdmdOBavAD5Xq4vLPxNP6kyA+B2YTtk/xM27TghtbwFGKn
# u9Vwnm7dFcpLxans4ONt2OxDQOMA5NwgcUv/YTpjhq9qoz6ivG55NRJGNvUXsM3w
# 2o7dR6Xh4MuEGrTSrOWGg2A5EcLH1XqQtkF5cZnAPM8W/9HUp8ggornWnFVQ9/6M
# ga+ermy5wy5XrmQpN+x3u6tit7xlHk1Hc+4XY4a4ie3BPXG2PhJhmZAn4ebNSBwN
# Hh8z7WTT9X9OFERepGSytZVeEP7hgyptSLcuhpwWeR4QdBb7dV++4p3PsAUQVHFp
# wkSbrRTv4EiJ0Lcz9P1HPGFoHiFAQQIDAQABo4IBeDCCAXQwDAYDVR0TAQH/BAIw
# ADA9BgNVHR8ENjA0MDKgMKAuhixodHRwOi8vY2NzY2EyMDIxLmNybC5jZXJ0dW0u
# cGwvY2NzY2EyMDIxLmNybDBzBggrBgEFBQcBAQRnMGUwLAYIKwYBBQUHMAGGIGh0
# dHA6Ly9jY3NjYTIwMjEub2NzcC1jZXJ0dW0uY29tMDUGCCsGAQUFBzAChilodHRw
# Oi8vcmVwb3NpdG9yeS5jZXJ0dW0ucGwvY2NzY2EyMDIxLmNlcjAfBgNVHSMEGDAW
# gBTddF1MANt7n6B0yrFu9zzAMsBwzTAdBgNVHQ4EFgQUO6KtBpOBgmrlANVAnyiQ
# C6W6lJwwSwYDVR0gBEQwQjAIBgZngQwBBAEwNgYLKoRoAYb2dwIFAQQwJzAlBggr
# BgEFBQcCARYZaHR0cHM6Ly93d3cuY2VydHVtLnBsL0NQUzATBgNVHSUEDDAKBggr
# BgEFBQcDAzAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAEQsN8wg
# PMdWVkwHPPTN+jKpdns5AKVFjcn00psf2NGVVgWWNQBIQc9lEuTBWb54IK6Ga3hx
# QRZfnPNo5HGl73YLmFgdFQrFzZ1lnaMdIcyh8LTWv6+XNWfoyCM9wCp4zMIDPOs8
# LKSMQqA/wRgqiACWnOS4a6fyd5GUIAm4CuaptpFYr90l4Dn/wAdXOdY32UhgzmSu
# xpUbhD8gVJUaBNVmQaRqeU8y49MxiVrUKJXde1BCrtR9awXbqembc7Nqvmi60tYK
# lD27hlpKtj6eGPjkht0hHEsgzU0Fxw7ZJghYG2wXfpF2ziN893ak9Mi/1dmCNmor
# GOnybKYfT6ff6YTCDDNkod4egcMZdOSv+/Qv+HAeIgEvrxE9QsGlzTwbRtbm6gwY
# YcVBs/SsVUdBn/TSB35MMxRhHE5iC3aUTkDbceo/XP3uFhVL4g2JZHpFfCSu2TQr
# rzRn2sn07jfMvzeHArCOJgBW1gPqR3WrJ4hUxL06Rbg1gs9tU5HGGz9KNQMfQFQ7
# 0Wz7UIhezGcFcRfkIfSkMmQYYpsc7rfzj+z0ThfDVzzJr2dMOFsMlfj1T6l22GBq
# 9XQx0A4lcc5Fl9pRxbOuHHWFqIBD/BCEhwniOCySzqENd2N+oz8znKooSISStnkN
# aYXt6xblJF2dx9Dn89FK7d1IquNxOwt0tI5dMIIGYjCCBMqgAwIBAgIRAKQpO24e
# 3denNAiHrXpOtyQwDQYJKoZIhvcNAQEMBQAwVTELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBDQSBSMzYwHhcNMjUwMzI3MDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjByMQswCQYDVQQGEwJHQjEXMBUGA1UECBMOV2VzdCBZb3Jrc2hpcmUxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEwMC4GA1UEAxMnU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBTaWduZXIgUjM2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEA04SV9G6kU3jyPRBLeBIHPNyUgVNnYayfsGOyYEXrn3+SkDYTLs1crcw/
# ol2swE1TzB2aR/5JIjKNf75QBha2Ddj+4NEPKDxHEd4dEn7RTWMcTIfm492TW22I
# 8LfH+A7Ehz0/safc6BbsNBzjHTt7FngNfhfJoYOrkugSaT8F0IzUh6VUwoHdYDpi
# ln9dh0n0m545d5A5tJD92iFAIbKHQWGbCQNYplqpAFasHBn77OqW37P9BhOASdmj
# p3IijYiFdcA0WQIe60vzvrk0HG+iVcwVZjz+t5OcXGTcxqOAzk1frDNZ1aw8nFhG
# EvG0ktJQknnJZE3D40GofV7O8WzgaAnZmoUn4PCpvH36vD4XaAF2CjiPsJWiY/j2
# xLsJuqx3JtuI4akH0MmGzlBUylhXvdNVXcjAuIEcEQKtOBR9lU4wXQpISrbOT8ux
# +96GzBq8TdbhoFcmYaOBZKlwPP7pOp5Mzx/UMhyBA93PQhiCdPfIVOCINsUY4U23
# p4KJ3F1HqP3H6Slw3lHACnLilGETXRg5X/Fp8G8qlG5Y+M49ZEGUp2bneRLZoyHT
# yynHvFISpefhBCV0KdRZHPcuSL5OAGWnBjAlRtHvsMBrI3AAA0Tu1oGvPa/4yeei
# Ayu+9y3SLC98gDVbySnXnkujjhIh+oaatsk/oyf5R2vcxHahajMCAwEAAaOCAY4w
# ggGKMB8GA1UdIwQYMBaAFF9Y7UwxeqJhQo1SgLqzYZcZojKbMB0GA1UdDgQWBBSI
# YYyhKjdkgShgoZsx0Iz9LALOTzAOBgNVHQ8BAf8EBAMCBsAwDAYDVR0TAQH/BAIw
# ADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDBKBgNVHSAEQzBBMDUGDCsGAQQBsjEB
# AgEDCDAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZn
# gQwBBAIwSgYDVR0fBEMwQTA/oD2gO4Y5aHR0cDovL2NybC5zZWN0aWdvLmNvbS9T
# ZWN0aWdvUHVibGljVGltZVN0YW1waW5nQ0FSMzYuY3JsMHoGCCsGAQUFBwEBBG4w
# bDBFBggrBgEFBQcwAoY5aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVi
# bGljVGltZVN0YW1waW5nQ0FSMzYuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2Nz
# cC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAYEAAoE+pIZyUSH5ZakuPVKK
# 4eWbzEsTRJOEjbIu6r7vmzXXLpJx4FyGmcqnFZoa1dzx3JrUCrdG5b//LfAxOGy9
# Ph9JtrYChJaVHrusDh9NgYwiGDOhyyJ2zRy3+kdqhwtUlLCdNjFjakTSE+hkC9F5
# ty1uxOoQ2ZkfI5WM4WXA3ZHcNHB4V42zi7Jk3ktEnkSdViVxM6rduXW0jmmiu71Z
# pBFZDh7Kdens+PQXPgMqvzodgQJEkxaION5XRCoBxAwWwiMm2thPDuZTzWp/gUFz
# i7izCmEt4pE3Kf0MOt3ccgwn4Kl2FIcQaV55nkjv1gODcHcD9+ZVjYZoyKTVWb4V
# qMQy/j8Q3aaYd/jOQ66Fhk3NWbg2tYl5jhQCuIsE55Vg4N0DUbEWvXJxtxQQaVR5
# xzhEI+BjJKzh3TQ026JxHhr2fuJ0mV68AluFr9qshgwS5SpN5FFtaSEnAwqZv3IS
# +mlG50rK7W3qXbWwi4hmpylUfygtYLEdLQukNEX1jiOKMIIGgjCCBGqgAwIBAgIQ
# NsKwvXwbOuejs902y8l1aDANBgkqhkiG9w0BAQwFADCBiDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYD
# VQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBS
# U0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMjEwMzIyMDAwMDAwWhcNMzgw
# MTE4MjM1OTU5WjBXMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1p
# dGVkMS4wLAYDVQQDEyVTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIFJvb3Qg
# UjQ2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAiJ3YuUVnnR3d6Lkm
# gZpUVMB8SQWbzFoVD9mUEES0QUCBdxSZqdTkdizICFNeINCSJS+lV1ipnW5ihkQy
# C0cRLWXUJzodqpnMRs46npiJPHrfLBOifjfhpdXJ2aHHsPHggGsCi7uE0awqKggE
# /LkYw3sqaBia67h/3awoqNvGqiFRJ+OTWYmUCO2GAXsePHi+/JUNAax3kpqstbl3
# vcTdOGhtKShvZIvjwulRH87rbukNyHGWX5tNK/WABKf+Gnoi4cmisS7oSimgHUI0
# Wn/4elNd40BFdSZ1EwpuddZ+Wr7+Dfo0lcHflm/FDDrOJ3rWqauUP8hsokDoI7D/
# yUVI9DAE/WK3Jl3C4LKwIpn1mNzMyptRwsXKrop06m7NUNHdlTDEMovXAIDGAvYy
# nPt5lutv8lZeI5w3MOlCybAZDpK3Dy1MKo+6aEtE9vtiTMzz/o2dYfdP0KWZwZIX
# bYsTIlg1YIetCpi5s14qiXOpRsKqFKqav9R1R5vj3NgevsAsvxsAnI8Oa5s2oy25
# qhsoBIGo/zi6GpxFj+mOdh35Xn91y72J4RGOJEoqzEIbW3q0b2iPuWLA911cRxgY
# 5SJYubvjay3nSMbBPPFsyl6mY4/WYucmyS9lo3l7jk27MAe145GWxK4O3m3gEFEI
# kv7kRmefDR7Oe2T1HxAnICQvr9sCAwEAAaOCARYwggESMB8GA1UdIwQYMBaAFFN5
# v1qqK0rPVIDh2JvAnfKyA2bLMB0GA1UdDgQWBBT2d2rdP/0BE/8WoWyCAi/QCj0U
# JTAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zATBgNVHSUEDDAKBggr
# BgEFBQcDCDARBgNVHSAECjAIMAYGBFUdIAAwUAYDVR0fBEkwRzBFoEOgQYY/aHR0
# cDovL2NybC51c2VydHJ1c3QuY29tL1VTRVJUcnVzdFJTQUNlcnRpZmljYXRpb25B
# dXRob3JpdHkuY3JsMDUGCCsGAQUFBwEBBCkwJzAlBggrBgEFBQcwAYYZaHR0cDov
# L29jc3AudXNlcnRydXN0LmNvbTANBgkqhkiG9w0BAQwFAAOCAgEADr5lQe1oRLjl
# ocXUEYfktzsljOt+2sgXke3Y8UPEooU5y39rAARaAdAxUeiX1ktLJ3+lgxtoLQhn
# 5cFb3GF2SSZRX8ptQ6IvuD3wz/LNHKpQ5nX8hjsDLRhsyeIiJsms9yAWnvdYOdEM
# q1W61KE9JlBkB20XBee6JaXx4UBErc+YuoSb1SxVf7nkNtUjPfcxuFtrQdRMRi/f
# InV/AobE8Gw/8yBMQKKaHt5eia8ybT8Y/Ffa6HAJyz9gvEOcF1VWXG8OMeM7Vy7B
# s6mSIkYeYtddU1ux1dQLbEGur18ut97wgGwDiGinCwKPyFO7ApcmVJOtlw9FVJxw
# /mL1TbyBns4zOgkaXFnnfzg4qbSvnrwyj1NiurMp4pmAWjR+Pb/SIduPnmFzbSN/
# G8reZCL4fvGlvPFk4Uab/JVCSmj59+/mB2Gn6G/UYOy8k60mKcmaAZsEVkhOFuoj
# 4we8CYyaR9vd9PGZKSinaZIkvVjbH/3nlLb0a7SBIkiRzfPfS9T+JesylbHa1LtR
# V9U/7m0q7Ma2CQ/t392ioOssXW7oKLdOmMBl14suVFBmbzrt5V5cQPnwtd3UOTpS
# 9oCG+ZZheiIvPgkDmA8FzPsnfXW5qHELB43ET7HHFHeRPRYrMBKjkb8/IN7Po0d0
# hQoF4TeMM+zYAJzoKQnVKOLg8pZVPT8wgga5MIIEoaADAgECAhEAmaOACiZVO2Wr
# 3G6EprPqOTANBgkqhkiG9w0BAQwFADCBgDELMAkGA1UEBhMCUEwxIjAgBgNVBAoT
# GVVuaXpldG8gVGVjaG5vbG9naWVzIFMuQS4xJzAlBgNVBAsTHkNlcnR1bSBDZXJ0
# aWZpY2F0aW9uIEF1dGhvcml0eTEkMCIGA1UEAxMbQ2VydHVtIFRydXN0ZWQgTmV0
# d29yayBDQSAyMB4XDTIxMDUxOTA1MzIxOFoXDTM2MDUxODA1MzIxOFowVjELMAkG
# A1UEBhMCUEwxITAfBgNVBAoTGEFzc2VjbyBEYXRhIFN5c3RlbXMgUy5BLjEkMCIG
# A1UEAxMbQ2VydHVtIENvZGUgU2lnbmluZyAyMDIxIENBMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAnSPPBDAjO8FGLOczcz5jXXp1ur5cTbq96y34vuTm
# flN4mSAfgLKTvggv24/rWiVGzGxT9YEASVMw1Aj8ewTS4IndU8s7VS5+djSoMcbv
# IKck6+hI1shsylP4JyLvmxwLHtSworV9wmjhNd627h27a8RdrT1PH9ud0IF+njvM
# k2xqbNTIPsnWtw3E7DmDoUmDQiYi/ucJ42fcHqBkbbxYDB7SYOouu9Tj1yHIohzu
# C8KNqfcYf7Z4/iZgkBJ+UFNDcc6zokZ2uJIxWgPWXMEmhu1gMXgv8aGUsRdaCtVD
# 2bSlbfsq7BiqljjaCun+RJgTgFRCtsuAEw0pG9+FA+yQN9n/kZtMLK+Wo837Q4QO
# ZgYqVWQ4x6cM7/G0yswg1ElLlJj6NYKLw9EcBXE7TF3HybZtYvj9lDV2nT8mFSkc
# SkAExzd4prHwYjUXTeZIlVXqj+eaYqoMTpMrfh5MCAOIG5knN4Q/JHuurfTI5XDY
# O962WZayx7ACFf5ydJpoEowSP07YaBiQ8nXpDkNrUA9g7qf/rCkKbWpQ5boufUnq
# 1UiYPIAHlezf4muJqxqIns/kqld6JVX8cixbd6PzkDpwZo4SlADaCi2JSplKShBS
# ND36E/ENVv8urPS0yOnpG4tIoBGxVCARPCg1BnyMJ4rBJAcOSnAWd18Jx5n858JS
# qPECAwEAAaOCAVUwggFRMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFN10XUwA
# 23ufoHTKsW73PMAywHDNMB8GA1UdIwQYMBaAFLahVDkCw6A/joq8+tT4HKbROg79
# MA4GA1UdDwEB/wQEAwIBBjATBgNVHSUEDDAKBggrBgEFBQcDAzAwBgNVHR8EKTAn
# MCWgI6Ahhh9odHRwOi8vY3JsLmNlcnR1bS5wbC9jdG5jYTIuY3JsMGwGCCsGAQUF
# BwEBBGAwXjAoBggrBgEFBQcwAYYcaHR0cDovL3N1YmNhLm9jc3AtY2VydHVtLmNv
# bTAyBggrBgEFBQcwAoYmaHR0cDovL3JlcG9zaXRvcnkuY2VydHVtLnBsL2N0bmNh
# Mi5jZXIwOQYDVR0gBDIwMDAuBgRVHSAAMCYwJAYIKwYBBQUHAgEWGGh0dHA6Ly93
# d3cuY2VydHVtLnBsL0NQUzANBgkqhkiG9w0BAQwFAAOCAgEAdYhYD+WPUCiaU58Q
# 7EP89DttyZqGYn2XRDhJkL6P+/T0IPZyxfxiXumYlARMgwRzLRUStJl490L94C9L
# GF3vjzzH8Jq3iR74BRlkO18J3zIdmCKQa5LyZ48IfICJTZVJeChDUyuQy6rGDxLU
# UAsO0eqeLNhLVsgw6/zOfImNlARKn1FP7o0fTbj8ipNGxHBIutiRsWrhWM2f8pXd
# d3x2mbJCKKtl2s42g9KUJHEIiLni9ByoqIUul4GblLQigO0ugh7bWRLDm0CdY9rN
# LqyA3ahe8WlxVWkxyrQLjH8ItI17RdySaYayX3PhRSC4Am1/7mATwZWwSD+B7eMc
# ZNhpn8zJ+6MTyE6YoEBSRVrs0zFFIHUR08Wk0ikSf+lIe5Iv6RY3/bFAEloMU+vU
# BfSouCReZwSLo8WdrDlPXtR0gicDnytO7eZ5827NS2x7gCBibESYkOh1/w1tVxTp
# V2Na3PR7nxYVlPu1JPoRZCbH86gc96UTvuWiOruWmyOEMLOGGniR+x+zPF/2DaGg
# K2W1eEJfo2qyrBNPvF7wuAyQfiFXLwvWHamoYtPZo0LHuH8X3n9C+xN4YaNjt2yw
# zOr+tKyEVAotnyU9vyEVOaIYMk3IeBrmFnn0gbKeTTyYeEEUz/Qwt4HOUBCrW602
# NCmvO1nm+/80nLy5r0AZvCQxaQ4xggXDMIIFvwIBATBqMFYxCzAJBgNVBAYTAlBM
# MSEwHwYDVQQKExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0Nl
# cnR1bSBDb2RlIFNpZ25pbmcgMjAyMSBDQQIQCDJPnbfakW9j5PKjPF5dUTANBglg
# hkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3
# DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEV
# MC8GCSqGSIb3DQEJBDEiBCCpm+SFextMCifxREfgYPDaZrggzHxsZJ4YuMlDiQX0
# WzANBgkqhkiG9w0BAQEFAASCAYCwqhxQF5wq3+pUJ+uDfqld+/2/RdMfh/S7yOvv
# qk2dyqfVYbS4VJoqtpZ2OQfH9Fy9NbtNf/kUvLBgTrO4NJUjMf25YqL4W2pzEK79
# LiJb4rQjakDlWGFlsH1IQbu0XlIPNU3IVSrUs0DirkPh8Hjxd02PhNEIPb5Bzp7v
# Y7TlR+O1EBzTPIGqKQkRHNCFoJldn3n4eMkGdWwSi4PzRAkFnFxxEwQ7E2frSVvS
# 1xzod0pSLH748O+P67o9LWZoAlIDDVcJSRFK1OktE38D4UNzIs0YMgPRrWXF3uzq
# 9YJU6Xj0hlPeZ27oimvoJ8fXBlyOrbzHe3KYYWfiO9tweR8xCDJnvB+unqzsFsel
# jQ4MJuOWWe6CXOCFWRfxMUZ+QTuQ7Kb5aYnZREwN4Mcp+N+Bd9G2x7gxO/l5VNdK
# yaiDRLr4cT3hpXYkFUVpaRAW3mRYnyJvotzk1Dbcwrk8XszLrFE7Q7gfbZpD/+Vl
# KsheWooPBBNj+KCUAkQegqXrta+hggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwC
# AQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQp
# O24e3denNAiHrXpOtyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNTExMTEyMjE4MjRaMD8GCSqGSIb3
# DQEJBDEyBDAdRY9O5TGnmoC/EwCi7Ei9HDlI9f66nLPSXqsp9abpQTEsqqWn1asN
# In0Mdi5hDdIwDQYJKoZIhvcNAQEBBQAEggIALt2kKj0GgMyszgJLyBHVpmSJ+FpT
# QfINWH2C9e1TXlihaMYJDR0lNcSStGtz9r1EmTHyG5suUlilQ6pfef6x4OLsIvym
# 0JuDTVfo5I5n5BAglJ2FUXLW6wL7tCQOyycbxFsdsmPDXgoM4wnZR6m0w1q9ZwCP
# Ktn0DtnT4ILY6ttuNeVBGUU3kNqvewfurrfGCzsGctNQttPTGNB8sYn9FZUNA8ph
# 3LC+8h6VPXRfPGNdy2GdofLprs5NZF5HK+rEXnU1e1/P2JslOvqarVjuHYNDqebm
# j0wmVlI5IAwtc2F1l1bD2B8OQ+RTVDyMMySAFGdL2+zzeC4SW+eZtavgEmhi3ACG
# IIzU+YTqRIPqTOm9MOp+0DRVw6sqFCpTela+ZO0Fj/eYcR+m0leTgjDwmlK0jjS6
# WTjf+uIxMDj61HRZJzLc8RBkmoIomDQX22AuKVnAiaSUUgo9s6iXwEdWd7BsnR6b
# O8fqS3WSugtdX25ZrbjqNVsJqeF3I4+3aS2/PxoCAO8P/Yn/g6PVUs2u+cAo/DWH
# CH7T+ahsWoBGxTNqlLBwfV5s7XtTRcseOh/RWqwk9ieB4LSkbiMxYRnasC+Kcihd
# Kax+jTfAQDc/XNgX2mHspZ+wbstfhQfkImgJLf2KGRWzReNguIYcmr9TBbxcP2Qb
# xrT3t4t3/3o235M=
# SIG # End signature block
