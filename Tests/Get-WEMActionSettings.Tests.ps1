BeforeAll {
    # Suppress module info messages during tests
    $Global:WemModuleShowInfo = $false
    # Import the module
    Import-Module "$PSScriptRoot\..\JBC.CitrixWEM\JBC.CitrixWEM.psd1" -Force

    # Load mock API response data from JSON file
    $script:MockApiResponse = Get-Content "$PSScriptRoot\TestData\Get-WEMActionSettings.Success.json" -Raw

    # Mock connection object (without ActiveSiteId to test explicit SiteId parameter)
    $script:MockConnection = [PSCustomObject]@{
        IsOnPrem     = $false
        BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
        CustomerId   = "test-customer-id"
        BearerToken  = "CWSAuth bearer=mock-token"
        WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        CloudProfile = "MockProfile"
        Expiry       = [datetime]::Now.AddMinutes(15)
        IsConnected  = $true
    }

    # Mock connection object with ActiveSiteId
    $script:MockConnectionWithActiveSite = [PSCustomObject]@{
        IsOnPrem       = $false
        BaseUrl        = "https://eu-api-webconsole.wem.cloud.com"
        CustomerId     = "test-customer-id"
        BearerToken    = "CWSAuth bearer=mock-token"
        WebSession     = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        CloudProfile   = "MockProfile"
        Expiry         = [datetime]::Now.AddMinutes(15)
        IsConnected    = $true
        ActiveSiteId   = 1
        ActiveSiteName = "Default Site"
    }
}

AfterAll {
    # Ensure connection is cleaned up after all tests
    InModuleScope JBC.CitrixWEM {
        $script:WemApiConnection = $null
    }
    # Clean up global variable
    Remove-Variable -Name WemModuleShowInfo -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-WEMActionSettings' {

    Context 'When connected to WEM API with explicit SiteId' {

        BeforeEach {
            # Set up connection in module scope (without ActiveSiteId)
            InModuleScope JBC.CitrixWEM -Parameters @{ Connection = $script:MockConnection } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            # Mock Invoke-WebRequest to return our mock API response
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = $script:MockApiResponse
                }
            }
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Should return action settings when SiteId 1 is provided' {
            $result = Get-WEMActionSettings -SiteId 1

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should return action settings with correct siteId property' {
            $result = Get-WEMActionSettings -SiteId 1

            $result.siteId | Should -Be 1
        }

        It 'Should return action settings with expected properties' {
            $result = Get-WEMActionSettings -SiteId 1

            $result.processApplications | Should -Be $false
            $result.processPrinters | Should -Be $false
            $result.processNetworkDrives | Should -Be $false
        }

        It 'Should call Invoke-WebRequest with correct URI containing siteId=1' {
            Get-WEMActionSettings -SiteId 1

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like "*siteId=1*"
            }
        }
    }

    Context 'When connected to WEM API with ActiveSiteId set' {

        BeforeEach {
            # Set up connection in module scope (with ActiveSiteId)
            InModuleScope JBC.CitrixWEM -Parameters @{ Connection = $script:MockConnectionWithActiveSite } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            # Mock Invoke-WebRequest to return our mock API response
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = $script:MockApiResponse
                }
            }
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Should use ActiveSiteId when no SiteId parameter is provided' {
            $result = Get-WEMActionSettings

            $result | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like "*siteId=1*"
            }
        }
    }

    Context 'When not connected to WEM API' {

        BeforeEach {
            # Ensure no connection in module scope
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Should write error when not connected' {
            Get-WEMActionSettings -SiteId 1 -ErrorVariable err -ErrorAction SilentlyContinue 2>&1 | Out-Null

            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'When no SiteId provided and no ActiveSiteId set' {

        BeforeEach {
            # Set up connection in module scope (without ActiveSiteId)
            InModuleScope JBC.CitrixWEM -Parameters @{ Connection = $script:MockConnection } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Should write error when no SiteId is provided and no ActiveSiteId is set' {
            Get-WEMActionSettings -ErrorVariable err -ErrorAction SilentlyContinue 2>&1 | Out-Null

            $err | Should -Not -BeNullOrEmpty
            $err[0].Exception.Message | Should -Match "No -SiteId was provided"
        }
    }

    Context 'When API returns an error' {

        BeforeEach {
            # Set up connection in module scope
            InModuleScope JBC.CitrixWEM -Parameters @{ Connection = $script:MockConnection } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                throw "API Error: Unauthorized"
            }
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Should handle API errors gracefully' {
            Get-WEMActionSettings -SiteId 1 -ErrorVariable err -ErrorAction SilentlyContinue 2>&1 | Out-Null

            $err | Should -Not -BeNullOrEmpty
            $err[0].Exception.Message | Should -Match "Unauthorized"
        }
    }
}
