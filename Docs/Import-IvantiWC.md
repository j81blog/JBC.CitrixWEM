## Importing Ivanti Workspace Control Building Blocks into Citrix WEM

This document describes how to use the `Import-IvantiWC*` functions to migrate resources from an Ivanti Workspace Control (IWC) Building Block XML file into Citrix Workspace Environment Management (WEM).

---

### Prerequisites

Export a building block as a single XML file.

Establish a WEM API connection before running any import. Follow the [Connecting to WEM](ConnectToWEMEnvironment.md) guide.

```powershell
Connect-WEMApi -Server 'wem.domain.local'
Set-WEMActiveDomain -DomainName 'domain.local'
#Optional retrieval of sites
Get-WEMConfigurationSite | Format-Table
Set-WEMActiveConfigurationSite -SiteId 1
```

---

### Import-IvantiWCApplication

Imports Ivanti Workspace Control applications into Citrix WEM as Application actions. Each enabled application is created via `New-WEMApplication` and assigned to its AD targets. Assignment targets that do not yet exist in WEM are created automatically. Disabled applications are skipped.

**Import all enabled applications:**

```powershell
Import-IvantiWCApplication -XmlFilePath 'C:\temp\LAB-BB.xml'
```

**Select which applications to import via a Graphical selection window:**

```powershell
Import-IvantiWCApplication -XmlFilePath 'C:\temp\LAB-BB.xml' -GUI
```

---

### Import-IvantiWCEnvironmentVariable

Imports Ivanti Workspace Control environment variables into Citrix WEM as Environment Variable actions. Each enabled variable is created via `New-WEMEnvironmentVariable` and assigned to its AD targets. Disabled variables are skipped.

**Import all enabled environment variables:**

```powershell
Import-IvantiWCEnvironmentVariable -XmlFilePath 'C:\temp\LAB-BB.xml'
```

**Select which environment variables to import via a Graphical selection window:**

```powershell
Import-IvantiWCEnvironmentVariable -XmlFilePath 'C:\temp\LAB-BB.xml' -GUI
```

---

### Import-IvantiWCNetworkDrive

Imports Ivanti Workspace Control network drives into Citrix WEM as Network Drive actions. Each enabled drive is created via `New-WEMNetworkDrive` and assigned to its AD targets. Disabled drives are skipped.

**Import all enabled network drives:**

```powershell
Import-IvantiWCNetworkDrive -XmlFilePath 'C:\temp\LAB-BB.xml'
```

**Select which network drives to import via a Graphical selection window:**

```powershell
Import-IvantiWCNetworkDrive -XmlFilePath 'C:\temp\LAB-BB.xml' -GUI
```

---

### Import-IvantiWCPolicy

Imports Ivanti Workspace Control policy sets into Citrix WEM as Group Policy Objects (GPOs). Each enabled policy set is created via `New-WEMGroupPolicyObject` and assigned to its AD targets. Policy sets with no registry operations and disabled sets are skipped. If a GPO with the same name already exists in WEM the item is skipped with an error.

**Import all enabled policy sets:**

```powershell
Import-IvantiWCPolicy -XmlFilePath 'C:\temp\LAB-BB.xml'
```

**Select which policy sets to import via a Graphical selection window:**

```powershell
Import-IvantiWCPolicy -XmlFilePath 'C:\temp\LAB-BB.xml' -GUI
```

---

### Import-IvantiWCPrinterMapping

Imports Ivanti Workspace Control printer mappings into Citrix WEM as Printer actions. Each enabled printer mapping is created via `New-WEMPrinter` and assigned to its AD targets. Disabled mappings are skipped.

**Import all enabled printer mappings:**

```powershell
Import-IvantiWCPrinterMapping -XmlFilePath 'C:\temp\LAB-BB.xml'
```

**Select which printer mappings to import via a Graphical selection window:**

```powershell
Import-IvantiWCPrinterMapping -XmlFilePath 'C:\temp\LAB-BB.xml' -GUI
```

---

### Import-IvantiWCRegistry

Imports Ivanti Workspace Control registry sets into Citrix WEM as Group Policy Objects (GPOs). Each enabled registry set is created via `New-WEMGroupPolicyObject` and assigned to its AD targets. Registry sets with no operations and disabled sets are skipped. If a GPO with the same name already exists in WEM the item is skipped with an error.

**Import all enabled registry sets:**

```powershell
Import-IvantiWCRegistry -XmlFilePath 'C:\temp\LAB-BB.xml'
```

**Select which registry sets to import via a Graphical selection window:**

```powershell
Import-IvantiWCRegistry -XmlFilePath 'C:\temp\LAB-BB.xml' -GUI
```

---

### Notes

- All functions require an active WEM API connection (`Connect-WEMApi`).
- If no `-SiteId` is provided, the active Configuration Set set via `Set-WEMActiveConfigurationSite` is used.
- The `-GUI` switch opens a GUI selection window, allowing you to pick specific items before the import begins.
- AD assignment targets referenced in the building block are resolved automatically and created in WEM if they do not already exist.
