function Remove-WEMPrinterAssignment {
    <#
    .SYNOPSIS
        Removes one or more WEM printer assignments.
    .DESCRIPTION
        This function removes one or more WEM printer assignments based on their unique ID.
        This is a destructive operation and should be used with caution.
    .PARAMETER Id
        The unique ID (or an array of IDs) of the printer assignment(s) to remove.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Remove-WEMPrinterAssignment -Id 123

        Removes the printer assignment with ID 123 after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMPrinterAssignment -SiteId 1 | Where-Object { $_.isDefault -eq $false } | Remove-WEMPrinterAssignment -WhatIf

        Shows which printer assignments in Site 1 are not default printers and would be removed, without actually removing them.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-22
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [int[]]$Id
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $TargetDescription = "Printer Assignment(s) with ID(s): $($Id -join ', ')"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Remove")) {
            $Body = @{
                idList = $Id
            }

            # The UriPath is the same for both Cloud and On-Premises.
            $UriPath = "services/wem/printerAssignment"

            Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
            Write-Verbose "Successfully sent request to remove $($TargetDescription)"
        }
    } catch {
        Write-Error "Failed to remove WEM Printer Assignment(s) with ID(s) '$($Id -join ', ')': $($_.Exception.Message)"
    }
}