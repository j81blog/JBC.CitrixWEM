#Requires -Modules Pester

<#
    .SYNOPSIS
        Regression tests for ADMX correlation in the Ivanti Workspace Control policy import.

    .DESCRIPTION
        Covers the two paths that turn an Ivanti policy set into WEM and AppVentiX policy data:
            Get-AdmxPolicySetting - parses the ADMX template into policies, elements and
                                    auxiliary values (enabledList/disabledList/valueList).
            Get-IvantiWCPolicy    - correlates the decoded registry file with that model and
                                    builds the WEMParams and AppVentiXParams exports.

        The cases under test:
          - Registry values written by enabledList, disabledList and enum valueList nodes have no
            ADMX element. They must resolve to their owning policy and land in RegistryEntries
            only, without producing extra policy elements and without a "does not match any
            policy" warning.
          - text elements with expandable="true" are REG_EXPAND_SZ. Their value must survive the
            export instead of being dropped with an "unsupported RegistryValueType" warning.
          - decimal elements keep their number. Only boolean elements become a checkbox.
          - multiText elements (REG_MULTI_SZ) are joined into a single value.
          - An ADMX whose XML declaration disagrees with its actual bytes (how the Office
            templates ship) must still load from the embedded building block data.
          - The WEM export writes the auxiliary values as registry operations, unescapes .reg
            string values and keeps REG_EXPAND_SZ.

        Get-IvantiWCPolicy and Get-AdmxPolicySetting are dot-sourced together with the private
        functions they call, so the tests need no WEM connection. The building block files are
        generated under $TestDrive from the fixture template in Fixtures\AdmxTemplates.

    .NOTES
        File     : IvantiWCPolicy.Tests.ps1
        Author   : John Billekens
        Copyright: (c) John Billekens Consultancy & AppVentiX
#>

BeforeAll {
    $script:projectRoot = Split-Path -Parent -Path $PSScriptRoot
    $script:publicRoot = Join-Path -Path $script:projectRoot -ChildPath 'JBC.CitrixWEM\Public'
    $script:privateRoot = Join-Path -Path $script:projectRoot -ChildPath 'JBC.CitrixWEM\Private'
    $script:fixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\AdmxTemplates'

    # Functions under test plus the private helpers they call.
    . (Join-Path -Path $script:privateRoot -ChildPath 'Get-AdmxPolicySetting.ps1')
    . (Join-Path -Path $script:publicRoot -ChildPath 'Get-IvantiWCPolicy.ps1')
    . (Join-Path -Path $script:privateRoot -ChildPath 'ConvertFrom-IvantiBB.ps1')
    . (Join-Path -Path $script:privateRoot -ChildPath 'ConvertFrom-IvantiAccessControl.ps1')
    . (Join-Path -Path $script:privateRoot -ChildPath 'Get-FileEncoding.ps1')
    . (Join-Path -Path $script:privateRoot -ChildPath 'Test-Base64String.ps1')

    # Reached only by access control entries that name a domain object. The fixtures assign to
    # everyone, so these never run; they are sourced so nothing is undefined under StrictMode.
    . (Join-Path -Path $script:privateRoot -ChildPath 'Get-ADDomainFQDN.ps1')
    . (Join-Path -Path $script:privateRoot -ChildPath 'Get-AdsiADDomain.ps1')

    $script:admxFixture = Join-Path -Path $script:fixtureRoot -ChildPath 'AppVentiXTest.admx'
    $script:admlFixture = Join-Path -Path $script:fixtureRoot -ChildPath 'AppVentiXTest.adml'

    # Ivanti stores the embedded files and the decoded text blocks as plain hex.
    function ConvertTo-IvantiHex {
        param([byte[]]$Bytes)
        ($Bytes | ForEach-Object { $_.ToString('x2') }) -join ''
    }

    function ConvertTo-IvantiTextHex {
        param([string]$Text)
        ConvertTo-IvantiHex -Bytes ([System.Text.Encoding]::GetEncoding(1252).GetBytes($Text))
    }

    # Registry file payloads for the types that are stored as hex in a .reg export.
    function ConvertTo-RegExpandHex {
        param([string]$Text)
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($Text + [char]0)
        'hex(2):' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join ',')
    }

    function ConvertTo-RegMultiHex {
        param([string[]]$Values)
        $bytes = [System.Text.Encoding]::Unicode.GetBytes((($Values -join [char]0) + [char]0 + [char]0))
        'hex(7):' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join ',')
    }

    <#
        Builds a minimal Ivanti building block holding one policy set and the fixture template.
        -DeclareWrongEncoding embeds the template as UTF-8 bytes while its XML declaration claims
        utf-16, which is how the Microsoft Office templates ship.
    #>
    function New-TestBuildingBlock {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that writes a throwaway building block under $TestDrive.')]
        param(
            [string]$PolicySetName = 'AppVentiX Test - Policy',
            [Parameter(Mandatory = $true)]
            [string]$RegistryFile,
            [switch]$DeclareWrongEncoding
        )

        $admxText = [System.IO.File]::ReadAllText($script:admxFixture)
        $admlText = [System.IO.File]::ReadAllText($script:admlFixture)
        if ($DeclareWrongEncoding.IsPresent) {
            $admxText = $admxText -replace 'encoding="utf-8"', 'encoding="utf-16"'
            $admlText = $admlText -replace 'encoding="utf-8"', 'encoding="utf-16"'
        }

        $utf8WithBom = [System.Text.UTF8Encoding]::new($true)
        $admxHex = ConvertTo-IvantiHex -Bytes ($utf8WithBom.GetBytes($admxText))
        $admlHex = ConvertTo-IvantiHex -Bytes ($utf8WithBom.GetBytes($admlText))
        $settingsHex = ConvertTo-IvantiTextHex -Text "ADMFILENAME:AppVentiXTest.admx`r`n"
        $registryHex = ConvertTo-IvantiTextHex -Text $RegistryFile

        $bb = @"
<?xml version="1.0" encoding="utf-8"?>
<respowerfuse>
  <buildingblock>
    <registries>
      <registry type="policy">
        <name>$PolicySetName</name>
        <description>Generated by IvantiWCPolicy.Tests.ps1</description>
        <enabled>yes</enabled>
        <runonce>no</runonce>
        <guid>{aaaaaaaa-0001-0001-0001-000000000001}</guid>
        <accesscontrol><accesstype>all</accesstype></accesscontrol>
        <policysettings>$settingsHex</policysettings>
        <registryfile>$registryHex</registryfile>
      </registry>
    </registries>
    <embeddedadms>
      <embeddedadm>
        <filename>AppVentiXTest.admx</filename>
        <embeddedbinary>$admxHex</embeddedbinary>
        <embeddedadml>$admlHex</embeddedadml>
      </embeddedadm>
    </embeddedadms>
  </buildingblock>
</respowerfuse>
"@

        $path = Join-Path -Path $TestDrive -ChildPath "$([System.Guid]::NewGuid().ToString()).xml"
        [System.IO.File]::WriteAllText($path, $bb, [System.Text.UTF8Encoding]::new($false))
        return $path
    }

    # One registry file exercising every element and auxiliary case in the fixture template.
    $script:fullRegistryFile = @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Policies\AppVentiXTest\Paths]
"defaultpath"=$(ConvertTo-RegExpandHex -Text '%USERPROFILE%\Docs')
"plainpath"="%userprofile%\\Documents\\AutoRecover"
"quoted"="say \"hi\""

[HKEY_CURRENT_USER\Software\Policies\AppVentiXTest\Options]
"delayseconds"=dword:0000001e
"toggleon"=dword:00000001
"lines"=$(ConvertTo-RegMultiHex -Values @('one', 'two'))
"simpleswitch"=dword:00000001

[HKEY_CURRENT_USER\Software\Policies\AppVentiXTest\Profile\givenname]
"Value"="John"
"Dummy"=dword:00000002
"Final"=dword:00000001
"External"=dword:00000001
"ExternalBackend"="com.appventix.test.Backend"

[HKEY_CURRENT_USER\Software\Policies\AppVentiXTest\AddinList]
"addinname"="TestAddin"
"policyon"=dword:00000001

[HKEY_CURRENT_USER\Software\Policies\AppVentiXTest\PathList]
"1"="C:\\Folder One"
"2"="C:\\Folder Two"
"@
}

Describe 'Get-AdmxPolicySetting' {

    BeforeAll {
        $script:allPolicies = Get-AdmxPolicySetting -AdmxPath $script:admxFixture -All
    }

    Context 'Auxiliary values' {

        It 'returns every enum valueList item as an auxiliary value' {
            $flags = $script:allPolicies | Where-Object PolicyName -EQ 'AvxFlags'
            $names = @($flags.AuxiliaryValues.ValueName | Sort-Object -Unique)

            $names | Should -Be @('External', 'ExternalBackend', 'Final')
        }

        It 'resolves the valueList defaultKey for each item' {
            $flags = $script:allPolicies | Where-Object PolicyName -EQ 'AvxFlags'

            @($flags.AuxiliaryValues.RegistryKey | Sort-Object -Unique) |
                Should -Be @('Software\Policies\AppVentiXTest\Profile\givenname')
        }

        # Angle brackets are avoided in the name: Pester reads them as a data placeholder.
        It 'flags a valueList item holding a delete node as a deletion' {
            $flags = $script:allPolicies | Where-Object PolicyName -EQ 'AvxFlags'
            $deleted = @($flags.AuxiliaryValues | Where-Object Delete)

            $deleted.Count | Should -Be 1
            $deleted[0].ValueName | Should -Be 'ExternalBackend'
        }

        It 'returns enabledList and disabledList items as auxiliary values' {
            $managed = $script:allPolicies | Where-Object PolicyName -EQ 'AvxManagedList'

            $managed.AuxiliaryValues.Count | Should -Be 2
            @($managed.AuxiliaryValues.ValueName | Sort-Object -Unique) | Should -Be @('policyon')
        }

        It 'returns an empty collection for a policy without list nodes' {
            $delay = $script:allPolicies | Where-Object PolicyName -EQ 'AvxDelay'

            $delay.AuxiliaryValues | Should -BeNullOrEmpty
        }

        It 'does not turn auxiliary values into policy elements' {
            $flags = $script:allPolicies | Where-Object PolicyName -EQ 'AvxFlags'

            @($flags.Elements.ElementId) | Should -Be @('AvxFlagsValue', 'AvxFlagsMode')
        }
    }

    Context 'Registry type mapping' {

        It 'maps a text element with expandable="true" to REG_EXPAND_SZ' {
            $paths = $script:allPolicies | Where-Object PolicyName -EQ 'AvxExpandablePath'
            $element = $paths.Elements | Where-Object ElementId -EQ 'AvxPathValue'

            $element.RegistryType | Should -Be 'REG_EXPAND_SZ'
        }

        It 'maps a plain text element to REG_SZ' {
            $paths = $script:allPolicies | Where-Object PolicyName -EQ 'AvxExpandablePath'
            $element = $paths.Elements | Where-Object ElementId -EQ 'AvxPlainValue'

            $element.RegistryType | Should -Be 'REG_SZ'
        }

        It 'maps a multiText element to REG_MULTI_SZ' {
            $multi = $script:allPolicies | Where-Object PolicyName -EQ 'AvxMultiLine'

            $multi.Elements[0].RegistryType | Should -Be 'REG_MULTI_SZ'
        }
    }
}

Describe 'Get-IvantiWCPolicy' {

    Context 'AppVentiX export of a fully configured policy set' {

        BeforeAll {
            $script:bbPath = New-TestBuildingBlock -RegistryFile $script:fullRegistryFile
            $script:warnings = @()
            $script:result = Get-IvantiWCPolicy -Path $script:bbPath -ExportFor AppVentiX `
                -WarningVariable +script:warnings -WarningAction SilentlyContinue
            $script:params = $script:result.AppVentiXParams
        }

        It 'imports without warnings' {
            $script:warnings | Should -BeNullOrEmpty
        }

        It 'returns one policy set holding every configured policy' {
            @($script:result).Count | Should -Be 1
            @($script:params.PolicyName | Sort-Object) | Should -Be @(
                'AvxDelay', 'AvxExpandablePath', 'AvxFlags', 'AvxManagedList', 'AvxMultiLine',
                'AvxPathList', 'AvxSimpleSwitch', 'AvxToggle'
            )
        }

        It 'keeps the value of an expandable path element' {
            $element = ($script:params | Where-Object PolicyName -EQ 'AvxExpandablePath').Elements |
                Where-Object ElementId -EQ 'AvxPathValue'

            $element.Value | Should -Be '%USERPROFILE%\Docs'
            $element.ValueType | Should -Be 'REG_EXPAND_SZ'
        }

        It 'writes the expandable path as REG_EXPAND_SZ in the registry entries' {
            $entry = ($script:params | Where-Object PolicyName -EQ 'AvxExpandablePath').RegistryEntries |
                Where-Object ValueName -EQ 'defaultpath'

            $entry.ValueData | Should -Be '%USERPROFILE%\Docs'
            $entry.ValueType | Should -Be 'REG_EXPAND_SZ'
        }

        It 'unescapes the doubled backslashes in a quoted string value' {
            $element = ($script:params | Where-Object PolicyName -EQ 'AvxExpandablePath').Elements |
                Where-Object ElementId -EQ 'AvxPlainValue'

            $element.Value | Should -Be '%userprofile%\Documents\AutoRecover'
        }

        It 'unescapes the value written to the registry entries as well' {
            $entry = ($script:params | Where-Object PolicyName -EQ 'AvxExpandablePath').RegistryEntries |
                Where-Object ValueName -EQ 'plainpath'

            $entry.ValueData | Should -Be '%userprofile%\Documents\AutoRecover'
        }

        It 'unescapes an escaped quote in a string value' {
            $element = ($script:params | Where-Object PolicyName -EQ 'AvxExpandablePath').Elements |
                Where-Object ElementId -EQ 'AvxQuotedValue'

            $element.Value | Should -Be 'say "hi"'
        }

        It 'unescapes the items of a list element' {
            $items = ($script:params | Where-Object PolicyName -EQ 'AvxPathList').Elements |
                Where-Object ElementId -EQ 'AvxPathListItems'

            $items.Value | Should -Be ('C:\Folder One' + [System.Environment]::NewLine + 'C:\Folder Two')
        }

        It 'keeps a decimal element as its number instead of a checkbox' {
            $element = ($script:params | Where-Object PolicyName -EQ 'AvxDelay').Elements |
                Where-Object ElementId -EQ 'AvxDelaySeconds'

            $element.Value | Should -Not -BeOfType [bool]
            $element.Value | Should -Be 30
        }

        It 'keeps a boolean element as a checkbox' {
            $element = ($script:params | Where-Object PolicyName -EQ 'AvxToggle').Elements |
                Where-Object ElementId -EQ 'AvxToggleOn'

            $element.Value | Should -BeOfType [bool]
            $element.Value | Should -BeTrue
        }

        It 'joins a REG_MULTI_SZ element into a single value' {
            $element = ($script:params | Where-Object PolicyName -EQ 'AvxMultiLine').Elements |
                Where-Object ElementId -EQ 'AvxLines'

            $element.Value | Should -Be ('one' + [System.Environment]::NewLine + 'two')
        }

        It 'resolves a policy-level value without elements' {
            $policy = $script:params | Where-Object PolicyName -EQ 'AvxSimpleSwitch'

            $policy.Enabled | Should -BeTrue
            $policy.PolicyValueName | Should -Be 'simpleswitch'
        }
    }

    Context 'WEM export' {

        BeforeAll {
            $script:bbPath = New-TestBuildingBlock -RegistryFile $script:fullRegistryFile
            $script:wemWarnings = $null
            $script:wem = Get-IvantiWCPolicy -Path $script:bbPath -ExportFor WEM -WarningVariable script:wemWarnings -WarningAction SilentlyContinue
            $script:ops = @($script:wem.WEMParams.RegistryOperations)
        }

        It 'exports valueList values as registry operations' {
            $op = $script:ops | Where-Object value -EQ 'ExternalBackend'
            $op.action | Should -Be 'SetValue'
            $op.regData | Should -Be 'com.appventix.test.Backend'
            $op.regType | Should -Be 'REG_SZ'
            $op.scope | Should -Be 'User'
        }

        It 'exports an enabledList value as a registry operation' {
            $op = $script:ops | Where-Object value -EQ 'policyon'
            $op.regData | Should -Be 1
            $op.regType | Should -Be 'REG_DWORD'
        }

        It 'unescapes .reg string values' {
            ($script:ops | Where-Object value -EQ 'plainpath').regData | Should -Be '%userprofile%\Documents\AutoRecover'
            ($script:ops | Where-Object value -EQ 'quoted').regData | Should -Be 'say "hi"'
        }

        It 'exports an expandable text element as REG_EXPAND_SZ' {
            ($script:ops | Where-Object value -EQ 'defaultpath').regType | Should -Be 'REG_EXPAND_SZ'
        }

        It 'does not warn about unmatched values' {
            @($script:wemWarnings | Where-Object { "$_" -like '*does not match any policy*' }) | Should -BeNullOrEmpty
        }
    }

    Context 'Auxiliary registry values' {

        BeforeAll {
            $script:bbPath = New-TestBuildingBlock -RegistryFile $script:fullRegistryFile
            $script:params = (Get-IvantiWCPolicy -Path $script:bbPath -ExportFor AppVentiX `
                    -WarningAction SilentlyContinue).AppVentiXParams
            $script:flags = $script:params | Where-Object PolicyName -EQ 'AvxFlags'
            $script:managed = $script:params | Where-Object PolicyName -EQ 'AvxManagedList'
        }

        It 'writes enum valueList values to the registry entries' {
            $names = @($script:flags.RegistryEntries.ValueName | Sort-Object)

            $names | Should -Be @('Dummy', 'External', 'ExternalBackend', 'Final', 'Value')
        }

        It 'keeps the registry data and type of a valueList value' {
            $entry = $script:flags.RegistryEntries | Where-Object ValueName -EQ 'ExternalBackend'

            $entry.ValueData | Should -Be 'com.appventix.test.Backend'
            $entry.ValueType | Should -Be 'REG_SZ'
        }

        It 'does not create policy elements for valueList values' {
            @($script:flags.Elements.ElementId | Sort-Object -Unique) |
                Should -Be @('AvxFlagsMode', 'AvxFlagsValue')
        }

        It 'writes an enabledList value to the registry entries' {
            $entry = $script:managed.RegistryEntries | Where-Object ValueName -EQ 'policyon'

            $entry.ValueData | Should -Be 1
            $entry.ValueType | Should -Be 'REG_DWORD'
        }

        It 'does not create a policy element for an enabledList value' {
            @($script:managed.Elements.ElementId) | Should -Be @('AvxAddinName')
        }
    }

    Context 'Unmatched registry values' {

        BeforeAll {
            $registryFile = @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Policies\AppVentiXTest\Options]
"delayseconds"=dword:0000000a
"nosuchvalue"=dword:00000001
"@
            $script:bbPath = New-TestBuildingBlock -RegistryFile $registryFile
            $script:warnings = @()
            $script:result = Get-IvantiWCPolicy -Path $script:bbPath -ExportFor AppVentiX `
                -WarningVariable +script:warnings -WarningAction SilentlyContinue
        }

        It 'warns once for a value that matches no policy, element or auxiliary value' {
            $matched = @($script:warnings | Where-Object { $_ -match "Registry value 'nosuchvalue' does not match" })

            $matched.Count | Should -Be 1
        }

        It 'still exports the policies that did match' {
            $script:result.AppVentiXParams.PolicyName | Should -Contain 'AvxDelay'
        }
    }

    Context 'Template encoding' {

        It 'loads an embedded template whose declaration disagrees with its bytes' {
            $bbPath = New-TestBuildingBlock -RegistryFile $script:fullRegistryFile -DeclareWrongEncoding
            $result = Get-IvantiWCPolicy -Path $bbPath -ExportFor AppVentiX -WarningAction SilentlyContinue

            $result.AppVentiXParams.PolicyName | Should -Contain 'AvxExpandablePath'
        }
    }
}
