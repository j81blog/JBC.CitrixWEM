<#
.SYNOPSIS
    Checks if the server component of a given SMB (UNC) path is a Fully Qualified Domain Name (FQDN).

.DESCRIPTION
    This function takes a string containing an SMB path (e.g., \\server\share) and determines if the
    server part of the path contains one or more periods, which indicates it is an FQDN
    (e.g., \\server.domain.com\share). It returns $true if it is an FQDN and $false otherwise.

.PARAMETER Path
    The full SMB path to check. The path must start with \\.

.EXAMPLE
    PS > Test-SmbPathIsFqdn -Path '\\fileserver.contoso.com\share\folder'
    True

.EXAMPLE
    PS > Test-SmbPathIsFqdn -Path '\\FILESERVER\share'
    False

.EXAMPLE
    PS > '\\dc01.ad.corp\sysvol' | Test-SmbPathIsFqdn
    True

.OUTPUTS
    [System.Boolean]
    Returns $true if the server name is an FQDN, and $false otherwise.

.NOTES
    Version        : 1.0
    Author         : John Billekens Consultancy
    Co-Author      : Gemini
    Creation Date  : 2025-08-29
#>
function Test-SmbPathIsFqdn {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 0,
            HelpMessage = 'Enter a valid SMB path that starts with \\.'
        )]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^\\\\[^\\]')]
        [string]$Path
    )

    try {
        # Split the path by the backslash delimiter.
        # The server name will be the third element (index 2) because of the leading empty strings
        # from the initial \\. e.g., '', '', 'server.domain.com', 'share'
        $PathComponents = $Path.Split([System.IO.Path]::DirectorySeparatorChar)
        $ServerName = $PathComponents[2]

        # An FQDN must contain at least one period.
        return $ServerName.Contains('.')
    } catch {
        Write-Error -Message "An unexpected error occurred while processing the path '$($Path)': $($_.Exception.Message)"
        return $false
    }
}
