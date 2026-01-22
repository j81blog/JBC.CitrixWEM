## Assigning a Citrix WEM Printer to an AD Group via PowerShell

This document outlines the process of assigning a printer to an Active Directory (AD) group within Citrix Workspace Environment Management (WEM) using a PowerShell script. The script leverages a custom module (`JBC.CitrixWEM`) to interact with the WEM API.

---

### 1. Initial Setup and Connection

To connect, follow this guide [Connecting to WEM](ConnectToWEMEnvironment.md)

### 2. Define Key Variables

The script defines two main variables: the name of the printer to be assigned and the name of the AD group that will receive the assignment.

```powershell
# The display name of the printer in WEM
$Printername = "<printername>"

# The sAMAccountName of the Active Directory group
$ADGroupName = "<AD Group Name>"
```

### 3. Locate the Printer in WEM

Before assigning the printer, the script confirms it exists in WEM. It retrieves all printers and filters the list to find the specific one by name. If the printer is not found, the script stops and throws an error.

```powershell
# Retrieve all printers and filter for the one matching $Printername
$WEMPrinter = Get-WEMPrinter | Where-Object { $_.name -ieq $Printername }

# If the printer object is not found, display an error and exit
if (-not $WEMPrinter) {
    Write-Error "Printer $Printername not found in WEM"
    return
}
```

### 4. Locate or Create the Assignment Target (AD Group)

WEM assigns resources to "Assignment Targets," which can be users or groups. This section checks if the specified AD group already exists as an assignment target in WEM. If not, it finds the group in Active Directory and adds it to WEM.

```powershell
# Get the forest and domain details required for naming conventions
$Forest = Get-WEMADForest
$Domain = Get-WEMADDomain -ForestName $Forest.forestName

# Construct the fully qualified name that WEM uses to identify the group
$WEMAssignmentTargetGroupName = '{0}/{1}/{2}' -f $Forest.forestName, $Domain.domainName, $ADGroupName

# Check if the group already exists as an assignment target in WEM
$WEMAssignmentTarget = Get-WEMAssignmentTarget | Where-Object { $_.name -ieq $WEMAssignmentTargetGroupName }

# If the assignment target does not exist, it must be created
if (-not $WEMAssignmentTarget) {
    # Find the group in Active Directory using the WEM cmdlets
    # The Where-Object ensures an exact match on the account name
    $ADGroup = Get-WEMADGroup -Filter $ADGroupName | Where-Object { $_.AccountName -ieq $ADGroupName }

    # Create a new assignment target in WEM using the AD group's properties
    # The -PassThru parameter outputs the newly created object to the pipeline
    $WEMAssignmentTarget = New-WEMAssignmentTarget -Sid $ADGroup.Sid -Name $ADGroup.Name -ForestName $ADGroup.ForestName -DomainName $ADGroup.DomainName -Type $ADGroup.Type -PassThru
}
```

### 5. Create the Printer Assignment

With both the printer object ($WEMPrinter) and the assignment target object ($WEMAssignmentTarget) identified or created, the script creates the actual assignment, linking the two together.

```powershell
# Assign the printer to the target group
$WEMPrinterAssignment = New-WEMPrinterAssignment -Target $WEMAssignmentTarget -Printer $WEMPrinter -PassThru
```

### 6. (Optional) Remove the Assignment

For completeness, the code includes the command to remove a printer assignment. In a real-world scenario, this would be used for de-provisioning, not immediately after creating an assignment. It demonstrates how to reverse the action using the assignment's unique ID.

```powershell
# This command removes the assignment that was just created
Remove-WEMPrinterAssignment -Id $WEMPrinterAssignment.id
```