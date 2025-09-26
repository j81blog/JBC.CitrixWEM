function Get-WEMApplication {
    <#
    .SYNOPSIS
        Retrieves application actions from a WEM Configuration Set.
    .DESCRIPTION
        This function gets a list of all configured application actions. If -SiteId is not specified,
        it uses the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query. Defaults to the active site.
    .PARAMETER IncludeAssignmentCount
        If specified, the result will include the count of assignments for each application.
    .EXAMPLE
        PS C:\> # After running Set-WEMActiveConfigurationSite -Id 1
        PS C:\> Get-WEMApplication

        Retrieves all application actions from the active Configuration Set (ID 1).
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-12
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeAssignmentCount
    )

    try {
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
        $UriPath = "services/wem/webApplications?siteId=$($ResolvedSiteId)"
        if ($IncludeAssignmentCount.IsPresent) {
            $UriPath += "&getAssignmentCount=true"
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Applications for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}