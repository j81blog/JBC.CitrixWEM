## Create and migrate a Citrix WEM Application via PowerShell

This document outlines the process of assigning an application to an Active Directory (AD) group within Citrix Workspace Environment Management (WEM) using a PowerShell script. The script leverages a custom module (`JBC.CitrixWEM`) to interact with the WEM API.

---

### 1. Initial Setup and Connection

First, the script sets up the environment. It imports the necessary custom PowerShell module and establishes a connection to the WEM API. It then specifies which WEM **Configuration Site** and **Domain** to work with.

```powershell
# Import the custom module to interact with the WEM API
Import-Module "JBC.CitrixWEM" -Force

# Authenticate and connect to the WEM Service or server
# 1. OnPrem:
Connect-WEMApi -WEMServer "https://<WEM Server FQDN>" -Credential <Your WEM Credential>

# 2. Citrix Cloud (Web Credentials):
Connect-WEMApi [-CustomerId <CustomerID>]

# 3. Citrix Cloud (API Credentials):
Connect-WEMApi -CustomerId <CustomerID> -ClientId <ClientID> -ClientSecret <Secret>

#List the Configuration Sites
Get-WEMConfigurationSite

# Set the active configuration site by its ID
Set-WEMActiveConfigurationSite -Id <SiteID>

# Set the active domain
Set-WEMActiveDomain
```

### 2. Define Key Variables
The following two variables will contain the necessary details to create and assign an application:

```powershell
# The Application parameters
$ApplicationParams = @{
    startMenuPath = "Start Menu\Programs"
    appType       = "InstallerApplication"
    state         = "Enabled"
    iconStream    = $(Export-FileIcon -FilePath "C:\Program Files\7-Zip\7zFM.exe" -Size 32 -AsBase64)
    parameter     = ""
    description   = "7-Zip File Manager"
    name          = "7-Zip"
    commandLine   = "C:\Program Files\7-Zip\7zFM.exe"
    workingDir    = "C:\Program Files\7-Zip"
    displayName   = "7-Zip"
    WindowStyle   = "Normal"
    ActionType    = "CreateAppShortcut"
}

# The sAMAccountName of the Active Directory group
$ADGroupName = "<AD Group Name>"
```

### 3. Locate the Application in WEM
Before assigning the application, we must confirm it exists in WEM. It retrieves all applications and filters the list to find the specific one by name. If the application is not found, we must throw an error and stop the actions.

```powershell
# Retrieve all applications and filter for the one matching $ApplicationParams.name
$WEMApplication = Get-WEMApplication | Where-Object { $_.name -ieq $ApplicationParams.name }

# If the application object is found, display an error and exit.
if ($WEMApplication.name -ieq $ApplicationParams.name) {
    Write-Error "Application $($ApplicationParams.name) already exists in WEM"
    return
}
```

### 4. Create the application
Now we are ready to create the application with the specifies parameters.
I added the SelfHealing option separate, but you could also add it to the initial parameters.

```PowerShell
#Create a new application
$WEMApplication = New-WEMApplication @ApplicationParams -SelfHealing $true -PassThru
```

### 5. Locate or Create the Assignment Target (AD Group)
WEM assigns resources to "Assignment Targets," which can be users or groups. This section checks if the specified AD group already exists as an assignment target in WEM. If not, it finds the group in Active Directory and adds it to WEM.

```powershell
# Get the forest and domain details required for naming conventions
$Forest = Get-WEMADForest
$Domain = Get-WEMADDomain -ForestName $Forest.forestName

# Construct the fully qualified name that WEM uses to identify the group
$WEMAssignmentTargetGroupName = '{0}/{1}/{2}' -f $Forest.forestName, $Domain.domainName, $ADGroupName

# Check if the group already exists as an assignment target in WEM
$WEMAssignmentTarget = Get-WEMAssignmentTarget | Where-Object { $_.name -ieq $WEMAssignmentTargetGroupName -or $_.name -ieq $ADGroupName }

# If the assignment target does not exist, it must be created
if (-not $WEMAssignmentTarget) {
    # Find the group in Active Directory using the WEM cmdlets
    # The Where-Object ensures an exact match on the account name
    $ADGroup = Get-WEMADGroup -Filter $ADGroupName | Where-Object { $_.AccountName -ieq $ADGroupName }

    # Create a new assignment target in WEM using the AD group's properties
    # The -PassThru parameter outputs the newly created object to the pipeline
    $WEMAssignmentTarget = New-WEMAssignmentTarget -Sid $ADGroup.Sid -Name $ADGroup.AccountName -ForestName $ADGroup.ForestName -DomainName $ADGroup.DomainName -Type $ADGroup.Type -PassThru
}
```

### 6. Create the Application Assignment
With both the application object ($WEMApplication) and the assignment target object ($WEMAssignmentTarget) identified or created, we can create the actual assignment, linking the two together.

```powershell
# Assign the application to the target group, and add to the startmenu
$WEMApplicationAssignment = New-WEMApplicationAssignment -Target $WEMAssignmentTarget -Application $WEMApplication -IsStartMenu -PassThru
```

### 7. (Optional) Remove the Assignment
For completeness, the following includes the command to remove a application assignment. In a real-world scenario, this would be used for de-provisioning, not immediately after creating an assignment. It demonstrates how to reverse the action using the assignment's unique ID.

```powershell
# This command removes the assignment that was just created
Remove-WEMApplicationAssignment -Id $WEMApplicationAssignment.id
```

### 8. (Optional) Remove the Application
For completeness, the following includes the command to remove a application. In a real-world scenario, this would be used for de-provisioning, not immediately after creating an application. It demonstrates how to reverse the action using the applications's unique ID.

```powershell
# This command removes the assignment that was just created
Remove-WEMApplication -Id $WEMApplication.id
```

### 9. Example
This example extracts details from a user GPO or Ivanti Workspace Control and creates the application(s) in WEM with the assignment.

```PowerShell
#Specify the GPO Name
$GpoName = "The Name of the GPO containing the Shortcuts"

#OPTION 1 GPO: Read the shortcuts
$Applications = Get-GppShortcut -GpoName $GpoName

#Optional, save to Json and import on other machine
Get-GppShortcut -GpoName $GpoName -AsJson -AsJson | Out-File -FilePath "path\to\applications.json"
#Import from JSON to continue
$Applications = Get-Content "path\to\applications.json" -Raw | ConvertFrom-Json

#OPTION 2 Ivanti Workspace Control
$Applications = Get-IvantiWCApplication -XmlFilePath "path\to\iwc_bb.xml"
#If you have multiple (per application) building blocks (experimental)
$Applications = Get-IvantiWCApplication -XmlPath "path\to\buildingblocks"

#Optional, save to Json and import on other machine
Get-IvantiWCApplication -XmlFilePath "path\to\iwc_bb.xml" -AsJson | Out-File -FilePath "path\to\applications.json"
#Import from JSON to continue
$Applications = Get-Content "path\to\applications.json" -Raw | ConvertFrom-Json

Import-Module "JBC.CitrixWEM" -Force

#Cloud: Specify the customer ID (or leave and a you will be presented with a selection)
$CustomerID = "abc12d3efghi"
Connect-WEMApi -CustomerId $CustomerID

#OnPrem: Specify the Server fqdn and Credentials
$WEMServer = "https://citrixwem.domain.local"
$WEMCredential = Get-Credential
Connect-WEMApi -WEMServer $WEMServer -Credential $WEMCredential

# To view the Configuration Site(s) to retrieve the ID
Get-WEMConfigurationSite | Format-Table

#Set the Active Configuration Site
$SiteId = 1
Set-WEMActiveConfigurationSite -Id $SiteId

#The following code will add the Applications to WEM, it will maintain a result if an item was successful or was failed.
#You can run the code again and again, only not yet processed or failed items will be created again.

Write-Host "We got $($Applications.count) applications"
foreach ( $Application in $Applications ) {
    if ($Application.Success -and $Application.Success -eq $true) {
        continue
    }
    $Params = $Application.WEMApplicationParams | ConvertTo-Hashtable
    $Forest = (Get-WEMActiveDomain).Forest
    $Domain = (Get-WEMActiveDomain).Domain
    #if (-not ($Application.Enabled -eq $true)) {
    #    Write-Host "Skipping Application, Application entry `"$($Application.Name)`" is not enabled" -ForegroundColor Yellow
    #    continue
    #}

    if (-not $Forest -or -not $Domain) {
        Write-Error "Unable to retrieve Active Directory domain information from WEM. Please ensure you are connected to the WEM API and that the Active Directory domain is properly configured."
        return
    }
    try {
        Write-Verbose "Creating new WEM application $($Application.Name)"
        try {
            $WEMApplication = New-WEMApplication @Params -SelfHealing $true -PassThru
            Write-Host "Succesfully created the application `"$($Application.Name)`"" -ForegroundColor Green
        } catch {
            Write-Host "Error creating WEM application $($Application.Name), Error $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "At Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
            Write-Host "Script Name: $($_.InvocationInfo.ScriptName)" -ForegroundColor Red
            $Application | Add-Member -MemberType NoteProperty -Name "Success" -Value $false -Force
            continue
        }
        # Check if Application was created
        if (-not $WEMApplication) {
            Write-Error "Application $($Application.Name) not found in WEM"
            return
        } else {
            Write-Host "WEM application $($WEMApplication.Name) with path $($WEMApplication.TargetPath) created successfully." -ForegroundColor Green
        }

        foreach ($WEMAssignment in $Application.WEMAssignments) {
            if ($WEMAssignment.Name -like "*\*") {
                $ADObjectName = $WEMAssignment.Name.Split('\')[-1]
            } else {
                $ADObjectName = $WEMAssignment.Name
            }
            $WEMAssignmentTargetGroupName = '{0}/{1}/{2}' -f $Forest, $Domain, $ADObjectName
            $WEMAssignmentTarget = Get-WEMAssignmentTarget | Where-Object { $_.name -ieq $WEMAssignmentTargetGroupName -or $_.name -ieq $WEMAssignment.Name -or $_.sid -ieq $WEMAssignment.Sid }
            if (-not $WEMAssignmentTarget) {
                # Find the group or user in Active Directory using the WEM cmdlets
                # The Where-Object ensures an exact match on the account name
                if ($WEMAssignment.Type -ieq "user") {
                    $ADObject = Get-WEMADUser -Filter $ADObjectName -ErrorAction SilentlyContinue | Where-Object { $_.AccountName -ieq $ADObjectName -or $_.Name -like "*/*/$ADObjectName" }
                    if ([String]::IsNullOrEmpty($ADObject)) {
                        Write-Host "Could not find user with name `"$($ADObjectName)`""
                        Write-Warning "Known issue, we are looking at this issue"
                        continue
                    }
                } else {
                    $ADObject = Get-WEMADGroup -Filter $ADObjectName -ErrorAction SilentlyContinue | Where-Object { $_.AccountName -ieq $ADObjectName -or $_.Name -like "*/*/$ADObjectName" }
                    if ([String]::IsNullOrEmpty($ADObject)) {
                        <# There seems to be a bug with log group names#>
                        $MaxLength = "$($ADObjectName)".Length
                        if ($MaxLength -gt 23) {
                            $MaxLength = 23
                        }
                        $ADObjectAlternativeSearch = "$($ADObjectName)".Substring(0, $MaxLength)
                        $ADObject = Get-WEMADGroup -Filter $ADObjectAlternativeSearch | Where-Object { $_.AccountName -ieq $ADObjectName -or $_.Name -like "*/*/$ADObjectName" }
                    }
                    if ([String]::IsNullOrEmpty($ADObject)) {
                        Write-Host "Could not find group with name `"$($ADObjectName)`""
                        continue
                    }
                }
                # Create a new assignment target in WEM using the AD group's properties
                # The -PassThru parameter outputs the newly created object to the pipeline
                $WEMAssignmentTarget = New-WEMAssignmentTarget -Sid $ADObject.Sid -Name $ADObject.AccountName -ForestName $ADObject.ForestName -DomainName $ADObject.DomainName -Type $ADObject.Type -PassThru
                Write-Host "Created new WEM assignment target for AD group $($ADObject.Name)"
            } else {
                Write-Host "Found existing WEM assignment target for AD group $($ADObjectName)"
            }
            # Assign the application to the target group
            $WEMAssignmentParams = $Application.WEMAssignmentParams | ConvertTo-Hashtable
            $WEMApplicationAssignment = New-WEMApplicationAssignment -Target $WEMAssignmentTarget -Application $WEMApplication -PassThru @WEMAssignmentParams
            if ($WEMApplicationAssignment) {
                Write-Host "Successfully created WEM application assignment for $($WEMAssignment.Name)" -ForegroundColor Green
            } else {
                Write-Error "Failed to create WEM application assignment for $($WEMAssignment.Name)"
            }
        }
        $Application | Add-Member -MemberType NoteProperty -Name "Success" -Value $true -Force
    } catch {
        $Application | Add-Member -MemberType NoteProperty -Name "Success" -Value $false -Force
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "At Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        Write-Host "Script Name: $($_.InvocationInfo.ScriptName)" -ForegroundColor Red
        Write-Host "Category: $($_.CategoryInfo.Category)" -ForegroundColor Red
        Write-Host "FullyQualifiedErrorId: $($_.FullyQualifiedErrorId)" -ForegroundColor Red
        continue
    }
}
```
