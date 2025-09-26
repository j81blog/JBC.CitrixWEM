function Get-WEMFileAssociationAssignment {
    <#
    .SYNOPSIS
        Retrieves file association assignments from a WEM Configuration Set.
    .DESCRIPTION
        This function gets a list of all file association assignments from a specified WEM
        Configuration Set (Site). If -SiteId is not specified, it uses the active
        Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query. Defaults to the active site.
    .EXAMPLE
        PS C:\> # After setting the active site
        PS C:\> Get-WEMFileAssociationAssignment

        Retrieves all file association assignments from the active Configuration Set.
    .NOTES
        Function  : Get-WEMFileAssociationAssignment
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.0
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId
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
        $UriPath = "services/wem/action/fileAssociationAssignment?siteId=$($ResolvedSiteId)"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM File Association Assignments for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}