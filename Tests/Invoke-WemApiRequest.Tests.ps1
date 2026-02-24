BeforeAll {
    # Suppress module info messages during tests
    $Global:WemModuleShowInfo = $false
    Import-Module "$PSScriptRoot\..\JBC.CitrixWEM\JBC.CitrixWEM.psd1" -Force

    # Mock connection objects
    $script:MockCloudConnection = [PSCustomObject]@{
        IsOnPrem     = $false
        BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
        CustomerId   = "test-customer-id"
        BearerToken  = "CWSAuth bearer=mock-token-12345"
        WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        CloudProfile = "MockProfile"
        Expiry       = [datetime]::Now.AddMinutes(15)
        IsConnected  = $true
    }

    $script:MockOnPremConnection = [PSCustomObject]@{
        IsOnPrem    = $true
        BaseUrl     = "http://wem.corp.local"
        CustomerId  = $null
        BearerToken = "session abc-123-def-456"
        WebSession  = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        Expiry      = [datetime]::Now.AddMinutes(15)
        IsConnected = $true
    }

    $script:MockApiResponse = @{
        items = @(
            @{ id = 1; name = "Test Item 1" }
            @{ id = 2; name = "Test Item 2" }
        )
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

Describe 'Invoke-WemApiRequest - Unit Tests' {

    Context 'Automatic mode - Cloud connection' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                param($Uri, $Method, $Headers)

                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($script:MockApiResponse | ConvertTo-Json -Depth 10)
                }
            }
        }

        It 'Builds correct URI with BaseUrl and UriPath' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq "https://eu-api-webconsole.wem.cloud.com/ConfigurationSets"
            }
        }

        It 'Removes leading slash from UriPath correctly' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "/ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq "https://eu-api-webconsole.wem.cloud.com/ConfigurationSets"
            }
        }

        It 'Adds Authorization header with BearerToken' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Headers['Authorization'] -eq "CWSAuth bearer=mock-token-12345"
            }
        }

        It 'Adds Citrix-CustomerId header for Cloud connections' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Headers['Citrix-CustomerId'] -eq "test-customer-id"
            }
        }

        It 'Adds Citrix-TransactionId header for Cloud connections' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Headers.ContainsKey('Citrix-TransactionId') -and $Headers['Citrix-TransactionId'] -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            }
        }

        It 'Uses correct HTTP Method - GET' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Method -eq 'GET'
            }
        }

        It 'Uses correct HTTP Method - POST' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method POST -Body @{ name = "Test" }

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'Adds Body as JSON for POST requests' {
            $testBody = @{ name = "Test Site"; description = "Test Description" }
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method POST -Body $testBody

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Body -and ($Body | ConvertFrom-Json).name -eq "Test Site"
            }
        }

        It 'Parses JSON response correctly' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET

            $result | Should -Not -BeNullOrEmpty
            $result.items | Should -HaveCount 2
            $result.items[0].id | Should -Be 1
        }

        It 'Uses correct Content-Type header' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $ContentType -eq "application/json; charset=UTF-8"
            }
        }

        It 'Uses UseBasicParsing parameter' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $UseBasicParsing -eq $true
            }
        }
    }

    Context 'Automatic mode - On-Premises connection' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($script:MockApiResponse | ConvertTo-Json -Depth 10)
                }
            }
        }

        It 'Uses On-Premises BaseUrl' {
            $result = Invoke-WemApiRequest -Connection $script:MockOnPremConnection -UriPath "services/wem/onPrem/ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq "http://wem.corp.local/services/wem/onPrem/ConfigurationSets"
            }
        }

        It 'Uses session BearerToken for On-Premises' {
            $result = Invoke-WemApiRequest -Connection $script:MockOnPremConnection -UriPath "services/wem/onPrem/ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Headers['Authorization'] -eq "session abc-123-def-456"
            }
        }

        It 'Does NOT add Citrix-CustomerId header for On-Premises' {
            $result = Invoke-WemApiRequest -Connection $script:MockOnPremConnection -UriPath "services/wem/onPrem/ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                -not $Headers.ContainsKey('Citrix-CustomerId')
            }
        }

        It 'Adds WebSession for On-Premises connections' {
            $result = Invoke-WemApiRequest -Connection $script:MockOnPremConnection -UriPath "services/wem/onPrem/ConfigurationSets" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $null -ne $WebSession
            }
        }
    }

    Context 'Manual mode voor testing' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($script:MockApiResponse | ConvertTo-Json -Depth 10)
                }
            }
        }

        It 'Works with Manual parameter set' {
            $result = Invoke-WemApiRequest -Manual -BaseUrl "https://test.api.com" -BearerToken "test-token" -CustomerId "test-id" -UriPath "test" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1
        }

        It 'Uses manually specified BaseUrl' {
            $result = Invoke-WemApiRequest -Manual -BaseUrl "https://manual.test.com" -BearerToken "manual-token" -UriPath "endpoint" -Method GET

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq "https://manual.test.com/endpoint"
            }
        }

        It 'Detects IsOnPrem correctly based on BearerToken (session)' {
            $result = Invoke-WemApiRequest -Manual -BaseUrl "http://onprem.local" -BearerToken "session xyz-123" -UriPath "test" -Method GET

            # On-Prem detected, no CustomerId header
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                -not $Headers.ContainsKey('Citrix-CustomerId')
            }
        }

        It 'Detects IsOnPrem correctly based on BearerToken (basic)' {
            $result = Invoke-WemApiRequest -Manual -BaseUrl "http://onprem.local" -BearerToken "basic ABC123==" -UriPath "test" -Method GET

            # On-Prem detected, no CustomerId header
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                -not $Headers.ContainsKey('Citrix-CustomerId')
            }
        }

        It 'Detects Cloud connection based on BearerToken (CWSAuth)' {
            $result = Invoke-WemApiRequest -Manual -BaseUrl "https://cloud.api.com" -BearerToken "CWSAuth bearer=xyz" -CustomerId "cloud-id" -UriPath "test" -Method GET

            # Cloud detected, CustomerId header present
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Headers['Citrix-CustomerId'] -eq "cloud-id"
            }
        }
    }

    Context 'Error handling' {

        It 'Throws error on 401 Unauthorized' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                throw "401 Unauthorized"
            }

            { Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET } | Should -Throw "*401*"
        }

        It 'Throws error on 404 Not Found' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                throw "404 Not Found"
            }

            { Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "InvalidEndpoint" -Method GET } | Should -Throw "*404*"
        }

        It 'Throws error on 500 Internal Server Error' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                throw "500 Internal Server Error"
            }

            { Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET } | Should -Throw "*500*"
        }

        It 'Includes URI in error message' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                throw "Generic error"
            }

            { Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "ConfigurationSets" -Method GET } | Should -Throw "*ConfigurationSets*"
        }
    }

    Context 'HTTP Methods' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = '{"success": true}'
                }
            }
        }

        It 'Supports GET method' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "test" -Method GET
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'GET' }
        }

        It 'Supports POST method' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "test" -Method POST
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'Supports PUT method' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "test" -Method PUT
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'Supports DELETE method' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "test" -Method DELETE
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'DELETE' }
        }

        It 'Supports PATCH method' {
            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "test" -Method PATCH
            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    Context 'Response handling' {

        It 'Returns null for empty response Content' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 204
                    Content    = $null
                }
            }

            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "test" -Method DELETE
            $result | Should -BeNullOrEmpty
        }

        It 'Parses JSON response with nested objects' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                $complexResponse = @{
                    data = @{
                        items = @(
                            @{ id = 1; metadata = @{ created = "2024-01-01" } }
                        )
                    }
                }
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($complexResponse | ConvertTo-Json -Depth 10)
                }
            }

            $result = Invoke-WemApiRequest -Connection $script:MockCloudConnection -UriPath "test" -Method GET
            $result.data.items[0].metadata.created | Should -Be "2024-01-01"
        }
    }
}
