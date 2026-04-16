<#
.SYNOPSIS
    Reads and parses Ivanti Workspace Control registry sets from a Building Block XML file or a
    standalone .reg file.
.DESCRIPTION
    Accepts either:
    - An Ivanti Workspace Control Building Block XML file: extracts every <registry type="registry">
      node, decodes the hex-encoded registryfile, and parses it. Name and description are taken
      from the <name> and <description> XML elements.
    - A standalone .reg file: parses it directly. Name and description are read from the
      ;<PFNAME> and ;<PFDESC> comment tags if present.

    Each value entry is returned as a structured object with its registry hive, key, value name,
    value data, value type, and an optional per-value description captured from the ;<PF>...</PF>
    comment tag that may follow the value line.

    Supports all standard .reg value types:
    - REG_SZ        (quoted string or hex(1):)
    - REG_EXPAND_SZ (hex(2):)
    - REG_BINARY    (hex: / hex(3):)
    - REG_DWORD     (dword: / hex(4):)
    - REG_MULTI_SZ  (hex(7):)
    - REG_QWORD     (qword: / hex(b):)

.PARAMETER Path
    Path to an Ivanti Workspace Control Building Block XML file or a standalone .reg file.

.PARAMETER ExportFor
    Target export format. 'AppVentiX' adds the AppVentiXParams property to each output object.
    Defaults to 'WEM'.

.EXAMPLE
    # From a Building Block XML
    Get-IvantiWCRegistry -Path 'C:\temp\LAB-BB.xml'

.EXAMPLE
    # From a standalone .reg file, exported for AppVentiX
    Get-IvantiWCRegistry -Path 'C:\temp\registry.reg' -ExportFor AppVentiX

.NOTES
    Function  : Get-IvantiWCRegistry
    Author    : John Billekens
    Copyright : (c) John Billekens Consultancy & AppVentiX
    Version   : 2026.0309.1200
#>
function Get-IvantiWCRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path,

        [ValidateSet('AppVentiX', 'WEM')]
        [string]$ExportFor = 'WEM'
    )

    #region Internal helpers

    function Convert-HexToString {
        param([string]$HexString)
        if ([string]::IsNullOrEmpty($HexString)) { return '' }
        $bytes = for ($i = 0; $i -lt $HexString.Length; $i += 2) {
            [System.Convert]::ToByte($HexString.Substring($i, 2), 16)
        }
        return [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
    }

    function Convert-RegistryHexToValue {
        param([string]$hexString, [string]$type)
        $hexData = $hexString -replace '^hex\(\w+\):', '' -replace '[,\s]', ''
        if ([string]::IsNullOrEmpty($hexData)) { return $null }
        try {
            $bytes = for ($i = 0; $i -lt $hexData.Length; $i += 2) {
                [System.Convert]::ToByte($hexData.Substring($i, 2), 16)
            }
            switch ($type) {
                'REG_SZ' { return [System.Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0) }
                'REG_EXPAND_SZ' { return [System.Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0) }
                'REG_BINARY' { return [System.BitConverter]::ToString($bytes) }
                'REG_DWORD' { if ($bytes.Count -eq 4) { return [System.BitConverter]::ToUInt32($bytes, 0) } return $null }
                'REG_MULTI_SZ' {
                    $fullString = [System.Text.Encoding]::Unicode.GetString($bytes)
                    return [array]($fullString -split '\0' | Where-Object { $_ })
                }
                'REG_QWORD' { if ($bytes.Count -eq 8) { return [System.BitConverter]::ToUInt64($bytes, 0) } return $null }
                default { return [System.BitConverter]::ToString($bytes) }
            }
        } catch {
            Write-Warning "Could not decode hex value for type $type. Error: $_"
            return $hexString
        }
    }

    function New-WEMRegItem {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory = $true)]
            [ValidateSet("CreateKey", "SetValue", "DeleteValue", "DeleteAllValues", "DeleteKey")]
            [string]$Action,

            [Parameter(Mandatory = $true)]
            [ValidateSet("Machine", "User")]
            [string]$Scope,

            [Parameter(Mandatory = $true)]
            [string]$Key,

            [Parameter(Mandatory = $false)]
            [Alias("Name", "ValueName")]
            [string]$Value = "",

            [Parameter(Mandatory = $false)]
            [Alias("RegType")]
            [ValidateSet("REG_SZ", "REG_DWORD", "REG_DWORD_LITTLE_ENDIAN", "REG_QWORD", "REG_QWORD_LITTLE_ENDIAN", "REG_MULTI_SZ", "REG_BINARY", "REG_EXPAND_SZ", "REG_NONE")]
            [string]$Type,

            [Parameter(Mandatory = $false)]
            [Alias("RegData")]
            [object]$Data
        )

        if ($Action -eq "SetValue") {
            if ([string]::IsNullOrEmpty($Type)) {
                throw "The -Type parameter is required when -Action is 'SetValue'."
            }
            if ($null -eq $Data) {
                throw "The -Data parameter is required when -Action is 'SetValue'."
            }
        }

        if ($Action -eq "SetValue") {
            $RegDataValue = if ($Type -eq "REG_MULTI_SZ") { [array]$Data } else { $Data }
            [PSCustomObject]@{
                action  = $Action
                regType = $Type
                scope   = $Scope
                regData = $RegDataValue
                key     = $Key
                value   = $Value
            }
        } else {
            [PSCustomObject]@{
                action  = $Action
                scope   = $Scope
                regData = ""
                key     = $Key
                value   = $Value
            }
        }
    }

    function Get-RegistryScope {
        param([string]$Hive, [string]$Class)
        if ($Hive -ieq 'HKEY_LOCAL_MACHINE') { return 'Machine' }
        if ($Hive -ieq 'HKEY_CURRENT_USER') { return 'User' }
        # fallback to Class
        if ($Class -ieq 'Machine') { return 'Machine' }
        return 'User'  # User or Both both map to User
    }

    function ConvertTo-RegistryEntries {
        param(
            [string]$Name,
            [string]$Description,
            [string]$RegContent,
            [string]$SourceFile,
            [bool]$Enabled = $true,
            [bool]$RunOnce = $false,
            [string]$ExportFor = 'WEM',
            [PSCustomObject[]]$Assignments = @()
        )

        $lines = $RegContent.Split([string[]]@("`r`n", "`n", "`r"), [StringSplitOptions]::None)

        # If name/description not provided, fall back to PFNAME/PFDESC tags in the content
        $resolvedName = $Name
        $resolvedDescription = $Description
        if ([string]::IsNullOrEmpty($resolvedName) -or [string]::IsNullOrEmpty($resolvedDescription)) {
            foreach ($line in $lines) {
                if ([string]::IsNullOrEmpty($resolvedName) -and $line -match ';<PFNAME>(.+)</PFNAME>') {
                    $resolvedName = $Matches[1].Trim()
                }
                if ([string]::IsNullOrEmpty($resolvedDescription) -and $line -match ';<PFDESC>(.+)</PFDESC>') {
                    $resolvedDescription = $Matches[1].Trim()
                }
                if (-not [string]::IsNullOrEmpty($resolvedName) -and -not [string]::IsNullOrEmpty($resolvedDescription)) {
                    break
                }
            }
        }

        Write-Verbose "Registry set: '$resolvedName' | Description: '$resolvedDescription'  | Enabled: '$Enabled' | RunOnce: '$RunOnce'"

        $entries = [System.Collections.Generic.List[PSCustomObject]]::new()
        $currentHive = ''
        $currentKey = ''

        for ($i = 0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]

            # Section header: [HKEY_...] or ![HKEY_...] (delete entire key)
            if ($line -match '^(!?)\[((HKEY_[^\\]+)(\\(.+))?)\]$') {
                $isKeyDeletion = $Matches[1] -eq '!'
                $sectionHive = $Matches[3]
                $sectionKey = if ($Matches[5]) { $Matches[5] } else { '' }

                if ($isKeyDeletion) {
                    # Emit a key-deletion entry; do not update current section context
                    Write-Verbose "  Delete key: $sectionHive\$sectionKey"
                    $entries.Add([PSCustomObject]([ordered]@{
                                RegistryHive      = $sectionHive
                                RegistryKey       = $sectionKey
                                RegistryKeyPath   = if ([string]::IsNullOrEmpty($sectionKey)) { $sectionHive } else { "$sectionHive\$sectionKey" }
                                RegistryValueName = $null
                                Value             = $null
                                ValueType         = $null
                                Description       = ''
                                Delete            = $true
                            }))
                } else {
                    $currentHive = $sectionHive
                    $currentKey = $sectionKey
                    Write-Verbose "  Section: $currentHive\$currentKey"
                }
                continue
            }

            # Skip comments, blank lines, and the editor header
            if ([string]::IsNullOrWhiteSpace($line) -or
                $line.StartsWith(';') -or
                $line.StartsWith('Windows Registry Editor')) {
                continue
            }

            # Skip structural placeholder default values (@="") on keys with no meaningful path
            # These are Ivanti reg file artifacts - empty-string default values on intermediate keys
            if ($line -match '^@=""$' -and [string]::IsNullOrEmpty($currentKey)) {
                continue
            }

            # Deletion marker on value: !"ValueName"=...
            $isDeletion = $false
            $parsedLine = $line
            if ($parsedLine.TrimStart().StartsWith('!"')) {
                $isDeletion = $true
                $parsedLine = $parsedLine.TrimStart().Substring(1)
            }

            $valueName = $null
            $rawValue = $null

            if ($parsedLine -match '^"([^"]*)"=(.+)') {
                $valueName = $Matches[1]
                $rawValue = $Matches[2].Trim()
            } elseif ($parsedLine -match '^@=(.+)') {
                $valueName = ''
                $rawValue = $Matches[1].Trim()
            } else {
                continue
            }

            # Skip empty-string default values on intermediate keys (structural artifacts)
            if ($valueName -eq '' -and $rawValue -eq '""') {
                continue
            }

            # Peek at next line for optional ;<PF>...</PF> per-value description
            $valueDescription = ''
            if (($i + 1) -lt $lines.Length -and $lines[$i + 1] -match ';<PF>(.+)</PF>') {
                $valueDescription = $Matches[1].Trim()
            }

            # Decode value data and determine type
            $registryValue = $null
            $registryValueType = 'Unknown'

            if ($rawValue.StartsWith('dword:')) {
                $registryValueType = 'REG_DWORD'
                try { $registryValue = [uint64]("0x" + $rawValue.Substring(6)) }
                catch { $registryValue = $rawValue; $registryValueType = 'Unknown' }
            } elseif ($rawValue.StartsWith('qword:')) {
                $registryValueType = 'REG_QWORD'
                try { $registryValue = [uint64]("0x" + $rawValue.Substring(6)) }
                catch { $registryValue = $rawValue; $registryValueType = 'Unknown' }
            } elseif ($rawValue.StartsWith('"') -and $rawValue.EndsWith('"')) {
                $registryValueType = 'REG_SZ'
                $registryValue = $rawValue.Substring(1, $rawValue.Length - 2)
            } elseif ($rawValue.StartsWith('hex(1):')) {
                $registryValueType = 'REG_SZ'
                $registryValue = Convert-RegistryHexToValue -hexString $rawValue -type 'REG_SZ'
            } elseif ($rawValue.StartsWith('hex(2):')) {
                $registryValueType = 'REG_EXPAND_SZ'
                $registryValue = Convert-RegistryHexToValue -hexString $rawValue -type 'REG_EXPAND_SZ'
            } elseif ($rawValue.StartsWith('hex(3):') -or $rawValue.StartsWith('hex:')) {
                $registryValueType = 'REG_BINARY'
                $registryValue = Convert-RegistryHexToValue -hexString $rawValue -type 'REG_BINARY'
            } elseif ($rawValue.StartsWith('hex(4):')) {
                $registryValueType = 'REG_DWORD'
                $registryValue = Convert-RegistryHexToValue -hexString $rawValue -type 'REG_DWORD'
            } elseif ($rawValue.StartsWith('hex(7):')) {
                $registryValueType = 'REG_MULTI_SZ'
                $registryValue = Convert-RegistryHexToValue -hexString $rawValue -type 'REG_MULTI_SZ'
            } elseif ($rawValue.StartsWith('hex(b):')) {
                $registryValueType = 'REG_QWORD'
                $registryValue = Convert-RegistryHexToValue -hexString $rawValue -type 'REG_QWORD'
            } else {
                $registryValueType = 'REG_SZ'
                $registryValue = $rawValue
            }

            $entries.Add(
                [PSCustomObject](
                    [PSCustomObject]@{
                        RegistryHive      = $currentHive
                        RegistryKey       = $currentKey
                        RegistryKeyPath   = if ([string]::IsNullOrEmpty($currentKey)) { $currentHive } else { "$currentHive\$currentKey" }
                        RegistryValueName = $valueName
                        Value             = $registryValue
                        ValueType         = $registryValueType
                        Description       = $valueDescription
                        Delete            = $isDeletion
                    }
                )
            )
        }

        Write-Verbose "  Parsed $($entries.Count) registry value(s)"

        $output = [ordered]@{
            Name        = $resolvedName
            Description = $resolvedDescription
            Enabled     = $Enabled
            RunOnce     = $RunOnce
            Entries     = $entries.ToArray()
            SourceFile  = $SourceFile
        }

        if ($ExportFor -eq 'AppVentiX') {
            $registryEntries = @(
                foreach ($entry in $entries) {
                    $deleteKey = $false
                    if ($entry.Delete -eq $true -and [string]::IsNullOrEmpty($entry.RegistryValueName)) {
                        $deleteKey = $true
                    }
                    $valueType = $entry.ValueType
                    if ([string]::IsNullOrEmpty(($valueType))) {
                        $valueType = 'REG_SZ'
                    }

                    [PSCustomObject]@{
                        RootKey   = $entry.RegistryHive
                        KeyPath   = $entry.RegistryKey
                        ValueName = $entry.RegistryValueName
                        ValueData = $entry.Value
                        ValueType = $valueType
                        Action    = if ($entry.Delete) { 'Remove' } else { 'Set' }
                        DeleteKey = $deleteKey
                    }

                }
            )
            $output.AppVentiXAssignments = @($Assignments | Select-Object Sid, Name, Type, DomainFQDN)
            $output.AppVentiXParams = (
                [ordered]@{
                    FriendlyName    = $resolvedName
                    Description     = $resolvedDescription
                    RegistryEntries = @($registryEntries)
                }
            )
        } elseif ($ExportFor -eq 'WEM') {
            $output.WEMAssignments = @($Assignments | Select-Object Sid, Name, Type, DomainFQDN, DomainNETBIOS)
            $output.WEMParams = [ordered]@{
                Name               = $resolvedName
                Description        = "[IWC-Registry] $resolvedDescription"
                RegistryOperations = @()
            }

            foreach ($entry in $entries) {
                $Scope = Get-RegistryScope -Hive $entry.RegistryHive -Class ''

                $Action = if ($entry.Delete) {
                    if ($null -eq $entry.RegistryValueName) { 'DeleteKey' } else { 'DeleteValue' }
                } else {
                    if ([string]::IsNullOrEmpty($entry.RegistryValueName)) { 'CreateKey' } else { 'SetValue' }
                }

                $RegItemParam = @{
                    Action = $Action
                    Scope  = $Scope
                    Key    = $entry.RegistryKey
                }
                if ($Action -eq 'SetValue') {
                    $RegItemParam.Value = $entry.RegistryValueName
                    $RegItemParam.Type = $entry.ValueType
                    $RegItemParam.Data = $entry.Value
                } elseif ($Action -eq 'DeleteValue') {
                    $RegItemParam.Value = $entry.RegistryValueName
                }
                $output.WEMParams.RegistryOperations += New-WEMRegItem @RegItemParam
            }
        }

        [PSCustomObject]$output
    }

    #endregion

    $absolutePath = (Resolve-Path -LiteralPath $Path).Path
    $extension = [System.IO.Path]::GetExtension($absolutePath).ToLower()

    if ($extension -eq '.xml') {
        # Building Block XML - extract all <registry type="registry"> nodes
        Write-Verbose "Loading Building Block XML: $absolutePath"
        try {
            $xmlContent = New-Object System.Xml.XmlDocument
            $xmlContent.Load($absolutePath)
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Xml.XmlException]::new("Failed to parse XML file '$absolutePath': $($_.Exception.Message)"),
                    'XmlParseError',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $absolutePath
                )
            )
        }

        $registryNodes = @($xmlContent.GetElementsByTagName('registry') | Where-Object { $_.type -eq 'registry' })
        Write-Verbose "Found $($registryNodes.Count) registry set node(s)"

        if ($registryNodes.Count -eq 0) {
            Write-Warning "No <registry type='registry'> nodes found in '$absolutePath'"
            return
        }

        foreach ($node in $registryNodes) {
            $nodeName = $node.name
            $nodeDescription = $node.description
            $decodedContent = (Convert-HexToString -HexString $node.registryfile).TrimStart([char]0xFEFF)
            if ($node.enabled -ieq "yes") {
                $enabled = $true
            } else {
                $enabled = $false
            }
            if ($node.runonce -ieq "yes") {
                $runOnce = $true
            } else {
                $runOnce = $false
            }
            Write-Verbose "Processing registry set: '$nodeName'"
            $Assignments = @(ConvertFrom-IvantiAccessControl -AccessControl $node.accesscontrol -IWCComponentName $nodeName -IWCComponent "Policy")

            ConvertTo-RegistryEntries -Name $nodeName -Description $nodeDescription -RunOnce $runOnce -RegContent $decodedContent -SourceFile $absolutePath -ExportFor $ExportFor -Assignments $Assignments
        }

    } else {
        # Standalone .reg file
        Write-Verbose "Loading .reg file: $absolutePath"
        try {
            $rawContent = Get-Content -LiteralPath $absolutePath -Raw -ErrorAction Stop
        } catch {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.IO.IOException]::new("Failed to read file '$absolutePath': $($_.Exception.Message)"),
                    'RegFileReadError',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $absolutePath
                )
            )
        }
        ConvertTo-RegistryEntries -Name '' -Description '' -RegContent $rawContent -SourceFile $absolutePath -ExportFor $ExportFor
    }
}

# SIG # Begin signature block
# MII6BgYJKoZIhvcNAQcCoII59zCCOfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDUG5erO2Ho8D7i
# M0YjZzok4PTEhCqCmrcOPFCTKAsau6CCIiowggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# IMab4H3OMyVnGxJPbFe8lg19sgvfCQJgX+qPIxEINCsrMA0GCSqGSIb3DQEBAQUA
# BIIBgL9J+2hefyjvaibp0Q2AxiSKweZ4Xhx75+SLbkf+USR2ZahawGG2lO9lLOCV
# Bci5DwQHXX27B2xX2GUB2VHf0OgN7GF7BOxTkKCy6mHqdqeg2pNRU0klMm8GfQTA
# /G9OSXiar8NsZlGdwun+sGW+YAGF7exHaCcuh0wbyGEQvIv8zet/qGiJKzavtp0y
# TBdIhyLLxDN/upvUm5VeUgz/FJPq9GNEndwOdAZOyid7sEP/vsI43mY3LAsAUmDn
# no+wJzXHgGmgHS+ta4IRtu//cWXG92oAtgAhAHLUF+vx8j8sPnDHZvmWvAwf8b/A
# /dFAsvUdvRrmeRRbPiQavUJpLOVm0X95MXN/EltG0fj5pko2x/Cuk7oHHif94Nq7
# sOlZByetmx+FbQ7LWy1rAdIZuboFiLUbSkJfYQRowcOQK0wlKByDOn67apxbGA1L
# IjxL3670HhiOk32SWbSDDbKvEzPBQaQVHeVGAlUEWCWDTJx0aK8soGv2X9WmqPGz
# 8M+caKGCFLIwghSuBgorBgEEAYI3AwMBMYIUnjCCFJoGCSqGSIb3DQEHAqCCFIsw
# ghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFqBgsqhkiG9w0BCRABBKCCAVkEggFV
# MIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBTh2Pqy/8Bw0Es
# MY2aRwuHVxauFFakJuVNt5AThXIbQgIGacZiOPNwGBMyMDI2MDQxNTE5NTc0Mi4w
# NDZaMASAAgH0oIHppIHmMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0OTFBLTA1RTAtRDk0NzE1
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
# r1nJfiWG2GwYe6ZoAF1bMIIHnzCCBYegAwIBAgITMwAAAFr2DWeMhe3dCAAAAAAA
# WjANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBU
# aW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjAxMDgxODU5MDNaFw0yNzAxMDcxODU5
# MDNaMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo0OTFBLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHkwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDv9DtHlo4FG/a5x3EC0XX1jzeB/vdW
# t2J5Wj+OhNZuLg/iSsenLFjErV+/X8SyVAKhyakFhNfVJTTIUvYxAd9nQCeMrlrB
# 8lLjPnaYYw8+BOY5eIGBmRJmjqyrzbfiqpRWssoP6E4NwZS0buGgavOuvAOapR3H
# 7Loeg3UqhSA9YsSRWcx62RRtYhgRu1NQZ9jjSw6O428F+azHD3bkwFMP3OzN1oUs
# UAbmaUIs/EUBiiKginyMYEJCnc6QqVNElkDhPw4E12893NeSjEQnZBpS9s2/pZ7k
# leLLHkJt6n5WYmXJC8p9sSSPGVw5KviIPm/67DzyHyPHYttvFrytY+uyV6cnlQmk
# lDvRK85S506540JHl1UCKe98blQVa5r6E3/7+GuzJ65riksiF3ObyVBxBgd+Ofjv
# KJhbdcPG/l4PQ/TyiEagzxL+x0ZNAvmL8bvBbxyb0qHEiGSvr/xZihToqWJ6T++s
# gJiTZ8oXrnEoToJPEIlOd1Ep//gMjG+8VvdOYGZ8jam9vR3lXUNe+aQxyRhM/Ase
# cIh3lZYhs+YQAbnBQ8pUfc9y0k5gevt2biMXhvQWUuOj+gDT5Llbg+ZvMIHOxiy8
# 4O9wrAxdPbpLfFH/HU3DAV966Pu/5PTOl7fFjxuyC/b/+A78jGNN7ZG/WPUYuh1m
# r10T2EQlHj7KTwIDAQABo4IByzCCAccwHQYDVR0OBBYEFI5jskOrcDHD9WW0crSc
# SOH515nCMB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7ZPdshMGwGA1UdHwRl
# MGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAy
# MC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJT
# QSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwZgYDVR0gBF8w
# XTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMAgGBmeBDAEEAjAN
# BgkqhkiG9w0BAQwFAAOCAgEAgJTPK/rd4SG9odZQ0wMfomJEJcRblO0DjXsiBSAW
# dvcbxpfKXoSsRKw8yJ4jqSF/3pblAMECqGiNM8LigHUdJq0h1wp4jKCzZKOVvua+
# 7FzWpil+0DFdwXxjl94IvalX8clHuwB126kPCgUBzWApzRbUEB4AEa5WIbcgCqJe
# XLTNAgHP8t6GO20zLFSb5wObuw1Vj3l6Ek9ihDA3iwbyWKtCCWesjKQzli2eFD/N
# m5LMkoSAf13WsIqyBi3bHrna8kcVTJN9d5gHIxkW+ffiLbbeqLVb2EFqh/jxq01M
# xHHs/GkLjt7pqDWYyrhaF+VbDz/4EmbHvqK4Rt832ZPSA8hNw31Ba4b5L+h9LYoy
# tQ9LiBocDAVkpvZLUOqHlPmrq2RcdzCPizg5x7G0RWQMtdbjL8CqvmTQtUnuLSDN
# bvaYlgIZ0z6IeplCyopBzlYR2jved7ZMwwrY7LHuRlCjsfcoPZ6hyljIJzg6etv7
# jz8wv8gxCEq1wnFO1Ae7QE6981jRHbTOHdNPYl1iOnVf0nXCCF+OK6aC8gi8Pp14
# 8afn2P3coCzu1HUkGlWlBVY9ytp1crroz7KbeS7p3ORb7mD6pov8/JAEppsG4hfl
# tD9FE1hWgvODFn1NoejA4ObNKMZnTRSu+o1698GX3UqFexQin6uRnXhqMuVMA0MD
# AtAxggPUMIID0AIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAWvYNZ4yF7d0IAAAAAABaMA0GCWCGSAFl
# AwQCAQUAoIIBLTAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIOZShUmN1l/uMeS4hqnkv751fYmZ/WQONt68SsHhBMDDMIHdBgsqhkiG
# 9w0BCRACLzGBzTCByjCBxzCBoAQgYrlkQIvqfej0bAbd08Ft4zaM4D0EvkHKNQlZ
# vzWlNEMwfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABa9g1njIXt3QgAAAAAAFowIgQgz/PxAjAeE5ch
# 71jXHZnzdbdaJdn9+I9RtQU3Kk+LLlkwDQYJKoZIhvcNAQELBQAEggIAGL/rmKdM
# v4J6n/IulhAYzgZ8oDX3IVRtW0BRYiJakGxfyXT+TZ0AeDdZg59XzvUyllG+AUQW
# 5Ob+v/kocLhXD3FIojLDo1zOx0cjr7bfxKoSTenAj0P+wCnFKL1dlM0wcAIMTYZo
# EiaEPECnJTM3WZ8JCzXPIwuhF5rKD6uHJXeVxYDJIthNujJS+YZJ3i2C/mi2UstS
# 7ro6TvRtrGqD9Ra2TCzElUjtcIn8FxX1IYeAZJz4DuF8ZWQJXJi9PhR6Trvv5o+m
# T24vUYoeZ8SWZXvic2OfSv2kxc57L+5wZINtPgYHNpajlSECWa64XUnjfG58/aTe
# 0fS3J7iz7+gWoReJPT0KZvX9bN+TfR7ruLLkl2dxc+BQxET5T5b0e2M3QqcyVO3a
# hKuDnIWS58+gsfh8a+yj3MRUhxedgQQjCTtveA1nP7Dg351qRsVObEBA2oGBm4fS
# ijECuIa9tNXgv6Pf9BaHLc+v5hzKIk/wnz2+U82XYlbm/ZcoRGXvbdsk9qqGCn2P
# R0XW69lW3RMrip2txVrZfxyetql4SerpNZrir9HUjpO5REOhgjdvzb2rcRuXiCBt
# Hky7joCAU9l8jmoAjkAryiHhn+u8L+xWZiXXzJh7IGnjXYfd41onLKc3m9LVu2km
# rJrM9Rb80ZNX+BLZ/96KeYorNv3L8fT5/8Q=
# SIG # End signature block
