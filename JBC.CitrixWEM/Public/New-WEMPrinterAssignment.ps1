function New-WEMPrinterAssignment {
    <#
    .SYNOPSIS
        Assigns a WEM printer action to a target.
    .DESCRIPTION
        This function creates a new assignment for a WEM printer, linking a target (user/group),
        a resource (the printer), and an optional filter rule. If -SiteId is not specified, it uses
        the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER Target
        The assignment target object (e.g., from Get-WEMADGroup or Get-WEMADUser) to which the printer will be assigned.
    .PARAMETER Printer
        The printer action object (from Get-WEMPrinter) that you want to assign.
    .PARAMETER FilterRule
        An optional filter rule object (from Get-WEMFilterRule) to apply to this assignment.
        If not provided, the "Always True" filter is used by default.
    .PARAMETER IsDefault
        Specifies if this printer should be set as the default printer for the target.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set. Defaults to the active site.
    .PARAMETER PassThru
        If specified, the command returns the newly created assignment object.
    .EXAMPLE
        PS C:\> $Printer = Get-WEMPrinter -DisplayName "PRT10954"
        PS C:\> $Group = Get-WEMADGroup -Filter "prt-utr-jlr"
        PS C:\> New-WEMPrinterAssignment -Target $Group -Printer $Printer -PassThru

        Assigns the specified printer to the specified group and returns the new assignment object.
    .NOTES
        Version:        1.4
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-09-16
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Target,

        [Parameter(Mandatory = $true)]
        [Alias("Resource")]
        [PSCustomObject]$Printer,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$FilterRule,

        [Parameter(Mandatory = $false)]
        [switch]$IsDefault,

        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    try {
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

        if (-not $Target.PSObject.Properties['id']) { throw "The provided -Target object does not have an 'id' property." }
        if (-not $Printer.PSObject.Properties['id']) { throw "The provided -Printer object does not have an 'id' property." }

        $ResolvedFilterId = 1 # Default to "Always True"
        if ($PSBoundParameters.ContainsKey('FilterRule')) {
            if (-not $FilterRule.PSObject.Properties['id']) { throw "The provided -FilterRule object does not have an 'id' property." }
            $ResolvedFilterId = $FilterRule.id
            Write-Verbose "Using specified filter rule '$($FilterRule.Name)' (ID: $ResolvedFilterId)"
        } else {
            Write-Verbose "No filter rule specified, using default 'Always True' (ID: 1)."
        }

        $TargetDescription = "Assign Printer '$($Printer.DisplayName)' (ID: $($Printer.id)) to Target '$($Target.Name)' (ID: $($Target.id))"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Create Assignment")) {
            $Body = @{
                siteId     = $ResolvedSiteId
                resourceId = $Printer.id
                targetId   = $Target.id
                filterId   = $ResolvedFilterId
                isDefault  = $IsDefault.IsPresent
            }

            $UriPath = "services/wem/printerAssignment"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

            if ($PassThru.IsPresent) {
                Write-Verbose "PassThru specified, retrieving newly created assignment..."
                # REFINED: More efficient lookup by filtering with -SiteId first.
                $Result = Get-WEMPrinterAssignment -SiteId $ResolvedSiteId | Where-Object { $_.resourceId -eq $Printer.id -and $_.targetId -eq $Target.id -and $_.filterId -eq $ResolvedFilterId }
            }

            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to create WEM Printer Assignment: $($_.Exception.Message)"
        return $null
    }
}