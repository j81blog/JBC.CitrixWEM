function Get-WEMVirtualDriveAssignment {
    <#
    .SYNOPSIS
        Retrieves virtual drive assignments from a WEM Configuration Set.
    .DESCRIPTION
        This function gets a list of all virtual drive assignments from a specified WEM
        Configuration Set (Site).
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query.
    .EXAMPLE
        PS C:\> Get-WEMVirtualDriveAssignment -SiteId 1

        Retrieves all virtual drive assignments for the Configuration Set with ID 1.
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

        # The UriPath is the same for both Cloud and On-Premises.
        $UriPath = "services/wem/action/virtualDriveAssignment?siteId=$($ResolvedSiteId)"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Virtual Drive Assignments for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}