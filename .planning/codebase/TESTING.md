# Testing Patterns

**Analysis Date:** 2026-01-28

## Test Framework

**Status:** Not detected

No automated testing framework (Pester) is currently configured in this codebase. No test files, test configuration, or CI/CD pipeline for testing exists.

**Recommended Framework:**
- Pester is the standard PowerShell testing framework
- Would be appropriate for this module given its API-focused design
- Could integrate with CI/CD pipeline via GitHub Actions

## Test File Organization

**Location:** Not applicable - no tests currently exist

**Future Structure (Recommended):**
```
JBC.CitrixWEM/
├── Tests/
│   ├── Unit/
│   │   ├── Public/
│   │   │   └── Connect-WEMApi.Tests.ps1
│   │   ├── Private/
│   │   │   └── Get-ExceptionDetails.Tests.ps1
│   │   └── Module.Tests.ps1
│   ├── Integration/
│   │   ├── Citrix.Cloud.Tests.ps1
│   │   └── OnPremises.Tests.ps1
│   └── Pester.Configuration.psd1
```

**Naming Pattern (Recommended):**
- `FunctionName.Tests.ps1` for unit tests
- `FunctionName.Integration.Tests.ps1` for integration tests
- Test file location mirrors source structure (Public/Private organization)

## Test Structure

**Current Status:**
No test patterns are established in the codebase.

**Recommended Pester Pattern:**

For a function like `Get-ExceptionDetails`:

```powershell
BeforeAll {
    # Import module
    Import-Module "$PSScriptRoot\..\..\JBC.CitrixWEM.psd1" -Force
}

Describe "Get-ExceptionDetails" {
    Context "When ErrorRecord contains simple exception" {
        It "Returns ordered hashtable with exception details" {
            try {
                Get-Item "NonExistentPath" -ErrorAction Stop
            } catch {
                $result = Get-ExceptionDetails -ErrorRecord $_
                $result | Should -Not -BeNullOrEmpty
                $result.ExceptionType | Should -Contain "ItemNotFoundException"
            }
        }
    }

    Context "When ErrorRecord contains nested InnerException" {
        It "Recursively extracts all inner exceptions" {
            # Create nested exception scenario
            $result = Get-ExceptionDetails -ErrorRecord $_
            $result.InnerExceptions | Should -Not -BeNullOrEmpty
        }
    }

    Context "When AsPlainText switch is specified" {
        It "Returns formatted string instead of PSCustomObject" {
            $result = Get-ExceptionDetails -ErrorRecord $_ -AsPlainText
            $result | Should -BeOfType [string]
        }
    }
}
```

## Setup and Teardown

**BeforeAll Block:**
- Import module with `-Force` flag
- Set up test credentials (mocked)
- Create temporary directories for file-based tests

**BeforeEach Block (Recommended):**
- Reset any module state
- Clear test API connection
- Reset module configuration

**AfterEach Block (Recommended):**
- Disconnect API session
- Clean up temporary files
- Reset module settings

**AfterAll Block (Recommended):**
- Remove module import
- Clean up credentials
- Remove temporary test files

## Mocking

**Mock Framework:** Pester's built-in `Mock` command (part of `-BeforeAll` or `-Describe` blocks)

**Pattern for API Functions:**

```powershell
Describe "Connect-WEMApi" {
    Context "Cloud authentication with API credentials" {
        BeforeEach {
            Mock Invoke-RestMethod {
                return @{
                    AccessToken = "mock-token-12345"
                    ExpiresIn   = 3600
                }
            }
        }

        It "Should authenticate successfully" {
            $result = Connect-WEMApi -CustomerId "test-id" -ClientId "test-client" `
                                      -ClientSecret (ConvertTo-SecureString "secret" -AsPlainText -Force)
            $result.Status | Should -Be "Success"
        }
    }
}
```

**What to Mock:**
- External API calls: `Invoke-RestMethod`, `Invoke-WebRequest`
- Citrix SDK calls: `Get-XDCredentials`, `Get-XDAuthentication`
- File system operations that depend on specific environment state
- Credential retrieval from external systems

**What NOT to Mock:**
- Core PowerShell functionality: `Get-Item`, `Write-Output`, `Join-Path`
- Internal module helper functions initially (test their integration)
- String/regex operations
- Object property access (PSObject.Properties)

## Fixtures and Test Data

**Current Status:**
No fixtures or test data factories exist.

**Recommended Approach:**

Create fixture files in `Tests/Fixtures/`:

```powershell
# Tests/Fixtures/TestData.ps1
function New-MockApiResponse {
    param([string]$Type)

    switch ($Type) {
        'Application' {
            @{
                IdSid         = 1
                Name          = 'Test App'
                Enabled       = $true
                PublisherName = 'Test Publisher'
            }
        }
        'Printer' {
            @{
                IdSid   = 2
                Name    = 'Test Printer'
                Enabled = $true
            }
        }
    }
}

function New-MockWEMConnection {
    @{
        ApiUrl      = 'https://test.cloud.citrix.com'
        BearerToken = 'mock-token'
        CustomerId  = 'test-customer-id'
        SessionId   = 'test-session-id'
        IsConnected = $true
    }
}
```

## Coverage

**Current Status:** No coverage requirements or tracking

**Target Coverage (Recommended):**
- Minimum 80% for public functions
- Minimum 70% for private helper functions
- 100% coverage for critical path code (authentication, API calls)

**View Coverage (Recommended):**
```bash
Invoke-Pester -Path Tests/ -CodeCoverage "JBC.CitrixWEM.psm1" -PassThru | Format-Table -Property Files, Lines, Hits, Misses, LinesMissed
```

## Test Types

**Unit Tests:**
- Test individual functions in isolation
- Mock external dependencies (API calls, file system)
- Scope: `Tests/Unit/`
- Examples:
  - `Get-ExceptionDetails.Tests.ps1` - error extraction and formatting
  - `Convert-BatchVarToPowerShell.Tests.ps1` - string conversion logic
  - `Expand-WEMResult.Tests.ps1` - response handling

**Integration Tests:**
- Test function interaction with actual or mocked API
- Test with real module state (after Connect-WEMApi)
- Scope: `Tests/Integration/`
- Examples:
  - Cloud authentication workflows
  - On-Premises authentication workflows
  - Multi-step operations (connect → get data → disconnect)

**E2E Tests:**
- Not currently recommended (requires live WEM environment)
- Could be added later for CI/CD against test WEM instance
- Would test full user workflows against real API

## Common Patterns

**Async/Pipeline Testing:**

```powershell
Context "Pipeline input support" {
    It "Accepts objects from pipeline" {
        $items = @(
            @{ Name = 'Item1' },
            @{ Name = 'Item2' }
        ) | Get-ItemCount

        $items | Measure-Object | Select-Object -ExpandProperty Count | Should -Be 2
    }
}
```

**Error Testing:**

```powershell
Context "Error conditions" {
    It "Throws when credential is null" {
        { Connect-WEMApi -WEMServer "http://test.local" -Credential $null } |
            Should -Throw
    }

    It "Throws with descriptive message for invalid server URI" {
        { Connect-WEMApi -WEMServer "invalid-uri" -Credential (Get-Credential) } |
            Should -Throw "*Please provide a valid address*"
    }

    It "Extracts all details from ErrorRecord" {
        try {
            Get-Item "NonExistent" -ErrorAction Stop
        } catch {
            $details = Get-ExceptionDetails -ErrorRecord $_
            $details.Message | Should -Not -BeNullOrEmpty
            $details.ExceptionType | Should -Not -BeNullOrEmpty
            $details.StackTrace | Should -Not -BeNullOrEmpty
        }
    }
}
```

**Validation Testing:**

```powershell
Context "Parameter validation" {
    It "Rejects CustomerId without proper format validation" {
        { Connect-WEMApi -CustomerId "" } | Should -Throw
    }

    It "Only accepts valid ApiRegion values" {
        { Connect-WEMApi -CustomerId "test" -ApiRegion "invalid" } |
            Should -Throw "*Should be one of*"
    }

    It "Validates WEMServer is a valid URI" {
        { Connect-WEMApi -WEMServer "not a uri" } |
            Should -Throw "*Invalid format*"
    }
}
```

## Run Commands (Recommended)

```bash
# Run all tests
Invoke-Pester -Path Tests/

# Watch mode (re-run on file changes)
# Note: Requires Pester 5.0+
$config = New-PesterConfiguration
$config.Run.Path = 'Tests/'
$config.Run.Watch = $true
Invoke-Pester -Configuration $config

# Code coverage
Invoke-Pester -Path Tests/ -CodeCoverage 'JBC.CitrixWEM/' -PassThru

# Run only unit tests
Invoke-Pester -Path Tests/Unit/

# Run specific test file
Invoke-Pester -Path Tests/Unit/Connect-WEMApi.Tests.ps1 -Verbose
```

## Notes on Testing This Module

**Challenges:**
1. **External Dependencies:** Module depends on Citrix Cloud and on-premises WEM APIs
2. **Credentials:** Tests require secure credential handling or mocking
3. **Environment State:** Connection state is maintained in `$script:WemApiConnection`
4. **Configuration:** Module configuration persists to disk in `%APPDATA%`

**Testing Strategy:**
1. **Unit tests** mock all API calls and file system operations
2. **Integration tests** use Pester mocks for API responses
3. **Setup/teardown** must clean module state between tests
4. **Fixtures** should provide realistic API response shapes
5. **Credentials** always mocked in automated tests

---

*Testing analysis: 2026-01-28*
