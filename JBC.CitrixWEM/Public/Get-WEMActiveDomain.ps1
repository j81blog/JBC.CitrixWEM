function Get-WEMActiveDomain {
    <#
    .SYNOPSIS
        Gets the currently active WEM AD Forest and Domain for the session.
    .DESCRIPTION
        This function displays the active WEM AD Forest and Domain that have been set
        using the Set-WEMActiveDomain function.
    .EXAMPLE
        PS C:\> Get-WEMActiveDomain

        Returns an object with the currently configured active Forest and Domain.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-26
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        # Check if the active domain/forest properties have been set on the connection object.
        if (-not $Connection.PSObject.Properties['ActiveForestName']) {
            throw "No active forest is set in the current session. Please use Set-WEMActiveDomain to set one."
        }
        if (-not $Connection.PSObject.Properties['ActiveDomainName']) {
            throw "No active domain is set in the current session. Please use Set-WEMActiveDomain to set one."
        }

        $DomainDetails = @{
            Forest = $Connection.ActiveForestName
            Domain = $Connection.ActiveDomainName
        }

        Write-Output ([PSCustomObject]$DomainDetails)
    } catch {
        Write-Error "Failed to retrieve active WEM AD Domain: $($_.Exception.Message)"
    }
}