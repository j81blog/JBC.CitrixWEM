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

Describe 'File Encoding and Line Endings' {

    BeforeDiscovery {
        $allFiles = Get-ChildItem -Path "$PSScriptRoot\..\JBC.CitrixWEM" -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File
        $EncodingTestCases = $allFiles | ForEach-Object {
            @{ FileName = $_.Name; FilePath = $_.FullName }
        }
    }

    It '<FileName> is UTF-8 with BOM' -TestCases $EncodingTestCases {
        param($FileName, $FilePath)
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $bytes.Length | Should -BeGreaterOrEqual 3
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
    }

    It '<FileName> uses CRLF line endings only' -TestCases $EncodingTestCases {
        param($FileName, $FilePath)
        $text = [System.IO.File]::ReadAllText($FilePath)
        ([regex]::Matches($text, '(?<!\r)\n')).Count | Should -Be 0 -Because 'bare LF line endings break the Authenticode signature after a git checkout'
        ([regex]::Matches($text, '\r(?!\n)')).Count | Should -Be 0 -Because 'bare CR line endings are not allowed'
    }

    It '<FileName> contains only ASCII characters' -TestCases $EncodingTestCases {
        param($FileName, $FilePath)
        $text = [System.IO.File]::ReadAllText($FilePath).TrimStart([char]0xFEFF)
        $nonAscii = [regex]::Matches($text, '[^\x00-\x7F]') | ForEach-Object { 'U+{0:X4}' -f [int][char]$_.Value } | Sort-Object -Unique
        $nonAscii | Should -BeNullOrEmpty -Because 'non-ASCII characters break on PS 5.1 without a BOM, use [char]0x.... instead'
    }
}

Describe 'Git Attributes' {

    It 'Marks PowerShell files as -text in .gitattributes' {
        $attributesPath = "$PSScriptRoot\..\.gitattributes"
        $attributesPath | Should -Exist
        $content = Get-Content -Path $attributesPath
        foreach ($extension in '*.ps1', '*.psm1', '*.psd1') {
            $content | Where-Object { $_ -match "^\s*$([regex]::Escape($extension))\s+.*-text" } | Should -Not -BeNullOrEmpty -Because "$extension must not be converted by core.autocrlf"
        }
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
