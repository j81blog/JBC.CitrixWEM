function Search-WEMActiveDirectoryObject {
    <#
    .SYNOPSIS
        Searches for Active Directory objects (users/groups) via the WEM service.
    .DESCRIPTION
        This function performs a search for Active Directory users or groups within a specified forest and domain.
        If ForestName and DomainName are not specified, it uses the active context from Set-WEMActiveDomain.
        The query is forwarded by the WEM service to the configured Cloud Connector or handled by the On-Premises server.
    .PARAMETER ForestName
        The FQDN of the Active Directory forest to search in. Defaults to the active forest.
    .PARAMETER DomainName
        The FQDN of the Active Directory domain to search in. Defaults to the active domain, or the ForestName.
    .PARAMETER Filter
        The search filter or query string to use for finding the object.
    .PARAMETER ObjectType
        The type of Active Directory object to search for.
    .PARAMETER MaxCount
        The maximum number of results to return from the search. Defaults to 100.
    .EXAMPLE
        PS C:\> # First, set the active domain context
        PS C:\> Set-WEMActiveDomain -DomainName "corp.local"
        PS C:\> # Now, search without specifying the domain
        PS C:\> Search-WEMActiveDirectoryObject -Filter "TestUser" -ObjectType Users

        Searches for "TestUser" within the active domain "corp.local".
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-21
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ForestName,

        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [string]$DomainName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Users", "Computers", "Containers", "NonDomainJoinedMachines", "SecurityGroups", "UsersAndSecurityGroups")]
        [string]$ObjectType,

        [Parameter(Mandatory = $false)]
        [int]$MaxCount = 100
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        # --- Resolve ForestName and DomainName from parameters or active context ---
        $ResolvedForestName = $null
        if ($PSBoundParameters.ContainsKey('ForestName')) {
            $ResolvedForestName = $ForestName
        } elseif ($Connection.ActiveForestName) {
            $ResolvedForestName = $Connection.ActiveForestName
            Write-Verbose "Using active Forest: '$($ResolvedForestName)'"
        } else {
            throw "No -ForestName was provided, and no active Forest has been set. Please use Set-WEMActiveDomain or specify the -ForestName parameter."
        }

        $ResolvedDomainName = $null
        if ($PSBoundParameters.ContainsKey('DomainName')) {
            $ResolvedDomainName = $DomainName
        } elseif ($Connection.ActiveDomainName) {
            $ResolvedDomainName = $Connection.ActiveDomainName
            Write-Verbose "Using active Domain: '$($ResolvedDomainName)'"
        } else {
            # Default DomainName to the resolved ForestName if no active domain is set
            $ResolvedDomainName = $ResolvedForestName
        }

        # URL-encode the filter to handle spaces and special characters correctly
        $EncodedFilter = [System.Web.HttpUtility]::UrlEncode($Filter)
        Write-Verbose "Encoded filter: $EncodedFilter"

        $SearchType = if ($ObjectType -in "SecurityGroups", "UsersAndSecurityGroups") { "Users" } else { $ObjectType }

        # Construct the complex URI from the parameters
        if ($Connection.IsOnPrem) {
            $UriPath = "services/wem/onPrem/identity/Forests/$($ResolvedForestName)/Domains/$($ResolvedDomainName)/$SearchType"
        } else {
            $UriPath = "services/wem/forward/identity/Forests/$($ResolvedForestName)/Domains/$($ResolvedDomainName)/$SearchType"
        }

        if ($ObjectType -ieq "Computers") {
            $UriPath += "?provider=AD&admin=&key=&queryOptions.take=$($MaxCount)&queryOptions.filter=co%20$($EncodedFilter)"
        } elseif ($ObjectType -ieq "Containers") {
            $UriPath += "?provider=AD&admin=&key=&queryOptions.skip=0&queryOptions.take=$($MaxCount)&queryOptions.recursive=true&queryOptions.filter=co%20$($EncodedFilter)"
        } elseif ($ObjectType -ieq "Users") {
            $UriPath += "?provider=AD&admin=&key=&queryOptions.take=$($MaxCount)&queryOptions.filter=co%20$($EncodedFilter)&queryOptions.searchType=0"
        } elseif ($ObjectType -ieq "SecurityGroups") {
            $UriPath += "?provider=AD&admin=&key=&queryOptions.take=$($MaxCount)&queryOptions.filter=co%20$($EncodedFilter)&queryOptions.searchType=1"
        } elseif ($ObjectType -ieq "UsersAndSecurityGroups") {
            $UriPath += "?provider=AD&admin=&key=&queryOptions.take=$($MaxCount)&queryOptions.filter=co%20$($EncodedFilter)&queryOptions.searchType=2"
        } elseif ($ObjectType -ieq "NonDomainJoinedMachines") {
            $UriPath = "services/wem/nonDomainJoinedAgents/remaining"
        } else {
            throw "Invalid ObjectType specified." # Should not be reached due to ValidateSet
        }
        Write-Verbose "Constructed URI Path: $UriPath"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to search Active Directory objects with filter '$($Filter)': $($_.Exception.Message)"
        return $null
    }
}