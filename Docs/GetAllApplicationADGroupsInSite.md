## Get all Application AD groups

Get all actively used AD groups in a configuration set

```PowerShell
$applications = Get-WEMApplication
$assignments = Get-WEMApplicationAssignment
$targets = Get-WEMAssignmentTarget
$ADGroups = @()
foreach ($app in $applications) {
    if ($app.state -eq "Enabled") {
        $ActiveAssignments = $assignments | Where-Object { $_.resourceId -eq $app.Id }
        foreach ($assignment in $ActiveAssignments) {
            $WEMADGroup = $targets | Where-Object { $_.Id -eq $assignment.targetId } | Select-Object -ExpandProperty "name" | Where-Object { $_ -ne $null -and $_ -ne "Everyone" }
            $Objects = $WEMADGroup -split "/"
            if ($Objects.Count -eq 3) {
                $ADGroups += $Objects[2]
            } else {
                $ADGroups += $Objects
            }
        }
    }
}
$ADGroups = $ADGroups | Sort-Object -Unique
```