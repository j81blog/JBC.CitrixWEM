function Remove-WEMPrinter {
    <#
    .SYNOPSIS
        Removes one or more WEM printer actions.
    .DESCRIPTION
        This function removes one or more WEM printer actions based on their unique ID.
        This is a destructive operation.
    .PARAMETER Id
        The unique ID (or an array of IDs) of the printer action(s) to remove.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Remove-WEMPrinter -Id 132

        Removes the WEM printer with ID 132 after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMPrinter -Id 132 | Remove-WEMPrinter -Force

        Finds the printer with ID 132 and removes it without asking for confirmation.
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

        if ($PSCmdlet.ShouldProcess("Printers with ID(s): $($Id -join ', ')", "Remove")) {
            $Body = @{
                idList = $Id
            }

            $UriPath = "services/wem/webPrinter"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
            Write-Verbose "Successfully sent request to remove printer(s) with ID(s): $($Id -join ', ')"
            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to remove WEM Printer(s) with ID(s) '$($Id -join ', ')': $($_.Exception.Message)"
    }
}