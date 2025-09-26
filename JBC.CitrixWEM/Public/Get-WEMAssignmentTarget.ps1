function Get-WEMAssignmentTarget {
    <#
    .SYNOPSIS
        Retrieves assignment targets (like AD objects) from a WEM Configuration Set.
    .DESCRIPTION
        This function queries and retrieves a list of assignment targets, such as users and groups,
        from a specific WEM Configuration Set (Site).
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query for assignment targets.
    .EXAMPLE
        PS C:\> Get-WEMAssignmentTarget -SiteId 1

        Retrieves all assignment targets associated with Site ID 1.
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-05
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

        # Build the specific filter structure required by the API
        $Filter = [PSCustomObject]@{
            param    = "SiteId"
            operator = "Equals"
            value    = $ResolvedSiteId
        }

        $Body = @{
            filters = @($Filter)
        }

        $UriPath = "services/wem/assignmentTarget/`$query"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Assignment Targets for Site ID $($ResolvedSiteId): $($_.Exception.Message)"
        return $null
    }
}