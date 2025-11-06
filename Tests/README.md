# JBC.CitrixWEM Pester Tests

This directory contains comprehensive Pester tests for the JBC.CitrixWEM PowerShell module.

## Prerequisites

- **PowerShell 5.1** or higher
- **Pester 5.0.0** or higher

### Install Pester

```powershell
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
```

## Test Structure

```
Tests/
├── JBC.CitrixWEM.Tests.ps1          # Module-level tests (manifest, imports, structure)
├── Unit/                             # Unit tests for individual functions
│   ├── ConvertTo-Hashtable.Tests.ps1 # 50+ tests for hashtable conversion
│   └── Resolve-WEMSid.Tests.ps1      # 40+ tests for SID resolution
├── Integration/                      # Integration tests with mocked dependencies
│   └── Connect-WEMApi.Tests.ps1      # 30+ tests for API connection
├── Invoke-Tests.ps1                  # Test runner script
└── README.md                         # This file
```

## Running Tests

### Run All Tests

```powershell
.\Invoke-Tests.ps1
```

### Run Specific Test Types

```powershell
# Run only Unit tests
.\Invoke-Tests.ps1 -TestType Unit

# Run only Integration tests
.\Invoke-Tests.ps1 -TestType Integration

# Run only Module-level tests
.\Invoke-Tests.ps1 -TestType Module
```

### Run Tests with Code Coverage

```powershell
# Run all tests with code coverage
.\Invoke-Tests.ps1 -TestType All -CodeCoverage

# Run unit tests with code coverage
.\Invoke-Tests.ps1 -TestType Unit -CodeCoverage
```

### Advanced Usage

```powershell
# Get result object for further processing
$Result = .\Invoke-Tests.ps1 -PassThru

# Specify output format (NUnitXml, JUnitXml, or NUnit2.5)
.\Invoke-Tests.ps1 -OutputFormat JUnitXml
```

## Test Coverage

### Module-Level Tests (JBC.CitrixWEM.Tests.ps1)
- **20+ tests** covering:
  - Module import and structure
  - Manifest validation
  - Function exports
  - Help content verification
  - Parameter validation

### ConvertTo-Hashtable.Tests.ps1
- **50+ tests** covering:
  - Simple object conversion
  - Nested object conversion (3+ levels deep)
  - Array and collection handling
  - Pipeline input
  - Edge cases (null, empty, special characters)
  - Real-world WEM object scenarios

### Resolve-WEMSid.Tests.ps1
- **40+ tests** covering:
  - Single and multiple SID resolution
  - Batch processing (25 SIDs per batch)
  - Pipeline input support
  - On-Premises vs Cloud URI paths
  - Error handling
  - Well-known and domain SID formats

### Connect-WEMApi.Tests.ps1
- **30+ tests** covering:
  - Parameter validation (3 parameter sets)
  - On-Premises authentication
  - Cloud authentication (EU, US, JP regions)
  - Credential format parsing (DOMAIN\user, user@domain)
  - Connection object creation
  - Error handling
  - Session management

## Test Output

After running tests, you'll find:

- **TestResults-[timestamp].xml** - Test execution results
- **CodeCoverage.xml** - Code coverage report (if -CodeCoverage used)

## Example Test Run

```powershell
PS C:\...\Tests> .\Invoke-Tests.ps1 -TestType All -CodeCoverage

Test path: C:\Users\...\Tests
Running all tests...
Code coverage analysis enabled

Starting Pester tests...
================================================================================

Starting discovery in 4 files.
Discovery found 120 tests in 245ms.
Running tests.

[+] C:\...\Tests\JBC.CitrixWEM.Tests.ps1 432ms (178ms|227ms)
[+] C:\...\Tests\Unit\ConvertTo-Hashtable.Tests.ps1 1.23s (456ms|789ms)
[+] C:\...\Tests\Unit\Resolve-WEMSid.Tests.ps1 891ms (312ms|567ms)
[+] C:\...\Tests\Integration\Connect-WEMApi.Tests.ps1 1.01s (389ms|634ms)

Tests completed in 3.56s
Tests Passed: 120, Failed: 0, Skipped: 0 NotRun: 0

================================================================================
Test Summary
================================================================================
Total Tests    : 120
Passed Tests   : 120
Failed Tests   : 0
Skipped Tests  : 0
Duration       : 00:00:03.5645321

Code Coverage:
  Coverage     : 78.45%
  Commands Hit : 342 / 436
  Output saved : C:\...\Tests\CodeCoverage.xml

Test results saved: C:\...\Tests\TestResults-20250215-143022.xml
================================================================================

All tests PASSED!
```

## Continuous Integration

The test suite is designed to work with CI/CD pipelines:

```yaml
# Example Azure DevOps pipeline
- task: PowerShell@2
  displayName: 'Run Pester Tests'
  inputs:
    targetType: 'filePath'
    filePath: 'Tests/Invoke-Tests.ps1'
    arguments: '-TestType All -CodeCoverage'

- task: PublishTestResults@2
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: 'Tests/TestResults-*.xml'

- task: PublishCodeCoverageResults@1
  inputs:
    codeCoverageTool: 'JaCoCo'
    summaryFileLocation: 'Tests/CodeCoverage.xml'
```

## Writing New Tests

When adding new functions to the module, follow these patterns:

### 1. Unit Test Template

```powershell
BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..\..\JBC.CitrixWEM\JBC.CitrixWEM.psd1'
    Import-Module $ModulePath -Force
}

Describe 'Your-Function' {
    Context 'Basic functionality' {
        It 'Should perform expected operation' {
            $Result = Your-Function -Parameter 'Value'
            $Result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Error handling' {
        It 'Should handle invalid input' {
            { Your-Function -Parameter $null } | Should -Throw
        }
    }
}

AfterAll {
    Remove-Module JBC.CitrixWEM -Force -ErrorAction SilentlyContinue
}
```

### 2. Mock External Dependencies

```powershell
Mock -ModuleName JBC.CitrixWEM Invoke-WemApiRequest {
    return [PSCustomObject]@{ Items = @() }
}
```

## Troubleshooting

### Issue: "Module not found"
**Solution**: Ensure you're running tests from the `Tests` directory, or update the `$ModulePath` in test files.

### Issue: "Pester version conflict"
**Solution**: Uninstall old Pester versions:
```powershell
Get-Module Pester -ListAvailable | Uninstall-Module -Force
Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
```

### Issue: "Tests fail with 'Mock not found'"
**Solution**: Ensure you're using Pester 5.x syntax:
```powershell
# Correct (Pester 5.x)
Mock -ModuleName JBC.CitrixWEM Function-Name { }

# Incorrect (Pester 4.x)
Mock Function-Name { }
```

## Contributing

When contributing tests:

1. Follow the existing test structure
2. Use descriptive test names starting with "Should"
3. Group related tests in `Context` blocks
4. Mock external dependencies (API calls, file system, etc.)
5. Test both success and failure scenarios
6. Aim for >80% code coverage

## Resources

- [Pester Documentation](https://pester.dev/)
- [Pester GitHub](https://github.com/pester/Pester)
- [PowerShell Testing Best Practices](https://pester.dev/docs/quick-start)
