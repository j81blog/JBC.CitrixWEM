function Get-WEMADUser {
    <#
    .SYNOPSIS
        Retrieves one or more WEM AD users based on a filter.
    .DESCRIPTION
        This function queries the WEM database to find users matching a filter string.
        If ForestName and DomainName are not specified, it uses the active context from Set-WEMActiveDomain.
    .PARAMETER Filter
        The filter string to use for finding the user(s) (e.g., a username).
    .PARAMETER ForestName
        The FQDN of the Active Directory forest to search in. Defaults to the active forest.
    .PARAMETER DomainName
        The FQDN of the Active Directory domain to search in. Defaults to the active domain.
    .EXAMPLE
        PS C:\> # After setting the active domain
        PS C:\> Get-WEMADUser -Filter "jdoe"

        Finds the user 'jdoe' in the active domain.
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-07
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [string]$ForestName,

        [Parameter(Mandatory = $false)]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [int]$MaxCount = 100
    )

    try {
        $SearchParams = @{
            Filter     = $Filter
            ObjectType = "UsersAndSecurityGroups"
            MaxCount   = $MaxCount
        }
        if ($PSBoundParameters.ContainsKey('ForestName')) { $SearchParams.Add('ForestName', $ForestName) }
        if ($PSBoundParameters.ContainsKey('DomainName')) { $SearchParams.Add('DomainName', $DomainName) }

        # Call the main search function and filter for USERS only
        $Result = Search-WEMActiveDirectoryObject @SearchParams | Where-Object { -not $_.isGroup }

        # Standardize the output object with consistent property names
        $Output = $Result | Select-Object -Property @{ Name = "Name"; Expression = { $_.Name } },
            @{ Name = "AccountName"; Expression = { $_.accountName } },
            @{ Name = "Sid"; Expression = { $_.securityId } },
            @{ Name = "ForestName"; Expression = { $_.forestName } },
            @{ Name = "DomainName"; Expression = { $_.domainName } },
            @{ Name = "Type"; Expression = { "User" } },
            @{ Name = "DistinguishedName"; Expression = { $_.distinguishedName } },
            @{ Name = "Email"; Expression = { $_.mail } },
            @{ Name = "UserPrincipalName"; Expression = { $_.userPrincipalName } },
            @{ Name = "DisplayName"; Expression = { $_.displayName } }

        Write-Output $Output
    } catch {
        Write-Error "Failed to retrieve WEM AD user(s): $($_.Exception.Message)"
        return $null
    }
}