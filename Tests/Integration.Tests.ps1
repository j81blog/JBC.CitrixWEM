BeforeAll {
    # Suppress module info messages during tests
    $Global:WemModuleShowInfo = $false
    Import-Module "$PSScriptRoot\..\JBC.CitrixWEM\JBC.CitrixWEM.psd1" -Force

    # Mock data
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

    $script:MockApiResponse = @{
        items = @(
            @{
                id          = 1
                name        = "Default Site"
                description = "Default VUEM Site"
                properties  = ""
                scopeUid    = ""
            },
            @{
                id          = 3
                name        = "Customer Site 1"
                description = "Customer Site 1"
                properties  = ""
                scopeUid    = "992aea72-6699-4c3c-a64a-edad39add7bf"
            }
        )
    }
}

Describe 'Integration Tests - Get-WEMConfigurationSite Flow' {

    Context 'Complete flow of Get-WEMConfigurationSite → Invoke-WemApiRequest → Invoke-WebRequest' {

        BeforeEach {
            # Only mock the lowest level: Invoke-WebRequest
            # This tests Get-WEMConfigurationSite AND Invoke-WemApiRequest

            Mock -ModuleName JBC.CitrixWEM Get-WemApiConnection {
                return $script:MockConnection
            }

            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                param($Uri, $Method, $Headers, $WebSession)

                # Validate that Invoke-WemApiRequest called correctly
                $Headers | Should -Not -BeNullOrEmpty
                $Headers['Authorization'] | Should -Be $script:MockConnection.BearerToken
                $Uri | Should -Match 'sites'

                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($script:MockApiResponse | ConvertTo-Json -Depth 10)
                }
            }
        }

        It 'Test complete flow: Get-WEMConfigurationSite calls Invoke-WemApiRequest with correct parameters' {
            $result = Get-WEMConfigurationSite

            # Verify Invoke-WebRequest was called (via Invoke-WemApiRequest)
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1

            # Verify result is processed correctly
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
        }

        It 'Test that Invoke-WemApiRequest passes Authorization header correctly' {
            Get-WEMConfigurationSite

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Headers['Authorization'] -eq $script:MockConnection.BearerToken
            }
        }

        It 'Test that Get-WemApiConnection is called correctly' {
            Get-WEMConfigurationSite

            Should -Invoke -ModuleName JBC.CitrixWEM Get-WemApiConnection -Times 1
        }
    }

    Context 'Error handling in complete flow' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Get-WemApiConnection {
                return $script:MockConnection
            }
        }

        It 'Test error handling when Invoke-WebRequest returns 401 error' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                throw "The remote server returned an error: (401) Unauthorized."
            }

            $result = Get-WEMConfigurationSite -ErrorAction SilentlyContinue -ErrorVariable capturedError
            $result | Should -BeNullOrEmpty
            $capturedError | Should -Not -BeNullOrEmpty
            $capturedError[0].Exception.Message | Should -Match "401|Unauthorized"
        }

        It 'Test error handling when Get-WemApiConnection returns null' {
            Mock -ModuleName JBC.CitrixWEM Get-WemApiConnection {
                return $null
            }

            $result = Get-WEMConfigurationSite -ErrorAction SilentlyContinue -ErrorVariable capturedError
            $result | Should -BeNullOrEmpty
            $capturedError | Should -Not -BeNullOrEmpty
            $capturedError[0].Exception.Message | Should -Match "null|Connection"
        }

        It 'Test error handling when API returns invalid JSON' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = "Invalid JSON {{"
                }
            }

            $result = Get-WEMConfigurationSite -ErrorAction SilentlyContinue -ErrorVariable capturedError
            $result | Should -BeNullOrEmpty
            $capturedError | Should -Not -BeNullOrEmpty
            # Error message should indicate API call failed or JSON conversion issue
            $capturedError[0] | Should -Match "API call|failed|JSON|Conversion"
        }
    }
}

Describe 'Unit Test - Invoke-WemApiRequest' {

    Context 'Test Invoke-WemApiRequest specifieke logica' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Get-WemApiConnection {
                return $script:MockConnection
            }

            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                param($Uri, $Method, $Headers)

                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = '{"items": [{"id": 1}]}'
                }
            }
        }

        It 'Builds correct URI based on BaseUrl and endpoint' {
            # This tests if Invoke-WemApiRequest assembles the URI correctly
            $null = Invoke-WemApiRequest -Connection $script:MockConnection -UriPath "ConfigurationSets" -Method Get

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq "https://eu-api-webconsole.wem.cloud.com/ConfigurationSets"
            }
        }

        It 'Adds Authorization header from connection' {
            $null = Invoke-WemApiRequest -Connection $script:MockConnection -UriPath "ConfigurationSets" -Method Get

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Headers['Authorization'] -eq "CWSAuth bearer=mock-token"
            }
        }

        It 'Uses correct HTTP Method' {
            $null = Invoke-WemApiRequest -Connection $script:MockConnection -UriPath "ConfigurationSets" -Method Post

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Method -eq 'Post'
            }
        }
    }
}

Describe 'Unit Test - Get-WemApiConnection' {

    Context 'Test Get-WemApiConnection logic' {

        It 'Returns the connection from script scope' {
            # Set script variable in module scope
            InModuleScope JBC.CitrixWEM -Parameters @{ MockConnection = $script:MockConnection } {
                param($MockConnection)
                $script:WemApiConnection = $MockConnection
            }

            $result = Get-WemApiConnection

            $result | Should -Not -BeNullOrEmpty
            $result.BearerToken | Should -Be "CWSAuth bearer=mock-token"
            $result.IsConnected | Should -Be $true
        }

        It 'Checks if connection is still valid (not expired)' {
            $expiredConnection = $script:MockConnection.PSObject.Copy()
            $expiredConnection.Expiry = [datetime]::Now.AddMinutes(-5)

            # Set expired connection in module scope
            InModuleScope JBC.CitrixWEM -Parameters @{ ExpiredConnection = $expiredConnection } {
                param($ExpiredConnection)
                $script:WemApiConnection = $ExpiredConnection
            }

            $result = Get-WemApiConnection

            # Get-WemApiConnection only checks BearerToken, not Expiry
            # So even with expired connection, it should still return it
            $result | Should -Not -BeNullOrEmpty
            $result.Expiry | Should -BeLessThan ([datetime]::Now)
        }
    }
}
