function Remove-WEMApplicationAssignment {
    <#
    .SYNOPSIS
        Removes one or more WEM application assignments.
    .DESCRIPTION
        This function removes one or more WEM application assignments based on their unique ID.
        This is a destructive operation and should be used with caution.
    .PARAMETER Id
        The unique ID (or an array of IDs) of the application assignment(s) to remove.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Remove-WEMApplicationAssignment -Id 247

        Removes the application assignment with ID 247 after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMApplicationAssignment -SiteId 1 | Where-Object { $_.resourceId -eq 123 } | Remove-WEMApplicationAssignment

        Removes all assignments for the application with resource ID 123 from Site 1.
    .EXAMPLE
        PS C:\> Remove-WEMApplicationAssignment -Id 247,248,249 -Confirm:$false

        Removes multiple application assignments by their IDs without prompting for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMApplicationAssignment -SiteId 1 | Where-Object { $_.targetName -eq "Domain Users" } | Remove-WEMApplicationAssignment -WhatIf

        Shows which application assignments for the "Domain Users" group would be removed, without actually removing them.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Claude
        Creation Date:  2025-11-06
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [int[]]$Id
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $TargetDescription = "Application Assignment(s) with ID(s): $($Id -join ', ')"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Remove")) {
            $Body = @{
                idList = $Id
            }

            # The UriPath is the same for both Cloud and On-Premises.
            $UriPath = "services/wem/applicationAssignment"

            Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
            Write-Verbose "Successfully sent request to remove $($TargetDescription)"
        }
    } catch {
        Write-Error "Failed to remove WEM Application Assignment(s) with ID(s) '$($Id -join ', ')': $($_.Exception.Message)"
    }
}
