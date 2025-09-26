function Get-WEMFilterRule {
    <#
    .SYNOPSIS
        Retrieves filter rules from a WEM Configuration Set.
    .DESCRIPTION
        This function gets a list of all configured filter rules from a specified WEM
        Configuration Set (Site). If -SiteId is not specified, it uses the active
        Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query. Defaults to the active site.
    .EXAMPLE
        PS C:\> # After running Set-WEMActiveConfigurationSite -Id 1
        PS C:\> Get-WEMFilterRule

        Retrieves all filter rules from the active Configuration Set (ID 1).
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-08
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
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
        $UriPath = "services/wem/filterRules?siteId=$($ResolvedSiteId)"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Filter Rules for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}