# JBC.CitrixWEM

[![Validate](https://github.com/j81blog/JBC.CitrixWEM/actions/workflows/validate.yml/badge.svg)](https://github.com/j81blog/JBC.CitrixWEM/actions/workflows/validate.yml)
[![Publish](https://github.com/j81blog/JBC.CitrixWEM/actions/workflows/publish.yml/badge.svg)](https://github.com/j81blog/JBC.CitrixWEM/actions/workflows/publish.yml)
[![PSGallery Version](https://img.shields.io/powershellgallery/v/JBC.CitrixWEM)](https://www.powershellgallery.com/packages/JBC.CitrixWEM)
[![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/JBC.CitrixWEM)](https://www.powershellgallery.com/packages/JBC.CitrixWEM)

A PowerShell module for managing Citrix Workspace Environment Management (WEM) via the WEM REST API. Supports both Citrix Cloud and On-Premises deployments.

## Installation

### From PowerShell Gallery (recommended)

```powershell
Install-Module -Name JBC.CitrixWEM -Scope CurrentUser
```

### From GitHub (latest dev build)

```powershell
iex (irm https://raw.githubusercontent.com/j81blog/JBC.CitrixWEM/refs/heads/main/Install-ModuleFromGithubMain.ps1)
```

## Requirements

- PowerShell 5.1 or later
- Citrix Cloud account or Citrix WEM On-Premises deployment
- WEM API access

## Quick Start

```powershell
# Connect to Citrix Cloud WEM
Connect-WEMApi -CustomerId 'your-customer-id'

# Connect to Citrix WEM On-Premises
$Credential = Get-Credential
Connect-WEMApi -WEMServer https://wem.domain.local -Credential $credential

# List all Configuration Sets
Get-WEMConfigurationSite

# Get all applications in a Configuration Set
Get-WEMApplication -SiteId 1
```

## Usage Examples

- [Connecting to WEM](Docs/ConnectToWEMEnvironment.md)
- [Create Applications And Assignment](Docs/CreateApplicationsAndAssignment.md)
- [Create Network Drive And Assignment](Docs/CreateNetworkDriveAndAssignment.md)
- [Create Printer Assignment](Docs/CreatePrinterAssignment.md)
- [Create File Type Associations](Docs/CreateFileTypeAssociations.md)
- [Export-FileIcon](Docs/Export-FileIcon.md)
- [Create Applications and assignments from existing shortcuts](Docs/CreateApplicationsFromShortcuts.md)
- [Update Application Icons](Docs/UpdateApplicationIcons.md)

## Contributing

Contributions are welcome. Please open an issue or submit a pull request.

## License

This project is licensed under the terms of the [LICENSE](LICENSE) file.
