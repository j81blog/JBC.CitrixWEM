function Get-WEMPrinter {
    <#
    .SYNOPSIS
        Retrieves printers from a WEM Configuration Set.
    .DESCRIPTION
        This function gets a list of all configured printer actions. If -SiteId is not specified,
        it uses the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to query. Defaults to the active site.
    .PARAMETER IncludeAssignmentCount
        If specified, the result will include the count of assignments for each printer.
    .EXAMPLE
        PS C:\> Get-WEMPrinter -SiteId 1

        Retrieves all printers for the Configuration Set with ID 1.
    .EXAMPLE
        PS C:\> # After running Set-WEMActiveConfigurationSite -Id 2
        PS C:\> Get-WEMPrinter

        Retrieves all printers from the active Configuration Set (ID 2).
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-07
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

        $UriPath = "services/wem/webPrinter?siteId=$($ResolvedSiteId)"
        if ($IncludeAssignmentCount.IsPresent) {
            $UriPath += "&getAssignmentCount=true"
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Printers: $($_.Exception.Message)"
        return $null
    }
}