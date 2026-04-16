function Get-AdmxPolicySetting {
    <#
    .SYNOPSIS
        Retrieves Group Policy setting details from ADMX/ADML files matching a registry key path and value name.

    .DESCRIPTION
        Parses ADMX files to find policy settings matching a given registry key and value name,
        returning registry type, element type, policy metadata, and display strings resolved from
        the corresponding ADML file.

        Supports three parameter sets:
        - Path     : Provide a path to an ADMX file or directory containing ADMX files.
        - XmlFile  : Provide file paths to ADMX and optionally ADML files as strings.
        - XmlContent : Provide raw XML content strings for ADMX and optionally ADML.

        Use -All to return every policy in the file(s) without filtering.
        Otherwise, both -RegistryKey and -ValueName are required.

        ADML auto-detection order (Path and XmlFile sets):
        1. Subfolder matching the current UI culture (e.g., en-GB) in the ADMX directory.
        2. Fallback to en-US subfolder.
        3. Any available language subfolder found.

    .PARAMETER AdmxPath
        Path to a single ADMX file or a directory containing ADMX files.

    .PARAMETER Recurse
        When AdmxPath is a directory, recurse into subdirectories to find ADMX files.

    .PARAMETER AdmxFilePath
        File path to a single ADMX file (XmlFile parameter set).

    .PARAMETER AdmlFilePath
        File path to a single ADML file (XmlFile parameter set). Optional; if omitted,
        auto-detection is attempted relative to the ADMX file location.

    .PARAMETER AdmxContent
        Raw XML string content of the ADMX file (XmlContent parameter set).

    .PARAMETER AdmlContent
        Raw XML string content of the ADML file (XmlContent parameter set). Optional.

    .PARAMETER AdmxFileName
        Optional filename hint for the ADMX source when using the XmlContent parameter set
        (e.g. 'ControlPanel.admx'). Populates the AdmxFile and SourceFile output fields.

    .PARAMETER AdmlFileName
        Optional filename hint for the ADML source when using the XmlContent parameter set
        (e.g. 'ControlPanel.adml'). Populates the AdmlFile and SourceAdml output fields.

    .PARAMETER All
        Return all policy settings from the ADMX file(s) without filtering by registry key or value name.
        When specified, -RegistryKey and -ValueName are not required.

    .PARAMETER RegistryKey
        The registry key path to match (e.g., 'SOFTWARE\Policies\Microsoft\Edge').
        HKLM/HKCU prefixes are stripped automatically.

    .PARAMETER ValueName
        The registry value name to match.

    .EXAMPLE
        Get-AdmxPolicySetting -AdmxPath 'C:\Windows\PolicyDefinitions' `
            -RegistryKey 'SOFTWARE\Policies\Microsoft\Edge' `
            -ValueName 'HomepageIsNewTabPage' -Recurse

    .EXAMPLE
        Get-AdmxPolicySetting -AdmxFilePath 'C:\PolicyDefs\msedge.admx' `
            -AdmlFilePath 'C:\PolicyDefs\en-US\msedge.adml' `
            -RegistryKey 'SOFTWARE\Policies\Microsoft\Edge' `
            -ValueName 'HomepageIsNewTabPage'

    .EXAMPLE
        $admxXml = Get-Content 'C:\PolicyDefs\msedge.admx' -Raw
        $admlXml = Get-Content 'C:\PolicyDefs\en-US\msedge.adml' -Raw
        Get-AdmxPolicySetting -AdmxContent $admxXml -AdmlContent $admlXml `
            -RegistryKey 'SOFTWARE\Policies\Microsoft\Edge' `
            -ValueName 'HomepageIsNewTabPage'

    .NOTES
        Function  : Get-AdmxPolicySetting
        Author    : John Billekens
    Copyright   : (c) John Billekens Consultancy & AppVentiX
        Version   : 2026.0307.1000
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        # --- Path parameter set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateScript({ Test-Path $_ })]
        [string]$AdmxPath,

        [Parameter(ParameterSetName = 'Path')]
        [switch]$Recurse,

        # --- XmlFile parameter set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'XmlFile')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$AdmxFilePath,

        [Parameter(ParameterSetName = 'XmlFile')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$AdmlFilePath,

        # --- XmlContent parameter set ---
        [Parameter(Mandatory = $true, ParameterSetName = 'XmlContent')]
        [ValidateNotNullOrEmpty()]
        [string]$AdmxContent,

        [Parameter(ParameterSetName = 'XmlContent')]
        [ValidateNotNullOrEmpty()]
        [string]$AdmlContent,

        [Parameter(ParameterSetName = 'XmlContent')]
        [string]$AdmxFileName,

        [Parameter(ParameterSetName = 'XmlContent')]
        [string]$AdmlFileName,

        # --- Common parameters ---
        [Parameter()]
        [switch]$All,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RegistryKey,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ValueName
    )

    #region Internal helpers

    function ConvertTo-NormalizedKey {
        [CmdletBinding()]
        param([string]$Key)
        $normalized = $Key -replace '^(HKEY_LOCAL_MACHINE|HKLM|HKEY_CURRENT_USER|HKCU)\\', ''
        if ($normalized -ne $Key) {
            Write-Verbose "Stripped registry hive prefix: '$($Key)' -> '$($normalized)'"
        }
        return $normalized
    }

    function Get-AdmlStringTable {
        <#
        .SYNOPSIS
            Parses an ADML XML document and returns a hashtable of string ID to display value.
        #>
        [CmdletBinding()]
        param([xml]$AdmlXml)

        $table = @{}
        $ns = New-Object System.Xml.XmlNamespaceManager($AdmlXml.NameTable)

        $rootNamespaceUri = $AdmlXml.DocumentElement.NamespaceURI
        $strings = if (-not [string]::IsNullOrEmpty($rootNamespaceUri)) {
            $ns.AddNamespace('ad', $rootNamespaceUri)
            $AdmlXml.SelectNodes('//ad:stringTable/ad:string', $ns)
        } else {
            $AdmlXml.SelectNodes('//stringTable/string')
        }
        foreach ($s in $strings) {
            $table[$s.GetAttribute('id')] = $s.InnerText
        }
        Write-Verbose "ADML string table loaded: $($table.Count) entries"
        return $table
    }

    function Resolve-AdmlString {
        <#
        .SYNOPSIS
            Resolves a $(string.ID) reference against a string table hashtable.
        #>
        [CmdletBinding()]
        param(
            [string]$Reference,
            [hashtable]$StringTable
        )
        if ($Reference -match '^\$\(string\.(.+)\)$') {
            $id = $Matches[1]
            if ($StringTable.ContainsKey($id)) {
                return $StringTable[$id]
            }
            Write-Verbose "ADML string reference not resolved: '$($id)' (string table has $($StringTable.Count) entries)"
        }
        return $Reference
    }

    function Find-AdmlFile {
        <#
        .SYNOPSIS
            Attempts to locate an ADML file adjacent to the given ADMX file path.
            Detection order: same-name ADML in UI culture subfolder, en-US, any available language.
        #>
        [CmdletBinding()]
        param([string]$AdmxFileFullPath)

        $admxDir = Split-Path -Parent $AdmxFileFullPath
        $admlName = [System.IO.Path]::GetFileNameWithoutExtension($AdmxFileFullPath) + '.adml'

        $culturesToTry = [System.Collections.Generic.List[string]]::new()

        $currentCulture = (Get-Culture).Name
        if (-not [string]::IsNullOrEmpty($currentCulture)) {
            $culturesToTry.Add($currentCulture)
        }
        if (-not $culturesToTry.Contains('en-US')) {
            $culturesToTry.Add('en-US')
        }

        foreach ($culture in $culturesToTry) {
            $candidate = Join-Path $admxDir "$($culture)\$($admlName)"
            Write-Verbose "ADML probe [$($culture)]: $($candidate)"
            if (Test-Path $candidate -PathType Leaf) {
                Write-Verbose "Resolved ADML via culture '$($culture)': $($candidate)"
                return $candidate
            }
        }

        # Fallback: any language subfolder
        Write-Verbose "ADML not found via culture probes, scanning subdirectories of '$($admxDir)' for '$($admlName)'"
        $anyAdml = Get-ChildItem -Path $admxDir -Filter $admlName -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $anyAdml) {
            Write-Verbose "Resolved ADML via fallback scan: $($anyAdml.FullName)"
            return $anyAdml.FullName
        }

        Write-Verbose "ADML not found for '$($admlName)' in any subfolder of '$($admxDir)'"
        return $null
    }

    function Get-CrossNamespaceStringTables {
        <#
        .SYNOPSIS
            Reads the policyNamespaces/using declarations from an ADMX document, locates each
            referenced ADMX file, loads its ADML string table, and returns a hashtable keyed
            by namespace prefix mapping to that prefix's string table hashtable.

            Search order per referenced namespace:
            1. Same directory as the source ADMX file.
            2. Recursive scan of that same directory.
            3. Any additional search root provided (e.g. the -AdmxPath directory).
        #>
        [CmdletBinding()]
        param(
            [xml]$AdmxXml,
            [string]$SourceAdmxDir,
            [string]$AdditionalSearchRoot
        )

        $result = @{}

        $rootNamespaceUri = $AdmxXml.DocumentElement.NamespaceURI
        $nsManager = New-Object System.Xml.XmlNamespaceManager($AdmxXml.NameTable)
        if (-not [string]::IsNullOrEmpty($rootNamespaceUri)) {
            $nsManager.AddNamespace('ad', $rootNamespaceUri)
            $usingNodes = $AdmxXml.SelectNodes('//ad:policyNamespaces/ad:using', $nsManager)
        } else {
            $usingNodes = $AdmxXml.SelectNodes('//policyNamespaces/using')
        }

        if ($null -eq $usingNodes -or $usingNodes.Count -eq 0) {
            Write-Verbose "No cross-namespace 'using' declarations found in ADMX"
            return $result
        }

        Write-Verbose "Found $($usingNodes.Count) cross-namespace 'using' declaration(s)"

        foreach ($usingNode in $usingNodes) {
            $prefix = $usingNode.GetAttribute('prefix')
            $namespace = $usingNode.GetAttribute('namespace')

            if ([string]::IsNullOrEmpty($prefix) -or [string]::IsNullOrEmpty($namespace)) {
                continue
            }

            Write-Verbose "Resolving namespace prefix '$($prefix)' (namespace: $($namespace))"

            # Derive candidate ADMX filename from the last segment of the namespace
            # e.g. Microsoft.Policies.Windows -> Windows.admx
            $namespaceParts = $namespace -split '\.'
            $candidateAdmxName = $namespaceParts[-1] + '.admx'

            # Build ordered list of search paths
            $searchPaths = [System.Collections.Generic.List[string]]::new()
            $searchPaths.Add($SourceAdmxDir)
            if (-not [string]::IsNullOrEmpty($AdditionalSearchRoot) -and
                $AdditionalSearchRoot -ne $SourceAdmxDir) {
                $searchPaths.Add($AdditionalSearchRoot)
            }

            $resolvedAdmxPath = $null

            foreach ($searchPath in $searchPaths) {
                if ([string]::IsNullOrEmpty($searchPath) -or -not (Test-Path $searchPath -ErrorAction SilentlyContinue)) {
                    continue
                }

                # 1. Direct child
                $directCandidate = Join-Path $searchPath $candidateAdmxName
                if (Test-Path $directCandidate -PathType Leaf) {
                    Write-Verbose "Found namespace ADMX (direct): $($directCandidate)"
                    $resolvedAdmxPath = $directCandidate
                    break
                }

                # 2. Recursive scan
                $recursiveMatch = Get-ChildItem -Path $searchPath -Filter $candidateAdmxName `
                    -Recurse -File -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($null -ne $recursiveMatch) {
                    Write-Verbose "Found namespace ADMX (recursive): $($recursiveMatch.FullName)"
                    $resolvedAdmxPath = $recursiveMatch.FullName
                    break
                }
            }

            if ($null -eq $resolvedAdmxPath) {
                Write-Warning "Cannot resolve ADMX for namespace prefix '$($prefix)' (expected '$($candidateAdmxName)'). Cross-namespace references using this prefix will be empty."
                continue
            }

            # Load the ADML for this namespace ADMX
            $resolvedAdmlPath = Find-AdmlFile -AdmxFileFullPath $resolvedAdmxPath
            if ($null -eq $resolvedAdmlPath) {
                Write-Warning "Found ADMX for prefix '$($prefix)' but no ADML. Cross-namespace display strings for this prefix will be empty."
                continue
            }

            try {
                [xml]$nsAdmlXml = Get-Content -LiteralPath $resolvedAdmlPath -Raw -ErrorAction Stop
                $nsStringTable = Get-AdmlStringTable -AdmlXml $nsAdmlXml
                $result[$prefix] = $nsStringTable
                Write-Verbose "Loaded string table for prefix '$($prefix)': $($nsStringTable.Count) entries from '$($resolvedAdmlPath)'"
            } catch {
                Write-Warning "Failed to load ADML '$($resolvedAdmlPath)' for prefix '$($prefix)': $($_.Exception.Message)"
            }
        }

        return $result
    }

    function Resolve-CrossNamespaceRef {
        <#
        .SYNOPSIS
            Resolves a cross-namespace string or category reference against a hashtable of
            per-prefix string tables.

            Handles two reference formats:
            - $(using:prefix.StringId)  - used for displayName/explainText/supportedOn
            - prefix:CategoryName       - used for parentCategory ref attribute values
        #>
        [CmdletBinding()]
        param(
            [string]$Reference,
            [hashtable]$NamespaceStringTables
        )

        if ([string]::IsNullOrEmpty($Reference) -or $NamespaceStringTables.Count -eq 0) {
            return $Reference
        }

        # Format 1: $(using:prefix.StringId)
        if ($Reference -match '^\$\(using:([^.]+)\.(.+)\)$') {
            $prefix = $Matches[1]
            $stringId = $Matches[2]
            if ($NamespaceStringTables.ContainsKey($prefix)) {
                $table = $NamespaceStringTables[$prefix]
                if ($table.ContainsKey($stringId)) {
                    Write-Verbose "Resolved cross-namespace ref '$(using:$($prefix).$($stringId))' -> '$($table[$stringId])'"
                    return $table[$stringId]
                }
                Write-Verbose "Cross-namespace string '$($stringId)' not found in prefix '$($prefix)' table ($($table.Count) entries)"
            } else {
                Write-Verbose "Cross-namespace prefix '$($prefix)' not loaded"
            }
            return $null
        }

        # Format 2: prefix:CategoryName (parentCategory ref)
        if ($Reference -match '^([^:$(]+):(.+)$') {
            $prefix = $Matches[1]
            $categoryId = $Matches[2]
            if ($NamespaceStringTables.ContainsKey($prefix)) {
                $table = $NamespaceStringTables[$prefix]
                # Category display names are stored with a conventional string ID pattern
                # Try common patterns: CategoryName, Cat_CategoryName
                foreach ($candidateId in @($categoryId, "Cat_$($categoryId)", "Category_$($categoryId)")) {
                    if ($table.ContainsKey($candidateId)) {
                        Write-Verbose "Resolved cross-namespace category '$($Reference)' via id '$($candidateId)' -> '$($table[$candidateId])'"
                        return $table[$candidateId]
                    }
                }
                Write-Verbose "Cross-namespace category '$($categoryId)' not found in prefix '$($prefix)' string table - returning raw ref"
            } else {
                Write-Verbose "Cross-namespace prefix '$($prefix)' not loaded for category ref '$($Reference)'"
            }
        }

        return $Reference
    }

    function Get-RegistryTypeFromElement {
        <#
        .SYNOPSIS
            Determines the registry type string from an ADMX XML element node.
        #>
        [CmdletBinding()]
        param(
            [System.Xml.XmlElement]$Element,
            [System.Xml.XmlNamespaceManager]$Ns,
            [bool]$UseNamespace = $true
        )

        $storeAsText = $Element.GetAttribute('storeAsText') -eq 'true'

        switch ($Element.LocalName) {
            'decimal'     {
                if ($storeAsText) {
                    Write-Verbose "Element type 'decimal' with storeAsText=true -> REG_SZ"
                    return 'REG_SZ'
                } else {
                    Write-Verbose "Element type 'decimal' -> REG_DWORD"
                    return 'REG_DWORD'
                }
            }
            'longDecimal' {
                Write-Verbose "Element type 'longDecimal' -> REG_QWORD"
                return 'REG_QWORD'
            }
            'text'        {
                Write-Verbose "Element type 'text' -> REG_SZ"
                return 'REG_SZ'
            }
            'multiText'   {
                Write-Verbose "Element type 'multiText' -> REG_MULTI_SZ"
                return 'REG_MULTI_SZ'
            }
            'boolean'     {
                Write-Verbose "Element type 'boolean' -> REG_DWORD"
                return 'REG_DWORD'
            }
            'list'        {
                Write-Verbose "Element type 'list' -> REG_SZ (multiple values)"
                return 'REG_SZ'
            }
            'enum'        {
                $firstItem = if ($UseNamespace) {
                    $Element.SelectSingleNode('ad:item/ad:value/*', $Ns)
                } else {
                    $Element.SelectSingleNode('item/value/*')
                }
                if ($null -ne $firstItem) {
                    switch ($firstItem.LocalName) {
                        'decimal' {
                            Write-Verbose "Element type 'enum' (first item value: decimal) -> REG_DWORD"
                            return 'REG_DWORD'
                        }
                        'string'  {
                            Write-Verbose "Element type 'enum' (first item value: string) -> REG_SZ"
                            return 'REG_SZ'
                        }
                        default   {
                            Write-Verbose "Element type 'enum' (first item value: $($firstItem.LocalName), unknown) -> REG_DWORD"
                            return 'REG_DWORD'
                        }
                    }
                }
                Write-Verbose "Element type 'enum' (no item value nodes found) -> REG_DWORD"
                return 'REG_DWORD'
            }
            default       {
                Write-Verbose "Element type '$($Element.LocalName)' not recognised -> UNKNOWN"
                return 'UNKNOWN'
            }
        }
    }

    function Get-ElementConstraints {
        <#
        .SYNOPSIS
            Returns a hashtable of constraints defined on a policy element (min, max, maxLength, etc.).
        #>
        [CmdletBinding()]
        param([System.Xml.XmlElement]$Element)

        $constraints = @{}

        $minValue = $Element.GetAttribute('minValue')
        $maxValue = $Element.GetAttribute('maxValue')
        $maxLength = $Element.GetAttribute('maxLength')
        $required = $Element.GetAttribute('required')

        if (-not [string]::IsNullOrEmpty($minValue)) { $constraints['MinValue'] = $minValue }
        if (-not [string]::IsNullOrEmpty($maxValue)) { $constraints['MaxValue'] = $maxValue }
        if (-not [string]::IsNullOrEmpty($maxLength)) { $constraints['MaxLength'] = $maxLength }
        if (-not [string]::IsNullOrEmpty($required)) { $constraints['Required'] = $required }

        return $constraints
    }

    function Invoke-AdmxSearch {
        <#
        .SYNOPSIS
            Performs the actual policy search against a parsed ADMX XML document.
        #>
        [CmdletBinding()]
        param(
            [xml]$AdmxXml,
            [hashtable]$StringTable,
            [hashtable]$NamespaceStringTables,
            [string]$DetectedHive,
            [bool]$ReturnAll = $false,
            [string]$NormalizedKey,
            [string]$SearchValueName,
            [string]$SourceFile,
            [string]$SourceAdml
        )

        $ns = New-Object System.Xml.XmlNamespaceManager($AdmxXml.NameTable)

        # Auto-detect namespace from the document root rather than assuming it.
        # Some ADMX files omit the namespace entirely; others use the standard URI.
        $rootNamespaceUri = $AdmxXml.DocumentElement.NamespaceURI
        $knownUri = 'http://schemas.microsoft.com/GroupPolicy/2006/07/PolicyDefinitions'
        $useNamespace = $false

        if (-not [string]::IsNullOrEmpty($rootNamespaceUri)) {
            $useNamespace = $true
            if ($rootNamespaceUri -ne $knownUri) {
                Write-Verbose "Document namespace '$($rootNamespaceUri)' differs from expected - using document namespace"
            } else {
                Write-Verbose "Document namespace matches expected URI"
            }
            $ns.AddNamespace('ad', $rootNamespaceUri)
        } else {
            Write-Verbose "Document has no namespace declaration - using namespace-agnostic XPath"
        }

        $policies = if ($useNamespace) {
            $AdmxXml.SelectNodes('//ad:policy', $ns)
        } else {
            $AdmxXml.SelectNodes('//policy')
        }

        if ($ReturnAll) {
            Write-Verbose "Returning all $($policies.Count) policies from '$($SourceFile)'"
        } else {
            Write-Verbose "Searching $($policies.Count) policies in '$($SourceFile)' for key '$($NormalizedKey)' valueName '$($SearchValueName)'"
        }

        foreach ($policy in $policies) {
            $policyKey = ConvertTo-NormalizedKey -Key $policy.GetAttribute('key')
            $policyValueName = $policy.GetAttribute('valueName')

            $isDirectMatch = ($policyKey -ieq $NormalizedKey) -and ($policyValueName -ieq $SearchValueName)
            $hasElementMatch = $false

            # Resolve enabledValue/disabledValue nodes
            $enabledValueNode = if ($useNamespace) {
                $policy.SelectSingleNode('ad:enabledValue', $ns)
            } else {
                $policy.SelectSingleNode('enabledValue')
            }
            $disabledValueNode = if ($useNamespace) {
                $policy.SelectSingleNode('ad:disabledValue', $ns)
            } else {
                $policy.SelectSingleNode('disabledValue')
            }

            $enabledValueResolved = if ($null -ne $enabledValueNode) {
                $child = $enabledValueNode.ChildNodes |
                    Where-Object { $_.NodeType -ne [System.Xml.XmlNodeType]::Whitespace } |
                    Select-Object -First 1
                if ($null -ne $child) {
                    if ($child.LocalName -eq 'decimal') { [uint64]$child.GetAttribute('value') }
                    elseif ($child.LocalName -eq 'string') { $child.InnerText }
                    else { $null }
                }
            }

            $disabledValueResolved = if ($null -ne $disabledValueNode) {
                $child = $disabledValueNode.ChildNodes |
                    Where-Object { $_.NodeType -ne [System.Xml.XmlNodeType]::Whitespace } |
                    Select-Object -First 1
                if ($null -ne $child) {
                    if ($child.LocalName -eq 'decimal') { [uint64]$child.GetAttribute('value') }
                    elseif ($child.LocalName -eq 'string') { $child.InnerText }
                    else { $null }
                }
            }

            $policyRegistryType = if ($null -ne $enabledValueNode) {
                $child = $enabledValueNode.ChildNodes |
                    Where-Object { $_.NodeType -ne [System.Xml.XmlNodeType]::Whitespace } |
                    Select-Object -First 1
                switch ($child.LocalName) {
                    'decimal' { 'REG_DWORD' }
                    'string'  { 'REG_SZ' }
                    default   { 'REG_DWORD' }
                }
            } else { 'REG_DWORD' }

            # Build Elements array from <elements> child nodes
            $elementNodes = if ($useNamespace) {
                $policy.SelectNodes('ad:elements/*', $ns)
            } else {
                $policy.SelectNodes('elements/*')
            }

            $elementsArray = [System.Collections.Generic.List[PSCustomObject]]::new()
            $matchedElement = $null

            foreach ($element in $elementNodes) {
                $elemKey = $element.GetAttribute('key')
                $elemKey = if ([string]::IsNullOrEmpty($elemKey)) { $policyKey } else { ConvertTo-NormalizedKey -Key $elemKey }
                $elemValueName = $element.GetAttribute('valueName')
                $elemId = $element.GetAttribute('id')
                $elemType = $element.LocalName

                $regType = Get-RegistryTypeFromElement -Element $element -Ns $ns -UseNamespace $useNamespace
                $elemConstraints = Get-ElementConstraints -Element $element

                $elemEnumItems = $null
                $elemTrueValue = $null
                $elemFalseValue = $null

                if ($elemType -eq 'enum') {
                    $enumItemNodes = if ($useNamespace) {
                        $element.SelectNodes('ad:item', $ns)
                    } else {
                        $element.SelectNodes('item')
                    }
                    $enumItems = foreach ($item in $enumItemNodes) {
                        $itemDisplay = Resolve-AdmlString -Reference $item.GetAttribute('displayName') -StringTable $StringTable
                        $valueNode = if ($useNamespace) {
                            $item.SelectSingleNode('ad:value/*', $ns)
                        } else {
                            $item.SelectSingleNode('value/*')
                        }
                        $itemValue = if ($null -eq $valueNode) { $null }
                                     elseif ($valueNode.LocalName -eq 'decimal') { $valueNode.GetAttribute('value') }
                                     elseif ($valueNode.LocalName -eq 'longDecimal') { $valueNode.GetAttribute('value') }
                                     elseif ($valueNode.LocalName -eq 'string') { $valueNode.InnerText }
                                     elseif ($valueNode.LocalName -eq 'delete') { $null }
                                     else { $valueNode.InnerText }
                        [PSCustomObject]@{
                            DisplayName   = $itemDisplay
                            RegistryValue = $itemValue
                            ValueType     = if ($null -ne $valueNode) { $valueNode.LocalName } else { $null }
                        }
                    }
                    $firstValueType = (@($enumItems) | Select-Object -First 1).ValueType
                    $regType = switch ($firstValueType) {
                        'decimal'     { 'REG_DWORD' }
                        'longDecimal' { 'REG_QWORD' }
                        'string'      { 'REG_SZ' }
                        default       { 'REG_DWORD' }
                    }
                    $elemEnumItems = @($enumItems)
                } elseif ($elemType -eq 'boolean') {
                    # Extract explicit trueValue/falseValue child nodes if present
                    $trueValueNode = if ($useNamespace) {
                        $element.SelectSingleNode('ad:trueValue/*', $ns)
                    } else {
                        $element.SelectSingleNode('trueValue/*')
                    }
                    $falseValueNode = if ($useNamespace) {
                        $element.SelectSingleNode('ad:falseValue/*', $ns)
                    } else {
                        $element.SelectSingleNode('falseValue/*')
                    }
                    if ($null -ne $trueValueNode) {
                        $elemTrueValue = if ($trueValueNode.LocalName -eq 'decimal') { [uint64]$trueValueNode.GetAttribute('value') }
                                         elseif ($trueValueNode.LocalName -eq 'string') { $trueValueNode.InnerText }
                                         else { $null }
                    }
                    if ($null -ne $falseValueNode) {
                        $elemFalseValue = if ($falseValueNode.LocalName -eq 'decimal') { [uint64]$falseValueNode.GetAttribute('value') }
                                          elseif ($falseValueNode.LocalName -eq 'string') { $falseValueNode.InnerText }
                                          else { $null }
                    }
                }

                $elementObj = [PSCustomObject]@{
                    ElementId       = $elemId
                    ElementType     = $elemType
                    ConfiguredState = 'Unconfigured'
                    RegistryKey     = $elemKey
                    ValueName       = $elemValueName
                    RegistryType    = $regType
                    Constraints     = if ($elemConstraints.Count -gt 0) { $elemConstraints } else { $null }
                    EnumItems       = $elemEnumItems
                    TrueValue       = $elemTrueValue
                    FalseValue      = $elemFalseValue
                }

                $elementsArray.Add($elementObj)

                if (-not $ReturnAll -and -not $hasElementMatch) {
                    if (($elemKey -ieq $NormalizedKey) -and ($elemValueName -ieq $SearchValueName)) {
                        $hasElementMatch = $true
                        $matchedElement = $elementObj
                        Write-Verbose "Element-level match: '$($policy.GetAttribute('name'))' element '$elemType' id='$elemId' valueName='$elemValueName' in '$SourceFile'"
                    }
                }
            }

            $shouldEmit = $ReturnAll -or $isDirectMatch -or $hasElementMatch
            if (-not $shouldEmit) { continue }

            # Resolve policy-level display strings
            $displayNameRef = $policy.GetAttribute('displayName')
            $explainRef     = $policy.GetAttribute('explainText')
            $displayName    = Resolve-AdmlString -Reference $displayNameRef -StringTable $StringTable
            $explainText    = Resolve-AdmlString -Reference $explainRef -StringTable $StringTable

            $categoryNode = if ($useNamespace) {
                $policy.SelectSingleNode('ad:parentCategory', $ns)
            } else {
                $policy.SelectSingleNode('parentCategory')
            }
            $categoryRef = if ($null -ne $categoryNode) { $categoryNode.GetAttribute('ref') } else { '' }

            $supportedNode = if ($useNamespace) {
                $policy.SelectSingleNode('ad:supportedOn', $ns)
            } else {
                $policy.SelectSingleNode('supportedOn')
            }
            $supportedRef = if ($null -ne $supportedNode) { $supportedNode.GetAttribute('ref') } else { '' }

            $categoryName = if ($categoryRef -match '^[^:$(]+:.+$') {
                Resolve-CrossNamespaceRef -Reference $categoryRef -NamespaceStringTables $NamespaceStringTables
            } else {
                Resolve-AdmlString -Reference $categoryRef -StringTable $StringTable
            }

            $supportedOn = $null
            if (-not [string]::IsNullOrEmpty($supportedRef)) {
                if ($supportedRef -match '^\$\(using:' -or $supportedRef -match '^[^:$(]+:.+$') {
                    $resolved = Resolve-CrossNamespaceRef -Reference $supportedRef -NamespaceStringTables $NamespaceStringTables
                    $supportedOn = if (-not [string]::IsNullOrEmpty($resolved)) { $resolved } else { $supportedRef }
                } else {
                    $supportedOn = Resolve-AdmlString -Reference $supportedRef -StringTable $StringTable
                }
            }

            $policyClass = $policy.GetAttribute('class')
            $resolvedClass = if ($policyClass -ieq 'Both' -and -not [string]::IsNullOrEmpty($DetectedHive)) {
                $DetectedHive
            } else {
                $policyClass
            }

            Write-Verbose "Emitting result: PolicyName='$($policy.GetAttribute('name'))' Elements=$($elementsArray.Count)"
            [PSCustomObject]@{
                PolicyName      = $policy.GetAttribute('name')
                DisplayName     = $displayName
                ExplainText     = $explainText
                Class           = $resolvedClass
                Category        = $categoryName
                SupportedOn     = $supportedOn
                ConfiguredState = 'Unconfigured'
                RegistryKey     = $policyKey
                ValueName       = $policyValueName
                RegistryType    = $policyRegistryType
                EnabledValue    = $enabledValueResolved
                DisabledValue   = $disabledValueResolved
                Elements        = if ($elementsArray.Count -gt 0) { $elementsArray.ToArray() } else { @() }
                MatchedElement  = $matchedElement
                AdmxFile        = $(try { [System.IO.Path]::GetFileName($SourceFile) } catch { $null })
                AdmlFile        = $(try { [System.IO.Path]::GetFileName($SourceAdml) } catch { $null })
                SourceFile      = $SourceFile
                SourceAdml      = $SourceAdml
            }
        }
    }

    #endregion Internal helpers

    #region Main logic

    # Infer return-all mode: explicit -All switch, or neither -RegistryKey nor -ValueName provided
    $returnAll = $returnAll -or ([string]::IsNullOrEmpty($RegistryKey) -and [string]::IsNullOrEmpty($ValueName))

    # When not in return-all mode both parameters are required
    if (-not $returnAll) {
        if ([string]::IsNullOrEmpty($RegistryKey) -or [string]::IsNullOrEmpty($ValueName)) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new('Specify both -RegistryKey and -ValueName, or omit both (or use -All) to return all policies.'),
                    'MissingSearchParameters',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $null
                )
            )
        }
    }

    $normalizedKey = if (-not [string]::IsNullOrEmpty($RegistryKey)) {
        ConvertTo-NormalizedKey -Key $RegistryKey
    } else {
        $null
    }

    # Detect the hive prefix from the original RegistryKey for resolving class="Both" policies
    $detectedHive = $null
    if (-not [string]::IsNullOrEmpty($RegistryKey)) {
        if ($RegistryKey -match '^(HKEY_LOCAL_MACHINE|HKLM)\') {
            $detectedHive = 'Machine'
        } elseif ($RegistryKey -match '^(HKEY_CURRENT_USER|HKCU)\') {
            $detectedHive = 'User'
        }
    }

    if ($returnAll) {
        Write-Verbose "Returning all policies (ParameterSet: $($PSCmdlet.ParameterSetName))"
    } else {
        Write-Verbose "Searching for: Key='$($normalizedKey)' ValueName='$($ValueName)' (ParameterSet: $($PSCmdlet.ParameterSetName))"
    }

    switch ($PSCmdlet.ParameterSetName) {

        'XmlContent' {
            Write-Verbose "Parameter set: XmlContent"

            try {
                if ($base64DecodedAdmx = Test-Base64String -InputString $AdmxContent -PassThru -AsString) {
                    [xml]$admxXml = $base64DecodedAdmx
                } else {
                    [xml]$admxXml = $AdmxContent
                }
                Write-Verbose "AdmxContent parsed successfully"
            } catch {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new("Failed to parse AdmxContent as XML: $($_.Exception.Message)"),
                        'InvalidAdmxXml',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        $AdmxContent
                    )
                )
            }

            $stringTable = @{}
            if ($PSBoundParameters.ContainsKey('AdmlContent')) {
                try {
                    if ($base64DecodedAdml = Test-Base64String -InputString $AdmlContent -PassThru -AsString) {
                        [xml]$admlXml = $base64DecodedAdml
                    } else {
                        [xml]$admlXml = $AdmlContent
                    }
                    $stringTable = Get-AdmlStringTable -AdmlXml $admlXml
                    Write-Verbose "AdmlContent parsed successfully"
                } catch {
                    Write-Warning "Failed to parse AdmlContent as XML: $($_.Exception.Message). Display names will not be resolved."
                }
            } else {
                Write-Warning "No AdmlContent provided. Display names will not be resolved."
            }

            Invoke-AdmxSearch -AdmxXml $admxXml -StringTable $stringTable `
                -NamespaceStringTables @{} `
                -DetectedHive $detectedHive `
                -ReturnAll $returnAll `
                -NormalizedKey $normalizedKey -SearchValueName $ValueName `
                -SourceFile $AdmxFileName `
                -SourceAdml $AdmlFileName
        }

        'XmlFile' {
            Write-Verbose "Parameter set: XmlFile - $($AdmxFilePath)"

            try {
                [xml]$admxXml = Get-Content -LiteralPath $AdmxFilePath -Raw -ErrorAction Stop
                Write-Verbose "ADMX file loaded: $($AdmxFilePath)"
            } catch {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.IO.IOException]::new("Failed to read ADMX file '$($AdmxFilePath)': $($_.Exception.Message)"),
                        'AdmxReadError',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $AdmxFilePath
                    )
                )
            }

            $stringTable = @{}
            $resolvedAdml = if ($PSBoundParameters.ContainsKey('AdmlFilePath')) {
                Write-Verbose "Using explicitly provided ADML: $($AdmlFilePath)"
                $AdmlFilePath
            } else {
                Write-Verbose "AdmlFilePath not provided, attempting auto-detection"
                Find-AdmlFile -AdmxFileFullPath $AdmxFilePath
            }

            if ($null -ne $resolvedAdml) {
                try {
                    [xml]$admlXml = Get-Content -LiteralPath $resolvedAdml -Raw -ErrorAction Stop
                    $stringTable = Get-AdmlStringTable -AdmlXml $admlXml
                    Write-Verbose "Loaded ADML: $($resolvedAdml)"
                } catch {
                    Write-Warning "Failed to read ADML '$($resolvedAdml)': $($_.Exception.Message). Display names will not be resolved."
                }
            } else {
                Write-Warning "No ADML file found for '$($AdmxFilePath)'. Display names will not be resolved."
            }

            Invoke-AdmxSearch -AdmxXml $admxXml -StringTable $stringTable `
                -NamespaceStringTables (Get-CrossNamespaceStringTables -AdmxXml $admxXml `
                    -SourceAdmxDir (Split-Path -Parent $AdmxFilePath) `
                    -AdditionalSearchRoot (Split-Path -Parent $AdmxFilePath)) `
                -DetectedHive $detectedHive `
                -ReturnAll $returnAll `
                -NormalizedKey $normalizedKey -SearchValueName $ValueName `
                -SourceFile $AdmxFilePath `
                -SourceAdml $(if ($null -ne $resolvedAdml) { $resolvedAdml } else { $null })
        }

        'Path' {
            Write-Verbose "Parameter set: Path - $($AdmxPath)"

            $admxFiles = if ((Get-Item -LiteralPath $AdmxPath).PSIsContainer) {
                $getSplat = @{
                    Path    = $AdmxPath
                    Filter  = '*.admx'
                    Recurse = $Recurse.IsPresent
                    File    = $true
                }
                Get-ChildItem @getSplat
            } else {
                Write-Verbose "AdmxPath is a single file: $($AdmxPath)"
                Get-Item -LiteralPath $AdmxPath
            }

            if (-not $admxFiles) {
                Write-Warning "No ADMX files found at '$($AdmxPath)'."
                return
            }

            Write-Verbose "Found $(@($admxFiles).Count) ADMX file(s) to process"

            foreach ($admxFile in $admxFiles) {
                Write-Verbose "Processing ADMX: $($admxFile.FullName)"

                try {
                    [xml]$admxXml = Get-Content -LiteralPath $admxFile.FullName -Raw -ErrorAction Stop
                    Write-Verbose "ADMX loaded successfully: $($admxFile.Name)"
                } catch {
                    Write-Warning "Failed to read '$($admxFile.Name)': $($_.Exception.Message). Skipping."
                    continue
                }

                $stringTable = @{}
                $resolvedAdml = Find-AdmlFile -AdmxFileFullPath $admxFile.FullName

                if ($null -ne $resolvedAdml) {
                    try {
                        [xml]$admlXml = Get-Content -LiteralPath $resolvedAdml -Raw -ErrorAction Stop
                        $stringTable = Get-AdmlStringTable -AdmlXml $admlXml
                        Write-Verbose "Loaded ADML: $($resolvedAdml)"
                    } catch {
                        Write-Warning "Failed to read ADML '$($resolvedAdml)': $($_.Exception.Message). Display names will not be resolved for $($admxFile.Name)."
                    }
                } else {
                    Write-Warning "No ADML found for '$($admxFile.Name)'. Display names will not be resolved."
                }

                $sourceAdmxDir = Split-Path -Parent $admxFile.FullName
                $additionalRoot = if ((Get-Item -LiteralPath $AdmxPath).PSIsContainer) { $AdmxPath } else { $sourceAdmxDir }
                $nsStringTables = Get-CrossNamespaceStringTables -AdmxXml $admxXml `
                    -SourceAdmxDir $sourceAdmxDir -AdditionalSearchRoot $additionalRoot

                Invoke-AdmxSearch -AdmxXml $admxXml -StringTable $stringTable `
                    -NamespaceStringTables $nsStringTables `
                    -DetectedHive $detectedHive `
                    -ReturnAll $returnAll `
                    -NormalizedKey $normalizedKey -SearchValueName $ValueName `
                    -SourceFile $admxFile.FullName `
                    -SourceAdml $(if ($null -ne $resolvedAdml) { $resolvedAdml } else { $null })
            }
        }
    }

    #endregion Main logic
}

# SIG # Begin signature block
# MII6BgYJKoZIhvcNAQcCoII59zCCOfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDYqfxiJcUPKon3
# yP2fnsynNrP2YubSKpAPOi6Ac5iMUaCCIiowggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# IDJc8+RFDX+pYexKatzicCUczndmHnA5GJaWaNyAE2p/MA0GCSqGSIb3DQEBAQUA
# BIIBgEmeXjIsZkIcWxC3UUUr41mvor+er/PxeiaeDs79Y9FI3GeMpxKcdBX+vyUL
# A0/su4o2g2gbP+JDnLcl2cAx7I6iB6EG2Dhzsz8j7OLS/ty36JIalv+uFmZNKNRL
# 1fhmjCofjhbLUgUmMyJgSgIiz1Oqcktk6arp0ojCUHinSRX5fDdDFWThBRxjNdtK
# TVwMSPs5XPqy3XP5pXFzJBXbH84jTsPnDuu7pT0kXuWjVz3oL2oWZyduTnTDrtKM
# EMYInSrTuJWsB16GgzuqIPCnjE401Cd0giap1KrTaQHu7VjaFh7mEB8+doQ/HsAY
# cyqy8HJiw1nUBas0ECGCnhNiViE7PQwU4oZPA1hVfiwxfIQmw+g16CUxWFV48lhg
# v2n/NOzV7AAomOptxmrjqgVl/Vnkai8XE1PFoZX2EJL/5Te/vgiEqEx2Im/+mo4l
# 823ixaOaOMbpGiUwUGeWTsfunEkH1OMH0LUHllfZ4Bz7OdR06IVMGxVxiBXrIjfB
# BLdwBqGCFLIwghSuBgorBgEEAYI3AwMBMYIUnjCCFJoGCSqGSIb3DQEHAqCCFIsw
# ghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFqBgsqhkiG9w0BCRABBKCCAVkEggFV
# MIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBZZS26qpL6Mgr5
# 0aN6+JtzMqEL57Fj1rp6BogiD4kf6QIGacZuNOsTGBMyMDI2MDQxNTE5NDM1Mi4w
# NDRaMASAAgH0oIHppIHmMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
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
# AQkEMSIEIGE4ycOc4Ykp2IYPxzHfc1uZmlHCtBOGVEBviR6v6bKgMIHdBgsqhkiG
# 9w0BCRACLzGBzTCByjCBxzCBoAQgLzEDVV2dG9McZRsPF/9yBMmzm7k+muVtXetQ
# lvnBg+8wfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABbSrWNQTJt3HQAAAAAAFswIgQgcIcDmRdK2VhC
# 7uWUtl7jNMn9x8zfnOBTl8hH91XjZiAwDQYJKoZIhvcNAQELBQAEggIAh/PK8Y7T
# VIIyYZbMRBAgQ3BBEUmCOnK0FfV+Li58FT0vczmNE7hQedxaQgK/3+9OeuM21u2l
# KdwrDTd7nGR2JuA3e02nOAkWyEFm1UIkPz7MhPlfgCCrt80vciA+HjBAWLkbz5Xk
# s8cOhGbtvdsZ24YZTcxiLZcWIl1WkEq2gbV0d1xMCI/o0lY9tjjxNcFFp0b4Vko0
# A8kQVj2dhoE0Xh9XdPdb2Diw1Xy/mM2XvUtNrBs5KyrlZ/fIouhNEMeEBbxKwgJa
# WGgHV7svwzAkFP2Zl8p958ddQFF4BZijPR6pqebk5lbs82SVvRvaRrm/QQ+lTPTi
# 6+Ww1DWQzRxWWO6diWlw+G40I5dVrbjVp9ip6EFJhx+y1gRmM96uTzLFulk4i1Kr
# +FJ8gUzMlAwfAqvNQFAhrkR6tLdKzImaTGlsIcugrNF60q7p5dR3dzK7ver2/HBd
# Dc1ZP2eSRLy6cEDJVGsmYQxydHia7cSBfXukGAgr7HX6ZIyMR8eV0syAMrEMQe7h
# WbGwNNMqBB69WQ2JhTi365fvjHQ/NNCxFj8/Bm0ufOukE5buMwOsFPjlGvWewol/
# EldW3v3+N/ioWVkf4T8dgX4mGZfb1JfHivs1JFHrs+X/EWT0J6qFuYPMEIwMbbUq
# 54bn8P16XCZPPAi//NjRmtB6ByqtcXbZ7fI=
# SIG # End signature block
