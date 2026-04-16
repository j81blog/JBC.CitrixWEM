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
                        $TargetValue = [array](ConvertFrom-HexToString -HexString $HexData -split '\0' | Where-Object { $_ })
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
# MII6BgYJKoZIhvcNAQcCoII59zCCOfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAVx07JJzt9BwX4
# RB50UhJCNfTB8to4quZpiewDok/SZ6CCIiowggXMMIIDtKADAgECAhBUmNLR1FsZ
# lUgTecgRwIeZMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDA0MTYxODM2MTZaFw00NTA0MTYxODQ0NDBaMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALORKgeD
# Bmf9np3gx8C3pOZCBH8Ppttf+9Va10Wg+3cL8IDzpm1aTXlT2KCGhFdFIMeiVPvH
# or+Kx24186IVxC9O40qFlkkN/76Z2BT2vCcH7kKbK/ULkgbk/WkTZaiRcvKYhOuD
# PQ7k13ESSCHLDe32R0m3m/nJxxe2hE//uKya13NnSYXjhr03QNAlhtTetcJtYmrV
# qXi8LW9J+eVsFBT9FMfTZRY33stuvF4pjf1imxUs1gXmuYkyM6Nix9fWUmcIxC70
# ViueC4fM7Ke0pqrrBc0ZV6U6CwQnHJFnni1iLS8evtrAIMsEGcoz+4m+mOJyoHI1
# vnnhnINv5G0Xb5DzPQCGdTiO0OBJmrvb0/gwytVXiGhNctO/bX9x2P29Da6SZEi3
# W295JrXNm5UhhNHvDzI9e1eM80UHTHzgXhgONXaLbZ7LNnSrBfjgc10yVpRnlyUK
# xjU9lJfnwUSLgP3B+PR0GeUw9gb7IVc+BhyLaxWGJ0l7gpPKWeh1R+g/OPTHU3mg
# trTiXFHvvV84wRPmeAyVWi7FQFkozA8kwOy6CXcjmTimthzax7ogttc32H83rwjj
# O3HbbnMbfZlysOSGM1l0tRYAe1BtxoYT2v3EOYI9JACaYNq6lMAFUSw0rFCZE4e7
# swWAsk0wAly4JoNdtGNz764jlU9gKL431VulAgMBAAGjVDBSMA4GA1UdDwEB/wQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTIftJqhSobyhmYBAcnz1AQ
# T2ioojAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQwFAAOCAgEAr2rd5hnn
# LZRDGU7L6VCVZKUDkQKL4jaAOxWiUsIWGbZqWl10QzD0m/9gdAmxIR6QFm3FJI9c
# Zohj9E/MffISTEAQiwGf2qnIrvKVG8+dBetJPnSgaFvlVixlHIJ+U9pW2UYXeZJF
# xBA2CFIpF8svpvJ+1Gkkih6PsHMNzBxKq7Kq7aeRYwFkIqgyuH4yKLNncy2RtNwx
# AQv3Rwqm8ddK7VZgxCwIo3tAsLx0J1KH1r6I3TeKiW5niB31yV2g/rarOoDXGpc8
# FzYiQR6sTdWD5jw4vU8w6VSp07YEwzJ2YbuwGMUrGLPAgNW3lbBeUU0i/OxYqujY
# lLSlLu2S3ucYfCFX3VVj979tzR/SpncocMfiWzpbCNJbTsgAlrPhgzavhgplXHT2
# 6ux6anSg8Evu75SjrFDyh+3XOjCDyft9V77l4/hByuVkrrOj7FjshZrM77nq81YY
# uVxzmq/FdxeDWds3GhhyVKVB0rYjdaNDmuV3fJZ5t0GNv+zcgKCf0Xd1WF81E+Al
# GmcLfc4l+gcK5GEh2NQc5QfGNpn0ltDGFf5Ozdeui53bFv0ExpK91IjmqaOqu/dk
# ODtfzAzQNb50GQOmxapMomE2gj4d8yu8l13bS3g7LfU772Aj6PXsCyM2la+YZr9T
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbCMIIEqqADAgECAhMzAABWh4wS
# B8KYYL2uAAAAAFaHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNDE0MjExOTE0WhcNMjYwNDE3
# MjExOTE0WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Y6MEBzN5XmjmQCUBmrWP3Xv
# 3kqEH4vtMaEMUsDJnl9lgweqe71Z5LQiuq0PapngjF/YRk95c8rqxtQJRMFvsnkv
# snlFeBZCsPPOzSbRUnlkyHLDQmOc9nKI/KFbqmkds70bB2z+gLQVkEZepiMgApJH
# y/eODoUZTXv58Yl4DFFdEvwW/TyC0vOI112mqqFCyN653yeBLDJ8LMvTvEvEaBih
# OXU0zNV1y52HvqIWg2h+e5WWaB2yL7locAD4dub1ZinnnRYochg5egSx41hHZDwe
# dcDyvzihq5IdqB3IeFnN5+kByQbLajYmXK+xy8G1QnIjMorDLx2+xWFBdzkOeKdF
# lPnHTAEFqlpqBFlNSU2axvcXUCJmgMVLjNW2lDNVzdpD1pgJpg+SBz7XBQ96IxVj
# TBKmLcoAlurLXPN0nzyDaAhja17p1zSFBR0idEi/T6Pr++HanksyVQLIpe0A/k8F
# zkLtGLeLOknRmsOC5gOT7nvGa8fUyWTptZJ3JohPAgMBAAGjggHVMIIB0TAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0GA1UdDgQW
# BBRPZasnKEZjDvsbRxzbBI296OsPPzAfBgNVHSMEGDAWgBSa8VR3dQyHFjdGoKze
# efn0f8F46TBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBF
# T0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUHMAKGWGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# SUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwNC5jcnQwVAYDVR0gBE0w
# SzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwFAAOCAgEA
# PH2f5SqSZRvE8G4BSeLiAJmu6YZ9MjnxZuMLlgjBRPX1/NF2oQ3U6OOK16b9Z6Cd
# Y/LCzdhDI1Dtvp36745TzKhUt3jCxONo5zFKbDlja/nR7Vly3qeKyQqop5hxzlEM
# xv3jSBBOLJUa5MppzjnYJEX7zInegb9213At3+fjYRNE2ZN5PwAdgo3jx2jHKIUE
# RVp3zMB2nwFEa6WPSL0rL5Qgu+jSXZDcZzBn8knxUTuMIHEAm3inxSsc7Kuy0Xw7
# eIPVndyZMC44RAbuMKWN2wv6FZJzecIfglGRamh/lpmgZLTHiTHmdkK/2mvAfQ6v
# cSHcngb3LYNGXkB0/BZf4PwTKL/vMLeaetQqyA+LuNXN20A6NSsE859WMNT/JjUU
# UJvF+3WUJ0mn2ufw79pLQyWAdXCHPaaDFLBlnGnN68eQ6w5tBOIxaFaPEtvCkBQ2
# c3QqHaiZS4FfLvP/XraDGEo8zALrYdWRaQxfUO+x2lo0/rn+d0BQoZPlc6c8KaIC
# RjzZDx6YqVlY1r4rWGzzWUkabduS7hsr1XM8l+OsD9gKI59ISz154ksW3NKtraSj
# z5GZFvgZB81TfXfbQmvdjXApiflx2HQ/ny3uLTiQGov+Zu5trrNTZsEJc3OGnVii
# Xx/vHOTUzGM4VgleXuALu9LifQxcgrVbZ39bw7vMGLowggbCMIIEqqADAgECAhMz
# AABWh4wSB8KYYL2uAAAAAFaHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jv
# c29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNDE0MjExOTE0WhcN
# MjYwNDE3MjExOTE0WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJy
# YWJhbnQxEjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtl
# bnMgQ29uc3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRh
# bmN5MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Y6MEBzN5XmjmQCU
# BmrWP3Xv3kqEH4vtMaEMUsDJnl9lgweqe71Z5LQiuq0PapngjF/YRk95c8rqxtQJ
# RMFvsnkvsnlFeBZCsPPOzSbRUnlkyHLDQmOc9nKI/KFbqmkds70bB2z+gLQVkEZe
# piMgApJHy/eODoUZTXv58Yl4DFFdEvwW/TyC0vOI112mqqFCyN653yeBLDJ8LMvT
# vEvEaBihOXU0zNV1y52HvqIWg2h+e5WWaB2yL7locAD4dub1ZinnnRYochg5egSx
# 41hHZDwedcDyvzihq5IdqB3IeFnN5+kByQbLajYmXK+xy8G1QnIjMorDLx2+xWFB
# dzkOeKdFlPnHTAEFqlpqBFlNSU2axvcXUCJmgMVLjNW2lDNVzdpD1pgJpg+SBz7X
# BQ96IxVjTBKmLcoAlurLXPN0nzyDaAhja17p1zSFBR0idEi/T6Pr++HanksyVQLI
# pe0A/k8FzkLtGLeLOknRmsOC5gOT7nvGa8fUyWTptZJ3JohPAgMBAAGjggHVMIIB
# 0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEE
# AYI3YQEABggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0G
# A1UdDgQWBBRPZasnKEZjDvsbRxzbBI296OsPPzAfBgNVHSMEGDAWgBSa8VR3dQyH
# FjdGoKzeefn0f8F46TBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIw
# Q1MlMjBFT0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUH
# MAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9z
# b2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwNC5jcnQwVAYD
# VR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwF
# AAOCAgEAPH2f5SqSZRvE8G4BSeLiAJmu6YZ9MjnxZuMLlgjBRPX1/NF2oQ3U6OOK
# 16b9Z6CdY/LCzdhDI1Dtvp36745TzKhUt3jCxONo5zFKbDlja/nR7Vly3qeKyQqo
# p5hxzlEMxv3jSBBOLJUa5MppzjnYJEX7zInegb9213At3+fjYRNE2ZN5PwAdgo3j
# x2jHKIUERVp3zMB2nwFEa6WPSL0rL5Qgu+jSXZDcZzBn8knxUTuMIHEAm3inxSsc
# 7Kuy0Xw7eIPVndyZMC44RAbuMKWN2wv6FZJzecIfglGRamh/lpmgZLTHiTHmdkK/
# 2mvAfQ6vcSHcngb3LYNGXkB0/BZf4PwTKL/vMLeaetQqyA+LuNXN20A6NSsE859W
# MNT/JjUUUJvF+3WUJ0mn2ufw79pLQyWAdXCHPaaDFLBlnGnN68eQ6w5tBOIxaFaP
# EtvCkBQ2c3QqHaiZS4FfLvP/XraDGEo8zALrYdWRaQxfUO+x2lo0/rn+d0BQoZPl
# c6c8KaICRjzZDx6YqVlY1r4rWGzzWUkabduS7hsr1XM8l+OsD9gKI59ISz154ksW
# 3NKtraSjz5GZFvgZB81TfXfbQmvdjXApiflx2HQ/ny3uLTiQGov+Zu5trrNTZsEJ
# c3OGnViiXx/vHOTUzGM4VgleXuALu9LifQxcgrVbZ39bw7vMGLowggcoMIIFEKAD
# AgECAhMzAAAAFydFCQuLh6/GAAAAAAAXMA0GCSqGSIb3DQEBDAUAMGMxCzAJBgNV
# BAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMT
# K01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2RlIFNpZ25pbmcgUENBIDIwMjEwHhcN
# MjYwMzI2MTgxMTMxWhcNMzEwMzI2MTgxMTMxWjBaMQswCQYDVQQGEwJVUzEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQg
# SUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEAgsdk/gMPZioBlcyfk6tDzJ+PRt4rSLGKW8ewpS0kRxXtURC3T3Gd
# bCKljobEn8ussqhGqQpRh/SXvRVwNXEIGb76UG5IPkCJ1S6/9BD61QQsKzPepW0S
# Nj8TXgsFxvS7MltoRuikIIp7Q5jQgaOM6QyK9++6ZVXUpYmZulAe6x8JrwZ0dNkE
# +rZ66lqtoocwepUSVUxM7odDmn8yDHjJ2DNPsfr3uRDix3X4qvh14jH/SW+2Cx7W
# IMhyIiQO201i6hUixmk4e2ZW8W7C1wPdTjq6BKb+zo8xbrt7ZKQvRX5QOA6dhLqu
# Pqj5sVKnxqfk19IC0SafTSTs8yC43Ew965BRRW8VL9ccoOmr4rxQy7aCgYTNk3dd
# /LphNaTTmnGp7kmLTxyHkB5geoWhYuuGrywS8E0wJv0W4rfOtHBV0e9sKvuUIeIU
# pnsx6ilxEVj6VQXvgD6yeCKnPmj3jJiJKAlmUDtth5yzRVBUl44sMiG4L5R/yyAC
# RKk2n088Q2YCoZS1O86+oMLKt1jaXGECOjbsVp8Id1VQw8he6J0KirOS5e25XlTd
# GPFb6oBOOaacgW78Kjf0bp+XzAgkc92mDGNJGYSjvdnj+7eMx6meW0DAIGdLRNj8
# /429MIspFBfz3KDqqpN71S4kQ2LLer3dxhDDczKVFL0HLwRuOvgjiG8CAwEAAaOC
# AdwwggHYMA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4E
# FgQUmvFUd3UMhxY3RqCs3nn59H/BeOkwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYI
# KwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9S
# ZXBvc2l0b3J5Lmh0bTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTASBgNVHRMB
# Af8ECDAGAQH/AgEAMB8GA1UdIwQYMBaAFNlBKbAPD2Ns72nX9c0pnqRIajDmMHAG
# A1UdHwRpMGcwZaBjoGGGX2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUy
# MFBDQSUyMDIwMjEuY3JsMH0GCCsGAQUFBwEBBHEwbzBtBggrBgEFBQcwAoZhaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJ
# RCUyMFZlcmlmaWVkJTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDIxLmNydDAN
# BgkqhkiG9w0BAQwFAAOCAgEAkHVaGf1NJt/JdoimmRZbMWr6baaDi8mkdWvWStk0
# hdZDpxSYTA7HuipAoLL3qIhI101XOl7fOiCh5++jZOamQdAV79ojEUNoIgCZmL2X
# JrLaGanwdjNynecJyYVCTrRf2+h7KknpWOp4axdOs6K9ZQ5g0IsQWXCwfc0dfkSk
# LKNY3pDcWLlJPh2jd5NUue6pNDv/2G5MFNJhCwltODebyAjGceU+XOzav+7i721Y
# QnQ+39m2aQOFO7zpAdaKAeAGhEd6Y6CdDGneSxcoujWvafWbv4ay3jo1ORSLUuWM
# bKr5X18QE4Sde+gppGLLSkZsrUh2eyYSkX1envWX7ZPzg2/wiuKRlQFarDn+N9+2
# 0BqzhxwkNyLzfYJp1Lg4fCXb24XqFjx8SDdRgebFImOfOLVze8XQ/CwkrEaib0PH
# u2t4GVk4FYroEbNUFqvjdBvTY3uiR5TdQoyXoYHvh+TxpLSY2vo7hhK9D/rpEpHC
# +qmmcRUE4d0gyO9Zb1vvt25fxM3ekjvDfVHcPq3qMr0Rwsk4krKZWUEgU1SXT5qN
# 6gqRrshxbT6OQgZ9/xT04qiXdzPQR6KindBvSpoOnxnALxcJyzVwNpKL+9u8EZYy
# 98qX6i+4gE/2J6cbpekcB0ZXDn/XQxoNUUb6/djT/wllVyG+vIHkdq71PzbH5rYx
# dcAwggeeMIIFhqADAgECAhMzAAAAB4ejNKN7pY4cAAAAAAAHMA0GCSqGSIb3DQEB
# DAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAyMDAeFw0yMTA0MDEyMDA1MjBaFw0z
# NjA0MDEyMDE1MjBaMGMxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xNDAyBgNVBAMTK01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2Rl
# IFNpZ25pbmcgUENBIDIwMjEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCy8MCvGYgo4t1UekxJbGkIVQm0Uv96SvjB6yUo92cXdylN65Xy96q2YpWCiTas
# 7QPTkGnK9QMKDXB2ygS27EAIQZyAd+M8X+dmw6SDtzSZXyGkxP8a8Hi6EO9Zcwh5
# A+wOALNQbNO+iLvpgOnEM7GGB/wm5dYnMEOguua1OFfTUITVMIK8faxkP/4fPdEP
# CXYyy8NJ1fmskNhW5HduNqPZB/NkWbB9xxMqowAeWvPgHtpzyD3PLGVOmRO4ka0W
# csEZqyg6efk3JiV/TEX39uNVGjgbODZhzspHvKFNU2K5MYfmHh4H1qObU4JKEjKG
# sqqA6RziybPqhvE74fEp4n1tiY9/ootdU0vPxRp4BGjQFq28nzawuvaCqUUF2PWx
# h+o5/TRCb/cHhcYU8Mr8fTiS15kRmwFFzdVPZ3+JV3s5MulIf3II5FXeghlAH9Cv
# icPhhP+VaSFW3Da/azROdEm5sv+EUwhBrzqtxoYyE2wmuHKws00x4GGIx7NTWznO
# m6x/niqVi7a/mxnnMvQq8EMse0vwX2CfqM7Le/smbRtsEeOtbnJBbtLfoAsC3TdA
# OnBbUkbUfG78VRclsE7YDDBUbgWt75lDk53yi7C3n0WkHFU4EZ83i83abd9nHWCq
# fnYa9qIHPqjOiuAgSOf4+FRcguEBXlD9mAInS7b6V0UaNwIDAQABo4ICNTCCAjEw
# DgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTZQSmw
# Dw9jbO9p1/XNKZ6kSGow5jBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUyH7SaoUqG8oZmAQHJ89QEE9oqKIwgYQGA1UdHwR9MHsw
# eaB3oHWGc2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jv
# c29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmlj
# YXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcmwwgcMGCCsGAQUFBwEBBIG2MIGzMIGB
# BggrBgEFBQcwAoZ1aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0
# cy9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBD
# ZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3J0MC0GCCsGAQUFBzABhiFo
# dHRwOi8vb25lb2NzcC5taWNyb3NvZnQuY29tL29jc3AwDQYJKoZIhvcNAQEMBQAD
# ggIBAH8lKp7+1Kvq3WYK21cjTLpebJDjW4ZbOX3HD5ZiG84vjsFXT0OB+eb+1TiJ
# 55ns0BHluC6itMI2vnwc5wDW1ywdCq3TAmx0KWy7xulAP179qX6VSBNQkRXzReFy
# jvF2BGt6FvKFR/imR4CEESMAG8hSkPYso+GjlngM8JPn/ROUrTaeU/BRu/1RFESF
# VgK2wMz7fU4VTd8NXwGZBe/mFPZG6tWwkdmA/jLbp0kNUX7elxu2+HtHo0QO5gdi
# KF+YTYd1BGrmNG8sTURvn09jAhIUJfYNotn7OlThtfQjXqe0qrimgY4Vpoq2MgDW
# 9ESUi1o4pzC1zTgIGtdJ/IvY6nqa80jFOTg5qzAiRNdsUvzVkoYP7bi4wLCj+ks2
# GftUct+fGUxXMdBUv5sdr0qFPLPB0b8vq516slCfRwaktAxK1S40MCvFbbAXXpAZ
# nU20FaAoDwqq/jwzwd8Wo2J83r7O3onQbDO9TyDStgaBNlHzMMQgl95nHBYMelLE
# HkUnVVVTUsgC0Huj09duNfMaJ9ogxhPNThgq3i8w3DAGZ61AMeF0C1M+mU5eucj1
# Ijod5O2MMPeJQ3/vKBtqGZg4eTtUHt/BPjN74SsJsyHqAdXVS5c+ItyKWg3Eforh
# ox9k3WgtWTpgV4gkSiS4+A09roSdOI4vrRw+p+fL4WrxSK5nMYIXMjCCFy4CAQEw
# cTBaMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSswKQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0AhMz
# AABWh4wSB8KYYL2uAAAAAFaHMA0GCWCGSAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIB
# DDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# ICFOT20dKhe3LuqypIF3E/LfqrfCUhahXsZuFs9CIUfVMA0GCSqGSIb3DQEBAQUA
# BIIBgCVppSDG5WTM+cYtStN9Gna04vQzIpu5tCeunhmubfRK8/UQfdaa6vRLT4PN
# kzOzyp0p56NmFbfnobz/8QhU0Ec8/PTEVLPNwaeQ9W28XYTLTF9NpOfSwq4r28kN
# N/UnOcFPPuyJiEORHKG7dFSTJgyy13/IO/VEfIwXMg6ZsemmpLU7oCMcVzUOTaRf
# gX8ynPdTaX0MgiiZI/BeNb95vbbs8BR/gScJRJg7yEYTaXf0LV/qpCE++hX7JK64
# fRs2zCZ+39g+ABlHTM6yvOuFKlimdnKCHF8jX7x6XtdLozR/b8nKyjJTNNGxBZ0D
# hTMSE1VloDtuZHRSaFkavcl9wtwQgVBRjO66JangvGqc8P9ASlOKYnRvd2L7KaGb
# xdnKgIq8juLIX4KHiLaEVA3wqndZCJBF//3Q0qbABYz0gKXi7WPolcG9IU1G4mr/
# Pcw0yhAvajM/6wICrZs//enzs1b2h/LfOXajI4Bc099OvxM2KLL/Pmz0vFBa6eLf
# 51Pc1KGCFLIwghSuBgorBgEEAYI3AwMBMYIUnjCCFJoGCSqGSIb3DQEHAqCCFIsw
# ghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFqBgsqhkiG9w0BCRABBKCCAVkEggFV
# MIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBXuPuzWBIpcpnG
# uDgyYmSyYX9YUDZJNyOENz4VrO1yWAIGacZuNO2YGBMyMDI2MDQxNTE5NTg0Ny41
# NThaMASAAgH0oIHppIHmMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3QTFBLTA1RTAtRDk0NzE1
# MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRo
# b3JpdHmggg8pMIIHgjCCBWqgAwIBAgITMwAAAAXlzw//Zi7JhwAAAAAABTANBgkq
# hkiG9w0BAQwFADB3MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMUgwRgYDVQQDEz9NaWNyb3NvZnQgSWRlbnRpdHkgVmVyaWZpY2F0
# aW9uIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMjAwHhcNMjAxMTE5MjAz
# MjMxWhcNMzUxMTE5MjA0MjMxWjBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJT
# QSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBAJ5851Jj/eDFnwV9Y7UGIqMcHtfnlzPREwW9ZUZHd5HBXXBvf7KrQ5cM
# SqFSHGqg2/qJhYqOQxwuEQXG8kB41wsDJP5d0zmLYKAY8Zxv3lYkuLDsfMuIEqvG
# YOPURAH+Ybl4SJEESnt0MbPEoKdNihwM5xGv0rGofJ1qOYSTNcc55EbBT7uq3wx3
# mXhtVmtcCEr5ZKTkKKE1CxZvNPWdGWJUPC6e4uRfWHIhZcgCsJ+sozf5EeH5KrlF
# nxpjKKTavwfFP6XaGZGWUG8TZaiTogRoAlqcevbiqioUz1Yt4FRK53P6ovnUfANj
# IgM9JDdJ4e0qiDRm5sOTiEQtBLGd9Vhd1MadxoGcHrRCsS5rO9yhv2fjJHrmlQ0E
# IXmp4DhDBieKUGR+eZ4CNE3ctW4uvSDQVeSp9h1SaPV8UWEfyTxgGjOsRpeexIve
# R1MPTVf7gt8hY64XNPO6iyUGsEgt8c2PxF87E+CO7A28TpjNq5eLiiunhKbq0Xbj
# kNoU5JhtYUrlmAbpxRjb9tSreDdtACpm3rkpxp7AQndnI0Shu/fk1/rE3oWsDqMX
# 3jjv40e8KN5YsJBnczyWB4JyeeFMW3JBfdeAKhzohFe8U5w9WuvcP1E8cIxLoKSD
# zCCBOu0hWdjzKNu8Y5SwB1lt5dQhABYyzR3dxEO/T1K/BVF3rV69AgMBAAGjggIb
# MIICFzAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYE
# FGtpKDo1L0hjQM972K9J6T7ZPdshMFQGA1UdIARNMEswSQYEVR0gADBBMD8GCCsG
# AQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVw
# b3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAwe
# CgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTIftJqhSob
# yhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHegdYZzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSWRlbnRpdHklMjBWZXJp
# ZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBBdXRob3JpdHklMjAyMDIw
# LmNybDCBlAYIKwYBBQUHAQEEgYcwgYQwgYEGCCsGAQUFBzAChnVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElkZW50aXR5
# JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5
# JTIwMjAyMC5jcnQwDQYJKoZIhvcNAQEMBQADggIBAF+Idsd+bbVaFXXnTHho+k7h
# 2ESZJRWluLE0Oa/pO+4ge/XEizXvhs0Y7+KVYyb4nHlugBesnFqBGEdC2IWmtKMy
# S1OWIviwpnK3aL5JedwzbeBF7POyg6IGG/XhhJ3UqWeWTO+Czb1c2NP5zyEh89F7
# 2u9UIw+IfvM9lzDmc2O2END7MPnrcjWdQnrLn1Ntday7JSyrDvBdmgbNnCKNZPmh
# zoa8PccOiQljjTW6GePe5sGFuRHzdFt8y+bN2neF7Zu8hTO1I64XNGqst8S+w+RU
# die8fXC1jKu3m9KGIqF4aldrYBamyh3g4nJPj/LR2CBaLyD+2BuGZCVmoNR/dSpR
# Cxlot0i79dKOChmoONqbMI8m04uLaEHAv4qwKHQ1vBzbV/nG89LDKbRSSvijmwJw
# xRxLLpMQ/u4xXxFfR4f/gksSkbJp7oqLwliDm/h+w0aJ/U5ccnYhYb7vPKNMN+SZ
# DWycU5ODIRfyoGl59BsXR/HpRGtiJquOYGmvA/pk5vC1lcnbeMrcWD/26ozePQ/T
# WfNXKBOmkFpvPE8CH+EeGGWzqTCjdAsno2jzTeNSxlx3glDGJgcdz5D/AAxw9Sdg
# q/+rY7jjgs7X6fqPTXPmaCAJKVHAP19oEjJIBwD1LyHbaEgBxFCogYSOiUIr0Xqc
# r1nJfiWG2GwYe6ZoAF1bMIIHnzCCBYegAwIBAgITMwAAAFtKtY1BMm3cdAAAAAAA
# WzANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBU
# aW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjAxMDgxODU5MDVaFw0yNzAxMDcxODU5
# MDVaMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo3QTFBLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHkwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCQVMwW255Q13ntAdCg+RuP+O+bYRcn
# 3LQsrhEk1kF75S4uFsf7XdqlHXquInXnoOlVoYjh37t8CVeE1BkkbaofQnK9QZog
# Sr/YrhaYB8iAbuUMd/GbMcJRXl1UvmaiSSp10WwzUHXGEqAv+nNIUCfzx+dAwUQ0
# JD11cMhYsy60R/QJayXlIOwSnk9t837UvPyjiS7xBGxzheqUjmN2Vaa2VFm1o1sE
# U5qB2kPxPL61rSzchCfm9PPVVtSJK2t7eBkweVm8twi9Sts2JwMQSL2n7CjBco/T
# rlx3EzyjA6BUjHmphvTCjjG+rqBtT43Zw4LCz+hDjEUs6yy+4xA9ZmwfUUnfX4bc
# vh0K+r2YLAZ+qFMvmE6TVS7JMHbVDPNlmAJD87ZTrdwIi9Ksle/1N4/7qt7xzIzz
# NMNN+NDOezXotIOAQnDLdHW6qHPdVYAm9/9+rB0ADaJ7Z9RzhdqC5PNfdEEUuN4r
# B1a2vB/LH+fhpaiGLGIgil9OB2Yjs2VvNup1SOnfvvJck3lpqY/dFGvbj2yYVY8B
# N6IerTuddMkqpkjEixDdO6dyG3txOgQG9sPd61s29uvnaUrYWyheJAKaH6gbFj1+
# DBLRykjn7T5lUwkOO7YIa1bh4mvY2Ph7I9NZuCluFrZJlZty+oTGRAjGuLIzMQF8
# /m1/wCYVk3uk2QIDAQABo4IByzCCAccwHQYDVR0OBBYEFO/y6lJVlmIVyXV8IGCs
# eG/Br9K2MB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7ZPdshMGwGA1UdHwRl
# MGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAy
# MC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJT
# QSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwZgYDVR0gBF8w
# XTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMAgGBmeBDAEEAjAN
# BgkqhkiG9w0BAQwFAAOCAgEAAB/s3flyoeDsV2DFhZrYIpVwEBnLTowlAdcP7gYg
# vzl3B9yGuP123VISsxW2ok2yBOr2GSndaeLu5yji5GsMpgDFcrjuy0peqyyrbWSM
# i4Vo0ytM1zs9LuMS6vfm0bQRCibwOrA+ZycB9SDus9WIs8riEaGpTAp261IsX1sU
# J+EwJje7fbpPl9hVE4RGt3sM0cIbRvscGgGyzJMUZkduCZ313dVcSqPdPpu1s7qL
# /elLoMecGXXsIiCJtWVk4+JQiR7qeu/S3Dmu7QMSTIqVWkpbUB/X5vUzinM5X8bV
# rgXC1OHbmX6sILCC7B+zzJHF9c8EM0A9MgLT4Z2M/SjRtduW1/oopTntUvER6r9m
# 2waTKWqOJHFL0COnTICkbxZptXi24UjTkKZQzExg9bTVXTRpCPeo1Lvra6FI1jDI
# uOk0HwQB8bQ06UYSLv/O7wFUPGekR4RcXrM+BHeSU4WiEEQMuhnDvyZPkMw86GdG
# q0SJCLBie62YDlQI8fXLX8PJR/UX43MAd8HRgWDTDVSakKVGotk2nXX+aV802RBy
# KixBed0qwYyHiJ6EKz+1OVZV4jELMXsC3SDawBNpdk0dygYpG/kUEcoG06fI49so
# gtDQlMBvivp3YJTeUTG14xVumimufV6vm/F8yvwyvgCbYDqR4Cb/EK5OtgPrcDlS
# zqYxggPUMIID0AIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAW0q1jUEybdx0AAAAAABbMA0GCWCGSAFl
# AwQCAQUAoIIBLTAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIAza4fwzmYB5n9mUPU581ABr3y70jtgSpySDE5s893AsMIHdBgsqhkiG
# 9w0BCRACLzGBzTCByjCBxzCBoAQgLzEDVV2dG9McZRsPF/9yBMmzm7k+muVtXetQ
# lvnBg+8wfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABbSrWNQTJt3HQAAAAAAFswIgQgcIcDmRdK2VhC
# 7uWUtl7jNMn9x8zfnOBTl8hH91XjZiAwDQYJKoZIhvcNAQELBQAEggIAYO5m106j
# rhWjdFK/SEp1fjNkfYVPFzAe5guWm1jFFa9kMwXjk/qgwln4mcmxz1RgFEYaReJt
# LozOD/KHLZmnDU5YRxBpJ31j5qmEsDFQncgTQdUK3FTrVMA9xin97Jh7kMkzebW4
# S4Rc9C2wcB1ryr/+LLCRurN+W5MtAFYpJEnz9q/4XAoOxwfbkpV1+nfAqCh305tT
# QQDh5KqvZ8pYhfggF31ekHvmilL6MxGXm6S4qo9mFsYg8nBbzBv80sJxaarOUrvA
# 1OJ9K7boFPEj+2b63CQrXd4qTxWwmUYM8MwAIc/ceKaNumeZ0wV7e9PnqbqgJQic
# CPM9IP9mb3KiU2zpkxNGOXf9GLpu0A+JjU2RsG8QZEa90VQhE/nQXhR4Ehpfw42K
# 2KMJsVnno9j8uRkphgaLv/3WX5omn8Se2X2hCc1id7T52WGGgDUvUjVRPizReP+1
# YNsBNEl0eFE3Ik6vy2i2/dR5SHCLF+MoLTO+htz/qVs/BNRiXWo9BLsDgrthMpAf
# 5848w5EYwjovra4CQMF4teULGqqnN3FArIc2N7C1b83bNwE1h5G/ck5RmGpSR4Co
# YgUwWmJ7Q9DIxgHhPspewnyGBzGCAnRDrctfbEg/pl/VecpH1JIzoPJF3gg917LS
# W56kRa9YFZe1At1bFADcTCrtF4W2eswE6BU=
# SIG # End signature block
