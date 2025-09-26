function Remove-WEMAssignmentTarget {
    <#
    .SYNOPSIS
        Removes one or more WEM assignment targets.
    .DESCRIPTION
        This function removes one or more WEM assignment targets (like AD users or groups) based on their unique ID.
        This is a destructive operation and should be used with caution.
    .PARAMETER Id
        The unique ID (or an array of IDs) of the assignment target(s) to remove.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Remove-WEMAssignmentTarget -Id 63

        Removes the WEM assignment target with ID 63 after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMAssignmentTarget -SiteId 19 | Where-Object { $_.Name -like "*Obsolete*" } | Remove-WEMAssignmentTarget -WhatIf

        Shows which assignment targets containing "Obsolete" would be removed, without actually removing them.
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-07
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [int[]]$Id
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $TargetDescription = "Assignment Target(s) with ID(s): $($Id -join ', ')"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Remove")) {
            $Body = @{
                idList = $Id
            }

            $UriPath = "services/wem/assignmentTarget"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
            Write-Verbose "Successfully sent request to remove $($TargetDescription)"
            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to remove WEM Assignment Target(s) with ID(s) '$($Id -join ', ')': $($_.Exception.Message)"
    }
}