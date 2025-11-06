function Remove-WEMApplication {
    <#
    .SYNOPSIS
        Removes one or more WEM application actions.
    .DESCRIPTION
        This function removes one or more WEM application actions based on their unique ID.
        This is a destructive operation and should be used with caution. Note that removing
        an application action will also remove all associated assignments.
    .PARAMETER Id
        The unique ID (or an array of IDs) of the application action(s) to remove.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Remove-WEMApplication -Id 698

        Removes the WEM application with ID 698 after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMApplication -DisplayName "Old Application" | Remove-WEMApplication

        Finds the application named "Old Application" and removes it via the pipeline.
    .EXAMPLE
        PS C:\> Remove-WEMApplication -Id 698,699,700 -Confirm:$false

        Removes multiple applications by their IDs without prompting for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMApplication | Where-Object { $_.state -eq "Disabled" } | Remove-WEMApplication -WhatIf

        Shows which disabled applications would be removed, without actually removing them.
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

        if ($PSCmdlet.ShouldProcess("Application(s) with ID(s): $($Id -join ', ')", "Remove")) {
            $Body = @{
                idList = $Id
            }

            $UriPath = "services/wem/webApplications"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
            Write-Verbose "Successfully sent request to remove application(s) with ID(s): $($Id -join ', ')"
            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to remove WEM Application(s) with ID(s) '$($Id -join ', ')': $($_.Exception.Message)"
    }
}
