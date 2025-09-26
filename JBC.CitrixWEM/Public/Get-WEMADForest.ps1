function Get-WEMADForest {
    <#
    .SYNOPSIS
        Retrieves the configured Active Directory forests from WEM.
    .DESCRIPTION
        This function retrieves a list of the Active Directory forests that are registered and recognized
        by the WEM service. It automatically selects the correct API endpoint for Cloud or On-Premises.
        Requires an active session established by Connect-WemApi.
    .EXAMPLE
        PS C:\> Get-WEMADForest

        Returns a list of all configured forests.
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-05
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        if ($Connection.IsOnPrem) {
            $UriPath = "services/wem/onPrem/identity/Forests"
        } else {
            $UriPath = "services/wem/forward/identity/Forests"
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # Consistent with other Get-* functions that return a list, return the 'Items' property.
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM AD Forests: $($_.Exception.Message)"
        return $null
    }
}