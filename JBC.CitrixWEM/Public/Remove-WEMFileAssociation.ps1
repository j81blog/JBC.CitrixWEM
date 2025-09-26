function Remove-WEMFileAssociation {
    <#
    .SYNOPSIS
        Removes one or more WEM file association actions.
    .DESCRIPTION
        This function removes one or more WEM file association actions based on their unique ID.
        This is a destructive operation and should be used with caution.
    .PARAMETER Id
        The unique ID (or an array of IDs) of the file association action(s) to remove.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Remove-WEMFileAssociation -Id 3

        Removes the file association action with ID 3 after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMFileAssociation | Where-Object { $_.Name -like "*Old*" } | Remove-WEMFileAssociation -WhatIf

        Shows which file associations with "Old" in their name would be removed, without actually removing them.
    .NOTES
        Function  : Remove-WEMFileAssociation
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [int[]]$Id
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $TargetDescription = "File Association Action(s) with ID(s): $($Id -join ', ')"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Remove")) {
            $Body = @{
                idList = $Id
            }

            # The UriPath is the same for both Cloud and On-Premises.
            $UriPath = "services/wem/action/fileAssociations"

            Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
            Write-Verbose "Successfully sent request to remove $($TargetDescription)"
        }
    } catch {
        Write-Error "Failed to remove WEM File Association Action(s) with ID(s) '$($Id -join ', ')': $($_.Exception.Message)"
    }
}