function Get-WEMPersonalizationSetting {
    <#
    .SYNOPSIS
        Retrieves the personalization settings (UI Agent settings) for a WEM Configuration Set.
    .DESCRIPTION
        This function retrieves the UI Agent personalization settings for a specific WEM Configuration Set (Site).
        These settings control the appearance and behavior of the WEM UI Agent, including splash screen,
        theme, colors, and other visual customization options.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query. If not specified, uses the active site.
    .EXAMPLE
        PS C:\> Get-WEMPersonalizationSetting -SiteId 16

        Returns an object containing the personalization settings for the Configuration Set with ID 16.
    .EXAMPLE
        PS C:\> Get-WEMPersonalizationSetting

        Returns the personalization settings for the currently active Configuration Set.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Claude Code
        Creation Date:  2025-10-28
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [Alias("Id")]
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

        # The UriPath for personalization settings
        $UriPath = "services/wem/advancedSetting/personalizationSettings?siteId=$($ResolvedSiteId)"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # This API call returns the settings object directly.
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Personalization Settings for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}
