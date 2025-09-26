function Get-WEMExternalServiceSetting {
    <#
    .SYNOPSIS
        Retrieves the external service settings from WEM.
    .DESCRIPTION
        This function retrieves settings related to external services, such as the Citrix DaaS (formerly CVAD)
        and Microsoft SCCM integration. It works for both Cloud and On-Premises connections.
        Requires an active session established by Connect-WemApi.
    .EXAMPLE
        PS C:\> Get-WEMExternalServiceSetting

        Returns an object containing the external service settings.
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
        $UriPath = "services/wem/externalServiceSettings"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # This API call returns the settings object directly.
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM External Service Settings: $($_.Exception.Message)"
        return $null
    }
}