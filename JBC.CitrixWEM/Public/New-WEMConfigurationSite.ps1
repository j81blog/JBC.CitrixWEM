function New-WEMConfigurationSite {
    <#
    .SYNOPSIS
        Creates a new WEM Configuration Set (Site).
    .DESCRIPTION
        This function creates a new WEM Configuration Set (Site) with the specified name and optional description.
        Requires an active session established by Connect-WemApi.
    .PARAMETER Name
        The name for the new Configuration Set.
    .PARAMETER Description
        An optional description for the Configuration Set.
    .EXAMPLE
        PS C:\> # First, connect to the API
        PS C:\> Connect-WemApi -CustomerId "abcdef123" -UseSdkAuthentication

        PS C:\> # Create a new configuration set
        PS C:\> New-WEMConfigurationSite -Name "Production Site" -Description "Production environment configuration"

    .EXAMPLE
        PS C:\> # Create a configuration set without a description
        PS C:\> New-WEMConfigurationSite -Name "Test Site"
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Claude
        Creation Date:  2025-11-06
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$Description
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $UriPath = "services/wem/sites"

        # Build the request body
        $Body = @{
            name = $Name
        }

        # Add description if provided
        if ($PSBoundParameters.ContainsKey('Description')) {
            $Body.description = $Description
        }

        $TargetDescription = "Configuration Set '$Name'"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Create Configuration Set")) {
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body
            Write-Verbose "Configuration Set '$Name' created successfully."
            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to create WEM Configuration Set: $($_.Exception.Message)"
        return $null
    }
}
