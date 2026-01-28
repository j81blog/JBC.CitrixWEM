# Codebase Structure

**Analysis Date:** 2026-01-28

## Directory Layout

```
JBC.CitrixWEM/
├── .planning/                    # GSD documentation (generated)
│   └── codebase/                # Codebase analysis docs
├── Docs/                         # User-facing usage documentation
│   ├── ConnectToWEMEnvironment.md
│   ├── CreateApplicationsAndAssignment.md
│   ├── CreateNetworkDriveAndAssignment.md
│   ├── CreatePrinterAssignment.md
│   ├── CreateFileTypeAssociations.md
│   ├── Export-FileIcon.md
│   ├── CreateApplicationsFromShortcuts.md
│   └── UpdateApplicationIcons.md
├── JBC.CitrixWEM/               # PowerShell module root
│   ├── JBC.CitrixWEM.psd1       # Module manifest
│   ├── JBC.CitrixWEM.psm1       # Module entry point
│   ├── Public/                  # 105 public functions
│   │   ├── Connect-WEMApi.ps1
│   │   ├── Disconnect-WEMApi.ps1
│   │   ├── Get-WEM*.ps1         # 50+ GET functions
│   │   ├── New-WEM*.ps1         # 20+ CREATE functions
│   │   ├── Set-WEM*.ps1         # 10+ UPDATE functions
│   │   ├── Remove-WEM*.ps1      # 10+ DELETE functions
│   │   ├── Invoke-WEMApiRequest.ps1
│   │   └── Convert-*.ps1        # Utility functions
│   └── Private/                 # 22 private helper functions
│       ├── Expand-WEMResult.ps1
│       ├── Get-Exception*.ps1
│       ├── Resolve-*.ps1
│       ├── Convert-*.ps1
│       └── Update-WEMModuleConfigSetting.ps1
├── Install-ModuleFromGithubMain.ps1  # GitHub installation script
├── Update-ModuleInfo.ps1             # Internal module build script
├── README.md                         # Main readme
└── LICENSE                           # MIT license
```

## Directory Purposes

**JBC.CitrixWEM/ (Module Root):**
- Purpose: Contains all PowerShell module files
- Contains: Manifest, entry point, public/private function directories
- Key files: `JBC.CitrixWEM.psd1`, `JBC.CitrixWEM.psm1`

**JBC.CitrixWEM/Public/:**
- Purpose: All exported functions available to module users
- Contains: 105 PowerShell functions organized by operation type (Get, New, Set, Remove, Import, etc.)
- Key files: Connection functions, WEM API functions, utility functions
- Naming: Verb-Noun format following PowerShell standards (e.g., Get-WEMApplication, New-WEMPrinter)

**JBC.CitrixWEM/Private/:**
- Purpose: Internal helper functions not exposed to users
- Contains: 22 utility functions for cross-cutting concerns
- Key files: Result expansion, error handling, icon processing, AD lookup, configuration management
- Naming: PascalCase or Verb-Noun for clarity

**Docs/:**
- Purpose: User-facing documentation and usage examples
- Contains: Markdown files demonstrating how to use major module features
- Key files: Connection guide, multi-step workflows for applications, printers, drives, icons

## Key File Locations

**Entry Points:**

- `JBC.CitrixWEM\JBC.CitrixWEM.psm1`: Module initialization, function loading, state setup
- `JBC.CitrixWEM\JBC.CitrixWEM.psd1`: Module manifest with 105 exported functions, metadata, version info
- `JBC.CitrixWEM\Public\Connect-WEMApi.ps1`: User's first step - establishes API connection

**Configuration:**

- `JBC.CitrixWEM\JBC.CitrixWEM.psd1`: PowerShell metadata (version: 2026.120.2345, PS 5.1+, GUID)
- `JBC.CitrixWEM\Public\Set-WEMModuleConfiguration.ps1`: Module settings (ShowModuleInfo flag, etc.)
- `JBC.CitrixWEM\Public\Set-WEMActiveConfigurationSite.ps1`: Tracks active WEM site for context
- `$env:APPDATA\JBC.CitrixWEM\JBC.CitrixWEM.json`: Persisted config file (ShowModuleInfo, ActiveSiteId)

**Core Logic:**

- `JBC.CitrixWEM\Public\Invoke-WEMApiRequest.ps1`: Central request dispatcher (HTTP, headers, auth)
- `JBC.CitrixWEM\Private\Expand-WEMResult.ps1`: Response normalization
- `JBC.CitrixWEM\Private\Update-WEMModuleConfigSetting.ps1`: Config file I/O

**WEM Resources (by function count):**

- Applications: `Get-WEMApplication.ps1`, `New-WEMApplication.ps1`, `Set-WEMApplication.ps1`, `Remove-WEMApplication.ps1`
- Assignments: `Get-WEMApplicationAssignment.ps1`, `New-WEMApplicationAssignment.ps1`, `Remove-WEMApplicationAssignment.ps1` (and variations for other resource types)
- Printers: `Get-WEMPrinter.ps1`, `New-WEMPrinter.ps1`, `Set-WEMPrinter.ps1`, `Remove-WEMPrinter.ps1`, etc.
- Network Drives: `Get-WEMNetworkDrive.ps1`, `New-WEMNetworkDrive.ps1`, `Set-WEMNetworkDrive.ps1`, `Remove-WEMNetworkDrive.ps1`, etc.
- File Associations: `Get-WEMFileAssociation.ps1`, `New-WEMFileAssociation.ps1`, etc.
- Environment Variables: `Get-WEMEnvironmentVariable.ps1`, `New-WEMEnvironmentVariable.ps1`, etc.
- AD/Settings: `Get-WEMADUser.ps1`, `Get-WEMADGroup.ps1`, `Get-WEMAdminPreference.ps1`, etc.

**Icon & File Operations:**

- `JBC.CitrixWEM\Public\Export-FileIcon.ps1`: Extract icons from executables
- `JBC.CitrixWEM\Public\Convert-IconFileToBase64.ps1`: Icon to base64 conversion
- `JBC.CitrixWEM\Private\ConvertTo-IconFormat.ps1`: Icon format handling
- `JBC.CitrixWEM\Private\Convert-BinaryIconToBase64.ps1`: Binary icon processing

**Active Directory & GPP:**

- `JBC.CitrixWEM\Private\Get-ADDomainFQDN.ps1`, `Get-ADDomainNetBIOS.ps1`: AD lookup helpers
- `JBC.CitrixWEM\Private\ConvertFrom-IvantiBB.ps1`, `ConvertFrom-IvantiAccessControl.ps1`: Legacy Ivanti WC migration support
- `JBC.CitrixWEM\Private\Resolve-GppSid.ps1`: Group Policy Preference SID resolution

**Import Functions:**

- `JBC.CitrixWEM\Public\Import-IvantiWCApplication.ps1`: Migrate applications from Ivanti WC
- `JBC.CitrixWEM\Public\Import-IvantiWCNetworkDrive.ps1`: Migrate network drives from Ivanti WC
- `JBC.CitrixWEM\Public\Import-IvantiWCPrinterMapping.ps1`: Migrate printers from Ivanti WC
- `JBC.CitrixWEM\Public\Import-WEMRegistryFile.ps1`: Registry-based configuration import

## Naming Conventions

**Files:**

- Pattern: `Verb-Noun.ps1` (e.g., Get-WEMApplication.ps1, New-WEMPrinter.ps1)
- Verbs: Standard PowerShell verbs (Get, New, Set, Remove, Import, Invoke, Export, Connect, Disconnect)
- Nouns: WEM-prefixed resource names (WEMApplication, WEMPrinter, WEMNetworkDrive) or utility descriptors
- Private functions: Either follow Verb-Noun or descriptive names (e.g., Expand-WEMResult, Update-WEMModuleConfigSetting)

**Directories:**

- Pattern: PascalCase or descriptive nouns (Public, Private, Docs)
- Naming: Clear functional grouping (Public/Private reflect scope; Docs for documentation)

## Where to Add New Code

**New Feature (WEM Resource CRUD):**

- Primary code: `JBC.CitrixWEM\Public\Get-WEM{Resource}.ps1`, `New-WEM{Resource}.ps1`, `Set-WEM{Resource}.ps1`, `Remove-WEM{Resource}.ps1`
- Support code: Add corresponding helper functions to `JBC.CitrixWEM\Private\` if needed (e.g., data conversion, validation)
- Update: `JBC.CitrixWEM\JBC.CitrixWEM.psd1` to add function names to `FunctionsToExport` array
- Documentation: Add `.md` file to `Docs/` directory with usage examples
- Pattern: Follow `Get-WEMApplication` as template for structure, error handling, SiteId resolution

**New Component/Module:**

- Implementation: `JBC.CitrixWEM\Public\{Verb}-{Noun}.ps1`
- File naming: Always `Verb-Noun.ps1` to maintain consistency
- Exports: Add to `FunctionsToExport` in `JBC.CitrixWEM.psd1`
- Structure: Required signature: function declaration + [CmdletBinding()] + [OutputType()] + param() block + try-catch with Get-WemApiConnection call

**Utilities:**

- Shared helpers: `JBC.CitrixWEM\Private\{Descriptive-Name}.ps1`
- Icon handling: `JBC.CitrixWEM\Private\Convert*IconFormat*.ps1`
- AD lookups: `JBC.CitrixWEM\Private\Get-AD*.ps1`
- Error handling: `JBC.CitrixWEM\Private\Get-ExceptionDetails.ps1`
- Config management: `JBC.CitrixWEM\Private\Update-WEMModuleConfigSetting.ps1`

## Special Directories

**$env:APPDATA\JBC.CitrixWEM/:**
- Purpose: Module runtime configuration persistence
- Generated: Yes, created at module import if doesn't exist
- Committed: No (user-specific)
- Contents: `JBC.CitrixWEM.json` (config file with ShowModuleInfo, ActiveSiteId)

**.planning/codebase/:**
- Purpose: GSD orchestrator documentation (ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md)
- Generated: Yes, by GSD mapping agents
- Committed: Yes (tracked in git)
- Contents: Analysis documents for code planning and execution

**Docs/:**
- Purpose: User-facing guides and examples
- Generated: No (manually maintained)
- Committed: Yes (tracked in git)
- Contents: Markdown files with copy-paste-ready examples

---

*Structure analysis: 2026-01-28*
