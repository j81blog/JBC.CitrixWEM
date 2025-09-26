function New-WEMNetworkDrive {
    <#
    .SYNOPSIS
        Creates a new network drive action in a WEM Configuration Set.
    .DESCRIPTION
        This function adds a new network drive action. If -SiteId is not specified, it uses
        the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER Name
        The unique name for the network drive action (e.g., "P: | Programs").
    .PARAMETER TargetPath
        The UNC path of the network drive to be mapped (e.g., \\server\share).
    .PARAMETER DisplayName
        The name of the drive as it will be displayed in File Explorer. Defaults to the Name parameter if not specified.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set. Defaults to the active site.
    .PARAMETER PassThru
        If specified, the command returns the newly created network drive object.
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-25
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [bool]$Enabled = $true,

        [Parameter(Mandatory = $false)]
        [switch]$SelfHealing,

        [Parameter(Mandatory = $false)]
        [switch]$SetAsHomeDrive,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        $ResolvedSiteId = 0
        if ($PSBoundParameters.ContainsKey('SiteId')) {
            $ResolvedSiteId = $SiteId
        } elseif ($Connection.ActiveSiteId) {
            $ResolvedSiteId = $Connection.ActiveSiteId
            Write-Verbose "Using active Configuration Set '$($Connection.ActiveSiteName)' (ID: $ResolvedSiteId)"
        } else {
            throw "No -SiteId was provided, and no active Configuration Set has been set. Please use Set-WEMActiveConfigurationSite or specify the -SiteId parameter."
        }

        # Default DisplayName to Name if not provided.
        if (-not $PSBoundParameters.ContainsKey('DisplayName')) {
            $DisplayName = $Name
        }

        if ($PSCmdlet.ShouldProcess($TargetPath, "Create WEM Network Drive '$($Name)' in Site ID '$($ResolvedSiteId)'")) {
            $Body = @{
                siteId         = $ResolvedSiteId
                enabled        = $Enabled
                actionType     = "MapNetworkDrive"
                useCredential  = $false # Credentials for network drives are typically managed within WEM itself.
                selfHealing    = $SelfHealing.ToBool()
                name           = $Name
                targetPath     = $TargetPath
                displayName    = $DisplayName
                setAsHomeDrive = $SetAsHomeDrive.ToBool()
            }
            if ($PSBoundParameters.ContainsKey('Description')) {
                $Body.Add('description', $Description)
            }

            $UriPath = "services/wem/action/networkDrives"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

            if ($PassThru.IsPresent) {
                Write-Verbose "PassThru specified, retrieving newly created network drive..."
                # Use the unique Name property for a reliable lookup.
                $Result = Get-WEMNetworkDrive -SiteId $ResolvedSiteId | Where-Object { $_.Name -ieq $Name }
            }

            Write-Output ($Result | Expand-WEMResult -ErrorAction SilentlyContinue)
        }
    } catch {
        Write-Error "Failed to create WEM Network Drive '$($TargetPath)': $($_.Exception.Message)"
        return $null
    }
}