function Get-WEMAdminPreference {
    <#
    .SYNOPSIS
        Retrieves the administrator preferences for the WEM console.
    .DESCRIPTION
        This function retrieves settings related to the administrator's console preferences,
        such as auto-login settings and port numbers.
        Requires an active session established by Connect-WemApi.
    .EXAMPLE
        PS C:\> Get-WEMAdminPreference

        Returns an object containing the administrator preference settings.
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
        $UriPath = "services/wem/adminPreference"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # This API call returns the settings object directly.
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Administrator Preferences: $($_.Exception.Message)"
        return $null
    }
}