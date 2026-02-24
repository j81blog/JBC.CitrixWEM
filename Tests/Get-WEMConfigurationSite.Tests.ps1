BeforeAll {
    # Suppress module info messages during tests
    $Global:WemModuleShowInfo = $false
    # Import the module
    Import-Module "$PSScriptRoot\..\JBC.CitrixWEM\JBC.CitrixWEM.psd1" -Force

    # Load mock API response data from JSON file
    $script:MockApiResponse = Get-Content "$PSScriptRoot\TestData\Get-WEMConfigurationSite.Success.json" -Raw

    # Mock connection object
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
}

AfterAll {
    # Ensure connection is cleaned up after all tests
    InModuleScope JBC.CitrixWEM {
        $script:WemApiConnection = $null
    }
    # Clean up global variable
    Remove-Variable -Name WemModuleShowInfo -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-WEMConfigurationSite' {

    Context 'When connected to WEM API' {

        BeforeEach {
            # Set up connection in module scope
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

        It 'Should return all configuration sites' {
            $result = Get-WEMConfigurationSite

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 4
        }

        It 'Should return configuration site with correct properties' {
            $result = Get-WEMConfigurationSite

            $firstSite = $result | Select-Object -First 1
            $firstSite.id | Should -Be 1
            $firstSite.name | Should -Be "Default Site"
            $firstSite.description | Should -Be "Default VUEM Site"
        }

        It 'Should call Invoke-WebRequest with correct parameters' {
            Get-WEMConfigurationSite

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -Exactly
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
            $errorOutput = Get-WEMConfigurationSite -ErrorVariable err 2>&1

            $errorOutput | Should -Not -BeNullOrEmpty
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
            $errorOutput = Get-WEMConfigurationSite -ErrorVariable err 2>&1

            $err | Should -Not -BeNullOrEmpty
            $err[0].Exception.Message | Should -Match "Unauthorized"
        }
    }
}
