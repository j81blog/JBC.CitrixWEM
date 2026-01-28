# Architecture

**Analysis Date:** 2026-01-28

## Pattern Overview

**Overall:** Modular PowerShell API Client Architecture

**Key Characteristics:**
- Function-based encapsulation with public/private separation
- Centralized API request handler (`Invoke-WEMApiRequest`)
- Session-based state management (script-scoped connection object)
- Support for multiple authentication backends (Citrix Cloud + On-Premises)
- Consistent result expansion and error handling

## Layers

**Connection Layer:**
- Purpose: Authenticate and manage API sessions across multiple backends
- Location: `JBC.CitrixWEM\Public\Connect-WEMApi.ps1`, `JBC.CitrixWEM\Public\Disconnect-WEMApi.ps1`, `JBC.CitrixWEM\Public\Get-WEMApiConnection.ps1`
- Contains: Authentication logic for Cloud (API credentials, SDK session), On-Premises (basic auth), session initialization
- Depends on: `Invoke-WEMApiRequest` for validation
- Used by: All WEM API functions through `Get-WEMApiConnection`

**API Request Layer:**
- Purpose: Centralize all HTTP communication with WEM API endpoints
- Location: `JBC.CitrixWEM\Public\Invoke-WEMApiRequest.ps1`
- Contains: HTTP method handling (GET, POST, PUT, DELETE, PATCH), header construction, authentication injection, URI building
- Depends on: PowerShell `Invoke-RestMethod`, connection object
- Used by: All resource functions (Get-, New-, Set-, Remove- WEM* functions)

**Result Processing Layer:**
- Purpose: Normalize API responses across heterogeneous endpoints
- Location: `JBC.CitrixWEM\Private\Expand-WEMResult.ps1`
- Contains: Response envelope handling (extracts `.Items` property if present)
- Depends on: None (pure utility)
- Used by: All Get-WEM* and Import-* functions

**Resource Functions Layer:**
- Purpose: Domain-specific operations (applications, printers, networks drives, assignments, etc.)
- Location: `JBC.CitrixWEM\Public\Get-WEM*.ps1`, `JBC.CitrixWEM\Public\New-WEM*.ps1`, `JBC.CitrixWEM\Public\Set-WEM*.ps1`, `JBC.CitrixWEM\Public\Remove-WEM*.ps1`
- Contains: 105+ public functions organized by resource type (Applications, Printers, NetworkDrives, Assignments, etc.)
- Depends on: API Request Layer, Result Processing Layer, utility functions
- Used by: End users

**Configuration/State Layer:**
- Purpose: Manage module configuration and active site context
- Location: `JBC.CitrixWEM\Public\Set-WEMModuleConfiguration.ps1`, `JBC.CitrixWEM\Public\Set-WEMActiveConfigurationSite.ps1`, `JBC.CitrixWEM\Private\Update-WEMModuleConfigSetting.ps1`
- Contains: JSON-based configuration file management in `%APPDATA%\JBC.CitrixWEM\`, active site tracking
- Depends on: File system, JSON serialization
- Used by: Resource functions needing default SiteId

**Utility/Helper Functions Layer:**
- Purpose: Support cross-cutting concerns (data conversion, icon processing, AD lookups, etc.)
- Location: `JBC.CitrixWEM\Private\` (22 functions)
- Contains: GPP parsing, icon conversion, encoding, AD domain lookups, error handling, logging
- Depends on: System APIs, .NET reflection
- Used by: Resource functions and high-level operations

## Data Flow

**Initialization Flow:**

1. Module loads (`JBC.CitrixWEM.psm1`)
2. Public/Private functions dot-sourced into module scope
3. Module config initialized from `%APPDATA%\JBC.CitrixWEM\JBC.CitrixWEM.json`
4. Module-wide variables set: `$script:WemApiConnection = $null`, `$Script:ProgressPreference = "SilentlyContinue"`
5. Connection info banner displayed (if not suppressed)

**Authentication & Connection Flow:**

1. User calls `Connect-WEMApi` with one of three parameter sets:
   - ApiCredentials: CustomerId + ClientId + ClientSecret (Cloud)
   - Sdk: CustomerId only (Cloud, uses cached DaaS session)
   - OnPremCredential: WEMServer + Credential (On-Premises)
2. Authentication handler:
   - Cloud: Obtains bearer token from Citrix Cloud OAuth
   - On-Premises: Establishes WebSession with basic auth
3. Connection object stored: `$script:WemApiConnection` (PSCustomObject with BaseUrl, BearerToken, CustomerId, IsOnPrem, etc.)
4. Active site loaded if previously set via `Set-WEMActiveConfigurationSite`

**API Request Flow:**

1. Resource function (e.g., `Get-WEMApplication`) called with parameters
2. Function resolves SiteId (explicit param or active site from config)
3. Function calls `Invoke-WEMApiRequest -UriPath "services/wem/..." -Method "GET" -Connection $Connection`
4. Request handler:
   - Constructs full URI: `BaseUrl/UriPath`
   - Builds headers: Authorization (bearer token), Content-Type, Accept, Citrix-CustomerId (Cloud), Citrix-TransactionId (Cloud)
   - Calls `Invoke-RestMethod` with appropriate HTTP method
   - Returns parsed JSON response
5. Response passed through `Expand-WEMResult` to normalize envelope
6. Results returned to caller

**State Management:**

- Active site configuration persisted to JSON file at `$env:APPDATA\JBC.CitrixWEM\JBC.CitrixWEM.json`
- Active site ID retrieved from config when function calls `Get-WEMApiConnection`
- Module cleanup on unload attempts graceful disconnect via `Disconnect-WEMApi`

## Key Abstractions

**Connection Object:**
- Purpose: Encapsulates authentication state and endpoint metadata
- Examples: `$script:WemApiConnection` set by `Connect-WEMApi`
- Pattern: PSCustomObject with properties: BaseUrl, BearerToken, CustomerId, IsOnPrem, ActiveSiteId, ActiveSiteName, WebSession (On-Premises)
- Immutable during session; recreated on reconnect

**SiteId Resolution:**
- Purpose: Allow functions to operate with explicit SiteId or fall back to active site
- Examples: All Get-WEM*, New-WEM*, Set-WEM* functions check `$PSBoundParameters.ContainsKey('SiteId')`
- Pattern: Explicit > Active > Error

**URI Path Convention:**
- Purpose: Standardize API endpoint references across functions
- Examples: `services/wem/webApplications?siteId=$SiteId`, `services/wem/networkDrives?siteId=$SiteId`
- Pattern: All endpoints follow `services/wem/{resource}?siteId=X` or `services/wem/{resource}/X` structure

**Response Envelope:**
- Purpose: Handle inconsistent API response structures (some endpoints return `{ Items: [...] }`, others return raw object)
- Examples: `Expand-WEMResult` unwraps envelope
- Pattern: Check for `.Items` property; if exists, return that; otherwise return as-is

## Entry Points

**Primary Entry Point:**
- Location: `JBC.CitrixWEM\JBC.CitrixWEM.psm1`
- Triggers: User imports module via `Import-Module JBC.CitrixWEM`
- Responsibilities: Load all functions, initialize state, display connection info, set up module cleanup

**Connection Entry Point:**
- Location: `JBC.CitrixWEM\Public\Connect-WEMApi.ps1`
- Triggers: User calls `Connect-WEMApi`
- Responsibilities: Validate credentials, obtain auth token, initialize connection object, set active site from config

**Resource Entry Points:**
- Location: `JBC.CitrixWEM\Public\Get-WEM*.ps1`, `New-WEM*.ps1`, `Set-WEM*.ps1`, `Remove-WEM*.ps1`, `Import-*.ps1`
- Triggers: User calls any resource function
- Responsibilities: Validate connection, resolve context (SiteId), call API, process results, return to user

**Configuration Entry Point:**
- Location: `JBC.CitrixWEM\Public\Set-WEMActiveConfigurationSite.ps1`, `Set-WEMModuleConfiguration.ps1`
- Triggers: User sets module configuration
- Responsibilities: Persist configuration to JSON, update script-scoped variables

## Error Handling

**Strategy:** Try-catch with descriptive error propagation

**Patterns:**

1. **Connection Validation** (`Get-WEMApiConnection`):
   - Checks if `$script:WemApiConnection` is null or token is empty
   - Throws: "Not connected to Citrix Cloud API. Please run Connect-WemApi first."

2. **API Error Wrapping** (`Invoke-WEMApiRequest`):
   - Catches `Invoke-RestMethod` exceptions
   - Re-throws with context: "Failed to complete API request: [original error]"

3. **Resource Function Error Handling** (all Get-WEM*, New-WEM*, etc.):
   - Wraps API calls in try-catch
   - Logs error message with context: "Failed to retrieve WEM [resource]: [details]"
   - Returns $null on failure

4. **Validation Errors** (parameter validation):
   - Uses ValidateScript attributes on URIs, enums, etc.
   - Custom validation for On-Premises URLs: must match `^(https?)://`

## Cross-Cutting Concerns

**Logging:**
- Approach: Write-Verbose for debug output, Write-Error for failures, Write-Information for banner/status
- Used by: Connection layer (connection details), Request layer (full URI, headers), Resource functions (operation context)

**Validation:**
- Approach: Parameter validation via [ValidateSet], [ValidateScript], [ValidateNotNullOrEmpty]
- Used by: Connection parameters (ApiRegion, Method), Resource parameters (State, AppType)

**Authentication:**
- Approach: Three-mode (Cloud-ApiCredentials, Cloud-Sdk, On-Premises)
- Cloud: OAuth 2.0 bearer token via `Invoke-RestMethod` to Citrix Cloud
- On-Premises: Basic auth via WebSession
- Validation: `Get-WEMApiConnection` ensures valid token before any API call

---

*Architecture analysis: 2026-01-28*
