<#
.SYNOPSIS
    Reads, decodes, and correlates Ivanti Workspace Control policy sets from a Building Block XML file.
.DESCRIPTION
    Reads an Ivanti Workspace Control Building Block XML file, pre-loads all embedded ADMX/ADML
    templates, and processes each policy set found within the file. For each policy set it correlates
    the applied registry settings with their ADMX definitions (via Get-AdmxPolicySetting) and returns
    a structured PowerShell object per policy set.

    Supports two export modes via -ExportFor:
    - WEM: returns correlated policy data only (default).
    - AppVentiX: additionally returns an AppVentiXParams property containing pre-structured policy
      data ready to pass directly to New-AppVentiXGroupPolicy -PolicyInputObject.

    Policy state (Enabled/Disabled/Unconfigured) is determined in priority order:
    1. POLICY:1/2 indicator from the embedded PolicySettings data.
    2. Policy-level registry value compared against ADMX enabledValue/disabledValue.
    3. Presence of element-level registry values (implies Enabled).

    List-type ADMX elements (values stored as numbered entries under a sub-key) are fully supported.
    Boolean elements with explicit trueValue/falseValue nodes are resolved correctly.

    Registry values written by enabledList, disabledList and enum valueList nodes have no ADMX element
    of their own. They are matched to their owning policy, exposed as AuxiliaryValues, and exported as
    registry entries only (they do not create extra policy elements).
.PARAMETER Path
    Path to the Ivanti Workspace Control Building Block XML file.
.PARAMETER IncludeADMFiles
    If specified, includes the ADMX and ADML filenames and their base64-encoded content in the output
    for each policy set. Required when piping output to New-AppVentiXGroupPolicy.
.PARAMETER ExportFor
    Target export format. 'AppVentiX' adds the AppVentiXParams property to each output object.
    Defaults to 'WEM'.
.PARAMETER IncludePolicyDescription
    If specified, includes the ADMX ExplainText (policy description) in the PolicySettings output.
.PARAMETER SaveResourceFiles
    If specified, saves the decoded ADMX/ADML files and the raw PolicySettings/RegistryFile data
    to disk at the path specified by -ExportPath.
.PARAMETER ExportPath
    Directory path where decoded resource files are saved when -SaveResourceFiles is used.
.EXAMPLE
    # Export policy data for use with AppVentiX
    $Policies = Get-IvantiWCPolicy -Path 'C:\temp\LAB-BB.xml' -IncludeADMFiles -ExportFor AppVentiX
    $result = $Policies | ForEach-Object {
        New-AppVentiXGroupPolicy `
            -FriendlyName $_.Name `
            -AdmxContent $_.ADMXContent `
            -AdmxFileName $_.ADMX `
            -AdmlContent $_.ADMLContent `
            -AdmlFileName $_.ADML `
            -PolicyInputObject $_.AppVentiXParams
    }
.EXAMPLE
    # Inspect correlated policy data as JSON
    Get-IvantiWCPolicy -Path 'C:\temp\LAB-BB.xml' | ConvertTo-Json -Depth 5
.EXAMPLE
    # Save decoded resource files for inspection
    Get-IvantiWCPolicy -Path 'C:\temp\LAB-BB.xml' -SaveResourceFiles -ExportPath 'C:\temp\TempPolicy'
.NOTES
    Function  : Get-IvantiWCPolicy
    Author    : John Billekens
    Copyright   : (c) John Billekens Consultancy
    Version   : 2026.1118.1200
#>
function Get-IvantiWCPolicy {
    [CmdletBinding(DefaultParameterSetName = 'AppVentiX')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$IncludeADMFiles,

        [ValidateSet("AppVentiX", "WEM")]
        [string]$ExportFor = "WEM",

        [switch]$IncludePolicyDescription,

        [Parameter(Mandatory = $true, ParameterSetName = 'Export')]
        [switch]$SaveResourceFiles,

        [Parameter(Mandatory = $true, ParameterSetName = 'Export')]
        [string]$ExportPath
    )

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
        param(
            [string]$hexString,
            [string]$type
        )

        # Extract hex bytes (remove hex(X): prefix and commas/spaces)
        $hexData = $hexString -replace '^hex\(\w+\):', '' -replace '[,\s]', ''

        if ([string]::IsNullOrEmpty($hexData)) { return $null }

        try {
            $bytes = for ($i = 0; $i -lt $hexData.Length; $i += 2) {
                [System.Convert]::ToByte($hexData.Substring($i, 2), 16)
            }

            switch ($type) {
                'REG_SZ' {
                    # hex(1) - null-terminated Unicode string
                    return [System.Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
                }
                'REG_EXPAND_SZ' {
                    # hex(2) - expandable string
                    return [System.Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
                }
                'REG_BINARY' {
                    # hex(3) or hex - binary data
                    return [System.BitConverter]::ToString($bytes)
                }
                'REG_DWORD' {
                    # hex(4) - 32-bit number (little-endian)
                    if ($bytes.Count -eq 4) {
                        return [System.BitConverter]::ToUInt32($bytes, 0)
                    }
                    return $null
                }
                'REG_MULTI_SZ' {
                    # hex(7) - multiple null-terminated strings
                    $fullString = [System.Text.Encoding]::Unicode.GetString($bytes)
                    return [array]($fullString -split '\0' | Where-Object { $_ })
                }
                'REG_QWORD' {
                    # hex(b) - 64-bit number (little-endian)
                    if ($bytes.Count -eq 8) {
                        return [System.BitConverter]::ToUInt64($bytes, 0)
                    }
                    return $null
                }
                default {
                    return [System.BitConverter]::ToString($bytes)
                }
            }
        } catch {
            Write-Warning "Could not decode hex value for type $type. Error: $_"
            return $hexString
        }
    }

    function Convert-HexToStream {
        param([string]$HexString)
        if ([string]::IsNullOrEmpty($HexString)) { return $null }
        try {
            $bytes = for ($i = 0; $i -lt $HexString.Length; $i += 2) {
                [System.Convert]::ToByte($HexString.Substring($i, 2), 16)
            }
            # A MemoryStream is more efficient for large data than holding a giant string
            $memStream = New-Object System.IO.MemoryStream(, $bytes)
            return $memStream
        } catch {
            Write-Warning "Could not convert hex string to stream. Error: $_"
            return $null
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


    try {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            throw "File not found at path: $Path"
        }

        # Resolve to absolute path
        $absolutePath = (Resolve-Path -Path $Path).Path
        Write-Verbose "Loading XML file: $absolutePath"
        # ConvertFrom-IvantiBB strips <webtop> sections, these contain nested XML declarations that XmlDocument rejects
        $xmlContent = ConvertFrom-IvantiBB -XmlFilePath $absolutePath

        # 1. Pre-load all ADM templates
        Write-Verbose "Pre-loading embedded ADMX/ADML templates..."
        $admTemplateStore = @{}
        $embeddedPolicies = $xmlContent.GetElementsByTagName('embeddedadm')
        $embeddedCount = $embeddedPolicies.Count
        Write-Verbose "Found $embeddedCount embedded template(s)"

        $templateCount = 0
        foreach ($adm in $embeddedPolicies) {
            $fileName = $adm.filename
            if (-not $admTemplateStore.ContainsKey($fileName)) {
                $templateCount++
                Write-Progress -Activity "Loading ADMX templates" -Status "$fileName" -PercentComplete ([int]($templateCount / [Math]::Max($embeddedCount, 1) * 100))
                Write-Verbose "Loading template $templateCount/$embeddedCount`: $fileName"
                $admlFileName = $fileName -replace '.admx$', '.adml'

                $admxStream = Convert-HexToStream -HexString $adm.embeddedbinary
                $admlStream = Convert-HexToStream -HexString $adm.embeddedadml

                if ($null -eq $admxStream) {
                    Write-Warning "Failed to decode ADMX template: $fileName"
                    continue
                }

                $admxReader = $null
                $admlReader = $null
                try {
                    # Read through a StreamReader so the byte order mark decides the encoding.
                    # The Office ADMX templates declare encoding="utf-16" while holding UTF-8 bytes,
                    # which makes a direct stream Load throw "There is no Unicode byte order mark".
                    $admxReader = New-Object System.IO.StreamReader($admxStream, [System.Text.Encoding]::UTF8, $true)
                    $admxXml = New-Object System.Xml.XmlDocument
                    $admxXml.Load($admxReader)

                    $admlXml = New-Object System.Xml.XmlDocument
                    if ($null -ne $admlStream) {
                        $admlReader = New-Object System.IO.StreamReader($admlStream, [System.Text.Encoding]::UTF8, $true)
                        $admlXml.Load($admlReader)
                    }

                    $admxBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($admxXml.OuterXml))
                    $admlBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($admlXml.OuterXml))

                    # Pre-load all policy settings from this template via Get-AdmxPolicySetting
                    Write-Verbose "  Indexing policy settings for: $fileName"
                    $allPolicySettings = Get-AdmxPolicySetting -AdmxContent $admxBase64 -AdmlContent $admlBase64 -AdmxFileName $fileName -AdmlFileName $admlFileName -All

                    # Build lookup: normalized RegistryKey\ValueName -> list of @{Policy; Element} objects
                    # Policy-level valueName maps to Element=$null; element valueName maps to the element object
                    # listLookup: normalized RegistryKey -> list of @{Policy; Element} for 'list' element types
                    # auxLookup: normalized RegistryKey\ValueName -> list of @{Policy; Auxiliary} for values written
                    #            by <enabledList>/<disabledList>/<valueList> nodes (no matching ADMX element)
                    $policyLookup = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $listLookup = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $auxLookup = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($ps in $allPolicySettings) {
                        # Policy-level (enabledValue/disabledValue controls this valueName)
                        if (-not [string]::IsNullOrEmpty($ps.ValueName)) {
                            $lookupKey = "$($ps.RegistryKey)\$($ps.ValueName)"
                            if (-not $policyLookup.ContainsKey($lookupKey)) {
                                $policyLookup[$lookupKey] = [System.Collections.Generic.List[object]]::new()
                            }
                            $policyLookup[$lookupKey].Add([PSCustomObject]@{ Policy = $ps; Element = $null })
                        }
                        # Element-level entries
                        foreach ($elem in $ps.Elements) {
                            if ($elem.ElementType -eq 'list') {
                                # List elements have no fixed valueName - index by their sub-key
                                $listKey = $elem.RegistryKey
                                if (-not $listLookup.ContainsKey($listKey)) {
                                    $listLookup[$listKey] = [System.Collections.Generic.List[object]]::new()
                                }
                                $listLookup[$listKey].Add([PSCustomObject]@{ Policy = $ps; Element = $elem })
                            } else {
                                $elemLookupKey = "$($elem.RegistryKey)\$($elem.ValueName)"
                                if (-not $policyLookup.ContainsKey($elemLookupKey)) {
                                    $policyLookup[$elemLookupKey] = [System.Collections.Generic.List[object]]::new()
                                }
                                $policyLookup[$elemLookupKey].Add([PSCustomObject]@{ Policy = $ps; Element = $elem })
                            }
                        }
                        # Auxiliary values (enabledList/disabledList/valueList) - resolve to the policy only
                        foreach ($aux in $ps.AuxiliaryValues) {
                            if ([string]::IsNullOrEmpty($aux.ValueName)) { continue }
                            $auxLookupKey = "$($aux.RegistryKey)\$($aux.ValueName)"
                            if (-not $auxLookup.ContainsKey($auxLookupKey)) {
                                $auxLookup[$auxLookupKey] = [System.Collections.Generic.List[object]]::new()
                            }
                            $auxLookup[$auxLookupKey].Add([PSCustomObject]@{ Policy = $ps; Auxiliary = $aux })
                        }
                    }

                    $admTemplateStore[$fileName] = [PSCustomObject]@{
                        ADMXFile     = $fileName
                        ADMLFile     = $admlFileName
                        ADMXContent  = $admxBase64
                        ADMLContent  = $admlBase64
                        PolicyLookup = $policyLookup
                        ListLookup   = $listLookup
                        AuxLookup    = $auxLookup
                    }

                    if ($SaveResourceFiles.IsPresent -eq $true) {
                        $id = [System.Guid]::NewGuid().ToString()
                        if (-not (Test-Path -Path $ExportPath)) {
                            New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
                        }
                        $admxExportPath = Join-Path -Path $ExportPath -ChildPath "$($id)_$($fileName)"
                        $admlExportPath = Join-Path -Path $ExportPath -ChildPath "$($id)_$($admlFileName)"
                        $admxXml.Save($admxExportPath)
                        $admlXml.Save($admlExportPath)
                    }
                } finally {
                    # Ensure readers and streams are always closed
                    if ($null -ne $admxReader) { $admxReader.Dispose() }
                    if ($null -ne $admlReader) { $admlReader.Dispose() }
                    if ($null -ne $admxStream) { $admxStream.Dispose() }
                    if ($null -ne $admlStream) { $admlStream.Dispose() }
                }
            }
        }

        # 2. Process each policy set
        $registryNodes = @($xmlContent.GetElementsByTagName('registry') | Where-Object { $_.type -eq 'policy' })
        $totalPolicySets = $registryNodes.Count
        Write-Verbose "Processing $totalPolicySets policy set(s)"

        $policySetIndex = 0
        foreach ($registryNode in $registryNodes) {
            $policySetIndex++
            $policySetName = $registryNode.name
            Write-Progress -Activity "Processing policy sets" -Status "$policySetName ($policySetIndex/$totalPolicySets)" -PercentComplete ([int]($policySetIndex / [Math]::Max($totalPolicySets, 1) * 100))
            Write-Verbose "Processing policy set $policySetIndex/$totalPolicySets`: $policySetName"
            $decodedPolicySettingsStr = (Convert-HexToString -HexString $registryNode.policysettings).TrimStart([char]0xFEFF)
            $decodedRegistryFileStr = (Convert-HexToString -HexString $registryNode.registryfile).TrimStart([char]0xFEFF)

            $Assignments = @(ConvertFrom-IvantiAccessControl -AccessControl $registryNode.accesscontrol -IWCComponentName $policySetName -IWCComponent "Policy")

            if ($SaveResourceFiles.IsPresent -eq $true) {
                $id = [System.Guid]::NewGuid().ToString()
                if (-not (Test-Path -Path $ExportPath)) {
                    New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
                }
                $policySettingsExportPath = Join-Path -Path $ExportPath -ChildPath "$($id)_$($policySetName)_PolicySettings.txt"
                $decodedPolicySettingsStr | Out-File -FilePath $policySettingsExportPath -Encoding UTF8
                $registryFileExportPath = Join-Path -Path $ExportPath -ChildPath "$($id)_$($policySetName)_RegistryFile.txt"
                $decodedRegistryFileStr | Out-File -FilePath $registryFileExportPath -Encoding UTF8
            }

            $admxFileNameMatch = $decodedPolicySettingsStr | Select-String -Pattern "ADMFILENAME:(.*)"
            if (-not $admxFileNameMatch) {
                Write-Warning "Policy set '$policySetName' does not specify an ADMX template file (ADMFILENAME not found)"
                continue
            }
            $admxFileName = $admxFileNameMatch.Matches.Groups[1].Value.Trim()
            Write-Verbose "  Using ADMX template: $admxFileName"

            # Parse PolicySettings.txt: build lookup DisplayName -> ConfiguredState
            # Format: POLICY:1:Class||Category|...|DisplayName  (1=Enabled, 2=Disabled)
            $policyStateFromSettings = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($settingsLine in $decodedPolicySettingsStr.Split([string[]]@("`r`n", "`n", "`r"), [StringSplitOptions]::RemoveEmptyEntries)) {
                if ($settingsLine -match '^POLICY:(\d+):[^|]+\|+(.+)$') {
                    $stateCode = $matches[1]
                    $displayPath = $matches[2]
                    $displayName = ($displayPath -split '\|')[-1].Trim()
                    $configuredState = switch ($stateCode) {
                        '1' { 'Enabled' }
                        '2' { 'Disabled' }
                        default { 'Unconfigured' }
                    }
                    if (-not $policyStateFromSettings.ContainsKey($displayName)) {
                        $policyStateFromSettings[$displayName] = $configuredState
                    }
                }
            }
            Write-Verbose "  Parsed $($policyStateFromSettings.Count) policy state(s) from PolicySettings"

            if (-not $admTemplateStore.ContainsKey($admxFileName)) {
                Write-Warning "Policy set '$policySetName' references ADMX template '$admxFileName' which was not found in embedded templates"
                continue
            }

            $currentTemplate = $admTemplateStore[$admxFileName]
            $policyLookup = $currentTemplate.PolicyLookup
            $listLookup = $currentTemplate.ListLookup
            $auxLookup = $currentTemplate.AuxLookup

            $regLines = $decodedRegistryFileStr.Split([string[]]@("`r`n", "`n", "`r"), [StringSplitOptions]::None)
            $currentSectionHive = ''
            $currentSectionKey = ''
            $currentListEntry = $null   # non-null when we're inside a list element sub-key section
            $currentListValues = $null   # accumulates string values for the current list section

            # Collect all matched registry entries grouped by PolicyName
            # Key: PolicyName, Value: @{ Policy; PolicyLevelEntry; ElementEntries: list }
            $policyGroups = [System.Collections.Generic.Dictionary[string, hashtable]]::new()

            for ($i = 0; $i -lt $regLines.Length; $i++) {
                $line = $regLines[$i]

                # Track the current section header (optional leading ! = delete key marker)
                if ($line -match '^!?\[((HKEY_[^\\]+)\\(.+?))\]') {
                    # If we just finished a list section, commit each item as a separate element entry
                    if ($null -ne $currentListEntry -and $null -ne $currentListValues -and $currentListValues.Count -gt 0) {
                        $listMatchedPolicy = $currentListEntry.Policy
                        $listMatchedElement = $currentListEntry.Element

                        if (-not $policyGroups.ContainsKey($listMatchedPolicy.PolicyName)) {
                            $policyGroups[$listMatchedPolicy.PolicyName] = @{
                                Policy           = $listMatchedPolicy
                                PolicyLevelEntry = $null
                                ElementEntries   = [System.Collections.Generic.List[PSCustomObject]]::new()
                                AuxiliaryEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
                                PFCategory       = ''
                                PFDisplayText    = ''
                            }
                        }
                        $policyGroups[$listMatchedPolicy.PolicyName].ElementEntries.Add([PSCustomObject]@{
                                ElementId          = $listMatchedElement.ElementId
                                ElementType        = 'list'
                                ConfiguredState    = 'Enabled'
                                Delete             = $false
                                RegistryHive       = $currentSectionHive
                                RegistryKey        = $listMatchedElement.RegistryKey
                                RegistryKeyPath    = "$currentSectionHive\$($listMatchedElement.RegistryKey)"
                                RegistryValueName  = ''
                                RegistryValue      = @($currentListValues | ForEach-Object { $_.Value })
                                RegistryValueNames = @($currentListValues | ForEach-Object { $_.ValueName })
                                RegistryValueType  = 'REG_SZ'
                                RegistryType       = $listMatchedElement.RegistryType
                                Constraints        = $listMatchedElement.Constraints
                                EnumItems          = $null
                                TrueValue          = $null
                                FalseValue         = $null
                            })
                        Write-Verbose "    Committed list element '$($listMatchedElement.ElementId)' with $($currentListValues.Count) item(s) for policy '$($listMatchedPolicy.PolicyName)'"
                    }

                    $currentSectionHive = $matches[2]
                    $currentSectionKey = $matches[3]

                    # Check if this new section is a list element sub-key
                    $normalizedSectionKey = $currentSectionKey -replace '^(HKEY_LOCAL_MACHINE|HKLM|HKEY_CURRENT_USER|HKCU)\\', ''
                    $listCandidates = $listLookup[$normalizedSectionKey]
                    if ($listCandidates -and $listCandidates.Count -gt 0) {
                        $currentListEntry = $listCandidates[0]   # take first match; list sub-keys are unique
                        $currentListValues = [System.Collections.Generic.List[object]]::new()
                        Write-Verbose "    Entering list element section: '$normalizedSectionKey' -> '$($currentListEntry.Policy.PolicyName)' element '$($currentListEntry.Element.ElementId)'"
                    } else {
                        $currentListEntry = $null
                        $currentListValues = $null
                    }
                }

                # Handle deletion markers
                $isDeletion = $false
                if ($line.TrimStart().StartsWith('!"')) {
                    $isDeletion = $true
                    $line = $line.TrimStart().Substring(1)
                    Write-Verbose "  Found deletion marker at line $($i + 1)"
                }

                if ($line -match '^"([^"]+)"=(.+)') {
                    $policyNameFromReg = $matches[1]
                    $rawValue = $matches[2].Trim()

                    # If we're inside a list element section, collect each item as {ValueName; Value}
                    if ($null -ne $currentListEntry -and $policyNameFromReg -match '^\d+$') {
                        $itemValue = if ($rawValue.StartsWith('"') -and $rawValue.EndsWith('"')) {
                            Convert-RegEscapedString -Value $rawValue.Substring(1, $rawValue.Length - 2)
                        } else { $rawValue }
                        $currentListValues.Add([PSCustomObject]@{ ValueName = $policyNameFromReg; Value = $itemValue })
                        continue
                    }

                    # Look for PF comment on the next line
                    $pfComment = ''
                    $pfCategory = ''
                    $pfDisplayText = ''
                    if (($i + 1) -lt $regLines.Length -and $regLines[$i + 1].TrimStart().StartsWith(';<PF>')) {
                        if ($regLines[$i + 1] -match ';<PF>(.*)</PF>') {
                            $pfComment = $matches[1]
                            if ($pfComment -match '^(HKEY_[^\\]+)\\([^\\]+)\\(.+)$') {
                                $pfCategory = $matches[2]
                                $pfDisplayText = $matches[3]
                            }
                        }
                    }

                    $registryValue = $null
                    $registryValueType = 'Unknown'

                    if ($rawValue.StartsWith('dword:') -or $rawValue.StartsWith('qword:')) {
                        $registryValueType = if ($rawValue.StartsWith('dword:')) { 'REG_DWORD' } else { 'REG_QWORD' }
                        try {
                            $registryValue = [uint64]("0x" + $rawValue.Split(':')[1])
                        } catch {
                            Write-Warning "Could not parse numeric value for '$policyNameFromReg': $rawValue. Error: $_"
                            $registryValue = $rawValue
                            $registryValueType = 'Unknown'
                        }
                    } elseif ($rawValue.StartsWith('"') -and $rawValue.EndsWith('"')) {
                        $registryValueType = 'REG_SZ'
                        $registryValue = Convert-RegEscapedString -Value $rawValue.Substring(1, $rawValue.Length - 2)
                    } elseif ($rawValue.StartsWith('hex')) {
                        if ($rawValue.StartsWith('hex(1):')) {
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
                            $registryValueType = 'REG_BINARY'
                            $registryValue = Convert-RegistryHexToValue -hexString $rawValue -type 'REG_BINARY'
                        }
                    } else {
                        $registryValueType = 'REG_SZ'
                        $registryValue = $rawValue
                    }

                    # Lookup policy via normalized key\valueName
                    $normalizedKey = $currentSectionKey -replace '^(HKEY_LOCAL_MACHINE|HKLM|HKEY_CURRENT_USER|HKCU)\\', ''
                    $lookupKey = "$normalizedKey\$policyNameFromReg"
                    $candidatePolicies = $policyLookup[$lookupKey]

                    $matchedEntry = $null
                    if ($candidatePolicies -and $candidatePolicies.Count -gt 1) {
                        $policyNames = ($candidatePolicies | ForEach-Object { $_.Policy.PolicyName }) -join ', '

                        if ($pfComment) {
                            foreach ($candidate in $candidatePolicies) {
                                if ($pfComment -match [regex]::Escape($candidate.Policy.RegistryKey)) {
                                    $matchedEntry = $candidate
                                    Write-Verbose "    Selected '$($candidate.Policy.PolicyName)' from multiple matches ($policyNames) based on registry key path match"
                                    break
                                }
                            }
                        }

                        if (-not $matchedEntry) {
                            $nonRecommended = $candidatePolicies | Where-Object { $_.Policy.PolicyName -notmatch '_recommended$' } | Select-Object -First 1
                            if ($nonRecommended) {
                                $matchedEntry = $nonRecommended
                                Write-Verbose "    Selected '$($matchedEntry.Policy.PolicyName)' from multiple matches ($policyNames) - preferred non-recommended policy"
                            }
                        }

                        if (-not $matchedEntry) {
                            $matchedEntry = $candidatePolicies[0]
                            Write-Warning "    Multiple policies found for '$lookupKey': $policyNames. Selected '$($matchedEntry.Policy.PolicyName)' (first match)"
                        }
                    } else {
                        $matchedEntry = $candidatePolicies | Select-Object -First 1
                    }

                    if ($matchedEntry) {
                        $matchedPolicy = $matchedEntry.Policy
                        $matchedElement = $matchedEntry.Element  # $null = policy-level match

                        Write-Verbose "    Matched policy: $($matchedPolicy.PolicyName) ($(if ($null -ne $matchedElement) { $matchedElement.ElementType } else { 'policy-level' }))"

                        # Ensure group entry exists for this policy
                        if (-not $policyGroups.ContainsKey($matchedPolicy.PolicyName)) {
                            $policyGroups[$matchedPolicy.PolicyName] = @{
                                Policy           = $matchedPolicy
                                PolicyLevelEntry = $null   # filled when policy-level valueName is matched
                                ElementEntries   = [System.Collections.Generic.List[PSCustomObject]]::new()
                                AuxiliaryEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
                                PFCategory       = $pfCategory
                                PFDisplayText    = $pfDisplayText
                            }
                        }

                        if ($null -eq $matchedElement) {
                            # Policy-level match (NoAutoUpdate, etc.) - determines ConfiguredState of the policy
                            $configuredState = 'Unconfigured'
                            if ($null -ne $matchedPolicy.EnabledValue -and "$registryValue" -eq "$($matchedPolicy.EnabledValue)") {
                                $configuredState = 'Enabled'
                            } elseif ($null -ne $matchedPolicy.DisabledValue -and "$registryValue" -eq "$($matchedPolicy.DisabledValue)") {
                                $configuredState = 'Disabled'
                            } elseif ($registryValueType -in @('REG_DWORD', 'REG_QWORD')) {
                                $configuredState = if ($registryValue -ne 0) { 'Enabled' } else { 'Disabled' }
                            } else {
                                $configuredState = 'Enabled'
                            }

                            $policyGroups[$matchedPolicy.PolicyName].PolicyLevelEntry = [PSCustomObject]@{
                                ConfiguredState   = $configuredState
                                Delete            = $isDeletion
                                RegistryHive      = $currentSectionHive
                                RegistryKey       = $matchedPolicy.RegistryKey
                                RegistryKeyPath   = "$currentSectionHive\$($matchedPolicy.RegistryKey)"
                                RegistryValueName = $policyNameFromReg
                                RegistryValue     = $registryValue
                                RegistryValueType = $registryValueType
                            }
                        } else {
                            # Element-level match
                            $elemType = $matchedElement.ElementType

                            # Determine ConfiguredState for boolean elements with explicit trueValue/falseValue
                            $configuredState = if ($elemType -eq 'boolean' -and $null -ne $matchedElement.TrueValue -and $null -ne $matchedElement.FalseValue) {
                                if ("$registryValue" -eq "$($matchedElement.TrueValue)") { 'Enabled' }
                                elseif ("$registryValue" -eq "$($matchedElement.FalseValue)") { 'Disabled' }
                                else { 'Enabled' }  # presence implies enabled
                            } else {
                                'Enabled'  # presence of any element value means policy is enabled
                            }

                            $elemEntry = [PSCustomObject]@{
                                ElementId         = $matchedElement.ElementId
                                ElementType       = $elemType
                                ConfiguredState   = $configuredState
                                Delete            = $isDeletion
                                RegistryHive      = $currentSectionHive
                                RegistryKey       = $matchedElement.RegistryKey
                                RegistryKeyPath   = "$currentSectionHive\$($matchedElement.RegistryKey)"
                                RegistryValueName = $policyNameFromReg
                                RegistryValue     = $registryValue
                                RegistryValueType = $registryValueType
                                RegistryType      = $matchedElement.RegistryType
                                Constraints       = $matchedElement.Constraints
                                EnumItems         = $matchedElement.EnumItems
                                TrueValue         = $matchedElement.TrueValue
                                FalseValue        = $matchedElement.FalseValue
                            }
                            $policyGroups[$matchedPolicy.PolicyName].ElementEntries.Add($elemEntry)
                        }
                    } else {
                        # No element matched - check the auxiliary values written by enabledList/disabledList/valueList
                        $matchedAux = $auxLookup[$lookupKey] | Select-Object -First 1

                        if ($matchedAux) {
                            $auxPolicy = $matchedAux.Policy

                            if (-not $policyGroups.ContainsKey($auxPolicy.PolicyName)) {
                                $policyGroups[$auxPolicy.PolicyName] = @{
                                    Policy           = $auxPolicy
                                    PolicyLevelEntry = $null
                                    ElementEntries   = [System.Collections.Generic.List[PSCustomObject]]::new()
                                    AuxiliaryEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
                                    PFCategory       = $pfCategory
                                    PFDisplayText    = $pfDisplayText
                                }
                            }
                            $policyGroups[$auxPolicy.PolicyName].AuxiliaryEntries.Add([PSCustomObject]@{
                                    Delete            = $isDeletion
                                    RegistryHive      = $currentSectionHive
                                    RegistryKey       = $matchedAux.Auxiliary.RegistryKey
                                    RegistryKeyPath   = "$currentSectionHive\$($matchedAux.Auxiliary.RegistryKey)"
                                    RegistryValueName = $policyNameFromReg
                                    RegistryValue     = $registryValue
                                    RegistryValueType = $registryValueType
                                })
                            Write-Verbose "    Matched auxiliary value '$policyNameFromReg' for policy '$($auxPolicy.PolicyName)'"
                        } else {
                            Write-Warning "    Registry value '$policyNameFromReg' does not match any policy in ADMX template '$admxFileName'"
                        }
                    }
                }
            }

            # Commit any pending list section after the last line
            if ($null -ne $currentListEntry -and $null -ne $currentListValues -and $currentListValues.Count -gt 0) {
                $listMatchedPolicy = $currentListEntry.Policy
                $listMatchedElement = $currentListEntry.Element

                if (-not $policyGroups.ContainsKey($listMatchedPolicy.PolicyName)) {
                    $policyGroups[$listMatchedPolicy.PolicyName] = @{
                        Policy           = $listMatchedPolicy
                        PolicyLevelEntry = $null
                        ElementEntries   = [System.Collections.Generic.List[PSCustomObject]]::new()
                        AuxiliaryEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
                        PFCategory       = ''
                        PFDisplayText    = ''
                    }
                }
                $policyGroups[$listMatchedPolicy.PolicyName].ElementEntries.Add([PSCustomObject]@{
                        ElementId          = $listMatchedElement.ElementId
                        ElementType        = 'list'
                        ConfiguredState    = 'Enabled'
                        Delete             = $false
                        RegistryHive       = $currentSectionHive
                        RegistryKey        = $listMatchedElement.RegistryKey
                        RegistryKeyPath    = "$currentSectionHive\$($listMatchedElement.RegistryKey)"
                        RegistryValueName  = ''
                        RegistryValue      = @($currentListValues | ForEach-Object { $_.Value })
                        RegistryValueNames = @($currentListValues | ForEach-Object { $_.ValueName })
                        RegistryValueType  = 'REG_SZ'
                        RegistryType       = $listMatchedElement.RegistryType
                        Constraints        = $listMatchedElement.Constraints
                        EnumItems          = $null
                        TrueValue          = $null
                        FalseValue         = $null
                    })
                Write-Verbose "    Committed list element '$($listMatchedElement.ElementId)' with $($currentListValues.Count) item(s) for policy '$($listMatchedPolicy.PolicyName)'"
            }

            # Build correlated settings: 1 object per policy
            $correlatedSettings = foreach ($group in $policyGroups.Values) {
                $admxPolicy = $group.Policy
                $policyEntry = $group.PolicyLevelEntry
                $elementEntries = $group.ElementEntries
                $auxiliaryEntries = $group.AuxiliaryEntries

                # Determine overall policy ConfiguredState
                # Priority: 1) PolicySettings.txt POLICY:1/2 indicator, 2) policy-level registry entry, 3) element presence
                $overallState = if ($policyStateFromSettings.ContainsKey($admxPolicy.DisplayName)) {
                    $policyStateFromSettings[$admxPolicy.DisplayName]
                } elseif ($null -ne $policyEntry) {
                    $policyEntry.ConfiguredState
                } elseif ($elementEntries.Count -gt 0 -or $auxiliaryEntries.Count -gt 0) {
                    'Enabled'
                } else {
                    'Unconfigured'
                }

                [PSCustomObject]([ordered]@{
                        PolicyName        = $admxPolicy.PolicyName
                        DisplayName       = $admxPolicy.DisplayName
                        ConfiguredState   = $overallState
                        Class             = $admxPolicy.Class
                        Category          = $admxPolicy.Category
                        SupportedOn       = $admxPolicy.SupportedOn
                        Description       = if ($IncludePolicyDescription) { $admxPolicy.ExplainText } else { $null }
                        EnabledValue      = $admxPolicy.EnabledValue
                        DisabledValue     = $admxPolicy.DisabledValue
                        RegistryHive      = if ($null -ne $policyEntry) { $policyEntry.RegistryHive } else { $null }
                        RegistryKey       = $admxPolicy.RegistryKey
                        RegistryKeyPath   = if ($null -ne $policyEntry) { $policyEntry.RegistryKeyPath } else { $null }
                        RegistryValueName = if ($null -ne $policyEntry) { $policyEntry.RegistryValueName } else { $null }
                        RegistryValue     = if ($null -ne $policyEntry) { $policyEntry.RegistryValue } else { $null }
                        RegistryValueType = if ($null -ne $policyEntry) { $policyEntry.RegistryValueType } else { $null }
                        Delete            = if ($null -ne $policyEntry) { $policyEntry.Delete } else { $false }
                        Elements          = if ($elementEntries.Count -gt 0) { $elementEntries.ToArray() } else { @() }
                        AuxiliaryValues   = if ($auxiliaryEntries.Count -gt 0) { $auxiliaryEntries.ToArray() } else { @() }
                        PFCategory        = $group.PFCategory
                        PFDisplayText     = $group.PFDisplayText
                    })
            }

            # Extract policy set metadata
            $runOnce = ($registryNode.runonce -eq 'yes')
            $setEnabled = ($registryNode.enabled -eq 'yes')
            $guid = $registryNode.guid

            $policySetOutput = [ordered]@{
                Name           = $registryNode.name
                Description    = $registryNode.description
                RunOnce        = $runOnce
                Enabled        = $setEnabled
                GUID           = $guid
                PolicySettings = $correlatedSettings
            }

            if ($ExportFor -eq 'AppVentiX') {
                $policySetOutput.AppVentiXAssignments = $Assignments
                $policySetOutput.AppVentiXParams = @()
                foreach ($policySetting in $correlatedSettings) {
                    # Element-level registry entries
                    $AppVentiXPolicyElements = @()
                    $AppVentiXPolicyRegistryKeys = @()
                    if ((-not [string]::IsNullOrEmpty($policySetting.RegistryHive)) -and (-not [string]::IsNullOrEmpty($policySetting.RegistryKey)) -and (-not [string]::IsNullOrEmpty($policySetting.RegistryValueName)) ) {
                        $AppVentiXPolicyRegistryKeys += [PSCustomObject]@{
                            RootKey   = $policySetting.RegistryHive
                            KeyPath   = $policySetting.RegistryKey
                            ValueName = $policySetting.RegistryValueName
                            ValueData = $policySetting.RegistryValue
                            ValueType = $policySetting.RegistryValueType
                            Action    = "Set"
                            DeleteKey = $policySetting.Delete
                        }
                    }

                    foreach ($element in $policySetting.Elements) {
                        if ($element.ElementType -eq 'list') {
                            $AppVentiXPolicyElements += [PSCustomObject]@{
                                ElementId         = $element.ElementId
                                RegistryKey       = $element.RegistryKey
                                RegistryValueName = ''
                                Value             = $element.RegistryValue -join [System.Environment]::NewLine
                                ValueType         = $element.RegistryValueType
                            }
                            if (-not [string]::IsNullOrEmpty($element.RegistryHive) -and -not [string]::IsNullOrEmpty($element.RegistryKey)) {
                                for ($idx = 0; $idx -lt $element.RegistryValue.Count; $idx++) {
                                    $AppVentiXPolicyRegistryKeys += [PSCustomObject]@{
                                        RootKey   = $element.RegistryHive
                                        KeyPath   = $element.RegistryKey
                                        ValueName = $element.RegistryValueNames[$idx]
                                        ValueData = $element.RegistryValue[$idx]
                                        ValueType = $element.RegistryType
                                        Action    = "Set"
                                        DeleteKey = $element.Delete
                                    }
                                }
                            }
                        } else {
                            $ElementValue = $null
                            $ElementValueType = $element.RegistryValueType
                            if ($null -ne $element.EnumItems -and $element.EnumItems.Count -gt 0) {
                                try {
                                    #$ElementValue = ($element.EnumItems | Where-Object { $_.RegistryValue -eq $element.RegistryValue }).DisplayName
                                    $ElementValue = $element.RegistryValue
                                    $ElementValueType = 'REG_SZ'
                                } catch { $null }
                            } elseif ($element.RegistryValueType -in @('REG_DWORD', 'REG_QWORD')) {
                                # Only boolean elements are a checkbox; decimal/longDecimal keep their number
                                $ElementValue = if ($element.ElementType -eq 'boolean') { $element.RegistryValue -ne 0 } else { $element.RegistryValue }
                            } elseif ($element.RegistryValueType -in @('REG_SZ', 'REG_EXPAND_SZ', 'REG_BINARY')) {
                                $ElementValue = $element.RegistryValue
                            } elseif ($element.RegistryValueType -eq 'REG_MULTI_SZ') {
                                $ElementValue = @($element.RegistryValue) -join [System.Environment]::NewLine
                            } else {
                                Write-Warning "Policy '$($registryNode.name)' Element '$($element.ElementId)' has unsupported RegistryValueType '$($element.RegistryValueType)' for AppVentiX export. Contact AppventiX Support for assistance."
                            }
                            $AppVentiXPolicyElements += [PSCustomObject]@{
                                ElementId         = $element.ElementId
                                RegistryKey       = $element.RegistryKey
                                RegistryValueName = $element.RegistryValueName
                                Value             = $ElementValue
                                ValueType         = $ElementValueType
                            }
                            if ((-not [string]::IsNullOrEmpty($element.RegistryHive)) -and (-not [string]::IsNullOrEmpty($element.RegistryKey)) -and (-not [string]::IsNullOrEmpty($element.RegistryValueName))) {
                                $AppVentiXPolicyRegistryKeys += [PSCustomObject]@{
                                    RootKey   = $element.RegistryHive
                                    KeyPath   = $element.RegistryKey
                                    ValueName = $element.RegistryValueName
                                    ValueData = $element.RegistryValue
                                    ValueType = $element.RegistryType
                                    Action    = "Set"
                                    DeleteKey = $element.Delete
                                }
                            }
                        }
                    }

                    # Auxiliary values (enabledList/disabledList/valueList) have no ADMX element,
                    # so they only produce registry entries
                    foreach ($auxValue in $policySetting.AuxiliaryValues) {
                        if ((-not [string]::IsNullOrEmpty($auxValue.RegistryHive)) -and (-not [string]::IsNullOrEmpty($auxValue.RegistryKey)) -and (-not [string]::IsNullOrEmpty($auxValue.RegistryValueName))) {
                            $AppVentiXPolicyRegistryKeys += [PSCustomObject]@{
                                RootKey   = $auxValue.RegistryHive
                                KeyPath   = $auxValue.RegistryKey
                                ValueName = $auxValue.RegistryValueName
                                ValueData = $auxValue.RegistryValue
                                ValueType = $auxValue.RegistryValueType
                                Action    = "Set"
                                DeleteKey = $auxValue.Delete
                            }
                        }
                    }
                    # Policy-level registry entry
                    if ($null -ne $policySetting.PolicyName) {
                        $policySetOutput.AppVentiXParams += [PSCustomObject]@{
                            PolicyName        = $policySetting.PolicyName
                            PolicyDisplayName = $policySetting.DisplayName
                            PolicyKey         = $policySetting.RegistryKey
                            PolicyValueName   = $policySetting.RegistryValueName
                            Enabled           = $policySetting.ConfiguredState -eq 'Enabled'
                            Elements          = @($AppVentiXPolicyElements)
                            RegistryEntries   = @($AppVentiXPolicyRegistryKeys)
                        }
                    }
                }
            }
            if ($ExportFor -eq 'WEM') {
                $policySetOutput.WEMAssignments = @($Assignments | Select-Object Sid, Name, Type, DomainFQDN, DomainNETBIOS)
                $policySetOutput.WEMParams = [ordered]@{
                    Name               = $registryNode.name
                    Description        = "[IWC-Policy] $($registryNode.description)"
                    RegistryOperations = @()
                }

                foreach ($policySetting in $correlatedSettings) {
                    # Policy-level registry entry
                    if (-not [string]::IsNullOrEmpty($policySetting.RegistryKey) -and -not [string]::IsNullOrEmpty($policySetting.RegistryValueName)) {
                        $Action = if ($policySetting.Delete) { 'DeleteValue' } else { 'SetValue' }
                        $Scope = Get-RegistryScope -Hive $policySetting.RegistryHive -Class $policySetting.Class
                        $RegItemParam = @{
                            Action = $Action
                            Scope  = $Scope
                            Key    = $policySetting.RegistryKey
                            Value  = $policySetting.RegistryValueName
                            Type   = $policySetting.RegistryValueType
                            Data   = $policySetting.RegistryValue
                        }
                        $policySetOutput.WEMParams.RegistryOperations += New-WEMRegItem @RegItemParam
                    }

                    # Element-level registry entries
                    foreach ($element in $policySetting.Elements) {
                        $Scope = Get-RegistryScope -Hive $element.RegistryHive -Class $policySetting.Class

                        if ($element.ElementType -eq 'list') {
                            if ($element.Delete) {
                                # Delete all values under the list key
                                $RegItemParam = @{
                                    Action = 'DeleteAllValues'
                                    Scope  = $Scope
                                    Key    = $element.RegistryKey
                                }
                                $policySetOutput.WEMParams.RegistryOperations += New-WEMRegItem @RegItemParam
                            } else {
                                # One SetValue per list item
                                for ($idx = 0; $idx -lt $element.RegistryValue.Count; $idx++) {
                                    $RegItemParam = @{
                                        Action = 'SetValue'
                                        Scope  = $Scope
                                        Key    = $element.RegistryKey
                                        Value  = $element.RegistryValueNames[$idx]
                                        Type   = $element.RegistryValueType
                                        Data   = $element.RegistryValue[$idx]
                                    }
                                    $policySetOutput.WEMParams.RegistryOperations += New-WEMRegItem @RegItemParam
                                }
                            }
                        } else {
                            # Non-list element
                            $Action = if ($element.Delete) {
                                if ([string]::IsNullOrEmpty($element.RegistryValueName)) { 'DeleteKey' } else { 'DeleteValue' }
                            } else {
                                if ([string]::IsNullOrEmpty($element.RegistryValueName)) { 'CreateKey' } else { 'SetValue' }
                            }
                            $RegItemParam = @{
                                Action = $Action
                                Scope  = $Scope
                                Key    = $element.RegistryKey
                            }
                            if ($Action -eq 'SetValue') {
                                $RegItemParam.Value = $element.RegistryValueName
                                $RegItemParam.Type = $element.RegistryValueType
                                $RegItemParam.Data = $element.RegistryValue
                            } elseif ($Action -eq 'DeleteValue') {
                                $RegItemParam.Value = $element.RegistryValueName
                            }
                            $policySetOutput.WEMParams.RegistryOperations += New-WEMRegItem @RegItemParam
                        }
                    }

                    # Auxiliary values (enabledList/disabledList/valueList) have no ADMX element,
                    # so they only produce registry operations
                    foreach ($auxValue in $policySetting.AuxiliaryValues) {
                        if ([string]::IsNullOrEmpty($auxValue.RegistryKey) -or [string]::IsNullOrEmpty($auxValue.RegistryValueName)) { continue }
                        $RegItemParam = @{
                            Action = if ($auxValue.Delete) { 'DeleteValue' } else { 'SetValue' }
                            Scope  = Get-RegistryScope -Hive $auxValue.RegistryHive -Class $policySetting.Class
                            Key    = $auxValue.RegistryKey
                            Value  = $auxValue.RegistryValueName
                        }
                        if (-not $auxValue.Delete) {
                            $RegItemParam.Type = $auxValue.RegistryValueType
                            $RegItemParam.Data = $auxValue.RegistryValue
                        }
                        $policySetOutput.WEMParams.RegistryOperations += New-WEMRegItem @RegItemParam
                    }
                }
            }
            if ($IncludeADMFiles) {
                $policySetOutput.ADMX = $currentTemplate.ADMXFile
                $policySetOutput.ADML = $currentTemplate.ADMLFile
                $policySetOutput.ADMXContent = $currentTemplate.ADMXContent
                $policySetOutput.ADMLContent = $currentTemplate.ADMLContent
            }

            Write-Verbose "Completed processing policy set: $policySetName"
            Write-Output ([PSCustomObject]$policySetOutput)
        }

        Write-Progress -Activity "Processing policy sets" -Completed
        Write-Verbose "Successfully processed $totalPolicySets policy set(s)"

    } catch {
        $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
        $filePath = if ($resolvedPath) { $resolvedPath.Path } else { $Path }

        $errorDetails = @(
            "Error processing Ivanti policy file",
            "File: $filePath",
            "Error: $($_.Exception.Message)",
            "Line: $($_.InvocationInfo.ScriptLineNumber)",
            "Position: $($_.InvocationInfo.PositionMessage)"
        )
        Write-Error ($errorDetails -join "`n")
        throw
    }
}

# SIG # Begin signature block
# MII6AgYJKoZIhvcNAQcCoII58zCCOe8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBCKd8brfJyZB8G
# JcFYNlVqUP4z9Tc7qIr6VWUt0zNScqCCIiYwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAvBgkqhkiG9w0BCQQxIgQgFs5N
# CECgBCQpYOru549RozviLrbg09aOwi0mBUzVnSIwDQYJKoZIhvcNAQEBBQAEggGA
# I2NdiKWq9e8LaFJlm/+AvR/xd9k3J5xjYeYwgf81tydSpQUJ+apdmHJ/VHO6cSgT
# mtT0ceq6SRkwEaXEjvEhedioHM0jEsAGHpcUVTKbkvK4bj7F4lCkGNNyRl0lwdJd
# nrKKFyG2BsajIMpdtxMUr5MBnaVl3uGRe2qelebsbO4Vx1AyN4KnsAI88cIR8asP
# pW5+2atEi0vwJFtcvy84H9LIh4hvkn40c4ocdfQVI3ErdPC0psVCDyiFgg2u36ep
# qyaqT984MOeXWI+S7Sb1vPwTNkt5Sys8CDRRBcQ2LKBLoUIZlU+cOUk6CCwlSAmS
# LQLXlSkgUB6e7wmLtK6k+9GCgfzCrSWN797UxsmqZZApLp0r5BUtfEAH1jl35Kfu
# 3szj9ZY56PV4AbbicvDB3RdwSLIbbsDSZhH4w5gq3/27qnqQJd+HK3jr8ECgeAhe
# nPwvu5iQVQyI6DsyfqkGuATmR6N1RF7Sml9FRXyLFcYj/gx38pS27NOL1cPyP/oj
# oYIUsjCCFK4GCisGAQQBgjcDAwExghSeMIIUmgYJKoZIhvcNAQcCoIIUizCCFIcC
# AQMxDzANBglghkgBZQMEAgEFADCCAWoGCyqGSIb3DQEJEAEEoIIBWQSCAVUwggFR
# AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIJFXNn+KVJqGAzbEQum5
# Tux6WSSIU9tayyWu+HoVK9asAgZq80sQ/IEYEzIwMjYxMTE4MTM0MjU5LjMzMlow
# BIACAfSggemkgeYwgeMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjdCMUEtMDVFMC1EOTQ3MTUwMwYD
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
# JYbYbBh7pmgAXVswggefMIIFh6ADAgECAhMzAAAAWXzacemNXvXAAAAAAABZMA0G
# CSqGSIb3DQEBDAUAMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVz
# dGFtcGluZyBDQSAyMDIwMB4XDTI2MDEwODE4NTkwMVoXDTI3MDEwNzE4NTkwMVow
# geMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsT
# JE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMe
# blNoaWVsZCBUU1MgRVNOOjdCMUEtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3Nv
# ZnQgUHVibGljIFJTQSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBAKYu5/40eEX+hT+5jFa146bid3dA4LnXYntv
# kP3CGw4LGARFhnvLMSJ/VtsubzDaeFnm7yb2KSM70WmHQprdCVqpvUH7l0uB4jNw
# 7urLoAR9kKHLE0VlMlDStDSxUBI3qwsdrjvdmvV0k+9/njuDEiSlzJTf7Dowd1K3
# bO4beRyaFhR+Y8tymECOqlOAffYrG2wZdVM51+QSBSe+PEykr8C6OnnqSipuF8fZ
# vCb6/huk0Zm6ZwsaixSHIAT2IEGvS7c63Im8jV3a8R0K6i2yiw0NNlnTSpwy/Zfv
# 7iwsLBwhfbjBTn+XOl6mPzDXQQ3V+SRP9xXbGKOsBTxzGid7aKAHw3o4Ahl9UGWL
# H9kNP3VUokE6JYkjlfpuUGZ6gQyqDewfxD4VoYIlopt4HZ0xQvqajuJx+cr8LR/I
# Z56gLLmwyMzde5+vtjBoilry/gSZwVGwgkvkIgpKPBQHGsSB0y3szr7Y7wEb6v0y
# Zal1XUvWnnz3inTaSWsCFrLPVwVmXy3ncY5/d25VpOkht+m697GWNbvsNOhAOHRa
# ftE9j/hhkoM6RsyJfBLnhqMcA/wcavf5oj5NeyRQdGZeLKcls9csKS3sBUzPidxx
# 2iiNH9CPaDq/bLJEOXasYohXMnRinu+fUk81s8VO7DQSF6ffn5oqSHoV8lf1Ax6u
# +kdShb8BAgMBAAGjggHLMIIBxzAdBgNVHQ4EFgQUj5bnC18D0vlnSRhCOiODGGuX
# NnYwHwYDVR0jBBgwFoAUa2koOjUvSGNAz3vYr0npPtk92yEwbAYDVR0fBGUwYzBh
# oF+gXYZbaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9z
# b2Z0JTIwUHVibGljJTIwUlNBJTIwVGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNy
# bDB5BggrBgEFBQcBAQRtMGswaQYIKwYBBQUHMAKGXWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwUHVibGljJTIwUlNBJTIw
# VGltZXN0YW1waW5nJTIwQ0ElMjAyMDIwLmNydDAMBgNVHRMBAf8EAjAAMBYGA1Ud
# JQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDBmBgNVHSAEXzBdMFEG
# DCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wCAYGZ4EMAQQCMA0GCSqG
# SIb3DQEBDAUAA4ICAQBEMhzC/ZcjpG/zURE7z2Yp5vrUxUjsE5Xa3t/2RGvESwvb
# msk3bLHhSFAajgo2XQ8xoGDP3sUhKCLPeICSbkVv6V8sSp8fJ8Jos6yrawf2YVis
# 8tcV+OO7U9S6JGPQzpmPncfzQc4ne1fqZ4+HiKabIDEoFdddQT2Egkk9fzxCY/EZ
# 52avJ27dSfrI/IDmyn9V10O3iQpg2F+C9vNTrk7nVgoDoHa9+Q3pYr0IHGnSmt5i
# rgGT436zo5WnXP8FxMhswH1aiyiSZiVzhor10C9C52cP3C8/PEoMKUXstLjoPO0T
# MkeW/1Fr186KXD45QRgBo0xImgtWTdzWFnlD+p7+iDBIuSrNcRXDRYuq/aYZaDhW
# SI0SYdPIWVh5XvXuWA31a8oQ0SO+oPa3Nk80k0864wiiyJ1KsbSnaaefg9vspegh
# rpY8ljCwxfCUtx5HQRNgAJOI8IKACK4d014Mk0hlRO0lQVRHegqIg29K6Xqkc360
# W2ZJGUcstlKokkVj6KAHjGyrLRPzepYfiZUJq4gXyxbpvKb1XJ2FN2682aUoNXo9
# RyRK1ch0f66k6+yj88kzvuC7+vJWtNDs/UpIM6Hhm0kU64JUJ7MMEQcAc7kpft7G
# m7YeRK+oKgqUgYXCfmzbX8nJXJZnPa8ADWVsIqsuNAxCI0CZXkULofqo5Be6zzGC
# A9QwggPQAgEBMHgwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABZfNpx6Y1e9cAAAAAAAFkwDQYJYIZIAWUDBAIB
# BQCgggEtMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
# IgQgRCEfmXyAnqTw14u0LBCW+/iuLGedFNLDsh38kRNCJmcwgd0GCyqGSIb3DQEJ
# EAIvMYHNMIHKMIHHMIGgBCDLRbqx24bpscXEJ+Hjj9xrcUVw7R8OyyMfSB2YGK3+
# vDB8MGWkYzBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBp
# bmcgQ0EgMjAyMAITMwAAAFl82nHpjV71wAAAAAAAWTAiBCATssmTpcpjRKbEb1GQ
# T07uNT/ySNfYRGBQ8C0h+ko1hzANBgkqhkiG9w0BAQsFAASCAgBpy4pR9i/e9V/B
# btXj7OJ9QUhpWTfJCRWorx7RYtSB45Kx4rKLsUH50OvmclQrmmz6KjGTqx/ve1h9
# gFGvbGXuT81k1iytUF8JCoGagRJqwvZlxTSHsmF80PJlymYbEoFmbRddcVbFsLhM
# I1+TpWx2i04lE5YYtiJFaXPqK3qtj60/b/OrE0FbnZITQNxSF0B9B4luP51VAUtR
# 5Vg+BnCPFxpo7i2Uc681arGysEE7ONUif2VQUD++lNnVSMF76HJsKyqH+8sA2smm
# sozmXQxt+5kiZIdmdCcKdYkJf/beb2cpAkPBmPX7UWDXwi4E6ElxdlMAxas3byUM
# p4RXESw1hRb7wweoN/YkzsDeegT2wvSQuVgbCIn0XjCeilP99dnjOW9IIkFNu45U
# DzY6ppPNnNc3iDIZdcrc0C0dXSGMQXATnCtOc/sXgmv+azuXHwsWzfdEPHi0nXrn
# ZQMmyB81ogcH4S5rWQqg1hPaVPqEea47MLLDO1D/+ygWS2x6HomczlxwmRGLKUbB
# tOZwjBNi2aNn23A6oPB4Utpcuo9x63KWllNtpGlDy/R0bfx6b0PCeLzVC+hRo9IW
# Shj4Yl0dR8SDm5GbOCrLa1Ezvx2tGLZ4ebFz1zRubgRDQK0L9/x+XNwgaqnXvLBc
# FifmGDjNbijGA2DG/r/tZ8OB2MbQIA==
# SIG # End signature block
