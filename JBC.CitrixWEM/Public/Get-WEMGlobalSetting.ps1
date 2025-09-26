function Get-WEMGlobalSetting {
    <#
    .SYNOPSIS
        Retrieves the global settings for the WEM environment.
    .DESCRIPTION
        This function retrieves the global parameters and settings for the entire WEM deployment.
        It works for both Cloud and On-Premises connections.
        Requires an active session established by Connect-WemApi.
    .EXAMPLE
        PS C:\> Get-WEMGlobalSetting

        Returns an object containing the global WEM settings.
    .NOTES
        Version:        1.0
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

        # The UriPath is the same for both Cloud and On-Premises.
        $UriPath = "services/wem/globalparameters"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # This API call returns the settings object directly.
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Global Settings: $($_.Exception.Message)"
        return $null
    }
}