function Get-WEMADGroup {
    <#
    .SYNOPSIS
        Retrieves one or more WEM AD groups based on a filter.
    .DESCRIPTION
        This function queries the WEM database to find groups matching a filter string.
        If ForestName and DomainName are not specified, it uses the active context from Set-WEMActiveDomain.
    .PARAMETER Filter
        The filter string to use for finding the group(s) (e.g., a group name).
    .PARAMETER ForestName
        The FQDN of the Active Directory forest to search in. Defaults to the active forest.
    .PARAMETER DomainName
        The FQDN of the Active Directory domain to search in. Defaults to the active domain.
    .EXAMPLE
        PS C:\> # After setting the active domain
        PS C:\> Get-WEMADGroup -Filter "WEM Admins"

        Finds the group 'WEM Admins' in the active domain.
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

        # Call the main search function and filter for GROUPS only
        $Result = Search-WEMActiveDirectoryObject @SearchParams | Where-Object { $_.isGroup }

        # Standardize the output object with consistent property names
        $Output = $Result | Select-Object -Property @{ Name = "Name"; Expression = { '{0}/{1}/{2}' -f $_.forestName, $_.domainName, $_.Name } },
            @{ Name = "AccountName"; Expression = { $_.accountName } },
            @{ Name = "Sid"; Expression = { $_.securityId } },
            @{ Name = "ForestName"; Expression = { $_.forestName } },
            @{ Name = "DomainName"; Expression = { $_.domainName } },
            @{ Name = "Type"; Expression = { "Group" } },
            @{ Name = "DistinguishedName"; Expression = { $_.distinguishedName } }

        Write-Output $Output
    } catch {
        Write-Error "Failed to retrieve WEM AD group(s): $($_.Exception.Message)"
        return $null
    }
}