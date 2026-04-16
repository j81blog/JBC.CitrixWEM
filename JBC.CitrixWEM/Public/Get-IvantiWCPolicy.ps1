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
    Version   : 2026.0308.1500
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

        # Resolve to absolute path for XmlDocument.Load()
        $absolutePath = (Resolve-Path -Path $Path).Path
        Write-Verbose "Loading XML file: $absolutePath"
        $xmlContent = New-Object System.Xml.XmlDocument
        $xmlContent.Load($absolutePath)

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

                try {
                    $admxXml = New-Object System.Xml.XmlDocument
                    $admxXml.Load($admxStream)

                    $admlXml = New-Object System.Xml.XmlDocument
                    if ($null -ne $admlStream) {
                        $admlXml.Load($admlStream)
                    }

                    $admxBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($admxXml.OuterXml))
                    $admlBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($admlXml.OuterXml))

                    # Pre-load all policy settings from this template via Get-AdmxPolicySetting
                    Write-Verbose "  Indexing policy settings for: $fileName"
                    $allPolicySettings = Get-AdmxPolicySetting -AdmxContent $admxBase64 -AdmlContent $admlBase64 -AdmxFileName $fileName -AdmlFileName $admlFileName -All

                    # Build lookup: normalized RegistryKey\ValueName -> list of @{Policy; Element} objects
                    # Policy-level valueName maps to Element=$null; element valueName maps to the element object
                    # listLookup: normalized RegistryKey -> list of @{Policy; Element} for 'list' element types
                    $policyLookup = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $listLookup = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
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
                    }

                    $admTemplateStore[$fileName] = [PSCustomObject]@{
                        ADMXFile     = $fileName
                        ADMLFile     = $admlFileName
                        ADMXContent  = $admxBase64
                        ADMLContent  = $admlBase64
                        PolicyLookup = $policyLookup
                        ListLookup   = $listLookup
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
                    # Ensure streams are always closed
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
                            $rawValue.Substring(1, $rawValue.Length - 2)
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
                        $registryValue = $rawValue.Substring(1, $rawValue.Length - 2)
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
                        Write-Warning "    Registry value '$policyNameFromReg' does not match any policy in ADMX template '$admxFileName'"
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

                # Determine overall policy ConfiguredState
                # Priority: 1) PolicySettings.txt POLICY:1/2 indicator, 2) policy-level registry entry, 3) element presence
                $overallState = if ($policyStateFromSettings.ContainsKey($admxPolicy.DisplayName)) {
                    $policyStateFromSettings[$admxPolicy.DisplayName]
                } elseif ($null -ne $policyEntry) {
                    $policyEntry.ConfiguredState
                } elseif ($elementEntries.Count -gt 0) {
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
                        RegistryHive      = $policyEntry.RegistryHive
                        RegistryKey       = $admxPolicy.RegistryKey
                        RegistryKeyPath   = $policyEntry.RegistryKeyPath
                        RegistryValueName = if ($null -ne $policyEntry) { $policyEntry.RegistryValueName } else { $null }
                        RegistryValue     = if ($null -ne $policyEntry) { $policyEntry.RegistryValue } else { $null }
                        RegistryValueType = if ($null -ne $policyEntry) { $policyEntry.RegistryValueType } else { $null }
                        Delete            = if ($null -ne $policyEntry) { $policyEntry.Delete } else { $false }
                        Elements          = if ($elementEntries.Count -gt 0) { $elementEntries.ToArray() } else { @() }
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
                                $ElementValue = $element.RegistryValue -ne 0
                            } elseif ($element.RegistryValueType -eq 'REG_SZ') {
                                $ElementValue = $element.RegistryValue
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
# MII6BgYJKoZIhvcNAQcCoII59zCCOfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCClGK1emsBc/pKE
# +M1t8xOmWe4XWPVpM3+z6C/acl2JMKCCIiowggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# IENuUccP0DxyPUbGeAqG45vT9VLg9cUf8wEpM4QzGuciMA0GCSqGSIb3DQEBAQUA
# BIIBgM7o8FwQtTJispu6jDSHrV/5OfXDcbvi1oXvSRNEfy1/0AgyQ8VLdM4h5H3z
# nNzTKVBjvVVDAhmIHxuXLI98p8Y/OK8gMnZ9u1qWIgk7q+sMztB0AcLmCXnpyuk0
# J01I/VQX6pdWdiLnJz797eQ8l8ZZGE96dHwD35v3tssKWinLxNqXDK6zfdgQ2DWx
# DPvrb7dqWp22+W1+TwyNYPOjk1hNNNk9o8r5Ul2OKIaYrNR/nvubJjwlk8XGdzZQ
# nn7OmvIYoErhP7YCFLyeIreNf3GyBbWVHwK4I7jr9fqGqH5BLCx1FmugcKVQOzrT
# CRuO1JUwXY7lq1nMf8L6vYjkhrwhA19nghiX0/gwRco0MzC/j7hoJfb27RvsZyYU
# ASIcougdXM0y7WOT9fV7OiKVES864NXUYXLI16IOyWNAbHneYmJwgMrPY6j41SWs
# UlQEFja5ueTJ2bkVKOz93V8EfKbQuRRqyhzw9KgO3xFlaD9rNXH0jO/TbNww5AhE
# jpmYy6GCFLIwghSuBgorBgEEAYI3AwMBMYIUnjCCFJoGCSqGSIb3DQEHAqCCFIsw
# ghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFqBgsqhkiG9w0BCRABBKCCAVkEggFV
# MIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCwwGReKck+loxD
# MuYbUUfOku5jwfIwZNCjlOKhOE0ZwAIGacZoEQJbGBMyMDI2MDQxNTE5NTczOS4z
# MTlaMASAAgH0oIHppIHmMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3QjFBLTA1RTAtRDk0NzE1
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
# r1nJfiWG2GwYe6ZoAF1bMIIHnzCCBYegAwIBAgITMwAAAFl82nHpjV71wAAAAAAA
# WTANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBU
# aW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjAxMDgxODU5MDFaFw0yNzAxMDcxODU5
# MDFaMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo3QjFBLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHkwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCmLuf+NHhF/oU/uYxWteOm4nd3QOC5
# 12J7b5D9whsOCxgERYZ7yzEif1bbLm8w2nhZ5u8m9ikjO9Fph0Ka3Qlaqb1B+5dL
# geIzcO7qy6AEfZChyxNFZTJQ0rQ0sVASN6sLHa473Zr1dJPvf547gxIkpcyU3+w6
# MHdSt2zuG3kcmhYUfmPLcphAjqpTgH32KxtsGXVTOdfkEgUnvjxMpK/Aujp56koq
# bhfH2bwm+v4bpNGZumcLGosUhyAE9iBBr0u3OtyJvI1d2vEdCuotsosNDTZZ00qc
# Mv2X7+4sLCwcIX24wU5/lzpepj8w10EN1fkkT/cV2xijrAU8cxone2igB8N6OAIZ
# fVBlix/ZDT91VKJBOiWJI5X6blBmeoEMqg3sH8Q+FaGCJaKbeB2dMUL6mo7icfnK
# /C0fyGeeoCy5sMjM3Xufr7YwaIpa8v4EmcFRsIJL5CIKSjwUBxrEgdMt7M6+2O8B
# G+r9MmWpdV1L1p5894p02klrAhayz1cFZl8t53GOf3duVaTpIbfpuvexljW77DTo
# QDh0Wn7RPY/4YZKDOkbMiXwS54ajHAP8HGr3+aI+TXskUHRmXiynJbPXLCkt7AVM
# z4nccdoojR/Qj2g6v2yyRDl2rGKIVzJ0Yp7vn1JPNbPFTuw0Ehen35+aKkh6FfJX
# 9QMervpHUoW/AQIDAQABo4IByzCCAccwHQYDVR0OBBYEFI+W5wtfA9L5Z0kYQjoj
# gxhrlzZ2MB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7ZPdshMGwGA1UdHwRl
# MGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAy
# MC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJT
# QSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwZgYDVR0gBF8w
# XTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMAgGBmeBDAEEAjAN
# BgkqhkiG9w0BAQwFAAOCAgEARDIcwv2XI6Rv81ERO89mKeb61MVI7BOV2t7f9kRr
# xEsL25rJN2yx4UhQGo4KNl0PMaBgz97FISgiz3iAkm5Fb+lfLEqfHyfCaLOsq2sH
# 9mFYrPLXFfjju1PUuiRj0M6Zj53H80HOJ3tX6mePh4immyAxKBXXXUE9hIJJPX88
# QmPxGedmrydu3Un6yPyA5sp/VddDt4kKYNhfgvbzU65O51YKA6B2vfkN6WK9CBxp
# 0preYq4Bk+N+s6OVp1z/BcTIbMB9WosokmYlc4aK9dAvQudnD9wvPzxKDClF7LS4
# 6DztEzJHlv9Ra9fOilw+OUEYAaNMSJoLVk3c1hZ5Q/qe/ogwSLkqzXEVw0WLqv2m
# GWg4VkiNEmHTyFlYeV717lgN9WvKENEjvqD2tzZPNJNPOuMIosidSrG0p2mnn4Pb
# 7KXoIa6WPJYwsMXwlLceR0ETYACTiPCCgAiuHdNeDJNIZUTtJUFUR3oKiINvSul6
# pHN+tFtmSRlHLLZSqJJFY+igB4xsqy0T83qWH4mVCauIF8sW6bym9VydhTduvNml
# KDV6PUckStXIdH+upOvso/PJM77gu/ryVrTQ7P1KSDOh4ZtJFOuCVCezDBEHAHO5
# KX7expu2HkSvqCoKlIGFwn5s21/JyVyWZz2vAA1lbCKrLjQMQiNAmV5FC6H6qOQX
# us8xggPUMIID0AIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAWXzacemNXvXAAAAAAABZMA0GCWCGSAFl
# AwQCAQUAoIIBLTAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIAjlRbCC5iliIeBiKs/51nAyWwzpzLQvKBycmMmnkKDQMIHdBgsqhkiG
# 9w0BCRACLzGBzTCByjCBxzCBoAQgy0W6sduG6bHFxCfh44/ca3FFcO0fDssjH0gd
# mBit/rwwfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABZfNpx6Y1e9cAAAAAAAFkwIgQgFz1jKicJQAfQ
# WkSPRedcsOuoQOHxTFAFxI2VSCznAIUwDQYJKoZIhvcNAQELBQAEggIARpkbWavo
# WMfw+uNVP9OSL6tkO86+85Bo9GjUscL0epHoVr+O5hcXNaZaJDQAvLLw0+qroODh
# 31Z36w8EBW1BOXbXiXfSl4iTswXHBeevE42n149duiYwED6ibJvIjJreU+cXJoli
# tmCpoAay02ewdbfU4kg6N7JviD/wWIw+Kcopxvcl8gLd1Wje9fv20wsJFjleGEKj
# XcafExhcXCR5fOialKwLWt844gsSbVRumu1TMQivl5lBW+gtHyMo4n2NxNlcCzNC
# e09IZC8ix+qsbHbjl3RjLhXkKGCVI6lgDY64s6wBp8IXzPhIzrB9N5c03/pUO6Oy
# HkQ4jtFbuNWQcXqIbRJaXj7Q/zau5RpFjY5fd6jnaIB1VaF0OJl1nmNzr8q9NXgZ
# wsXgK3ltM5mE9LFOVJ52DNPF28p0DTxVj5pArnhKodQNglcwjT2fejfReP9WKZhQ
# H8Ydl6xU1WTSey+y4dAo3wLiKb6URV+X+U129GsAcJTNh8nwAELMmbeNOdePo1TI
# 1+68eIhtrmevKsxI1qXexHfzICYhMuIA/XPvFB7NcVvt6SfxZutTKoOmTtj5YL7H
# gWC31Nndll+Sa/4Gn9gc9SqY17sLVN4HNll8v6e1r4hI3/7QE1wuZWyVUfWBZahz
# L2mNblGj+2Mc+x2DaHWmT/Yab1BWvAKLmqM=
# SIG # End signature block
