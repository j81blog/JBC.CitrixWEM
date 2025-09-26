function New-WEMPrinter {
    <#
    .SYNOPSIS
        Creates a new network printer in Citrix WEM.
    .DESCRIPTION
        This function adds a new network printer action. If -SiteId is not specified, it uses
        the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER Name
        The unique name for the printer action.
    .PARAMETER PrinterPath
        The UNC path of the network printer (e.g., \\server\printer).
    .PARAMETER DisplayName
        The name of the printer to be displayed to the user. This is optional.
    .NOTES
        Version:        1.3
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-22
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [Alias("Path")]
        [string]$PrinterPath,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [bool]$Enabled = $true,

        [Parameter(Mandatory = $false)]
        [bool]$SelfHealing = $true,

        [Parameter(Mandatory = $false)]
        [bool]$UseCredential = $false,

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

        if ($PSCmdlet.ShouldProcess($PrinterPath, "Create WEM Printer '$($Name)' in Site ID '$($ResolvedSiteId)'")) {
            $Body = @{
                siteId        = $ResolvedSiteId
                enabled       = $Enabled
                actionType    = "NetWorkPrinter"
                useCredential = $UseCredential
                selfHealing   = $SelfHealing
                name          = $Name
                targetPath    = $PrinterPath
            }
            # CORRECTED: Only add DisplayName and Description if they are explicitly provided.
            if ($PSBoundParameters.ContainsKey('DisplayName')) {
                $Body.Add('displayName', $DisplayName)
            }
            if ($PSBoundParameters.ContainsKey('Description')) {
                $Body.Add('description', $Description)
            }

            $UriPath = "services/wem/webPrinter"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

            if ($PassThru.IsPresent) {
                Write-Verbose "PassThru specified, retrieving newly created printer..."
                $Result = Get-WEMPrinter -SiteId $ResolvedSiteId | Where-Object { $_.Name -ieq $Name }
            }

            Write-Output ($Result | Expand-WEMResult -ErrorAction SilentlyContinue)
        }
    } catch {
        Write-Error "Failed to create WEM Printer '$($PrinterPath)': $($_.Exception.Message)"
        return $null
    }
}