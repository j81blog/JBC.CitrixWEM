function Get-WEMSharedStorage {
    <#
    .SYNOPSIS
        Retrieves the shared storage settings for the WEM deployment.
    .DESCRIPTION
        This function retrieves the configuration for the shared storage location used by the
        WEM infrastructure services. It works for both Cloud and On-Premises connections.
    .EXAMPLE
        PS C:\> Get-WEMSharedStorage

        Returns an object containing the shared storage settings.
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-08
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        # Determine the correct API path for Cloud or On-Premises.
        if ($Connection.IsOnPrem) {
            $UriPath = "services/wem/onPrem/sharedStorage"
        } else {
            $UriPath = "services/wem/forward/sharedStorage"
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # This API call returns the settings object directly.
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Shared Storage settings: $($_.Exception.Message)"
        return $null
    }
}