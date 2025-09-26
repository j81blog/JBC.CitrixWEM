function Get-WEMConfigurationSite {
    <#
    .SYNOPSIS
        Retrieves WEM Configuration Sets (Sites).
    .DESCRIPTION
        This function retrieves a list of all WEM Configuration Sets (Sites) for the current customer.
        It can optionally include hidden sites and the special site for unbound agents.
        Requires an active session established by Connect-WemApi.
    .PARAMETER IncludeHidden
        If specified, the results will include configuration sets that are marked as hidden.
    .PARAMETER IncludeUnboundAgentsSite
        If specified, the results will include the special "Unbound Agents" site.
    .EXAMPLE
        PS C:\> # First, connect to the API
        PS C:\> Connect-WemApi -CustomerId "abcdef123" -UseSdkAuthentication

        PS C:\> # Retrieve all visible configuration sets
        PS C:\> Get-WEMConfigurationSite

    .EXAMPLE
        PS C:\> # Retrieve all sets, including hidden ones and the unbound agents site
        PS C:\> Get-WEMConfigurationSite -IncludeHidden -IncludeUnboundAgentsSite
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
        [switch]$IncludeHidden,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeUnboundAgentsSite
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $UriPath = "services/wem/sites"
        $QueryParts = [System.Collections.Generic.List[string]]::new()

        if ($IncludeHidden.IsPresent) {
            $QueryParts.Add("includeHidden=true")
        }

        if ($IncludeUnboundAgentsSite.IsPresent) {
            $QueryParts.Add("includeUnboundAgentsSite=true")
        }

        if ($QueryParts.Count -gt 0) {
            $UriPath += "?$($QueryParts -join '&')"
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to retrieve WEM Configuration Sets: $($_.Exception.Message)"
        return $null
    }
}