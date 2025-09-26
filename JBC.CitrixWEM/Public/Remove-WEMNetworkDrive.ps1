function Remove-WEMNetworkDrive {
    <#
    .SYNOPSIS
        Removes one or more WEM network drive actions.
    .DESCRIPTION
        This function removes one or more WEM network drive actions based on their unique ID.
        This is a destructive operation and should be used with caution.
    .PARAMETER Id
        The unique ID (or an array of IDs) of the network drive action(s) to remove.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Remove-WEMNetworkDrive -Id 32

        Removes the network drive action with ID 32 after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMNetworkDrive -SiteId 1 | Where-Object { $_.Name -like "*Legacy*" } | Remove-WEMNetworkDrive -WhatIf

        Shows which network drive actions containing "Legacy" in their name would be removed, without actually removing them.
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

        $TargetDescription = "Network Drive Action(s) with ID(s): $($Id -join ', ')"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Remove")) {
            $Body = @{
                idList = $Id
            }

            # The UriPath is the same for both Cloud and On-Premises.
            $UriPath = "services/wem/action/networkDrives"

            Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
            Write-Verbose "Successfully sent request to remove $($TargetDescription)"
        }
    } catch {
        Write-Error "Failed to remove WEM Network Drive Action(s) with ID(s) '$($Id -join ', ')': $($_.Exception.Message)"
    }
}