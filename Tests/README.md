# Test Strategy for JBC.CitrixWEM Module

## Test Levels

### 1. Unit Tests (per function)
Each function is tested separately with mocked dependencies.

### 2. Integration Tests
Test multiple functions together with only external API mocked.

### 3. E2E Tests (optional)
Complete flow with real API (only for dev/test environment).

## Test Coverage Overview

| Function | Unit Test | Integration Test | Mocked Dependencies |
|---------|-----------|------------------|---------------------|
| Get-WEMConfigurationSite | ✅ | ✅ | Invoke-WebRequest |
| Invoke-WemApiRequest | ✅ | ✅ | Invoke-WebRequest |
| Get-WemApiConnection | ✅ | ✅ | $script:WemApiConnection |
| Connect-WEMApi | ✅ | - | Invoke-WebRequest, Set-WEMActiveDomain |

## Test Files

### Unit Tests
- **Get-WemApiConnection.Tests.ps1** - Tests only Get-WemApiConnection function
  - Valid connection scenarios
  - Invalid connection scenarios (null, empty, whitespace)
  - Connection properties validation
  - Verbose output masking
  - Edge cases

- **Invoke-WemApiRequest.Tests.ps1** - Tests only Invoke-WemApiRequest function
  - Automatic mode (Cloud & On-Premises)
  - Manual mode for testing
  - URI building
  - Header construction (Authorization, CustomerId, TransactionId)
  - HTTP Methods (GET, POST, PUT, DELETE, PATCH)
  - Body serialization
  - Error handling (401, 404, 500)
  - Response parsing

- **Get-WEMConfigurationSite.Tests.ps1** - Tests only Get-WEMConfigurationSite function
  - Connected scenarios
  - Not connected scenarios
  - API error scenarios
  - Parameter filtering (Id, Name)

- **Connect-WEMApi.Tests.ps1** - Tests authentication to WEM API
  - Cloud API Credentials authentication
    - Successful connection with ClientId/ClientSecret
    - Bearer token format validation
    - API region handling (EU, US, JP, AP)
    - Connection properties validation
    - Error handling (token endpoint failures, invalid responses)
  - On-Premises authentication
    - Successful connection with DOMAIN\Username format
    - Successful connection with user@domain format
    - Basic authentication header construction
    - Session token handling
    - WebSession creation
    - Error handling (missing SessionId, invalid username format)
  - Connection state management
    - Sets $script:WemApiConnection correctly
    - Disconnects existing connection before new connection
    - PassThru parameter functionality

### Integration Tests
- **Integration.Tests.ps1** - Tests complete flow
  - Get-WEMConfigurationSite → Invoke-WemApiRequest → Invoke-WebRequest
  - Parameter passing between functions
  - Authorization header propagation
  - WebSession management
  - Error propagation through the stack

## Test Data

Mock API responses are stored in the `TestData` folder as JSON files. This keeps tests clean and enables reuse across multiple test files.

### Folder Structure
```
Tests/
├── TestData/
│   └── Get-WEMConfigurationSite.Success.json
├── Get-WEMConfigurationSite.Tests.ps1
├── ...
```

### Naming Convention
Files follow the pattern: `<FunctionName>.<Scenario>.json`

Examples:
- `Get-WEMConfigurationSite.Success.json` - Successful API response
- `Get-WEMConfigurationSite.Empty.json` - Empty response
- `Get-WEMConfigurationSite.SingleItem.json` - Response with single item

### Usage in Tests
```powershell
BeforeAll {
    $script:MockApiResponse = Get-Content "$PSScriptRoot\TestData\Get-WEMConfigurationSite.Success.json" -Raw
}

Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest {
    return [PSCustomObject]@{
        StatusCode = 200
        Content    = $script:MockApiResponse
    }
}
```

## Running Tests

### All tests
```powershell
Invoke-Pester -Path .\Tests\
```

### Specific test file
```powershell
Invoke-Pester -Path .\Tests\Get-WemApiConnection.Tests.ps1
Invoke-Pester -Path .\Tests\Invoke-WemApiRequest.Tests.ps1
Invoke-Pester -Path .\Tests\Get-WEMConfigurationSite.Tests.ps1
Invoke-Pester -Path .\Tests\Connect-WEMApi.Tests.ps1
Invoke-Pester -Path .\Tests\Integration.Tests.ps1
```

### With Code Coverage
```powershell
$config = New-PesterConfiguration
$config.Run.Path = ".\Tests\"
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = ".\JBC.CitrixWEM\Public\*.ps1", ".\JBC.CitrixWEM\Private\*.ps1"
$config.CodeCoverage.OutputPath = ".\coverage.xml"
$config.CodeCoverage.OutputFormat = "JaCoCo"

Invoke-Pester -Configuration $config
```

### Specific contexts
```powershell
# Only error handling tests
Invoke-Pester -Path .\Tests\ -Tag "ErrorHandling"

# Only Cloud connection tests
Invoke-Pester -Path .\Tests\ -Tag "Cloud"
```

## What is tested?

### Unit Test Approach (e.g. Invoke-WemApiRequest.Tests.ps1)
```
Get-WEMConfigurationSite ❌ NOT TESTED (not in scope)
    ↓
Invoke-WemApiRequest ✅ TESTED (all logic)
    ↓
Get-WemApiConnection ❌ MOCKED
    ↓
Invoke-WebRequest ❌ MOCKED
```

### Integration Test Approach (Integration.Tests.ps1)
```
Get-WEMConfigurationSite ✅ TESTED
    ↓
Invoke-WemApiRequest ✅ TESTED (actually executed)
    ↓
Get-WemApiConnection ❌ MOCKED (returns mock connection)
    ↓
Invoke-WebRequest ❌ MOCKED (no real HTTP)
```

## Best Practices

1. **Mock at the right level**
   - Unit tests: Mock all dependencies
   - Integration tests: Mock only external calls (Invoke-WebRequest)

2. **Use `-ModuleName` when mocking**
   ```powershell
   Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest { ... }
   ```

3. **BeforeAll vs BeforeEach**
   - `BeforeAll`: One-time setup (import module, create constants)
   - `BeforeEach`: Per-test setup (mocks, variables that need resetting)

4. **Test error scenarios**
   - 401 Unauthorized
   - 404 Not Found
   - 500 Internal Server Error
   - Null/Empty values
   - Invalid input

5. **Verify not only output, but also that functions are called correctly**
   ```powershell
   Should -Invoke -ModuleName JBC.CitrixWEM Invoke-WebRequest -Times 1 -ParameterFilter {
       $Headers['Authorization'] -eq "expected-token"
   }
   ```

## Examples

### Unit Test (single function)
Test only the logic of one function, all dependencies are mocked.
```powershell
Mock -ModuleName JBC.CitrixWEM Get-WemApiConnection { return $MockConnection }
Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest { return $MockResponse }
$result = Invoke-WemApiRequest -Connection $MockConnection -UriPath "test" -Method GET
```

### Integration Test (multiple functions)
Test the cooperation between functions, only external calls are mocked.
```powershell
Mock -ModuleName JBC.CitrixWEM Get-WemApiConnection { return $MockConnection }
Mock -ModuleName JBC.CitrixWEM Invoke-WebRequest { return $MockResponse }
# Invoke-WemApiRequest is NOT mocked, actually executed
$result = Get-WEMConfigurationSite
```

### Component Test
Test a specific component (e.g. error handling, parameter validation).
```powershell
It 'Validates required parameters' {
    { Invoke-WemApiRequest -UriPath $null -Method GET } | Should -Throw
}
```
