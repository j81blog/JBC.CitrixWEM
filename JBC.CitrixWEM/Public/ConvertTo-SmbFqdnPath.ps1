<#
.SYNOPSIS
    Converts a simple SMB (UNC) path to use a Fully Qualified Domain Name (FQDN) for the server.

.DESCRIPTION
    This function takes an SMB path and ensures the server component is an FQDN.
    If the path already contains an FQDN, it is returned unmodified.
    If the server is a simple hostname, the function appends a domain to it.

    The domain can be explicitly provided via the -Domain parameter. If not provided, the function
    defaults to the domain of the current user, retrieved from the $env:USERDNSDOMAIN environment variable.

.PARAMETER Path
    The full SMB path to convert, e.g., '\\SERVER\share' or '\\server.contoso.com\share'.

.PARAMETER Domain
    Optional. The domain name to append to the server name if it is not already an FQDN.
    If omitted, the function uses the current user's domain.

.EXAMPLE
    PS > ConvertTo-SmbFqdnPath -Path '\\FILESERVER\Users'
    \\FILESERVER.contoso.com\Users

    Description:
    Assumes the current user's domain is 'contoso.com'. It converts the simple hostname 'FILESERVER'
    to an FQDN and returns the full path.

.EXAMPLE
    PS > ConvertTo-SmbFqdnPath -Path '\\WEB01\Logs' -Domain 'dev.local'
    \\WEB01.dev.local\Logs

    Description:
    Explicitly provides the domain 'dev.local' to create the FQDN path.

.EXAMPLE
    PS > ConvertTo-SmbFqdnPath -Path '\\dc01.ad.corp\sysvol'
    \\dc01.ad.corp\sysvol

    Description:
    The path already uses an FQDN, so the function returns the input path unchanged.

.EXAMPLE
    PS > '\\APP-SERVER\Install' | ConvertTo-SmbFqdnPath
    \\APP-SERVER.contoso.com\Install

    Description:
    Demonstrates using the function with pipeline input.

.RETURNS
    [string]
    The converted SMB path with an FQDN server name.

.NOTES
    Version        : 1.0
    Author         : John Billekens Consultancy
    Co-Author      : Gemini
    Creation Date  : 2025-08-29
    Dependencies   : Requires the Test-SmbPathIsFqdn function to be available in the session.
#>
function ConvertTo-SmbFqdnPath {
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
        [string]$Path,

        [Parameter(
            Mandatory = $false,
            Position = 1,
            HelpMessage = 'Specify the domain to append. Defaults to the current user domain.'
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Domain
    )

    try {
        # First, check if the function Test-SmbPathIsFqdn exists.
        if (-not (Get-Command 'Test-SmbPathIsFqdn' -ErrorAction SilentlyContinue)) {
            throw "The required helper function 'Test-SmbPathIsFqdn' was not found in the current session."
        }

        # If the path is already an FQDN, no conversion is needed.
        if (Test-SmbPathIsFqdn -Path $Path) {
            return $Path
        }

        # Determine which domain to use for the conversion.
        $DomainToUse = ''
        if ($PSBoundParameters.ContainsKey('Domain')) {
            $DomainToUse = $Domain
        } else {
            $DomainToUse = $env:USERDNSDOMAIN
        }

        # If we still don't have a domain, we cannot proceed.
        if ([string]::IsNullOrEmpty($DomainToUse)) {
            throw "Could not determine the domain to use. Please provide a domain using the -Domain parameter or ensure `$env:USERDNSDOMAIN is set."
        }

        # Split the path into its components. We only split into a maximum of 4 parts
        # to correctly handle paths with multiple subfolders.
        # e.g., '\\SERVER\share\folder\subfolder' -> '', '', 'SERVER', 'share\folder\subfolder'
        $PathComponents = $Path.Split([System.IO.Path]::DirectorySeparatorChar, 4)
        $ServerName = $PathComponents[2]
        $SharePath = $PathComponents[3]

        # Construct the new FQDN server name and the final path.
        $FqdnServer = "$($ServerName).$($DomainToUse)"
        $NewPath = Join-Path -Path "\\$($FqdnServer)" -ChildPath $SharePath

        return $NewPath
    } catch {
        Write-Error -Message "Failed to convert path '$($Path)': $($_.Exception.Message)"
    }
}
