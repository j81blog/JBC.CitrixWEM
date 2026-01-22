function Import-WEMRegistryFile {
    <#
    .SYNOPSIS
        Imports registry entries from a .reg file into WEM.
    .DESCRIPTION
        This function parses a Windows Registry (.reg) file and creates WEM Registry Entries
        for each value found. Only HKEY_CURRENT_USER entries are supported.
        Supports both Create and Delete registry actions. Delete entries in the .reg file
        (format: "ValueName"=-) are imported as Delete actions in WEM.
        Requires an active session established by Connect-WemApi.
    .PARAMETER Path
        The path to the .reg file to import.
    .PARAMETER SiteId
        The unique ID of the Configuration Set to import the Registry Entries into.
    .PARAMETER Prefix
        Optional prefix to add to the name of each imported registry entry.
        The name will be formatted as "<Prefix><ValueName>".
    .PARAMETER Tags
        Optional array of tags to associate with all imported Registry Entries.
    .PARAMETER Enabled
        When specified, the imported Registry Entries will be enabled.
    .PARAMETER RunOnce
        When specified, the registry action will only be applied once per user session.
    .PARAMETER DuplicateAction
        What to do when an item with the same name already exists.
        - KeepBoth: Create the new entry regardless (default)
        - Skip: Skip entries that already exist
    .PARAMETER PassThru
        If specified, returns the created registry entry objects.
    .EXAMPLE
        PS C:\> # First, connect to the API
        PS C:\> Connect-WemApi -CustomerId "abcdef123" -UseSdkAuthentication

        PS C:\> # Import a registry file
        PS C:\> Import-WEMRegistryFile -Path "C:\exports\settings.reg" -SiteId 7

    .EXAMPLE
        PS C:\> # Import with a prefix and tags
        PS C:\> Import-WEMRegistryFile -Path "C:\exports\settings.reg" -SiteId 7 -Prefix "App_" -Tags @("Production", "Settings")

    .EXAMPLE
        PS C:\> # Import but skip existing entries
        PS C:\> Import-WEMRegistryFile -Path "C:\exports\settings.reg" -SiteId 7 -DuplicateAction Skip

    .EXAMPLE
        PS C:\> # Import entries as enabled
        PS C:\> Import-WEMRegistryFile -Path "C:\exports\settings.reg" -SiteId 7 -Enabled

    .EXAMPLE
        PS C:\> # Import entries with RunOnce option
        PS C:\> Import-WEMRegistryFile -Path "C:\exports\settings.reg" -SiteId 7 -Enabled -RunOnce

    .EXAMPLE
        PS C:\> # Import a .reg file containing delete entries
        PS C:\> # If the .reg file contains entries like:
        PS C:\> # [HKEY_CURRENT_USER\Software\MyApp]
        PS C:\> # "OldSetting"=-
        PS C:\> # These will be imported as Delete actions in WEM
        PS C:\> Import-WEMRegistryFile -Path "C:\exports\cleanup.reg" -SiteId 7 -Enabled
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Claude
        Creation Date:  2026-01-20
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [Alias("FilePath", "FullName")]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $false)]
        [string]$Prefix,

        [Parameter(Mandatory = $false)]
        [string[]]$Tags,

        [Parameter(Mandatory = $false)]
        [switch]$Enabled,

        [Parameter(Mandatory = $false)]
        [switch]$RunOnce,

        [Parameter(Mandatory = $false)]
        [ValidateSet("KeepBoth", "Skip")]
        [string]$DuplicateAction = "KeepBoth",

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    begin {
        # Maximum number of entries allowed
        $MaxEntries = 1000

        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $ResolvedSiteId = 0
        if ($PSBoundParameters.ContainsKey('SiteId')) {
            $ResolvedSiteId = $SiteId
        } elseif ($Connection.ActiveSiteId) {
            $ResolvedSiteId = $Connection.ActiveSiteId
            Write-Verbose "Using active Configuration Set '$($Connection.ActiveSiteName)' (ID: $ResolvedSiteId)"
        } else {
            throw "No -SiteId was provided, and no active Configuration Set has been set. Please use Set-WEMActiveConfigurationSite or specify the -SiteId parameter."
        }

        # Get existing registry entries if we need to check for duplicates
        $ExistingEntries = @()
        if ($DuplicateAction -eq "Skip") {
            Write-Verbose "Retrieving existing registry entries to check for duplicates..."
            $ExistingEntries = @(Get-WEMRegistryEntry -SiteId $ResolvedSiteId)
            Write-Verbose "Found $($ExistingEntries.Count) existing registry entries."
        }

        $CreatedEntries = @()
    }

    process {
        try {
            # Read the reg file content
            $RegContent = Get-Content -Path $Path -Raw -Encoding Unicode -ErrorAction SilentlyContinue
            if ([string]::IsNullOrEmpty($RegContent)) {
                # Try reading as UTF8 or ANSI
                $RegContent = Get-Content -Path $Path -Raw -ErrorAction Stop
            }

            if ([string]::IsNullOrEmpty($RegContent)) {
                throw "The registry file is empty or could not be read."
            }

            # Validate it's a valid reg file
            if ($RegContent -notmatch '^\s*(Windows Registry Editor Version 5\.00|REGEDIT4)') {
                throw "The file does not appear to be a valid Windows Registry file. Expected 'Windows Registry Editor Version 5.00' or 'REGEDIT4' header."
            }

            # Parse the registry file
            $RegistryEntries = @()
            $CurrentPath = $null

            # Split into lines, handling both \r\n and \n
            $Lines = $RegContent -split '\r?\n'

            for ($i = 0; $i -lt $Lines.Count; $i++) {
                $Line = $Lines[$i].Trim()

                # Skip empty lines and comments
                if ([string]::IsNullOrWhiteSpace($Line) -or $Line.StartsWith(';')) {
                    continue
                }

                # Skip the header
                if ($Line -match '^(Windows Registry Editor Version 5\.00|REGEDIT4)$') {
                    continue
                }

                # Check for registry key path [HKEY_...]
                if ($Line -match '^\[(.+)\]$') {
                    $FullKeyPath = $Matches[1]

                    # Check if this is a delete key (starts with -)
                    if ($FullKeyPath.StartsWith('-')) {
                        Write-Verbose "Skipping delete key: $FullKeyPath"
                        $CurrentPath = $null
                        continue
                    }

                    # Only support HKEY_CURRENT_USER
                    if ($FullKeyPath -match '^HKEY_CURRENT_USER\\(.+)$') {
                        $CurrentPath = $Matches[1]
                        Write-Verbose "Processing key: HKEY_CURRENT_USER\$CurrentPath"
                    } elseif ($FullKeyPath -match '^HKCU\\(.+)$') {
                        $CurrentPath = $Matches[1]
                        Write-Verbose "Processing key: HKCU\$CurrentPath"
                    } else {
                        Write-Warning "Skipping unsupported registry hive: $FullKeyPath (only HKEY_CURRENT_USER is supported)"
                        $CurrentPath = $null
                    }
                    continue
                }

                # If we don't have a current path, skip this line
                if ($null -eq $CurrentPath) {
                    continue
                }

                # Parse registry value
                # Handle line continuation (lines ending with \)
                $FullLine = $Line
                while ($FullLine.EndsWith('\') -and ($i + 1) -lt $Lines.Count) {
                    $i++
                    $FullLine = $FullLine.TrimEnd('\') + $Lines[$i].Trim()
                }

                # Match value name and data
                # Format: "ValueName"=Type:Data or "ValueName"="StringData" or @=Data (default value)
                if ($FullLine -match '^"(.+)"=(.+)$' -or $FullLine -match '^@=(.+)$') {
                    if ($Matches.Count -eq 2) {
                        # Default value (@)
                        $ValueName = "(Default)"
                        $ValueData = $Matches[1]
                    } else {
                        $ValueName = $Matches[1]
                        $ValueData = $Matches[2]
                    }

                    # Check for delete value
                    $ActionType = "Create"
                    if ($ValueData -eq '-') {
                        # Delete value entry - no type or value needed
                        $ActionType = "Delete"
                        $RegistryEntry = [PSCustomObject]@{
                            TargetPath  = $CurrentPath
                            TargetName  = $ValueName
                            TargetType  = $null
                            TargetValue = $null
                            ActionType  = $ActionType
                        }
                        $RegistryEntries += $RegistryEntry
                        Write-Verbose "Found delete value entry: $ValueName"
                        continue
                    }

                    # Parse the value type and data
                    $TargetType = $null
                    $TargetValue = $null

                    if ($ValueData -match '^"(.*)"$') {
                        # REG_SZ (string)
                        $TargetType = "REG_SZ"
                        # Unescape the string value
                        $TargetValue = $Matches[1] -replace '\\\\', '\' -replace '\\"', '"'
                    } elseif ($ValueData -match '^dword:([0-9a-fA-F]+)$') {
                        # REG_DWORD
                        $TargetType = "REG_DWORD"
                        $TargetValue = [Convert]::ToInt64($Matches[1], 16)
                    } elseif ($ValueData -match '^qword:([0-9a-fA-F]+)$') {
                        # REG_QWORD
                        $TargetType = "REG_QWORD"
                        $TargetValue = [Convert]::ToInt64($Matches[1], 16)
                    } elseif ($ValueData -match '^hex\(2\):(.*)$') {
                        # REG_EXPAND_SZ (expandable string)
                        $TargetType = "REG_EXPAND_SZ"
                        $HexData = $Matches[1] -replace '\s', '' -replace ',', ''
                        $TargetValue = ConvertFrom-HexToString -HexString $HexData
                    } elseif ($ValueData -match '^hex\(7\):(.*)$') {
                        # REG_MULTI_SZ (multi-string)
                        $TargetType = "REG_MULTI_SZ"
                        $HexData = $Matches[1] -replace '\s', '' -replace ',', ''
                        $TargetValue = ConvertFrom-HexToString -HexString $HexData
                    } elseif ($ValueData -match '^hex\(0\):(.*)$') {
                        # REG_NONE
                        $TargetType = "REG_NONE"
                        $HexData = $Matches[1] -replace '\s', '' -replace ',', ''
                        $TargetValue = $HexData
                    } elseif ($ValueData -match '^hex\(b\):(.*)$') {
                        # REG_QWORD (alternative hex format)
                        $TargetType = "REG_QWORD"
                        $HexData = $Matches[1] -replace '\s', '' -replace ',', ''
                        # Convert little-endian hex bytes to QWORD
                        $Bytes = for ($j = 0; $j -lt $HexData.Length; $j += 2) {
                            [Convert]::ToByte($HexData.Substring($j, 2), 16)
                        }
                        $TargetValue = [BitConverter]::ToInt64($Bytes, 0)
                    } elseif ($ValueData -match '^hex:(.*)$') {
                        # REG_BINARY
                        $TargetType = "REG_BINARY"
                        $HexData = $Matches[1] -replace '\s', '' -replace ',', ''
                        $TargetValue = $HexData
                    } else {
                        Write-Warning "Skipping unsupported value format for '$ValueName': $ValueData"
                        continue
                    }

                    # Add to our list
                    $RegistryEntry = [PSCustomObject]@{
                        TargetPath  = $CurrentPath
                        TargetName  = $ValueName
                        TargetType  = $TargetType
                        TargetValue = $TargetValue
                        ActionType  = "Create"
                    }
                    $RegistryEntries += $RegistryEntry
                    Write-Verbose "Resulted in entry:$($RegistryEntry | Format-List | Out-String)"
                }
            }

            Write-Verbose "Parsed $($RegistryEntries.Count) registry entries from file."

            # Check for maximum entries limit
            if ($RegistryEntries.Count -gt $MaxEntries) {
                throw "The registry file contains $($RegistryEntries.Count) entries, which exceeds the maximum limit of $MaxEntries entries."
            }

            if ($RegistryEntries.Count -eq 0) {
                Write-Warning "No HKEY_CURRENT_USER registry entries found in the file."
                return
            }

            Write-Host "Found $($RegistryEntries.Count) registry entries to import." -ForegroundColor Cyan

            # Create the registry entries in WEM
            $SuccessCount = 0
            $SkipCount = 0
            $ErrorCount = 0

            foreach ($Entry in $RegistryEntries) {
                # Build the display name
                $DisplayName = $Entry.TargetName
                if ($PSBoundParameters.ContainsKey('Prefix') -and -not [string]::IsNullOrEmpty($Prefix)) {
                    $DisplayName = "$Prefix$DisplayName"
                }

                # Check for duplicates
                if ($DuplicateAction -eq "Skip") {
                    $Existing = $ExistingEntries | Where-Object {
                        $_.name -eq $DisplayName -and
                        $_.targetPath -eq $Entry.TargetPath -and
                        $_.targetName -eq $Entry.TargetName
                    }
                    if ($Existing) {
                        Write-Verbose "Skipping duplicate entry: $DisplayName ($($Entry.TargetPath)\$($Entry.TargetName))"
                        $SkipCount++
                        continue
                    }
                }

                $ActionVerb = if ($Entry.ActionType -eq "Delete") { "Delete" } else { "Create" }
                $TargetDescription = "Registry Entry '$DisplayName' at '$($Entry.TargetPath)\$($Entry.TargetName)'"
                if ($PSCmdlet.ShouldProcess($TargetDescription, "$ActionVerb Registry Entry")) {
                    try {
                        $Params = @{
                            SiteId      = $ResolvedSiteId
                            TargetPath  = $Entry.TargetPath
                            TargetName  = $Entry.TargetName
                            Name        = $DisplayName
                            ActionType  = $Entry.ActionType
                        }

                        # Only add TargetType and TargetValue for Create actions
                        if ($Entry.ActionType -eq "Create") {
                            $Params.TargetType  = $Entry.TargetType
                            $Params.TargetValue = $Entry.TargetValue
                        }

                        if ($Enabled.IsPresent) {
                            $Params.Enabled = $true
                        }

                        if ($RunOnce.IsPresent) {
                            $Params.RunOnce = $true
                        }

                        if ($PSBoundParameters.ContainsKey('Tags') -and $null -ne $Tags -and $Tags.Count -gt 0) {
                            Write-Verbose "Assigning tags: $($Tags -join ', ')"
                            $Params.Tags = $Tags
                        }
                        try {
                            New-WEMRegistryEntry @Params
                            $TypeInfo = if ($Entry.ActionType -eq "Delete") { "Delete" } else { $Entry.TargetType }
                            Write-Host "Created: [$($Entry.ActionType)] $DisplayName ($TypeInfo)" -ForegroundColor Green
                            $SuccessCount++
                            $CreatedEntries += $Result
                        } catch {
                            Write-Warning "Failed to create: $DisplayName"
                            $ErrorCount++
                        }
                    } catch {
                        Write-Error "Error creating '$DisplayName': $($_.Exception.Message)"
                        $ErrorCount++
                    }
                }
            }

            # Summary
            Write-Host ""
            Write-Host "Import Summary:" -ForegroundColor Cyan
            Write-Host "  Created: $SuccessCount" -ForegroundColor Green
            if ($SkipCount -gt 0) {
                Write-Host "  Skipped (duplicates): $SkipCount" -ForegroundColor Yellow
            }
            if ($ErrorCount -gt 0) {
                Write-Host "  Errors: $ErrorCount" -ForegroundColor Red
            }

        } catch {
            Write-Error "Failed to import registry file: $($_.Exception.Message)"
        }
    }

    end {
        if ($PassThru -and $CreatedEntries.Count -gt 0) {
            Write-Output $CreatedEntries
        }
    }
}

# SIG # Begin signature block
# MIImdwYJKoZIhvcNAQcCoIImaDCCJmQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB6LA+DAdWQHIHw
# G/9Ee+r5IZYyWhKA6M3r9Vesd8O7cKCCIAowggYUMIID/KADAgECAhB6I67aU2mW
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
# MC8GCSqGSIb3DQEJBDEiBCDA/JoeY5faq/CHQv4HsGC3uuzdABvPVZQ9/6YXxqNC
# sDANBgkqhkiG9w0BAQEFAASCAYAjl5JYQjrAWjmQ1qtBbHC41Liipp0SplVG1uFh
# zku/wGgFhYHv709GXO8FeNDt8ZB9icU94gn+M0LFOyzo6F64Jv5cIgicHsW186QW
# TCcc28423X/Ny+e0kGBeEUjyhfKpJmAY5rWU15hBlEYE82aoOVo3w4t58oQWWg2L
# tgv7glMSQqw7SoP9dmB781M2aNgCIE18DVUK/jG9jn7ljUlIYCnbD54gpwx951jB
# vqqnd3v6NROpLoovbCQ7vSPPTXz4xJW9PFL9MsxlnXWY4lQUrq4p01cNp2zFuOsq
# oUnm7BDGsGnr40/M+NPnWGOOUT+tN1bbg28Mp4NVdNgore/kX3aBHOAxwe34Z2iG
# LcMrYtNaCoDQepqlqtFhCPQeytP4EkV/f6WcBLMi3pfwmFmJiFTNXdr24C4J5ZRM
# FfNUWanjYjc8wT8RlO/25Jva6Kca9ugIvGufqdVOlZeWVjZQmxQVQanEVzIOaOJa
# OA3cnjvY7uii3J/PYFB99IYuvJqhggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwC
# AQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQp
# O24e3denNAiHrXpOtyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAxMjAyMjM3MTRaMD8GCSqGSIb3
# DQEJBDEyBDBOlrU9npznZpYdG2hacKqB4ZwKdYheZAy3DxZ3Y1mJloLv3dW6L5gs
# bVKcxQdNQKMwDQYJKoZIhvcNAQEBBQAEggIApoX3EEBSkEbmFj7Z243S3WXvaiGZ
# V1hzKx6d0yidkFAaN0XgwhaHXbAMWTj/zpQTIuoaIvTraesoB1tQyhgWVCxmgoPl
# 7RQzoml0Tkl/i4oK7bhgovbRcCvAZNSXZpSe6Ul1oNM3GHoF1KHLd+6y05sXt2zn
# oaO2yZGhYuet7/orNS6ZSyLIVSd10jAlnrztRh4wgCn/jwOze9VDACBLxoJM0Ixo
# bvfPLjzJJYUQ4hyuAGNgd+n5cWdj6SnERFcxjOIS55tZoZAMkvXgpNm7VcmiUhzt
# V326jLqoZHE0AOC1csxEmd00CW+jRt2yqMexo2B1+/y2hoZc3JGANCtLcCwjSPS6
# UZ7JBU7trMDW+Xkn5Pc4FQuLhq7OqGsfHJO6bJIlr55EwIOQb8JCP8gvR6T8mT9Z
# MmgmphU45fTGnkzDyz/BFYHlGMbh40U1YuyiRdPm+VVGTHwvuy8zS2IX43bnM8qk
# BZgzz/hiOaGgMJZ5yOjNTQwgKwEh7zoIXzgVDMt+OAdzTrD27dCKDFAO8M8tQhF9
# GOS3UdVJRwUZ6uiTjryjFOJ4Xde3Yim8QpUAhstXXzkxC2mI5KEmfdar1PE8ZXS0
# OA7ajzWM0slr40CgkgX/KA6N07TF+VhQR81UyezZ+2KiwDJuuHogWMa+7Yjgax2h
# 5cni9D56Ra/qwk8=
# SIG # End signature block
