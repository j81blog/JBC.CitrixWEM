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

        Registry values written by enabledList, disabledList and enum valueList nodes are returned in
        the AuxiliaryValues property. These have no matching entry in Elements.

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
        Version   : 2026.1118.1200
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
                if ($Element.GetAttribute('expandable') -eq 'true') {
                    Write-Verbose "Element type 'text' with expandable=true -> REG_EXPAND_SZ"
                    return 'REG_EXPAND_SZ'
                }
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

    function Get-AdmxListValue {
        <#
        .SYNOPSIS
            Converts an <enabledList>, <disabledList> or enum <valueList> node into registry value descriptors.
        .DESCRIPTION
            These nodes write registry values that have no matching <elements> entry, so they are not
            covered by the element parsing. Each <item> takes its key from its own key attribute, the
            list defaultKey, or the policy key, in that order.
        #>
        [CmdletBinding()]
        param(
            [System.Xml.XmlElement]$ListNode,
            [string]$PolicyKey,
            [System.Xml.XmlNamespaceManager]$Ns,
            [bool]$UseNamespace = $true
        )

        $defaultKey = $ListNode.GetAttribute('defaultKey')

        $itemNodes = if ($UseNamespace) {
            $ListNode.SelectNodes('ad:item', $Ns)
        } else {
            $ListNode.SelectNodes('item')
        }

        foreach ($item in $itemNodes) {
            $itemKey = $item.GetAttribute('key')
            if ([string]::IsNullOrEmpty($itemKey)) { $itemKey = $defaultKey }
            $itemKey = if ([string]::IsNullOrEmpty($itemKey)) { $PolicyKey } else { ConvertTo-NormalizedKey -Key $itemKey }

            $valueNode = if ($UseNamespace) {
                $item.SelectSingleNode('ad:value/*', $Ns)
            } else {
                $item.SelectSingleNode('value/*')
            }

            $itemValue = $null
            $itemType = $null
            $itemDelete = $false
            if ($null -ne $valueNode) {
                switch ($valueNode.LocalName) {
                    'decimal'     { $itemValue = $valueNode.GetAttribute('value'); $itemType = 'REG_DWORD' }
                    'longDecimal' { $itemValue = $valueNode.GetAttribute('value'); $itemType = 'REG_QWORD' }
                    'string'      { $itemValue = $valueNode.InnerText; $itemType = 'REG_SZ' }
                    'delete'      { $itemDelete = $true }
                    default       { $itemValue = $valueNode.InnerText; $itemType = 'REG_SZ' }
                }
            }

            [PSCustomObject]@{
                RegistryKey  = $itemKey
                ValueName    = $item.GetAttribute('valueName')
                Value        = $itemValue
                RegistryType = $itemType
                Delete       = $itemDelete
            }
        }
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

            # Auxiliary registry values written by <enabledList>/<disabledList> and enum <valueList> nodes
            $auxiliaryValues = [System.Collections.Generic.List[PSCustomObject]]::new()
            $listNodes = if ($useNamespace) {
                $policy.SelectNodes('ad:enabledList|ad:disabledList|ad:elements/ad:enum/ad:item/ad:valueList', $ns)
            } else {
                $policy.SelectNodes('enabledList|disabledList|elements/enum/item/valueList')
            }
            foreach ($listNode in $listNodes) {
                foreach ($auxValue in @(Get-AdmxListValue -ListNode $listNode -PolicyKey $policyKey -Ns $ns -UseNamespace $useNamespace)) {
                    $auxiliaryValues.Add($auxValue)
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
                AuxiliaryValues = if ($auxiliaryValues.Count -gt 0) { $auxiliaryValues.ToArray() } else { @() }
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
# MII6AgYJKoZIhvcNAQcCoII58zCCOe8CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCK/agxUUG+6uoR
# enjScyXf7kzG5u9wB74AOSgK/nbxfaCCIiYwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAvBgkqhkiG9w0BCQQxIgQgiz4q
# RB2vL3+Em/+d+V1Uduk22TGzE/TXs4fcOrYxqLQwDQYJKoZIhvcNAQEBBQAEggGA
# IOP01uOqINUSFl9jKxfkSe77QHkrrHbhq669zeQxtvc7Tm8wtZ3WP7qc4FNBA2DU
# 7DFloIPHStrhouj4C9Rwnwsp3FE1DW54czwOcxnusahku9JummVLjkZLFp1Ossxi
# an6V5Z41ih/fPxu7BZ196dZ1nHcwMRmyJdyg2mNxPKYh9lFL54Ej4g+Q2fxM5SRH
# aSyFnSM9Ce/oEMWbaI/Al0XxR8Wc6oOgq1L3sLlKGvaTjOxIcoaEUe8XdK8ifvRy
# fB23KfkMSsM1PNd6ElfdgrEYHpqchpvA+u9LAk8L4mHORvJc70l6L2OQ5mVF4sMt
# P5dMxGkOuqZYUx8CwceL+QRk2+z6iNjn4mh7FEP4YAXj+DQAeXL4HpuNHDpQsOyq
# Lu1fX479k4VRuJQ3uRsf2svVIabu4AEMcKC1gFDpeTjoUJiV8SrnLsPwuRWgIQsk
# FAlHPYCv+Ci6k04GLmVTmmWq9WnUFJmKfiYIr6czmQ/zGS8hmKgz9kl0eQ2wJuCf
# oYIUsjCCFK4GCisGAQQBgjcDAwExghSeMIIUmgYJKoZIhvcNAQcCoIIUizCCFIcC
# AQMxDzANBglghkgBZQMEAgEFADCCAWoGCyqGSIb3DQEJEAEEoIIBWQSCAVUwggFR
# AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIA3agR75PZhRVBHzGsgw
# Wkr7KQLX/7OklzZhZc89YhcDAgZq80s28WIYEzIwMjYxMTE4MTM0MjA2LjgzM1ow
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
# IgQgr95Is/+pkDpS1ZnhB+RNKrmlEj22enPUMP9Sy2pok4owgd0GCyqGSIb3DQEJ
# EAIvMYHNMIHKMIHHMIGgBCAvMQNVXZ0b0xxlGw8X/3IEybObuT6a5W1d61CW+cGD
# 7zB8MGWkYzBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3RhbXBp
# bmcgQ0EgMjAyMAITMwAAAFtKtY1BMm3cdAAAAAAAWzAiBCAvBX47N35sG98AzKot
# 6LIPANnZF24XKYSYB+wUXYPfUTANBgkqhkiG9w0BAQsFAASCAgAMaX2/awJLqDwx
# Zp59xwkd2laZmTcP1cN2K4xyo7DwpwaVFSX7YQIeYpZ3aGwojMrxDNrDgUIDV0ME
# CZf7kBwylkGLxdqXXph3UjvfwMrEM+uIuO1zC7fW4JhCxW9NFfI11QLwVGur6rXU
# 8Mx+iyO+DM7+pwNow09JHhpYx7krZZDv2k7P4SCwJV9Nd35RmYGjYgUyDRoVcLS8
# TV4ojY40SDVEecYTPAk8zzZXUTirYRP/L93fZRwoixhez0Gp62l7cZdRXfl/3ycK
# AkTG75Z2TrkdZ6g8CWDGnPifNFTr5QsVpKqkvj/2FBlbW0bkrcqbAKUUET8RkXVv
# UkHCfulgmoqBPPq/c0jfBLJlV41xioizPKveH20BFE1QsuHl2w9ST8bCKo5C5GQk
# EOJysX8hxmQKwQCk00fncE4P0h1cJEytDeB3uiH4qR64afoLbPiW4J6JfWuSDiE5
# /0YSN14ayIgskdWnv+lJ2PZoLrLU1tYKnRHyPgpvzG8DCItR8tRfsC1oDrZypL2W
# CUZJ7WJKdyJW4AmJrHVCnVvCheUsDXTtgix0yBwiWs+x/qy71DogIIAwRSbwzw+e
# 0tIpG8HmgTqHtD5TpwTugO043sdW5Pmhsa/z8eVJnX/xvo9XdwA/pKFaLVZGfqwO
# LsMuGGefbREwyr/9C4EZOTQETmyMNA==
# SIG # End signature block
