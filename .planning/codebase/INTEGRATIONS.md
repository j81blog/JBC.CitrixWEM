# External Integrations

**Analysis Date:** 2026-01-28

## APIs & External Services

**Citrix Workspace Environment Management (WEM) - Cloud:**
- Service: Citrix Cloud WEM API
- What it's used for: Manage applications, printers, network drives, file associations, personalization settings, and configuration sets
  - SDK/Client: Native .NET WebRequest (no third-party SDK)
  - Auth: CWSAuth bearer token (OAuth 2.0 client credentials flow)
  - Endpoints: `https://{region}-api-webconsole.wem.cloud.com/services/wem/*`
  - Regions: EU (`api-eu.cloud.com`), US (`api-us.cloud.com`), Japan (`api.citrixcloud.jp`), AP (`api-ap.cloud.com`)

**Citrix Workspace Environment Management (WEM) - On-Premises:**
- Service: WEM Infrastructure Server (On-Premises)
- What it's used for: Same as Cloud but for self-hosted WEM deployments
  - Auth: Session token (Basic auth → SessionId bearer token)
  - Endpoints: `http(s)://{wem-server}/services/wem/onPrem/*` or `http(s)://{wem-server}/services/wem/forward/*`

**Citrix Cloud SDK (Optional):**
- Service: Citrix.PoshSdkProxy.Commands module
- What it's used for: Cloud authentication via cached Citrix session credentials (reduces friction for existing Citrix users)
  - Methods used: `Get-XDCredentials`, `Clear-XDCredentials`, `Get-XDAuthentication`
  - When used: Only if `-CustomerId` passed to `Connect-WEMApi` without API credentials
  - Fallback: Can authenticate directly with API credentials

**Citrix Cloud Trust OAuth:**
- Service: Citrix Cloud Trust OAuth2 endpoint
- What it's used for: Obtain bearer tokens for API credential authentication
  - Endpoint: `https://{region}.cctrustoauth2/root/tokens/clients`
  - Flow: Client credentials (Client ID + Client Secret)
  - Token type: `access_token` (formatted as `CWSAuth bearer=<token>`)

## Data Storage

**Databases:**
- Type: Remote via API - Citrix WEM backend (SQL Server)
- Connection: REST API calls via `Invoke-WemApiRequest`
- Client: Native HTTP requests (no ORM)
- Read/Write: Full CRUD operations available for most resources

**File Storage:**
- Local filesystem only for:
  - Icon files: Extracted/converted locally before upload
  - Configuration file: `%APPDATA%\JBC.CitrixWEM\JBC.CitrixWEM.json`
  - No cloud blob storage integration

**Caching:**
- Session-based in-memory: WEM API connection object cached in `$script:WemApiConnection`
- Module config cached in `$Script:WEMModuleConfig`
- No external cache service (Redis, Memcached)

## Authentication & Identity

**Auth Provider:**
- Citrix Cloud OAuth2 (Cloud deployments)
- Basic HTTP Authentication (On-Premises deployments)
- Optional Citrix SDK session bridging

**Implementation:**
- Connect-WEMApi supports three modes:
  1. **Cloud API Credentials:** Client ID + Client Secret → Bearer token via Citrix Trust OAuth
  2. **Cloud SDK Session:** Leverages existing Citrix SDK cached session (Get-XDCredentials)
  3. **On-Premises:** Domain\username + password → Session token via POST /services/wem/onPrem/LogIn

- Token storage: In-memory `$script:WemApiConnection` object (not persisted)
- Token expiration: Tracked but automatic refresh not implemented (session must be recreated)
- Credential handling: SecureString support for programmatic automation

## Active Directory Integration

**Auth Provider:**
- Not used for authentication (uses WEM API credentials)
- Used for identity/group resolution only

**Integration Points:**
- Query AD forests: `Get-WEMADForest`
- Query AD domains: `Get-WEMADDomain`
- Query AD users: `Get-WEMADUser`
- Query AD groups: `Get-WEMADGroup`
- Search AD objects: `Search-WEMActiveDirectoryObject`
- Resolve SID: `Resolve-WEMSid`
  - Implementation: Uses Windows API `LookupAccountSid` / `LookupAccountName`
  - File: `C:\Users\JohnBillekens\GitHub\JBC.CitrixWEM\JBC.CitrixWEM\Public\Resolve-WEMSid.ps1`
  - Use case: Translate SIDs from Group Policy Preferences to readable names

## Group Policy Preferences (GPP) Integration

**Data Source:**
- Legacy GPP XML files from Citrix or Ivanti environments
- Used for migrations

**Integration Points:**
- `Get-GppDriveMapping` - Parse Drive Maps from GPP XML
- `Get-GppPrinterMapping` - Parse Printer Maps from GPP XML
- `Get-GppShortcut` - Parse Desktop Shortcuts from GPP XML
- Implementation pattern: Parse XML, decrypt credentials if needed, map to WEM objects
- Files: `C:\Users\JohnBillekens\GitHub\JBC.CitrixWEM\JBC.CitrixWEM\Public\Get-Gpp*.ps1`

## Ivanti WEM/Workspace Composer Integration

**Data Source:**
- Ivanti Workspace Control (WC) database or exports
- Used for migrations from Ivanti to Citrix WEM

**Integration Points:**
- `Get-IvantiWCApplication` - Query Ivanti applications
- `Get-IvantiWCNetworkDrive` - Query Ivanti network drives
- `Get-IvantiWCPrinterMapping` - Query Ivanti printer mappings
- `Get-IvantiWCEnvironmentVariable` - Query Ivanti environment variables
- `Import-IvantiWCApplication` - Migrate applications
- `Import-IvantiWCNetworkDrive` - Migrate network drives
- `Import-IvantiWCPrinterMapping` - Migrate printer mappings
- `Import-IvantiWCEnvironmentVariable` - Migrate environment variables
- Implementation: Parse Ivanti XML/JSON exports, transform, create WEM equivalents
- Files: `C:\Users\JohnBillekens\GitHub\JBC.CitrixWEM\JBC.CitrixWEM\Public\Get-IvantiWC*.ps1`, `Import-IvantiWC*.ps1`

## Monitoring & Observability

**Error Tracking:**
- Built-in try/catch with descriptive error messages
- Verbose logging support via `-Verbose` common parameter
- Error messages capture HTTP status codes and response body details

**Logs:**
- PowerShell built-in logging (Write-Error, Write-Warning, Write-Host)
- Verbose output: `Write-Verbose` used throughout
- Colored console output via custom `Write-InformationColored` function
  - File: `C:\Users\JohnBillekens\GitHub\JBC.CitrixWEM\JBC.CitrixWEM\Private\Write-InformationColored.ps1`

**API Request Logging:**
- Full HTTP request/response details available with `-Verbose` in `Invoke-WemApiRequest`
- Response content logged as JSON

## CI/CD & Deployment

**Hosting:**
- GitHub (repository hosting)
- PowerShell Gallery (module distribution) - registered if published

**CI Pipeline:**
- None detected in codebase

**Deployment Method:**
- Direct GitHub clone + `Install-ModuleFromGithubMain.ps1` script
- or via PowerShell Gallery `Install-Module JBC.CitrixWEM`

**Code Signing:**
- Module is signed with Certum Code Signing certificate (2021 CA)
- Signature blocks present in all `.ps1` files
- Digital signature enforces integrity

## Webhooks & Callbacks

**Incoming:**
- Not applicable - module is client-side only

**Outgoing:**
- No webhook support in current implementation
- All operations are request/response based

## Environment Configuration

**Required env vars:**
- None required at runtime
- Optional: Credentials can be passed programmatically or via Get-Credential prompts

**Secrets location:**
- Credentials: Passed as PSCredential objects or SecureString
- Not stored on disk (except in-memory during session)
- User AppData config file (`%APPDATA%\JBC.CitrixWEM\JBC.CitrixWEM.json`) contains non-sensitive settings only

**Citrix Customer ID:**
- Required for Cloud deployments
- Not a secret (public identifier for tenant)
- Passed as parameter

**Citrix Client ID/Secret:**
- Required for Cloud API credential authentication
- Should be stored in secure credential manager
- Passed via SecureString parameter or Get-Credential dialog

---

*Integration audit: 2026-01-28*
