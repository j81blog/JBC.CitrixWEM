BeforeAll {
    # Suppress module info messages during tests
    $Global:WemModuleShowInfo = $false
    Import-Module "$PSScriptRoot\..\JBC.CitrixWEM\JBC.CitrixWEM.psd1" -Force
}

AfterAll {
    # Clean up global variable
    Remove-Variable -Name WemModuleShowInfo -Scope Global -ErrorAction SilentlyContinue
    # Ensure connection is cleaned up after all tests
    InModuleScope JBC.CitrixWEM {
        $script:WemApiConnection = $null
    }
}

Describe 'Get-WemApiConnection - Unit Tests' {

    Context 'Valid connection object' {

        BeforeEach {
            # Create a valid connection using InModuleScope
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    IsOnPrem     = $false
                    BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
                    CustomerId   = "test-customer-id"
                    BearerToken  = "CWSAuth bearer=mock-token"
                    WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    CloudProfile = "MockProfile"
                    Expiry       = [datetime]::Now.AddMinutes(15)
                    IsConnected  = $true
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }
        }

        AfterEach {
            # Cleanup
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Returns the script scope connection object' {
            $result = Get-WemApiConnection

            $result | Should -Not -BeNullOrEmpty
            $result.BaseUrl | Should -Be "https://eu-api-webconsole.wem.cloud.com"
            $result.CustomerId | Should -Be "test-customer-id"
            $result.IsConnected | Should -Be $true
        }

        It 'Returns connection with BearerToken' {
            $result = Get-WemApiConnection

            $result.BearerToken | Should -Be "CWSAuth bearer=mock-token"
        }

        It 'Returns connection with WebSession' {
            $result = Get-WemApiConnection

            $result.WebSession | Should -Not -BeNullOrEmpty
            $result.WebSession | Should -BeOfType [Microsoft.PowerShell.Commands.WebRequestSession]
        }

        It 'Returns connection with CloudProfile for Cloud connections' {
            $result = Get-WemApiConnection

            $result.CloudProfile | Should -Be "MockProfile"
        }

        It 'Returns connection with Expiry datetime' {
            $result = Get-WemApiConnection

            $result.Expiry | Should -BeOfType [datetime]
            $result.Expiry | Should -BeGreaterThan ([datetime]::Now)
        }

        It 'Returns same object as $script:WemApiConnection' {
            $result = Get-WemApiConnection

            # Compare properties directly - result should match what we set
            $result.BaseUrl | Should -Be "https://eu-api-webconsole.wem.cloud.com"
            $result.BearerToken | Should -Be "CWSAuth bearer=mock-token"
            $result.CustomerId | Should -Be "test-customer-id"
        }
    }

    Context 'On-Premises connection' {

        BeforeEach {
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    IsOnPrem    = $true
                    BaseUrl     = "http://wem.corp.local"
                    CustomerId  = $null
                    BearerToken = "session abc-123-def"
                    WebSession  = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    Expiry      = [datetime]::Now.AddMinutes(30)
                    IsConnected = $true
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Returns On-Premises connection correctly' {
            $result = Get-WemApiConnection

            $result.IsOnPrem | Should -Be $true
            $result.BaseUrl | Should -Be "http://wem.corp.local"
            $result.BearerToken | Should -Match "^session"
        }

        It 'Has no CustomerId for On-Premises' {
            $result = Get-WemApiConnection

            $result.CustomerId | Should -BeNullOrEmpty
        }

        It 'Has no CloudProfile for On-Premises' {
            $result = Get-WemApiConnection

            $result.PSObject.Properties.Name | Should -Not -Contain 'CloudProfile'
        }
    }

    Context 'Invalid connection scenarios' {

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Throws error when $script:WemApiConnection is null' {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }

            { Get-WemApiConnection } | Should -Throw "*Not connected*Connect-WemApi*"
        }

        It 'Throws error when BearerToken is null' {
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    IsOnPrem     = $false
                    BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
                    CustomerId   = "test-customer-id"
                    BearerToken  = $null
                    WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    IsConnected  = $true
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            { Get-WemApiConnection } | Should -Throw "*Not connected*Connect-WemApi*"
        }

        It 'Throws error when BearerToken is empty string' {
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    IsOnPrem     = $false
                    BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
                    CustomerId   = "test-customer-id"
                    BearerToken  = ""
                    WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    IsConnected  = $true
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            { Get-WemApiConnection } | Should -Throw "*Not connected*Connect-WemApi*"
        }

        It 'Accepts BearerToken with whitespace (function only checks IsNullOrEmpty)' {
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    IsOnPrem     = $false
                    BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
                    CustomerId   = "test-customer-id"
                    BearerToken  = "   "  # Whitespace is not empty, so it's technically valid
                    WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    IsConnected  = $true
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            # Function uses IsNullOrEmpty, not IsNullOrWhiteSpace, so this passes
            $result = Get-WemApiConnection
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Error message contains Connect-WemApi instruction' {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }

            try {
                Get-WemApiConnection
                throw "Should have thrown an error"
            } catch {
                $_.Exception.Message | Should -Match "Connect-WemApi"
            }
        }
    }

    Context 'Connection property validation' {

        BeforeEach {
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    IsOnPrem     = $false
                    BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
                    CustomerId   = "test-customer-id"
                    BearerToken  = "CWSAuth bearer=mock-token"
                    WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    CloudProfile = "MockProfile"
                    Expiry       = [datetime]::Now.AddMinutes(15)
                    IsConnected  = $true
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }
        }

        AfterEach {
            $script:WemApiConnection = $null
        }

        It 'Returns all expected properties' {
            $result = Get-WemApiConnection

            $result.PSObject.Properties.Name | Should -Contain 'IsOnPrem'
            $result.PSObject.Properties.Name | Should -Contain 'BaseUrl'
            $result.PSObject.Properties.Name | Should -Contain 'CustomerId'
            $result.PSObject.Properties.Name | Should -Contain 'BearerToken'
            $result.PSObject.Properties.Name | Should -Contain 'WebSession'
            $result.PSObject.Properties.Name | Should -Contain 'Expiry'
            $result.PSObject.Properties.Name | Should -Contain 'IsConnected'
        }

        It 'BaseUrl is a string' {
            $result = Get-WemApiConnection

            $result.BaseUrl | Should -BeOfType [string]
        }

        It 'CustomerId is a string' {
            $result = Get-WemApiConnection

            $result.CustomerId | Should -BeOfType [string]
        }

        It 'BearerToken is a string' {
            $result = Get-WemApiConnection

            $result.BearerToken | Should -BeOfType [string]
        }

        It 'IsOnPrem is a boolean' {
            $result = Get-WemApiConnection

            $result.IsOnPrem | Should -BeOfType [bool]
        }

        It 'IsConnected is a boolean' {
            $result = Get-WemApiConnection

            $result.IsConnected | Should -BeOfType [bool]
        }

        It 'Expiry is a datetime' {
            $result = Get-WemApiConnection

            $result.Expiry | Should -BeOfType [datetime]
        }
    }

    Context 'Multiple calls to Get-WemApiConnection' {

        BeforeEach {
            $script:WemApiConnection = [PSCustomObject]@{
                IsOnPrem     = $false
                BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
                CustomerId   = "test-customer-id"
                BearerToken  = "CWSAuth bearer=test-token"
                WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                Expiry       = [datetime]::Now.AddMinutes(15)
                IsConnected  = $true
            }
        }

        AfterEach {
            $script:WemApiConnection = $null
        }

        It 'Returns consistently same connection with multiple calls' {
            $result1 = Get-WemApiConnection
            $result2 = Get-WemApiConnection

            $result1.BaseUrl | Should -Be $result2.BaseUrl
            $result1.BearerToken | Should -Be $result2.BearerToken
            $result1.CustomerId | Should -Be $result2.CustomerId
        }

        It 'Returns reference to same script variable' {
            $result1 = Get-WemApiConnection

            # Change something directly in the module scope
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection.IsConnected = $false
            }

            # Both result1 and a new call should show the changed value
            $result1.IsConnected | Should -Be $false

            $result2 = Get-WemApiConnection
            $result2.IsConnected | Should -Be $false
        }
    }

    Context 'Verbose output' {

        BeforeEach {
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    IsOnPrem     = $false
                    BaseUrl      = "https://eu-api-webconsole.wem.cloud.com"
                    CustomerId   = "test-customer-id"
                    BearerToken  = "CWSAuth bearer=test-token-secret"
                    WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    Expiry       = [datetime]::Now.AddMinutes(15)
                    IsConnected  = $true
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }
        }

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Writes verbose output with connection details' {
            $verboseOutput = Get-WemApiConnection -Verbose 4>&1

            $verboseOutput | Should -Not -BeNullOrEmpty
            $verboseOutput -join ' ' | Should -Match "BaseUrl|CustomerId"
        }

        It 'Masks BearerToken in verbose output' {
            # Capture verbose and result separately
            $result = Get-WemApiConnection -Verbose 4>&1 -OutVariable verboseOut
            $verboseOutput = ($verboseOut | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }) -join ' '

            # The verbose message should contain masked token
            $verboseOutput | Should -Match "\\*\\*\\*\\*\\*\\*\\*\\*"
            # And should not contain the actual secret
            $verboseOutput | Should -Not -Match "test-token-secret"
        }
    }

    Context 'Edge cases' {

        AfterEach {
            InModuleScope JBC.CitrixWEM {
                $script:WemApiConnection = $null
            }
        }

        It 'Works with minimal required properties' {
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    BearerToken = "minimal-token"
                    BaseUrl     = "https://minimal.api.com"
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            $result = Get-WemApiConnection

            $result | Should -Not -BeNullOrEmpty
            $result.BearerToken | Should -Be "minimal-token"
        }

        It 'Works with extra custom properties' {
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    BearerToken     = "test-token"
                    BaseUrl         = "https://test.api.com"
                    CustomProperty1 = "Value1"
                    CustomProperty2 = 12345
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            $result = Get-WemApiConnection

            $result | Should -Not -BeNullOrEmpty
            $result.CustomProperty1 | Should -Be "Value1"
            $result.CustomProperty2 | Should -Be 12345
        }

        It 'Works with expired Expiry date (function does not check this)' {
            $expiredTime = [datetime]::Now.AddMinutes(-10)
            InModuleScope JBC.CitrixWEM -Parameters @{
                Connection = [PSCustomObject]@{
                    BearerToken = "test-token"
                    BaseUrl     = "https://test.api.com"
                    Expiry      = $expiredTime
                    IsConnected = $true
                }
            } {
                param($Connection)
                $script:WemApiConnection = $Connection
            }

            # Get-WemApiConnection only checks BearerToken, not Expiry
            $result = Get-WemApiConnection

            $result | Should -Not -BeNullOrEmpty
            $result.Expiry | Should -BeLessThan ([datetime]::Now)
        }
    }
}
