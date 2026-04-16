## Connecting to Citrix WEM via PowerShell

This document outlines the process of connecting to the Citrix WEM environment. OnPrem or DaaS, both can be connected to using the same PowerShell module.

---

### Importing the WEM Module

Import the WEM module to interact with the WEM API
```powershell
Import-Module "JBC.CitrixWEM" -Force
```

### Connecting to the WEM Server OnPrem

To connect to an on-premise environment, we need the address of the WEM server or loadbalance VIP. And credentials to connect to it.
Authenticate and connect to the WEM Service or server. Create a credential object
```powershell
$Credential = Get-Credential -Message "Enter the credentials for the WEM Environment"
```

Define the WEM server address
```powershell
$WEMServer = "https://wem.domain.com"
```

Now we are ready to connect to the WEM server
```powershell
Connect-WEMApi -WEMServer $WEMServer -Credential $Credential [-IgnoreCertificateErrors]
```

### Connecting to the WEM Services (Using the SDK)

Just run the following command, a popup will be shown where you can enter your credentials.
```powershell
Connect-WEMApi [-CustomerId <CustomerID>]
```

### Connecting to the WEM Services (Using API Credentials)

Another option you'll have is to specify API (Service principal) credentials.
```powershell
$CustomerID = "abc12d3efghi"
$ClientID = "12345678-90ab-cdef-1234-567890abcdef"
$ClientSecret = "supers3cret"
Connect-WEMApi -CustomerId $CustomerID -ClientId $ClientID -ClientSecret $ClientSecret
```

### Connected, what now...

When you are connected, You'll be greeted with a message:
```
To make changes to a configuration set, make sure you select one using
Set-WEMActiveConfigurationSite -Id <Configuration Set ID>

You can view all available configuration sets by running:
Get-WemConfigurationSite.

NOTE: To suppress this message in the future run: Set-WEMModuleConfiguration -ShowWEMApiInfo $false
```

As described, you can disable this message to be shown in the future by disabling it:
```powershell
Set-WEMModuleConfiguration -ShowWEMApiInfo $false
```

Next you can configure general settings. But if you want to add, change or remove actions in a Configuration Site, you must specify or set a active Configuration Site.
To list the Configuration Sites:
```powershell
Get-WEMConfigurationSite | Format-Table
```

You can use your selected Configuration Site ID by specifying the SiteID parameter for each command:
```powershell
Get-WEMApplication -SiteId <SiteID>
```

You can also set an active site so you don't have to specify it:
```powershell
Set-WEMActiveConfigurationSite -Id <SiteID>
```

Next you can run your actions, when finished you can choose to disconnect from the WEM server:
```powershell
Disconnect-WEMApi
```
