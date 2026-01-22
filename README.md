# JBC.CitrixWEM

Citrix WEM PowerShell module based on WEM API

## Installation FromGitHub

Use the following PowerShell command to install the latest (GitHub) version from the git `main` branch. This method assumes a default [`PSModulePath`](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_psmodulepath) environment variable and installs to the CurrentUser scope.

```powershell
iex (irm https://raw.githubusercontent.com/j81blog/JBC.CitrixWEM/refs/heads/main/Install-ModuleFromGithubMain.ps1)
```

## Usage Example documentation

* [Connecting to WEM](Docs/ConnectToWEMEnvironment.md)
* [Create Applications And Assignment](Docs/CreateApplicationsAndAssignment.md)
* [Create Network Drive And Assignment](Docs/CreateNetworkDriveAndAssignment.md)
* [Create Printer Assignment](Docs/CreatePrinterAssignment.md)
* [Create File Type Associations](Docs/CreateFileTypeAssociations.md)
* [Export-FileIcon](Docs/Export-FileIcon.md)
* [Create Applications and assignments from existing shortcuts](Docs/CreateApplicationsFromShortcuts.md)
* [Update Application Icons](Docs/UpdateApplicationIcons.md)
