# Coding Conventions

**Analysis Date:** 2026-01-28

## Naming Patterns

**Functions:**
- Use Pascal-Case with Verb-Noun pattern
- Public functions: `Connect-WEMApi`, `Get-WEMApplication`, `Set-WEMPrinter`
- Private functions: `Expand-WEMResult`, `Get-ExceptionDetails`, `Convert-BatchVarToPowerShell`
- Standard PowerShell verbs: Get, Set, New, Remove, Invoke, Convert, Export, Import, Disconnect
- Prefix functions with context: `WEM` for WEM API functions, specific domain for utility functions

**Variables:**
- Use PascalCase for script variables: `$PublicPath`, `$PrivateFunctions`, `$ModuleName`
- Use PascalCase for parameters: `$CustomerId`, `$ClientId`, `$WEMServer`, `$Credential`
- Use camelCase for local function variables: `$convertedPath`, `$expandedPath`, `$apiCredentials`
- Private module-level variables prefixed with `$script:`: `$script:WemApiConnection`, `$script:WEMConfigFilePath`
- Environment variables accessed via `$env:VARIABLENAME`

**Types:**
- Use Pascal-Case for custom types and classes
- Use standard .NET types: `[string]`, `[int]`, `[System.Management.Automation.PSCredential]`
- Use `[PSCustomObject]` for custom return objects
- Use ordered hashtables `[ordered]@{}` for structured data

**Files:**
- Use Pascal-Case: `Connect-WEMApi.ps1`, `Get-ExceptionDetails.ps1`
- Match function name to filename exactly
- Public functions in `Public/` directory
- Private helper functions in `Private/` directory

## Code Style

**Formatting:**
- No linting tool configured (no `.eslintrc`, prettier, or PSScriptAnalyzer config)
- Indentation: 4 spaces
- Max line length: ~120 characters (based on observed patterns)
- Brace style: Open braces on same line for blocks (`if ($condition) {`)

**Parameter Declaration:**
- Use `[CmdletBinding()]` attribute on all functions
- Document all parameters with `[Parameter(...)]` attributes
- Include validation attributes: `[ValidateNotNullOrEmpty()]`, `[ValidateSet(...)]`, `[ValidateScript(...)]`
- Use descriptive parameter names with context: `$CustomerId`, `$WEMServer`, `$ApiRegion`
- Default parameters with `[Parameter(Mandatory = $false)]`
- Use `[OutputType(...)]` attribute when function returns typed objects

**Code Organization:**
- Each function is a separate file
- PSM1 module file dot-sources all Public and Private functions
- Module manifest (PSD1) explicitly exports only Public functions
- Aliases defined and exported via manifest

## Import Organization

**Order:**
1. Requires statements: `#Requires -Version 5.1`
2. CmdletBinding attribute
3. Parameter block
4. Begin block (if needed)
5. Process block (main logic)
6. End block (cleanup)
7. Code signature block at end of file

**Module Imports:**
- Module requires PowerShell 5.1 minimum
- No external module dependencies required (Citrix SDK is optional)
- Optional dependencies are checked at runtime with `-ErrorAction Stop` and appropriate error handling

**Path Aliases:**
- No path aliases used in codebase
- Uses full paths with `Join-Path` for dynamic path construction
- Example: `$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'`

## Error Handling

**Patterns:**
- Use try/catch blocks for critical operations that can fail
- Use `throw` with descriptive messages: `throw "Invalid format! Please provide..."`
- Catch specific errors when possible
- Use `-ErrorAction Stop` for cmdlets that should fail immediately
- Re-throw errors with context: `throw "Failed to convert icon file to base64. Details: $($_.Exception.Message)"`
- Use `Get-ExceptionDetails` helper function to extract comprehensive error information from ErrorRecord
- Extract exception details recursively including InnerException chain

**Example Pattern:**
```powershell
try {
    Get-Item "C:\NonExistent\Path" -ErrorAction Stop
} catch {
    $details = Get-ExceptionDetails -ErrorRecord $_
    Write-Error "Operation failed: $($details.Message)"
}
```

## Logging

**Framework:** Native PowerShell Write-* cmdlets (no external logging framework)

**Patterns:**
- `Write-Verbose`: Detailed diagnostic information during normal operation
  - "Attempting to connect to On-Premises WEM Server: $($WEMServer)"
  - "No existing cached session found. Attempting to authenticate via Get-XDAuthentication."
- `Write-Warning`: Conditions that are not errors but may affect behavior
  - "No active WEM AD Domain has been set. Please use Set-WEMActiveDomain to set one."
- `Write-Error`: Actual errors during execution
  - "Failed to connect to WEM API. Details: $($_.Exception.Message)"
- `Write-Output`: Standard function results (use for return values)
- Use `-Verbose` preference for debug-level information
- Use `-ErrorAction SilentlyContinue` for expected failures that don't need user notification

**Debug Information:**
- Use `-Verbose` parameter to enable verbose output
- Module initializes with development warning shown via `Write-Warning`

## Comments

**When to Comment:**
- Complex regex patterns should be explained
- Non-obvious algorithm logic requires comments
- Workarounds for PowerShell limitations should be documented
- Inline comments explain the "why" not the "what"

**JSDoc/TSDoc:**
- Use PowerShell comment-based help format exclusively
- Comment-based help appears in `<# #>` block at start of function
- Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.NOTES`, `.OUTPUTS` sections
- Version and author information in `.NOTES` section

**Example Help Block:**
```powershell
<#
.SYNOPSIS
    Authenticates to the Citrix WEM API.

.DESCRIPTION
    This function authenticates against the Citrix WEM API and supports three methods:
    1. Cloud with API credentials (ClientId and ClientSecret).
    2. Cloud with existing Citrix DaaS PowerShell SDK session.
    3. On-Premises with user credentials.

.PARAMETER CustomerId
    The Citrix Customer ID. Required for Cloud authentication methods.

.EXAMPLE
    PS C:\> Connect-WEMApi -CustomerId "mycustomerid"

.NOTES
    Version:        1.4
    Author:         John Billekens Consultancy
    Co-Author:      Gemini
    Creation Date:  2025-08-05
#>
```

## Function Design

**Size:** Functions range from 10 to 200+ lines depending on complexity
- Helper functions like `Expand-WEMResult` are 15-20 lines
- Core API functions like `Connect-WEMApi` are 150+ lines
- No hard size limit enforced but long functions are broken into helper functions

**Parameters:**
- All parameters documented with help text
- Use parameter sets for mutually exclusive options (`ParameterSetName`)
- Use `[ValidateScript()]` for complex validation logic
- Use `[ValidateSet()]` for enum-like parameters (e.g., ApiRegion)
- Pipeline input via `[Parameter(ValueFromPipeline = $true)]` where applicable

**Return Values:**
- Functions return typed objects via `[OutputType(...)]`
- Return custom objects via `[PSCustomObject]@{}`
- Return ordered hashtables for structured data via `[ordered]@{}`
- Some functions return early for null/empty input
- Use `Write-Output` explicitly for return values to avoid accidental string returns

## Module Design

**Exports:**
- Only Public functions explicitly exported via `Export-ModuleMember -Function`
- Private functions available internally via dot-sourcing but hidden from users
- Aliases exported separately: `Export-ModuleMember -Alias *`
- Manifest file (PSD1) lists all exported functions explicitly

**Barrel Files:**
- PSM1 acts as barrel file for all functions
- Dot-sources all Public and Private PS1 files on module load
- Error handling for failed function imports
- Module-level cleanup via `OnRemove` script block variable

**Module Configuration:**
- Module configuration stored in JSON file
- Location: `%APPDATA%\JBC.CitrixWEM\JBC.CitrixWEM.json`
- Updated via `Update-WEMModuleConfigSetting` helper
- Module version uses date-based versioning: `2026.120.2345`

---

*Convention analysis: 2026-01-28*
