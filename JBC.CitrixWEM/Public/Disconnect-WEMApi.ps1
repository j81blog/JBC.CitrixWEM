function Disconnect-WEMApi {
    <#
    .SYNOPSIS
        Disconnects the active Citrix WEM API session.
    .DESCRIPTION
        This function clears the current authentication details. If connected to an On-Premises
        environment, it will also send a logout request to the server to terminate the session.
    .EXAMPLE
        PS C:\> Disconnect-WEMApi

        Disconnects the active session and removes the stored credentials.
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-05
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:WemApiConnection) {
        Write-Verbose "No active WEM API session to disconnect."
        return
    }

    try {
        # If it's an On-Prem session, explicitly log out from the server.
        if ($script:WemApiConnection.IsOnPrem) {
            Write-Verbose "Logging out from On-Premises WEM server..."
            $UriPath = "services/wem/onPrem/LogOut"
            Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $script:WemApiConnection
        }
    } catch {
        # Write a warning if the logout fails, but proceed with clearing the local variable.
        Write-Warning "An error occurred during server logout, but the local session will be cleared. Details: $($_.Exception.Message)"
    } finally {
        # Always clear the script-scoped variable.
        $script:WemApiConnection = $null
        Write-Host "Successfully disconnected from WEM API."
    }
}