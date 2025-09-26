function Get-WemApiConnection {
    <#
    .SYNOPSIS
        Retrieves the current Citrix WEM API connection.
    .DESCRIPTION
        Ensures that a connection to the Citrix Cloud WEM API has been established by verifying the script-scoped connection object and its required properties (BearerToken and CustomerId) are not null or empty. If the connection is not valid, an error is thrown instructing the user to establish a connection first.
    .OUTPUTS
        System.Object
        Returns the script-scoped WemApiConnection object containing the active API session details.
    .EXAMPLE
        PS> Get-WemApiConnection
        Retrieves the active Citrix WEM API connection. If not connected, an error is thrown advising to run Connect-WemApi.
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-05
    #>
    # It ensures that a connection has been established before other cmdlets are run.
    if ($null -eq $script:WemApiConnection -or ([String]::IsNullOrEmpty($($script:WemApiConnection.BearerToken)))) {
        throw "Not connected to Citrix Cloud API. Please run Connect-WemApi first."
    }
    $verboseOutput = $script:WemApiConnection.psObject.Copy()
    $verboseOutput.BearerToken = "********"
    Write-Verbose "Connection: $($verboseOutput | Out-String)"
    return $script:WemApiConnection
}