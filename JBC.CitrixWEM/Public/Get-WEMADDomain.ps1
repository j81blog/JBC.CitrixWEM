function Get-WEMADDomain {
    <#
    .SYNOPSIS
        Retrieves the Active Directory domains within a specified forest.
    .DESCRIPTION
        This function retrieves a list of the Active Directory domains that belong to a specific forest
        as recognized by the WEM service.
        Requires an active session established by Connect-WemApi.
    .PARAMETER ForestName
        The Fully Qualified Domain Name (FQDN) of the forest to query for domains.
        This parameter accepts input from the pipeline by property name.
    .EXAMPLE
        PS C:\> Get-WEMADDomain -ForestName "domain.local"

        Returns a list of all domains in the "domain.local" forest.
    .EXAMPLE
        PS C:\> Get-WEMADForest | Get-WEMADDomain

        Retrieves all configured forests and then finds all domains within each of those forests.
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-05
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$ForestName
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        if ($Connection.IsOnPrem) {
            $UriPath = "/services/wem/onPrem/identity/Forests/$($ForestName)/Domains?provider=AD&parentDomain=&admin=&key="
        } else {
            $UriPath = "/services/wem/forward/identity/Forests/$($ForestName)/Domains?provider=AD&parentDomain=&admin=&key="
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection | Expand-WEMResult

        Write-Output ($Result)
    } catch {
        Write-Error "Failed to retrieve WEM AD Domains for forest '$($ForestName)': $($_.Exception.Message)"
        return $null
    }
}