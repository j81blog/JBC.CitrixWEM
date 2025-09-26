function Get-WEMNetworkDrive {
    <#
    .SYNOPSIS
        Retrieves network drive actions from a WEM Configuration Set.
    .DESCRIPTION
        This function gets a list of all configured network drive actions from a specified
        WEM Configuration Set (Site).
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query.
    .PARAMETER IncludeAssignmentCount
        If specified, the result will include the count of assignments for each network drive.
    .EXAMPLE
        PS C:\> Get-WEMNetworkDrive -SiteId 1

        Retrieves all network drive actions for the Configuration Set with ID 1.
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
        [int]$SiteId,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeAssignmentCount
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
        $UriPath = "services/wem/action/networkDrives?siteId=$($ResolvedSiteId)"
        if ($IncludeAssignmentCount.IsPresent) {
            $UriPath += "&getAssignmentCount=true"
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Network Drives for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}