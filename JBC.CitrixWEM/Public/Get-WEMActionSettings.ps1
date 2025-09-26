function Get-WEMActionSettings {
    <#
    .SYNOPSIS
        Retrieves advanced action settings from a WEM Configuration Set.
    .DESCRIPTION
        This function gets the advanced settings related to actions from a specified WEM Configuration Set (Site).
        Requires an active session established by Connect-WemApi.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query. This is required for both Cloud and On-Premises.
    .EXAMPLE
        PS C:\> Get-WEMActionSettings -SiteId 1

        Retrieves the action settings for the Configuration Set with ID 1.
    .NOTES
        Version:        1.4
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-05
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $ResolvedSiteId = 0
        if ($PSBoundParameters.ContainsKey('SiteId')) {
            $ResolvedSiteId = $SiteId
        } elseif ($Connection.ActiveSiteId) {
            $ResolvedSiteId = $Connection.ActiveSiteId
            Write-Verbose "Using active Configuration Set '$($Connection.ActiveSiteName)' (ID: $ResolvedSiteId)"
        } else {
            throw "No -SiteId was provided, and no active Configuration Set has been set. Please use Set-WEMActiveConfigurationSite or specify the -SiteId parameter."
        }

        # The UriPath is the same for both Cloud and On-Premises.
        $UriPath = "services/wem/advancedSetting/actionSettings?siteId=$($ResolvedSiteId)"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # This specific API call does not nest its result in an 'Items' property.
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Action Settings for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}