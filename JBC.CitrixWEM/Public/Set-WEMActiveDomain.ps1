function Set-WEMActiveDomain {
    <#
    .SYNOPSIS
        Sets the active WEM AD Forest and Domain for the current session.
    .DESCRIPTION
        This function intelligently validates and sets a specific WEM AD Forest and Domain as the active context.
        - If run with no parameters, it will attempt to find a single forest and single domain automatically.
        - If a parameter is provided, it will narrow the search.
        Subsequent cmdlets that require these values can then use them automatically.
    .PARAMETER DomainName
        The FQDN of the Active Directory domain to set as active.
    .PARAMETER ForestName
        The FQDN of the Active Directory forest to search within.
    .EXAMPLE
        PS C:\> Set-WEMActiveDomain -Verbose

        In an environment with one forest and one domain, this command automatically sets the active context
        and displays verbose messages about the process.
    .NOTES
        Version:        1.3
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-12
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [string]$ForestName
    )

    try {
        $Connection = Get-WemApiConnection
        $FoundDomains = @()

        # Determine which scenario to use based on provided parameters
        if ($PSBoundParameters.ContainsKey('ForestName') -and $PSBoundParameters.ContainsKey('DomainName')) {
            # Scenario 1: Both are specified (most specific)
            Write-Verbose "Validating specific pair: Forest '$($ForestName)', Domain '$($DomainName)'..."
            if (Get-WEMADForest | Where-Object { $_.forestName -eq $ForestName }) {
                $FoundDomains = @(Get-WEMADDomain -ForestName $ForestName | Where-Object { $_.domainName -ieq $DomainName })
            }
        } elseif ($PSBoundParameters.ContainsKey('DomainName')) {
            # Scenario 2: Only DomainName is specified
            Write-Verbose "Searching for unique domain '$($DomainName)' across all forests..."
            $FoundDomains = @( Get-WEMADForest | ForEach-Object {
                    Get-WEMADDomain -ForestName $_.forestName | Where-Object { $_.domainName -ieq $DomainName }
                })
        } elseif ($PSBoundParameters.ContainsKey('ForestName')) {
            # Scenario 3: Only ForestName is specified
            Write-Verbose "Searching for unique domain within forest '$($ForestName)'..."
            $DomainsInForest = Get-WEMADDomain -ForestName $ForestName
            if ($DomainsInForest.Count -eq 1) {
                $FoundDomains = $DomainsInForest
            } else {
                throw "Forest '$($ForestName)' contains multiple domains. Please specify the one you want to use with the -DomainName parameter."
            }
        } else {
            # Scenario 4: No parameters specified (least specific)
            Write-Verbose "Attempting to auto-detect a single forest and domain..."
            $AllForests = @(Get-WEMADForest)
            if ($AllForests.Count -ne 1) {
                throw "Multiple forests found. Please be more specific by providing the -ForestName parameter."
            }
            $DomainsInSoleForest = @(Get-WEMADDomain -ForestName $AllForests.forestName)
            if ($DomainsInSoleForest.Count -ne 1) {
                throw "The forest '$($AllForests.forestName)' contains multiple domains. Please specify the one you want to use with the -DomainName parameter."
            }
            $FoundDomains = $DomainsInSoleForest
        }

        # --- Process the results ---
        if ($FoundDomains.Count -eq 0) {
            throw "No matching domain could be found with the specified criteria."
        } elseif ($FoundDomains.Count -gt 1) {
            throw "Multiple domains named '$($DomainName)' were found. Please be more specific by providing the -ForestName parameter."
        }

        $TargetDomain = $FoundDomains[0]
        $TargetDescription = "Forest: '$($TargetDomain.forestName)', Domain: '$($TargetDomain.domainName)'"

        if ($PSCmdlet.ShouldProcess($TargetDescription, "Set as Active WEM AD Domain")) {
            $script:WemApiConnection | Add-Member -MemberType NoteProperty -Name "ActiveForestName" -Value $TargetDomain.forestName -Force
            $script:WemApiConnection | Add-Member -MemberType NoteProperty -Name "ActiveDomainName" -Value $TargetDomain.domainName -Force

            Write-Verbose "Active WEM AD context set to:"
            Write-Verbose "  Forest: $($script:WemApiConnection.ActiveForestName)"
            Write-Verbose "  Domain: $($script:WemApiConnection.ActiveDomainName)"
        }
    } catch {
        Write-Error "Failed to set active WEM AD Domain: $($_.Exception.Message)"
    }
}