function Remove-WEMNetworkDriveAssignment {
    <#
    .SYNOPSIS
        Removes one or more WEM network drive assignments.
    .DESCRIPTION
        This function removes one or more WEM network drive assignments based on their unique ID.
        This is a destructive operation and should be used with caution.
    .PARAMETER Id
        The unique ID (or an array of IDs) of the network drive assignment(s) to remove.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Remove-WEMNetworkDriveAssignment -Id 72

        Removes the network drive assignment with ID 72 after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMNetworkDriveAssignment -SiteId 1 | Where-Object { $_.driveLetter -eq 'Z' } | Remove-WEMNetworkDriveAssignment -WhatIf

        Shows which assignments for the Z: drive in Site 1 would be removed, without actually removing them.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-25
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [int[]]$Id
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $TargetDescription = "Network Drive Assignment(s) with ID(s): $($Id -join ', ')"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Remove")) {
            $Body = @{
                idList = $Id
            }

            # The UriPath is the same for both Cloud and On-Premises.
            $UriPath = "services/wem/action/networkDriveAssignment"

            Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
            Write-Verbose "Successfully sent request to remove $($TargetDescription)"
        }
    } catch {
        Write-Error "Failed to remove WEM Network Drive Assignment(s) with ID(s) '$($Id -join ', ')': $($_.Exception.Message)"
    }
}