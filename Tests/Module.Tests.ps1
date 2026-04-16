BeforeAll {
    $Global:WemModuleShowInfo = $false
    $script:ManifestPath = "$PSScriptRoot\..\JBC.CitrixWEM\JBC.CitrixWEM.psd1"
    $script:PublicPath    = "$PSScriptRoot\..\JBC.CitrixWEM\Public"
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Variable -Name WemModuleShowInfo -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Module Manifest' {

    It 'Has a valid manifest file' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Has a ModuleVersion' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.Version | Should -Not -BeNullOrEmpty
    }

    It 'Has an Author' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.Author | Should -Not -BeNullOrEmpty
    }

    It 'Has a Description' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $manifest.Description | Should -Not -BeNullOrEmpty
    }

    It 'Has a valid GUID' {
        $manifest = Test-ModuleManifest -Path $script:ManifestPath
        $guid = [System.Guid]::Empty
        [System.Guid]::TryParse($manifest.Guid.ToString(), [ref]$guid) | Should -Be $true
    }
}

Describe 'Public Function Help' {

    BeforeDiscovery {
        $publicFiles = Get-ChildItem -Path "$PSScriptRoot\..\JBC.CitrixWEM\Public" -Filter '*.ps1' -File
        $FunctionTestCases = $publicFiles | ForEach-Object {
            $functionName = $_.BaseName
            @{ FunctionName = $functionName; FilePath = $_.FullName }
        }
    }

    It '<FunctionName> has a Synopsis' -TestCases $FunctionTestCases {
        param($FunctionName, $FilePath)
        $help = Get-Help -Name $FunctionName -ErrorAction SilentlyContinue
        $help.Synopsis | Should -Not -BeNullOrEmpty
    }

    It '<FunctionName> has a Notes section' -TestCases $FunctionTestCases {
        param($FunctionName, $FilePath)
        $help = Get-Help -Name $FunctionName -ErrorAction SilentlyContinue
        $notes = $help.alertSet.alert.Text
        $notes | Should -Not -BeNullOrEmpty
    }

    It '<FunctionName> has at least 1 Example' -TestCases $FunctionTestCases {
        param($FunctionName, $FilePath)
        $help = Get-Help -Name $FunctionName -ErrorAction SilentlyContinue
        $help.examples.example.Count | Should -BeGreaterOrEqual 1
    }
}

Describe 'PSScriptAnalyzer' {

    BeforeDiscovery {
        $allFiles = Get-ChildItem -Path "$PSScriptRoot\..\JBC.CitrixWEM" -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File
        $AnalyzerTestCases = $allFiles | ForEach-Object {
            @{ FileName = $_.Name; FilePath = $_.FullName }
        }
    }

    BeforeAll {
        if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
            Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck -Scope CurrentUser
        }
        Import-Module PSScriptAnalyzer -Force
    }

    It '<FileName> has no PSScriptAnalyzer errors' -TestCases $AnalyzerTestCases {
        param($FileName, $FilePath)
        $results = Invoke-ScriptAnalyzer -Path $FilePath -Severity Error
        $results | Should -BeNullOrEmpty
    }
}

Describe 'Authenticode Signatures' {

    BeforeDiscovery {
        $publicFiles = Get-ChildItem -Path "$PSScriptRoot\..\JBC.CitrixWEM\Public" -Filter '*.ps1' -File
        $SignatureTestCases = $publicFiles | ForEach-Object {
            @{ FileName = $_.Name; FilePath = $_.FullName }
        }
    }

    It '<FileName> has a Valid Authenticode signature' -TestCases $SignatureTestCases {
        param($FileName, $FilePath)
        $sig = Get-AuthenticodeSignature -FilePath $FilePath
        $sig.Status | Should -Be 'Valid'
    }
}
