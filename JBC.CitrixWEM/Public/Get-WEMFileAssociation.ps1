function Get-WEMFileAssociation {
    <#
    .SYNOPSIS
        Retrieves file type association actions from a WEM Configuration Set.
    .DESCRIPTION
        This function gets a list of all configured file type association actions. If -SiteId is not specified,
        it uses the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query. Defaults to the active site.
    .PARAMETER IncludeAssignmentCount
        If specified, the result will include the count of assignments for each association.
    .EXAMPLE
        PS C:\> # After setting the active site
        PS C:\> Get-WEMFileAssociation

        Retrieves all file associations from the active Configuration Set.
    .NOTES
        Function  : Get-WEMFileAssociation
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.0
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
        $UriPath = "services/wem/action/fileAssociations?siteId=$($ResolvedSiteId)"
        if ($IncludeAssignmentCount.IsPresent) {
            $UriPath += "&getAssignmentCount=true"
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM File Associations for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}