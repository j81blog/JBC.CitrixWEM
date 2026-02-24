BeforeAll {
    # Suppress module info messages during tests
    $Global:WemModuleShowInfo = $false
    Import-Module "$PSScriptRoot\..\JBC.CitrixWEM\JBC.CitrixWEM.psd1" -Force

    # Mock API region map
    $script:ApiRegionMap = @{
        "eu" = "api-eu.cloud.com"
        "us" = "api-us.cloud.com"
        "jp" = "api.citrixcloud.jp"
        "ap" = "api-ap.cloud.com"
    }

    # Mock successful Cloud API token response
    $script:MockCloudTokenResponse = @{
        access_token = "mock-access-token-12345"
        token_type   = "Bearer"
        expires_in   = 3600
    }

    # Mock successful On-Premises login response
    $script:MockOnPremLoginResponse = @{
        SessionId = "mock-session-id-abc-123"
    }
}

AfterAll {
    # Clean up global variable
    Remove-Variable -Name WemModuleShowInfo -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Connect-WEMApi - Cloud API Credentials' {

    Context 'Successful Cloud connection with API Credentials' {

        BeforeEach {
            # Mock Invoke-WebRequest for token endpoint
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                param($Uri, $Method, $Body)

                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($script:MockCloudTokenResponse | ConvertTo-Json -Depth 10)
                }
            }

            # Mock Set-WEMActiveDomain to avoid issues
            Mock -ModuleName JBC.CitrixWEM Set-WEMActiveDomain {}

            # Mock Write-InformationColored to suppress info messages
            Mock -ModuleName JBC.CitrixWEM Write-InformationColored {}

            # Mock Disconnect-WEMApi in case there's an existing connection
            Mock -ModuleName JBC.CitrixWEM Disconnect-WEMApi {}
        }

        AfterEach {
            # Clean up connection
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Connects successfully with ClientId and ClientSecret' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            { Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Calls token endpoint with correct parameters' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -like "*cctrustoauth2/root/tokens/clients*" -and
                $Method -eq 'POST' -and
                $Body.grant_type -eq 'client_credentials' -and
                $Body.client_id -eq 'test-client'
            }
        }

        It 'Sets correct BaseUrl for EU region' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ApiRegion "eu"

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.BaseUrl | Should -Be "https://eu-api-webconsole.wem.cloud.com"
            }
        }

        It 'Sets correct BaseUrl for US region' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ApiRegion "us"

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.BaseUrl | Should -Be "https://us-api-webconsole.wem.cloud.com"
            }
        }

        It 'Sets BearerToken with CWSAuth prefix' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.BearerToken | Should -Be "CWSAuth bearer=mock-access-token-12345"
            }
        }

        It 'Sets CustomerId correctly' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.CustomerId | Should -Be "test-customer"
            }
        }

        It 'Sets IsConnected to true' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.IsConnected | Should -Be $true
            }
        }

        It 'Sets IsOnPrem to false for Cloud connections' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.IsOnPrem | Should -Be $false
            }
        }

        It 'Calls Disconnect-WEMApi if there is an existing connection' {
            # Simulate existing connection
            InModuleScope JBC.CitrixWEM -Parameters @{ MockConnection = @{ IsConnected = $true } } {
                param($MockConnection)
                $script:WemApiConnection = $MockConnection
            }

            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret

            Should -Invoke -ModuleName JBC.CitrixWEM Disconnect-WEMApi -Times 1
        }

        It 'Returns connection details with PassThru switch' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            $result = Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.CustomerId | Should -Be "test-customer"
        }
    }

    Context 'Error handling for Cloud API Credentials' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Set-WEMActiveDomain {}
            Mock -ModuleName JBC.CitrixWEM Write-InformationColored {}
            Mock -ModuleName JBC.CitrixWEM Disconnect-WEMApi {}
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Throws error when token endpoint returns non-200 status' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 401
                    Content    = '{"error": "invalid_client"}'
                }
            }

            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            { Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Throw "*Failed to obtain Bearer Token*"
        }

        It 'Throws error when token response is invalid JSON' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = "Invalid JSON {{"
                }
            }

            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            { Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Throw "*Failed to parse*"
        }

        It 'Throws error when Invoke-WebRequest fails' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                throw "Network error"
            }

            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            { Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Throw "*Failed to connect to WEM API*"
        }
    }

    Context 'API Region validation' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($script:MockCloudTokenResponse | ConvertTo-Json -Depth 10)
                }
            }
            Mock -ModuleName JBC.CitrixWEM Set-WEMActiveDomain {}
            Mock -ModuleName JBC.CitrixWEM Write-InformationColored {}
            Mock -ModuleName JBC.CitrixWEM Disconnect-WEMApi {}
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Accepts EU region' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            { Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ApiRegion "eu" } | Should -Not -Throw
        }

        It 'Accepts US region' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            { Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ApiRegion "us" } | Should -Not -Throw
        }

        It 'Accepts JP region' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            { Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ApiRegion "jp" } | Should -Not -Throw
        }

        It 'Accepts AP region' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            { Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret -ApiRegion "ap" } | Should -Not -Throw
        }

        It 'Uses EU region by default' {
            $secureSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force

            Connect-WEMApi -CustomerId "test-customer" -ClientId "test-client" -ClientSecret $secureSecret

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.BaseUrl | Should -Be "https://eu-api-webconsole.wem.cloud.com"
            }
        }
    }
}

Describe 'Connect-WEMApi - On-Premises' {

    Context 'Successful On-Premises connection' {

        BeforeEach {
            # Mock Invoke-WebRequest for login endpoint
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                param($Uri, $Method, $Headers, $WebSession)

                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($script:MockOnPremLoginResponse | ConvertTo-Json -Depth 10)
                }
            }

            # Mock Set-WEMActiveDomain
            Mock -ModuleName JBC.CitrixWEM Set-WEMActiveDomain {}

            # Mock Write-InformationColored
            Mock -ModuleName JBC.CitrixWEM Write-InformationColored {}

            # Mock Disconnect-WEMApi
            Mock -ModuleName JBC.CitrixWEM Disconnect-WEMApi {}
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Connects successfully with DOMAIN\Username format' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            { Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Connects successfully with user@domain format' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("testuser@contoso.local", $securePassword)

            { Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Calls login endpoint with correct URI' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq "https://wem.contoso.local/services/wem/onPrem/LogIn" -and
                $Method -eq 'POST'
            }
        }

        It 'Sets Authorization header with basic auth' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential

            Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
                $Headers['Authorization'] -like "basic *"
            }
        }

        It 'Sets BearerToken with session prefix' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.BearerToken | Should -Be "session mock-session-id-abc-123"
            }
        }

        It 'Sets BaseUrl correctly' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.BaseUrl | Should -Be "https://wem.contoso.local"
            }
        }

        It 'Sets IsOnPrem to true' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.IsOnPrem | Should -Be $true
            }
        }

        It 'Sets IsConnected to true' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.IsConnected | Should -Be $true
            }
        }

        It 'Does not set CustomerId for On-Premises' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.CustomerId | Should -BeNullOrEmpty
            }
        }

        It 'Works with HTTP protocol' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "http://wem.contoso.local" -Credential $credential

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.BaseUrl | Should -Be "http://wem.contoso.local"
            }
        }

        It 'Creates WebSession for On-Premises connections' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential

            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.WebSession | Should -Not -BeNullOrEmpty
                $script:WemApiConnection.WebSession | Should -BeOfType [Microsoft.PowerShell.Commands.WebRequestSession]
            }
        }

        It 'Returns connection details with PassThru switch' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            $result = Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential -PassThru

            $result | Should -Not -BeNullOrEmpty
            $result.Server | Should -Be "wem.contoso.local"
        }
    }

    Context 'Error handling for On-Premises' {

        BeforeEach {
            Mock -ModuleName JBC.CitrixWEM Set-WEMActiveDomain {}
            Mock -ModuleName JBC.CitrixWEM Write-InformationColored {}
            Mock -ModuleName JBC.CitrixWEM Disconnect-WEMApi {}
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Throws error when login response does not contain SessionId' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = '{"success": true}'
                }
            }

            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            { Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Throw "*did not return a Session ID*"
        }

        It 'Throws error when username format is invalid' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                return [PSCustomObject]@{
                    StatusCode = 200
                    Content    = ($script:MockOnPremLoginResponse | ConvertTo-Json -Depth 10)
                }
            }

            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("invalidusername", $securePassword)

            { Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Throw "*DOMAIN\user*"
        }

        It 'Throws error when Invoke-WebRequest fails' {
            Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
                throw "Connection refused"
            }

            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            { Connect-WEMApi -WEMServer "https://wem.contoso.local" -Credential $credential -ErrorAction Stop -WarningAction SilentlyContinue} | Should -Throw "*Failed to connect to WEM API*"
        }

        It 'Validates WEMServer URI format' {
            $securePassword = ConvertTo-SecureString "password123" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential("CONTOSO\testuser", $securePassword)

            { Connect-WEMApi -WEMServer "invalid-uri" -Credential $credential -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Throw "*Invalid format*"
        }
    }
}
