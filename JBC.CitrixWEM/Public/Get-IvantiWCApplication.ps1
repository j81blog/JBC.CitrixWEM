function Get-IvantiWCApplication {
    <#
    .SYNOPSIS
        Retrieves Ivanti Workspace Control application configurations from XML files.

    .DESCRIPTION
        Processes Ivanti Workspace Control XML building block file(s) and extracts application
        settings, assignments, and metadata. Supports both single large XML files and
        directories containing multiple separate XML files (one per application).

    .PARAMETER XmlFilePath
        (Legacy parameter) Path to a single Ivanti Workspace Control XML building block file.
        This parameter is maintained for backward compatibility. Use -XmlPath instead.

    .PARAMETER XmlPath
        Path to either:
        - A single XML file containing all application configurations
        - A directory containing multiple XML files (one per application)

    .PARAMETER AsJson
        Switch to output the results as JSON format instead of PowerShell objects.

    .EXAMPLE
        Get-IvantiWCApplication -XmlFilePath "C:\Config\IvantiApps.xml"

        Processes a single XML file (legacy parameter usage).

    .EXAMPLE
        Get-IvantiWCApplication -XmlPath "C:\Config\IvantiApps.xml"

        Processes a single XML file containing all applications.

    .EXAMPLE
        Get-IvantiWCApplication -XmlPath "C:\Config\Applications\" -AsJson

        Processes all XML files in the specified directory and outputs as JSON.

    .NOTES
        Function  : Get-IvantiWCApplication
        Author    : John Billekens
        CoAuthor  : Claude (Anthropic)
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 2025.1111.2145
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByFilePath',
            HelpMessage = "Path to the Ivanti Workspace Control XML building block file."
        )]
        [ValidateScript({
                if (-not (Test-Path $_ -PathType Leaf)) {
                    throw "File '$_' does not exist."
                }
                return $true
            })]
        [string]$XmlFilePath,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByPath',
            HelpMessage = "Path to the Ivanti Workspace Control XML building block file or directory containing XML files."
        )]
        [ValidateScript({
                if (-not (Test-Path $_)) {
                    throw "Path '$_' does not exist."
                }
                return $true
            })]
        [string]$XmlPath,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Output the results as JSON."
        )]
        [switch]$AsJson
    )

    $JsonOutput = @()
    $ApplicationsToProcess = @()

    # Handle backward compatibility - map XmlFilePath to XmlPath
    if ($PSCmdlet.ParameterSetName -eq 'ByFilePath') {
        $XmlPath = $XmlFilePath
    }

    # Determine if XmlPath is a file or directory
    if (Test-Path -Path $XmlPath -PathType Leaf) {
        # Single XML file mode
        Write-Verbose "Processing single XML file: $XmlPath"
        try {
            [xml]$IvantiXmlData = Get-Content -Path $XmlPath -Raw -ErrorAction Stop
            $ApplicationsToProcess = @($IvantiXmlData.SelectNodes("//application"))
        } catch {
            Write-Error "Failed to load XML file '$XmlPath': $_"
            return
        }
    } elseif (Test-Path -Path $XmlPath -PathType Container) {
        # Directory with multiple XML files mode
        Write-Verbose "Processing directory containing multiple XML files: $XmlPath"
        $XmlFiles = Get-ChildItem -Path $XmlPath -Filter "*.xml" -File

        if ($XmlFiles.Count -eq 0) {
            Write-Warning "No XML files found in directory: $XmlPath"
            return
        }

        Write-Verbose "Found $($XmlFiles.Count) XML file(s) in directory."

        foreach ($XmlFile in $XmlFiles) {
            try {
                [xml]$XmlData = Get-Content -Path $XmlFile.FullName -Raw -ErrorAction Stop
                $Apps = @($XmlData.SelectNodes("//application"))

                if ($Apps.Count -gt 0) {
                    $ApplicationsToProcess += $Apps
                    Write-Verbose "Loaded $($Apps.Count) application(s) from '$($XmlFile.Name)'"
                } else {
                    Write-Warning "No application nodes found in file: $($XmlFile.Name)"
                }
            } catch {
                Write-Warning "Failed to load XML file '$($XmlFile.Name)': $_"
                continue
            }
        }
    } else {
        Write-Error "XmlPath must be either a file or a directory."
        return
    }

    if ($ApplicationsToProcess.Count -eq 0) {
        Write-Warning "No applications found to process."
        return
    }

    $ItemsWithErrors = @()
    $TotalNumberOfItems = $ApplicationsToProcess.Count
    $Counter = 0
    Write-Verbose "Found $TotalNumberOfItems applications to process in the Ivanti Workspace Control XML."
    for ($i = 0; $i -lt $ApplicationsToProcess.Count; $i++) {
        $Counter++
        $Application = $ApplicationsToProcess[$i]
        Write-Progress -Activity "Processing Applications" -Status "Processing item $($Counter) of $($TotalNumberOfItems)" -CurrentOperation "Application: `"$($Application.configuration.title)`"" -PercentComplete (($Counter / $TotalNumberOfItems) * 100)
        $Enabled = $false
        $State = "Disabled"
        if ($Application.settings.enabled -eq "yes") {
            $Enabled = $true
            $State = "Enabled"
        }
        if ($Application.settings.enabled -eq "no" -or [string]::IsNullOrEmpty($Application.settings.enabled)) {
            $Enabled = $false
            $State = "Disabled"
        }
        $URL = ""
        $Parameters = "$($Application.configuration.parameters)"
        $CommandLine = "$($Application.configuration.commandline)"
        $WorkingDir = "$($Application.configuration.workingdir)"
        $DisplayName = "$($Application.configuration.title)"
        $Description = "$($Application.configuration.description)"

        $BinaryIconData = $null
        if (-not [string]::IsNullOrEmpty($($Application.configuration.icon32x256))) {
            $BinaryIconData = $($Application.configuration.icon32x256)
        } elseif (-not [string]::IsNullOrEmpty($($Application.configuration.icon32x16))) {
            $BinaryIconData = $($Application.configuration.icon32x16)
        } elseif (-not [string]::IsNullOrEmpty($($Application.configuration.icon16x16))) {
            $BinaryIconData = $($Application.configuration.icon16x16)
        }
        if (-not [string]::IsNullOrEmpty($BinaryIconData)) {
            $IconStream = Convert-BinaryIconToBase64 -IconData $BinaryIconData -Size 32
        } else {
            $IconStream = "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"
        }

        $StartMenuPath = "$($Application.configuration.menu)"
        if ($StartMenuPath -eq "") {
            $StartMenuPath = "Start Menu\Programs"
        } elseif ($StartMenuPath -like "Start\*") {
            $StartMenuPath = "Start Menu\Programs$($StartMenuPath.Substring(5))"
        }

        $Assignments = @()
        $AccessControl = $Application.accesscontrol
        $AccessItems = @($AccessControl.grouplist.group)
        if ($AccessControl.accesstype -eq "all") {
            $Assignments += [PSCustomObject]@{
                Sid  = "S-1-1-0"
                Name = "Everyone"
                Type = "group"
            }
        } elseif (($AccessControl.access_mode -ieq 'or' -and $AccessItems.Count -ge 1) -or
            ($AccessControl.access_mode -ieq 'and' -and $AccessItems.Count -eq 1)) {
            foreach ($AccessItem in $AccessItems) {
                if ($AccessControl.notgrouplist.group -contains $AccessItem) {
                    Write-Warning "Exclusion rules (notgrouplist) are currently not supported for application '$($Application.configuration.title)' (App is $($State))."
                    $ItemsWithErrors += $Application
                } elseif ($AccessItem.type -ne "group" -and $AccessItem.type -ne "user") {
                    Write-Warning "Unsupported object type '$($AccessItem.type)' for application '$($Application.configuration.title)'. Only 'group' or 'user' are supported."
                    $ItemsWithErrors += $Application
                } else {
                    $ObjectName = $AccessItem.'#text'
                    if ($ObjectName -like "*\*") {
                        $ObjectName = $ObjectName.Split("\")[1]
                    }
                    $Assignments += [PSCustomObject]@{
                        Sid  = $AccessItem.sid
                        Name = $ObjectName
                        Type = $AccessItem.type
                    }
                }
            }
            if ($Assignments.Count -eq 0) {
                $Assignments += [PSCustomObject]@{
                    Sid  = "S-1-1-0"
                    Name = "Everyone"
                    Type = "group"
                }
            }
        } else {
            Write-Warning "Unsupported access control mode '$($AccessControl.access_mode)' with $($AccessItems.Count) item(s) for application '$($Application.configuration.title)'."
            $ItemsWithErrors += $Application
        }
        $IsDesktop = $false
        if ($Application.configuration.desktop -ine "none" -and -not [string]::IsNullOrEmpty($($Application.configuration.desktop))) {
            $IsDesktop = $true
        }
        $isQuickLaunch = $false
        if ($Application.configuration.quicklaunch -ine "none" -and -not [string]::IsNullOrEmpty($($Application.configuration.quicklaunch))) {
            $isQuickLaunch = $true
        }

        $isStartMenu = $false
        if ($Application.configuration.createmenushortcut -ieq "yes") {
            $isStartMenu = $true
        }
        if ([string]::IsNullOrEmpty($workingDir)) {
            $workingDir = Split-Path -Path $CommandLine -Parent
        }

        $isAutoStart = $false
        if ($Application.settings.autoall -ine "no" -and -not [string]::IsNullOrEmpty($($Application.settings.autoall))) {
            $isAutoStart = $true
        }
        $WindowStyle = $Application.settings.startstyle
        if ([string]::IsNullOrEmpty($WindowStyle) -or $WindowStyle -like "nor*") {
            $WindowStyle = "Normal"
        } elseif ($WindowStyle -like "max*") {
            $WindowStyle = "Maximized"
        } elseif ($WindowStyle -like "min*") {
            $WindowStyle = "Minimized"
        } else {
            $WindowStyle = "Normal"
        }

        $Output = [PSCustomObject]@{
            Name                 = $DisplayName
            Enabled              = $Enabled
            WEMAssignments       = @($Assignments)
            WEMAssignmentParams  = [PSCustomObject]@{
                isAutoStart   = $IsAutoStart
                isDesktop     = $IsDesktop
                isQuickLaunch = $IsQuickLaunch
                isStartMenu   = $IsStartMenu
            }
            WEMApplicationParams = [PSCustomObject]@{
                startMenuPath = $StartMenuPath
                appType       = "InstallerApplication"
                state         = $State
                iconStream    = $IconStream
                parameter     = $Parameters
                description   = $Description
                name          = $DisplayName
                commandLine   = $CommandLine
                workingDir    = $WorkingDir
                url           = $URL
                displayName   = $DisplayName
                windowStyle   = $WindowStyle
                actionType    = "CreateAppShortcut"
            }
        }
        if ($AsJson) {
            $JsonOutput += $Output
        } else {
            Write-Output $Output
        }
    }
    Write-Progress -Activity "Processing Applications" -Completed
    Write-Verbose "Processing completed. Processed $TotalNumberOfItems applications."
    if ($AsJson) {
        Write-Verbose "Converting output to JSON format."
        return ($JsonOutput | ConvertTo-Json -Depth 5)
    }
}

# SIG # Begin signature block
# MIImdwYJKoZIhvcNAQcCoIImaDCCJmQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBqlBMU2GHozivS
# ShKypQkH2GSDB85gCaUnu9/273bs4aCCIAowggYUMIID/KADAgECAhB6I67aU2mW
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
# MC8GCSqGSIb3DQEJBDEiBCDH8nTHOfUNa6HKfGJ0niepeRPo0nwU5V0RilirpQzV
# 9DANBgkqhkiG9w0BAQEFAASCAYBcQnb0WJGqSRvbmtjrfoSCAJgMVSgnDk9X9b6t
# Dll6t32QtL9Am0uEEnX7ZzfbAQJalCXm1NfINxtVShX4JNXsYsM0E7CMb9iz98bm
# 3SJAZVDc+q+pArauxCgU/7IZYRUwmd/jx43X8+V8bfgiWaMeOtNBdWj02MieM2XM
# LmOjo3yWzkOyop1l4vg93HOzD0s8RZpycQN/7f0dZs5Vka3wboGQwGOSJBQGdz+n
# c5lzLpsW+cMG5IgeF5imVLt9nmLKlIJMOsK9LuggVy7Oi/B/9Bkpr6vsPiKtAoiG
# PNQ0yI8oIhXoCYO8q+a/c4pWzRqbIjGHjDyJr1/GbCr/AA6ZDAXtMutd1Y6SKhMH
# 5rAjMLJAXgf9YDX5t+PYR2/8D2NKd0pmZh3DQlramqaK1whKIEhLSPrE/Dr8AQhl
# qiM2ckvAFlsLYPZPc46l7vIXqqo2/dkuK+ikPo987MTLrGQcjXx0wBA3V6YNaVdO
# LeHyYUzaRIj6WeFMpcev1DOrAy2hggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwC
# AQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQp
# O24e3denNAiHrXpOtyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNTExMTEyMTMzMTlaMD8GCSqGSIb3
# DQEJBDEyBDAJ8MEowzxVMbEsz5BOmlV3r0q+WU61CbE7x5YdrmmeNgduFeSYIkef
# XI+tTZML3s0wDQYJKoZIhvcNAQEBBQAEggIAt6H+xY4bpEq0l6tJoziAoc2lW0LX
# kPY5DjNAaiTs4jfXD0YqR6ZYRcjd5yQ5pf+zPZRi2GsZYEI4v+GKh+tCuzl6ct1z
# POBEVtjzuO1OI1UCyp5rPQ1oQk6V/1/Jn5k8ywxCcFsTFme7CztPR+pTAberU1ru
# VHP2reE3egfULH7srAUIXRR8VYMC/NduEQBYFcbqDB+FpqcX8Ub7HnbIjWLfOMq0
# KlF6BAa7eWGJ3rbUfr7fmu2EsRsR9a4KfLClF0Qc4Az5QU64gfQ6/gD2xsUkAOE8
# eOdj5TwP6ilUzxGYyOuhC+Uh46i1Pqza4oCs4NPCzFvn1WYmfVwDJN0ALbZ89edM
# NZGICGFmcu9vU4WhDc9JrgQqEaiHGxLaAHTOo21wBuaKxIBS95WK0o2LsTn/TwQc
# BuAM9Wc8i6Qj937og0dU7IceZ2J++9BfVpXA8YppnkiMnN/Ubkon9DxDUJcdsmhs
# SpRAWUYK2fq5EUbif9YbOChHzV/7dYnPRSKBYAfuDiF+gg99+M6c6UnqhwI/Q4He
# 5E6q0rWZPEQg7hW+2XfSERfMBbNVq/bVfdZeqL4KvDqnjf+RN2UV5RVD2MOVAe3g
# t5UxnJTLhpCQtEUtIRurDuxkILAl4cKH2xwm7PvfInB2HpiDHIRJd/1V+IuUo1+Y
# WTGlrxT4U2XmrSk=
# SIG # End signature block
