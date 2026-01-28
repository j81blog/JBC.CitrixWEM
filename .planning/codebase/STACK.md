# Technology Stack

**Analysis Date:** 2026-01-28

## Languages

**Primary:**
- PowerShell 5.1+ - Core module language for all cmdlets

**Secondary:**
- JSON - Configuration storage and API payload format
- XML - Group Policy Preference parsing (GPP structures)

## Runtime

**Environment:**
- PowerShell Desktop Edition 5.1 (Windows PowerShell)
- PowerShell Core 7.x compatible for modern systems

**Package Manager:**
- Built-in PowerShell module system (no NuGet dependencies)
- Lockfile: Not applicable (pure PowerShell implementation)

## Frameworks

**Core:**
- No external PowerShell frameworks - native .NET integration

**API Client:**
- Native .NET WebRequest APIs (`Invoke-WebRequest`)
- No third-party HTTP client libraries

**Testing:**
- No built-in test framework detected
- Manual testing approach

**Build/Dev:**
- Pester compatible (can be added for testing)
- Git for version control

## Key Dependencies

**Critical:**
- `Citrix.PoshSdkProxy.Commands` - Optional SDK module for Cloud authentication via cached Citrix sessions
  - Purpose: Bridges to existing Citrix environments with cached credentials
  - Not required if using API credentials or On-Premises auth

**Infrastructure:**
- .NET Framework System libraries for:
  - `System.Net` - HTTP client functionality
  - `System.Security.Cryptography.X509Certificates` - Certificate handling
  - `System.Management.Automation` - PowerShell credential management
  - `System.IO` - File operations
  - `System.Text.Encoding` - Base64 encoding for credentials

**Optional Icons/Graphics:**
- System icon extraction using Windows API (`System.Drawing.Icon`)
- PNG codec for icon conversion
- GDI+ for bitmap operations

## Configuration

**Environment:**
- Module stores settings in user AppData: `%APPDATA%\JBC.CitrixWEM\JBC.CitrixWEM.json`
- Settings file contains module preferences (e.g., `ShowModuleInfo`, `ShowWEMApiInfo`)
- No external config files required at deployment time

**Build:**
- Module manifest: `JBC.CitrixWEM\JBC.CitrixWEM.psd1`
- Root module: `JBC.CitrixWEM\JBC.CitrixWEM.psm1`
- PowerShell 5.1 requirement enforced via `#Requires -Version 5.1`

## Platform Requirements

**Development:**
- Windows PowerShell 5.1 or PowerShell 7.x
- .NET Framework 4.5+ (for Windows PowerShell)
- .NET 6.0+ (for PowerShell Core)
- Visual Studio Code with PowerShell extension (recommended)

**Production:**
- Target: Windows PowerShell Desktop Edition 5.1 minimum
- Citrix environments (Cloud or On-Premises WEM infrastructure)
- Network access to:
  - Citrix Cloud API endpoints (`api-eu.cloud.com`, `api-us.cloud.com`, `api.citrixcloud.jp`, `api-ap.cloud.com`)
  - Or On-Premises WEM Infrastructure Server (HTTP/HTTPS)

## Active Directory Integration

**Purpose:**
- Query AD forests, domains, users, and groups via WEM API
- Use as targets for assignment rules

**Implementation:**
- No direct AD client library - all AD queries proxied through WEM API
- Supports SID resolution via Windows API (`LookupAccountName`, `LookupAccountSid`)
- GPP credential translation for legacy migrations

## Certificate Handling

**Feature:**
- `-IgnoreCertificateErrors` switch in `Connect-WEMApi` bypasses certificate validation
- Implements custom `TrustAllCertsPolicy` for self-signed certificates in On-Premises scenarios
- Uses `ServicePointManager` to enforce TLS 1.2+ protocols

---

*Stack analysis: 2026-01-28*
