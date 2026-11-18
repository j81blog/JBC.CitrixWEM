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
    Version   : 2026.1118.1200
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

    function Convert-RegEscapedString {
        # .reg string values escape a backslash as \\ and a quote as \". Without this a path
        # such as "%userprofile%\\Documents" keeps its doubled separators.
        param([string]$Value)
        return $Value -replace '\\([\\"])', '$1'
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
                $registryValue = Convert-RegEscapedString -Value $rawValue.Substring(1, $rawValue.Length - 2)
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
            # ConvertFrom-IvantiBB strips <webtop> sections, these contain nested XML declarations that XmlDocument rejects
            $xmlContent = ConvertFrom-IvantiBB -XmlFilePath $absolutePath
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
# MII6AgYJKoZIhvcNAQcCoII58zCCOe8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAsx4duCdzmOgUt
# 68vyFNOpnBHRDtYoJNTqZBtYVIOXVqCCIiYwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbAMIIEqKADAgECAhMzAAxah1Vq
# R2NpPKqSAAAADFqHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBBT0MgQ0EgMDMwHhcNMjYxMTE3MDE0NjAwWhcNMjYxMTIw
# MDE0NjAwWjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAkxAgXhorpiKQSF8LYykP38Cn
# DqcRYwHiCpWdAwxYxPR3BuZdTQgkNwy4exDN21zE78rhWrQcnBU+ERBPdRZxHAez
# vyAk7hs2tZm2G+iqgv9+aFf2h1YWeZM1o6gTcCk+CGUddzjUid7B0n9iCUitHfTd
# Ac2DAcLOVQc2eFpOLhgKD2ABbSL7iQPlaHKq1YTmAlnQsovojDlwjCtfJhVFKsBy
# bz4QDT/t6L2J02WG7MJ4Ty2mMi2Ncsq8Jcx1Y91Ab/6TkO3rrLqCV8S2ajZpDKxG
# NzkznH55Uy7a/pSUHIg181hcjx2hkHMhzPeTzbzW5rH5x6SZxti1nRoXfyfna0jN
# iiC5S1IbMgucg3GJ9TQ4McfrO56WbxFJF9QSI1X7dPEPArfabnxwaGXHSnTFMvL6
# A3Mrusbxng9AcAqogWeGtQRZj22ATFAXA+GWKQu+BcZkBRmIiMNaRqx54+iINJAS
# BVv/DLFa+CPoEhf0YgLA1DUfsJ4CpcEewQ0iA3wzAgMBAAGjggHTMIIBzzAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA6BgNVHSUEMzAxBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYZKwYBBAGCN2HK9PELgrHSgxH33KNOluu6MTAdBgNVHQ4EFgQU
# a7vPo3rl7uOyvSVDXOGHQlRWLWEwHwYDVR0jBBgwFoAUpEMMf3ZapYXnPo0oDwwX
# okVpcMYwZwYDVR0fBGAwXjBcoFqgWIZWaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwQU9D
# JTIwQ0ElMjAwMy5jcmwwdAYIKwYBBQUHAQEEaDBmMGQGCCsGAQUFBzAChlhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElE
# JTIwVmVyaWZpZWQlMjBDUyUyMEFPQyUyMENBJTIwMDMuY3J0MFQGA1UdIARNMEsw
# SQYEVR0gADBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wDQYJKoZIhvcNAQEMBQADggIBAKw0
# 3tsE8NphE+cpQtl7MPVz2Lv/qNHE+9Dw0KCFiM2HvRQdRgKQnUq9xpUSvSXLUNEh
# 0MKKRUXalgTz2hNFHk2NyDb10kfq8osU6AOMuZcQEsPsF1wNlexQ/+qZMQN17euD
# d3SSXCJVX5dw7Y7o6Vx95hEaAd+at0DKiueNnKnZzNwPKbRQCQ6FOaOyv8+ueAP5
# om3MoA/dJxsdqKh6oCHx7NljNTOp4bm1E6gDjoB9kjcfm7tVi3fL/A10FDeJwio8
# COhmmx1Ue2i8yNMCyqj7R/dKRlgW/4l69dwI3jxR5kMY/S1V2gqySQTtzRJR8f3x
# JUGidbYUlFb7K51NiakJ62M8xrNL4kjdsOagr+kdxykY78iXNAtFY+R0o7m4T+6S
# wiYnP8eFQe8OqUPHy8N8ifhuKMnfMdHA0sHlE+PFvYOm6Ttc93sJhXD0iFEUjDgg
# 324CHYF6v4rnhn4+5RIH9BTPeOu1ZY9W9U7fa/zCo7dRLQdvxwTaG+rNen2Uj+Hp
# 2NnFkiB/iJD8/FCOp4WFSyIPII/O9em6W1wKxw75e2ABzXc4L4jDRPNY83rO9+q7
# YC4glbGah7Uqf8cLfT+SmOQVFTwQUy33lQ36Y0ltblETR6LEv2rWJybXyckwvh2k
# 4tHQmsuVqMT8F4ScBucZjdMeehoZZOQH8rPApYOiMIIGwDCCBKigAwIBAgITMwAM
# WodVakdjaTyqkgAAAAxahzANBgkqhkiG9w0BAQwFADBaMQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3Nv
# ZnQgSUQgVmVyaWZpZWQgQ1MgQU9DIENBIDAzMB4XDTI2MTExNzAxNDYwMFoXDTI2
# MTEyMDAxNDYwMFowgYMxCzAJBgNVBAYTAk5MMRYwFAYDVQQIEw1Ob29yZC1CcmFi
# YW50MRIwEAYDVQQHEwlTY2hpam5kZWwxIzAhBgNVBAoTGkpvaG4gQmlsbGVrZW5z
# IENvbnN1bHRhbmN5MSMwIQYDVQQDExpKb2huIEJpbGxla2VucyBDb25zdWx0YW5j
# eTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAJMQIF4aK6YikEhfC2Mp
# D9/Apw6nEWMB4gqVnQMMWMT0dwbmXU0IJDcMuHsQzdtcxO/K4Vq0HJwVPhEQT3UW
# cRwHs78gJO4bNrWZthvoqoL/fmhX9odWFnmTNaOoE3ApPghlHXc41InewdJ/YglI
# rR303QHNgwHCzlUHNnhaTi4YCg9gAW0i+4kD5WhyqtWE5gJZ0LKL6Iw5cIwrXyYV
# RSrAcm8+EA0/7ei9idNlhuzCeE8tpjItjXLKvCXMdWPdQG/+k5Dt66y6glfEtmo2
# aQysRjc5M5x+eVMu2v6UlByINfNYXI8doZBzIcz3k8281uax+cekmcbYtZ0aF38n
# 52tIzYoguUtSGzILnINxifU0ODHH6zuelm8RSRfUEiNV+3TxDwK32m58cGhlx0p0
# xTLy+gNzK7rG8Z4PQHAKqIFnhrUEWY9tgExQFwPhlikLvgXGZAUZiIjDWkaseePo
# iDSQEgVb/wyxWvgj6BIX9GICwNQ1H7CeAqXBHsENIgN8MwIDAQABo4IB0zCCAc8w
# DAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwOgYDVR0lBDMwMQYKKwYBBAGC
# N2EBAAYIKwYBBQUHAwMGGSsGAQQBgjdhyvTxC4Kx0oMR99yjTpbrujEwHQYDVR0O
# BBYEFGu7z6N65e7jsr0lQ1zhh0JUVi1hMB8GA1UdIwQYMBaAFKRDDH92WqWF5z6N
# KA8MF6JFaXDGMGcGA1UdHwRgMF4wXKBaoFiGVmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDUyUy
# MEFPQyUyMENBJTIwMDMuY3JsMHQGCCsGAQUFBwEBBGgwZjBkBggrBgEFBQcwAoZY
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQl
# MjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBBT0MlMjBDQSUyMDAzLmNydDBUBgNVHSAE
# TTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMA0GCSqGSIb3DQEBDAUAA4IC
# AQCsNN7bBPDaYRPnKULZezD1c9i7/6jRxPvQ8NCghYjNh70UHUYCkJ1KvcaVEr0l
# y1DRIdDCikVF2pYE89oTRR5Njcg29dJH6vKLFOgDjLmXEBLD7BdcDZXsUP/qmTED
# de3rg3d0klwiVV+XcO2O6OlcfeYRGgHfmrdAyornjZyp2czcDym0UAkOhTmjsr/P
# rngD+aJtzKAP3ScbHaioeqAh8ezZYzUzqeG5tROoA46AfZI3H5u7VYt3y/wNdBQ3
# icIqPAjoZpsdVHtovMjTAsqo+0f3SkZYFv+JevXcCN48UeZDGP0tVdoKskkE7c0S
# UfH98SVBonW2FJRW+yudTYmpCetjPMazS+JI3bDmoK/pHccpGO/IlzQLRWPkdKO5
# uE/uksImJz/HhUHvDqlDx8vDfIn4bijJ3zHRwNLB5RPjxb2Dpuk7XPd7CYVw9IhR
# FIw4IN9uAh2Ber+K54Z+PuUSB/QUz3jrtWWPVvVO32v8wqO3US0Hb8cE2hvqzXp9
# lI/h6djZxZIgf4iQ/PxQjqeFhUsiDyCPzvXpultcCscO+XtgAc13OC+Iw0TzWPN6
# zvfqu2AuIJWxmoe1Kn/HC30/kpjkFRU8EFMt95UN+mNJbW5RE0eixL9q1icm18nJ
# ML4dpOLR0JrLlajE/BeEnAbnGY3THnoaGWTkB/KzwKWDojCCBygwggUQoAMCAQIC
# EzMAAAAYDeuRVamKAJgAAAAAABgwDQYJKoZIhvcNAQEMBQAwYzELMAkGA1UEBhMC
# VVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjE0MDIGA1UEAxMrTWlj
# cm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2lnbmluZyBQQ0EgMjAyMTAeFw0yNjAz
# MjYxODExMzJaFw0zMTAzMjYxODExMzJaMFoxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJRCBW
# ZXJpZmllZCBDUyBBT0MgQ0EgMDMwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQDIgNpgNFaiif2VWeWP5I6PnFXxJ/lB37fJR55GCvR7GLZBMkBijbiKVwgp
# BI3xM5nf484znH/qncJ+OCq6y3jgnQW+R8Zd7U+7LjlrmcskalzSQ0ghMxEpnBW8
# /HHs2V8ZJzQk6HP+SDsbvsL7LdlH/eO2l4mknhDBwr0Z/Q966TvEth5b8kCxj1vq
# iV4YNthLGRqZR9u2fK/yBMWu83p6O4uo2Edg++gEew5IL7vnnnKFqmSh/R9vPJy3
# WF1YcZewAUx8sXZNUnx3ZhVg59l2LpitPiwzE6FMqIsqaEvVe3MzuFd2a/uWDZH6
# VbDyUiRK78mIg1DQYA9zDEyyBFcNI+nxVSzglvL6u7PRuNqgcV3sf6ELxw89ysQM
# /Z4R1hRFWXRpyOWKKAKtfBHTk0UnNiPcxmLMMYs8jeUjOidfVPjTIry/UVwnwxdl
# kK85cZfBEMYZ/DBNOwdomP459Y1n8izKkbhsa+p4lw+cQVxATBFx9ggR79HhryT7
# HDmpPLvkJvBZ4wW4CW32UT2SMyDe28nIOU3m+hfHlVeKcLBQcym5VoRDjIcCVI7u
# qgGW2PNME0cfei8zCwCy6HCsssJWFS7eg/YbFhnATJcyWfMrkNuAbMfMN8Npg8cr
# S6jVVowyD0GG5zdgi+uQVcSK/638mA1xEYK3pnIoQgO09uuDBwIDAQABo4IB3DCC
# AdgwDgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBSk
# Qwx/dlqlhec+jSgPDBeiRWlwxjBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9z
# aXRvcnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAU2UEpsA8PY2zvadf1zSmepEhqMOYwcAYDVR0f
# BGkwZzBloGOgYYZfaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENvZGUlMjBTaWduaW5nJTIwUENB
# JTIwMjAyMS5jcmwwfQYIKwYBBQUHAQEEcTBvMG0GCCsGAQUFBzAChmFodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElEJTIw
# VmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3J0MA0GCSqG
# SIb3DQEBDAUAA4ICAQBxxyBW+X6mhdRiSwD9PMMWcGUAnx5/QUwnNvZdFGEX+4DR
# DIr9WCh4C87wHtw+lg1D3uzK10DstPX0LFLBFAC3vWMYX4ImXwoLhoR0xlN8mUdo
# rJ3bgnpCJWuI1531Z1rCwPuUrSkBxfOIGDk3p2ECb3Ho/xHi5PRSR/OUrWuQHwXi
# aXMTuXu3IRLezwVkZpFmNwYRD57R9Nx2F/yM7tzOY0Hh0hGCaYEK38/6FrS0SXad
# XWyDUCfn5XOGACRjUCnHx+JQUG0f4SHD+iblpAI0gl+ZHnVmdXXxHTZeTa0CYCIh
# FxKP2922s0g6zLmeiV13LWUmtt/UF7TrWXpMi2/0UNniaDoH7rnPGRV5xVX8uXy4
# sZii4aswzqPM7Y7+mzcranqZ8EjZk5gjLhQ3A2sZaprlOu8CaRmyfcIiVH7zVfgA
# vm81MWXFziAf7my7QOvnyEFPGddq8MSfPtfRyw/Uq3uH6KpoaJNIfPYH6fceZSi5
# 3Rat1A9grExq3ROjhhSpTcchuBItAMNVPxoKNbUm+iR/X3XkL+9WQginjyHe+hXL
# clY8vAGXFD1p40PqMIpAYsmEJBFKW9df4//1N5oQDr/FY9IBJl/oSS979i5rtT7N
# Zz9KvYraCPRBGs0QCy+sWvgQa0coM70QJVLeVwmSxUO/0od0w9Qry7bSLrxGoDCC
# B54wggWGoAMCAQICEzMAAAAHh6M0o3uljhwAAAAAAAcwDQYJKoZIhvcNAQEMBQAw
# dzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjFI
# MEYGA1UEAxM/TWljcm9zb2Z0IElkZW50aXR5IFZlcmlmaWNhdGlvbiBSb290IENl
# cnRpZmljYXRlIEF1dGhvcml0eSAyMDIwMB4XDTIxMDQwMTIwMDUyMFoXDTM2MDQw
# MTIwMTUyMFowYzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjE0MDIGA1UEAxMrTWljcm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2ln
# bmluZyBQQ0EgMjAyMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALLw
# wK8ZiCji3VR6TElsaQhVCbRS/3pK+MHrJSj3Zxd3KU3rlfL3qrZilYKJNqztA9OQ
# acr1AwoNcHbKBLbsQAhBnIB34zxf52bDpIO3NJlfIaTE/xrweLoQ71lzCHkD7A4A
# s1Bs076Iu+mA6cQzsYYH/Cbl1icwQ6C65rU4V9NQhNUwgrx9rGQ//h890Q8JdjLL
# w0nV+ayQ2Fbkd242o9kH82RZsH3HEyqjAB5a8+Ae2nPIPc8sZU6ZE7iRrRZywRmr
# KDp5+TcmJX9MRff241UaOBs4NmHOyke8oU1TYrkxh+YeHgfWo5tTgkoSMoayqoDp
# HOLJs+qG8Tvh8SnifW2Jj3+ii11TS8/FGngEaNAWrbyfNrC69oKpRQXY9bGH6jn9
# NEJv9weFxhTwyvx9OJLXmRGbAUXN1U9nf4lXezky6Uh/cgjkVd6CGUAf0K+Jw+GE
# /5VpIVbcNr9rNE50Sbmy/4RTCEGvOq3GhjITbCa4crCzTTHgYYjHs1NbOc6brH+e
# KpWLtr+bGecy9CrwQyx7S/BfYJ+ozst7+yZtG2wR461uckFu0t+gCwLdN0A6cFtS
# RtR8bvxVFyWwTtgMMFRuBa3vmUOTnfKLsLefRaQcVTgRnzeLzdpt32cdYKp+dhr2
# ogc+qM6K4CBI5/j4VFyC4QFeUP2YAidLtvpXRRo3AgMBAAGjggI1MIICMTAOBgNV
# HQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNlBKbAPD2Ns
# 72nX9c0pnqRIajDmMFQGA1UdIARNMEswSQYEVR0gADBBMD8GCCsGAQUFBwIBFjNo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5o
# dG0wGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAf
# BgNVHSMEGDAWgBTIftJqhSobyhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHeg
# dYZzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwSWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUl
# MjBBdXRob3JpdHklMjAyMDIwLmNybDCBwwYIKwYBBQUHAQEEgbYwgbMwgYEGCCsG
# AQUFBzAChnVodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRp
# ZmljYXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcnQwLQYIKwYBBQUHMAGGIWh0dHA6
# Ly9vbmVvY3NwLm1pY3Jvc29mdC5jb20vb2NzcDANBgkqhkiG9w0BAQwFAAOCAgEA
# fyUqnv7Uq+rdZgrbVyNMul5skONbhls5fccPlmIbzi+OwVdPQ4H55v7VOInnmezQ
# EeW4LqK0wja+fBznANbXLB0KrdMCbHQpbLvG6UA/Xv2pfpVIE1CRFfNF4XKO8XYE
# a3oW8oVH+KZHgIQRIwAbyFKQ9iyj4aOWeAzwk+f9E5StNp5T8FG7/VEURIVWArbA
# zPt9ThVN3w1fAZkF7+YU9kbq1bCR2YD+MtunSQ1Rft6XG7b4e0ejRA7mB2IoX5hN
# h3UEauY0byxNRG+fT2MCEhQl9g2i2fs6VOG19CNep7SquKaBjhWmirYyANb0RJSL
# WjinMLXNOAga10n8i9jqeprzSMU5ODmrMCJE12xS/NWShg/tuLjAsKP6SzYZ+1Ry
# 358ZTFcx0FS/mx2vSoU8s8HRvy+rnXqyUJ9HBqS0DErVLjQwK8VtsBdekBmdTbQV
# oCgPCqr+PDPB3xajYnzevs7eidBsM71PINK2BoE2UfMwxCCX3mccFgx6UsQeRSdV
# VVNSyALQe6PT12418xon2iDGE81OGCreLzDcMAZnrUAx4XQLUz6ZTl65yPUiOh3k
# 7Yww94lDf+8oG2oZmDh5O1Qe38E+M3vhKwmzIeoB1dVLlz4i3IpaDcR+iuGjH2Td
# aC1ZOmBXiCRKJLj4DT2uhJ04ji+tHD6n58vhavFIrmcxghcyMIIXLgIBATBxMFox
# CzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzAp
# BgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBBT0MgQ0EgMDMCEzMADFqH
# VWpHY2k8qpIAAAAMWocwDQYJYIZIAWUDBAIBBQCgXjAQBgorBgEEAYI3AgEMMQIw
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAvBgkqhkiG9w0BCQQxIgQg4K7M
# AoCx5TZ/iCs0HCfJ7j+ukkltguLX8ZYU3fX97uAwDQYJKoZIhvcNAQEBBQAEggGA
# SlflK68eGOi/K3rywoJIid4kXXyR6R+1IVJLCf4KqkFivqn3stHbN0hlXefdbU7f
# yzHHzG1CJEs1se3uoETLDml2LBT3crSY7MCeOhVy7INLT3SOmi7try2ufyl6ycfT
# G7fP64Urrn0lYw3bQ7vXFnrkSxc7kC49BrRICY/Z6Ub9J8CbczUmLB7nm5ICMegS
# F2zOQn0gaiCJXR4K0jQELvbv010Wi5STYJVD/sP447lH7+pyJ0DIEuXjgDG9v69d
# NB9oqUrsIOdd3R+LaEuBmHlaheE4nQvDIsGjeMNueIxnuvt5e4vU6eTcT6pN/zzu
# wMAiet8RCdGKW4VjeyL/977Qq2yPRhC3ldewZswLn43aU34U9Ryl+m5haY/a9gXG
# FRZrhvojK8y2wLrFcvG94nqctES7FJufXnPsjKY6Q5jU3/8sQjSBIGrtoN9cdvBJ
# tQoTqz3NgDN7azdqceSOCZAzosjL9BAnKBK8tCd0jJmdGFQi3wRTEpIBT0Gek2+i
# oYIUsjCCFK4GCisGAQQBgjcDAwExghSeMIIUmgYJKoZIhvcNAQcCoIIUizCCFIcC
# AQMxDzANBglghkgBZQMEAgEFADCCAWoGCyqGSIb3DQEJEAEEoIIBWQSCAVUwggFR
# AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEILas7o9SlFcmGbrSRog3
# Ceh2vfh9vTAMq88uDJehuiRdAgZq80s28mIYEzIwMjYxMTE4MTM0MzAzLjA2NVow
# BIACAfSggemkgeYwgeMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjdBMUEtMDVFMC1EOTQ3MTUwMwYD
# VQQDEyxNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0
# eaCCDykwggeCMIIFaqADAgECAhMzAAAABeXPD/9mLsmHAAAAAAAFMA0GCSqGSIb3
# DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24g
# Um9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAyMDAeFw0yMDExMTkyMDMyMzFa
# Fw0zNTExMTkyMDQyMzFaMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAnnznUmP94MWfBX1jtQYioxwe1+eXM9ETBb1lRkd3kcFdcG9/sqtDlwxKoVIc
# aqDb+omFio5DHC4RBcbyQHjXCwMk/l3TOYtgoBjxnG/eViS4sOx8y4gSq8Zg49RE
# Af5huXhIkQRKe3Qxs8Sgp02KHAznEa/Ssah8nWo5hJM1xznkRsFPu6rfDHeZeG1W
# a1wISvlkpOQooTULFm809Z0ZYlQ8Lp7i5F9YciFlyAKwn6yjN/kR4fkquUWfGmMo
# pNq/B8U/pdoZkZZQbxNlqJOiBGgCWpx69uKqKhTPVi3gVErnc/qi+dR8A2MiAz0k
# N0nh7SqINGbmw5OIRC0EsZ31WF3Uxp3GgZwetEKxLms73KG/Z+MkeuaVDQQheang
# OEMGJ4pQZH55ngI0Tdy1bi69INBV5Kn2HVJo9XxRYR/JPGAaM6xGl57Ei95HUw9N
# V/uC3yFjrhc087qLJQawSC3xzY/EXzsT4I7sDbxOmM2rl4uKK6eEpurRduOQ2hTk
# mG1hSuWYBunFGNv21Kt4N20AKmbeuSnGnsBCd2cjRKG79+TX+sTehawOoxfeOO/j
# R7wo3liwkGdzPJYHgnJ54UxbckF914AqHOiEV7xTnD1a69w/UTxwjEugpIPMIIE6
# 7SFZ2PMo27xjlLAHWW3l1CEAFjLNHd3EQ79PUr8FUXetXr0CAwEAAaOCAhswggIX
# MA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQUa2ko
# OjUvSGNAz3vYr0npPtk92yEwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUH
# AgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0
# b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMA
# dQBiAEMAQTAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFMh+0mqFKhvKGZgE
# ByfPUBBPaKiiMIGEBgNVHR8EfTB7MHmgd6B1hnNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNh
# dGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3Js
# MIGUBggrBgEFBQcBAQSBhzCBhDCBgQYIKwYBBQUHMAKGdWh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwSWRlbnRpdHklMjBW
# ZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBBdXRob3JpdHklMjAy
# MDIwLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAX4h2x35ttVoVdedMeGj6TuHYRJkl
# FaW4sTQ5r+k77iB79cSLNe+GzRjv4pVjJviceW6AF6ycWoEYR0LYhaa0ozJLU5Yi
# +LCmcrdovkl53DNt4EXs87KDogYb9eGEndSpZ5ZM74LNvVzY0/nPISHz0Xva71Qj
# D4h+8z2XMOZzY7YQ0Psw+etyNZ1CesufU211rLslLKsO8F2aBs2cIo1k+aHOhrw9
# xw6JCWONNboZ497mwYW5EfN0W3zL5s3ad4Xtm7yFM7Ujrhc0aqy3xL7D5FR2J7x9
# cLWMq7eb0oYioXhqV2tgFqbKHeDick+P8tHYIFovIP7YG4ZkJWag1H91KlELGWi3
# SLv10o4KGag42pswjybTi4toQcC/irAodDW8HNtX+cbz0sMptFJK+KObAnDFHEsu
# kxD+7jFfEV9Hh/+CSxKRsmnuiovCWIOb+H7DRon9TlxydiFhvu88o0w35JkNbJxT
# k4MhF/KgaXn0GxdH8elEa2Imq45gaa8D+mTm8LWVydt4ytxYP/bqjN49D9NZ81co
# E6aQWm88TwIf4R4YZbOpMKN0CyejaPNN41LGXHeCUMYmBx3PkP8ADHD1J2Cr/6tj
# uOOCztfp+o9Nc+ZoIAkpUcA/X2gSMkgHAPUvIdtoSAHEUKiBhI6JQivRepyvWcl+
# JYbYbBh7pmgAXVswggefMIIFh6ADAgECAhMzAAAAW0q1jUEybdx0AAAAAABbMA0G
# CSqGSIb3DQEBDAUAMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVz
# dGFtcGluZyBDQSAyMDIwMB4XDTI2MDEwODE4NTkwNVoXDTI3MDEwNzE4NTkwNVow
# geMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
# JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMe
# blNoaWVsZCBUU1MgRVNOOjdBMUEtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3Nv
# ZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAJBUzBbbnlDXee0B0KD5G4/475thFyfctCyu
# ESTWQXvlLi4Wx/td2qUdeq4ideeg6VWhiOHfu3wJV4TUGSRtqh9Ccr1BmiBKv9iu
# FpgHyIBu5Qx38ZsxwlFeXVS+ZqJJKnXRbDNQdcYSoC/6c0hQJ/PH50DBRDQkPXVw
# yFizLrRH9AlrJeUg7BKeT23zftS8/KOJLvEEbHOF6pSOY3ZVprZUWbWjWwRTmoHa
# Q/E8vrWtLNyEJ+b089VW1Ikra3t4GTB5Wby3CL1K2zYnAxBIvafsKMFyj9OuXHcT
# PKMDoFSMeamG9MKOMb6uoG1PjdnDgsLP6EOMRSzrLL7jED1mbB9RSd9fhty+HQr6
# vZgsBn6oUy+YTpNVLskwdtUM82WYAkPztlOt3AiL0qyV7/U3j/uq3vHMjPM0w034
# 0M57Nei0g4BCcMt0dbqoc91VgCb3/36sHQANontn1HOF2oLk8190QRS43isHVra8
# H8sf5+GlqIYsYiCKX04HZiOzZW826nVI6d++8lyTeWmpj90Ua9uPbJhVjwE3oh6t
# O510ySqmSMSLEN07p3Ibe3E6BAb2w93rWzb26+dpSthbKF4kApofqBsWPX4MEtHK
# SOftPmVTCQ47tghrVuHia9jY+Hsj01m4KW4WtkmVm3L6hMZECMa4sjMxAXz+bX/A
# JhWTe6TZAgMBAAGjggHLMIIBxzAdBgNVHQ4EFgQU7/LqUlWWYhXJdXwgYKx4b8Gv
# 0rYwHwYDVR0jBBgwFoAUa2koOjUvSGNAz3vYr0npPtk92yEwbAYDVR0fBGUwYzBh
# oF+gXYZbaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9z
# b2Z0JTIwUHVibGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNy
# bDB5BggrBgEFBQcBAQRtMGswaQYIKwYBBQUHMAKGXWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIw
# VGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNydDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBmBgNVHSAEXzBdMFEG
# DCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wCAYGZ4EMAQQCMA0GCSqG
# SIb3DQEBDAUAA4ICAQAAH+zd+XKh4OxXYMWFmtgilXAQGctOjCUB1w/uBiC/OXcH
# 3Ia4/XbdUhKzFbaiTbIE6vYZKd1p4u7nKOLkawymAMVyuO7LSl6rLKttZIyLhWjT
# K0zXOz0u4xLq9+bRtBEKJvA6sD5nJwH1IO6z1YizyuIRoalMCnbrUixfWxQn4TAm
# N7t9uk+X2FUThEa3ewzRwhtG+xwaAbLMkxRmR24JnfXd1VxKo90+m7Wzuov96Uug
# x5wZdewiIIm1ZWTj4lCJHup679LcOa7tAxJMipVaSltQH9fm9TOKczlfxtWuBcLU
# 4duZfqwgsILsH7PMkcX1zwQzQD0yAtPhnYz9KNG125bX+iilOe1S8RHqv2bbBpMp
# ao4kcUvQI6dMgKRvFmm1eLbhSNOQplDMTGD1tNVdNGkI96jUu+troUjWMMi46TQf
# BAHxtDTpRhIu/87vAVQ8Z6RHhFxesz4Ed5JThaIQRAy6GcO/Jk+QzDzoZ0arRIkI
# sGJ7rZgOVAjx9ctfw8lH9RfjcwB3wdGBYNMNVJqQpUai2Taddf5pXzTZEHIqLEF5
# 3SrBjIeInoQrP7U5VlXiMQsxewLdINrAE2l2TR3KBikb+RQRygbTp8jj2yiC0NCU
# wG+K+ndglN5RMbXjFW6aKa59Xq+b8XzK/DK+AJtgOpHgJv8Qrk62A+twOVLOpjGC
# A9QwggPQAgEBMHgwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABbSrWNQTJt3HQAAAAAAFswDQYJYIZIAWUDBAIB
# BQCgggEtMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgwZExAHdiMcSy9YjBBtrwabiWTb3Qj9Ct59hEFG1d+xQwgd0GCyqGSIb3DQEJ
# EAIvMYHNMIHKMIHHMIGgBCAvMQNVXZ0b0xxlGw8X/3IEybObuT6a5W1d61CW+cGD
# 7zB8MGWkYzBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBp
# bmcgQ0EgMjAyMAITMwAAAFtKtY1BMm3cdAAAAAAAWzAiBCAvBX47N35sG98AzKot
# 6LIPANnZF24XKYSYB+wUXYPfUTANBgkqhkiG9w0BAQsFAASCAgBQVkqquKmBV5JW
# 4a5S1UU0PtbGFHxXXZzY9AIRHQhqLt9dIerp6DBf5FgNmPJmNP+BB8RdSAaWk0Ca
# 3eRizkm8vy193TZnQe214hqIusiuvW6gmjzDP5C46C/QHHVnVQbXJco4ZY4cKsi0
# vF4BsGAQF7s+pnd2mswXrNX/NjTQiss6K5WRcSydAM3Yl78W5CYnNEiVTVyzLc8m
# +LzODLg2HtDjLyuy7sk049sGecJ1kPWgjqnwC6Mv0Fv5ofREW3GBkarKFbwAAT7F
# 1yaD/y6ZicDvlEjxEtA6hEVf/yPNHRBpcoW14FpvqmpAcgrrjo3BNoV47pIjrSGV
# h/tndcv1sQlpdGBAysMXR9BQnjvyXjRA6JwIbDsGQwnLH2b1LWJM5uP1W6l1NOUK
# PzxLk2ezWQJRJTdouT40GDpZ3Rr51Ollz5VE9tQam+ey9xz436wKpFXe6RmXxihL
# 8ACvrQda093FwDc6Xl/EWoJw4O9fOk70IEZvl1wwBvQ6dAn0mJx0/TIwgCFhGW8F
# OVIxnx7RJ1t/ty5enjWLmiGpkpiPLVfJfcWZbWqqEXhP+rB/jnhPBYqwiKM/3ciJ
# l09q8GFBXaWnu6YED/7Dfg6KDgDywY+IBzD3AeaPu+5roh0LhYn/mx1KKYhMKy3w
# sBUFQS9HaEYqb67TBf1HbVYT7LiMvA==
# SIG # End signature block
