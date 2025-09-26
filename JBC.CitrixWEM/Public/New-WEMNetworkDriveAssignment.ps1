function New-WEMNetworkDriveAssignment {
    <#
    .SYNOPSIS
        Assigns a WEM network drive action to a target.
    .DESCRIPTION
        This function creates a new assignment for a WEM network drive, linking a target (user/group),
        a resource (the network drive), a drive letter, and an optional filter rule. If -SiteId is not specified,
        it uses the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER Target
        The assignment target object (e.g., from Get-WEMADGroup or Get-WEMADUser) to which the drive will be assigned.
    .PARAMETER NetworkDrive
        The network drive action object (from Get-WEMNetworkDrive) that you want to assign.
    .PARAMETER DriveLetter
        The drive letter to assign to the network drive (e.g., "Z").
    .PARAMETER FilterRule
        An optional filter rule object (from Get-WEMFilterRule) to apply to this assignment.
        If not provided, the "Always True" filter is used by default.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set. Defaults to the active site.
    .PARAMETER PassThru
        If specified, the command returns the newly created assignment object.
    .EXAMPLE
        PS C:\> $Drive = Get-WEMNetworkDrive -DisplayName "Shared Drive"
        PS C:\> $Group = Get-WEMADGroup -Filter "All Users"
        PS C:\> New-WEMNetworkDriveAssignment -Target $Group -NetworkDrive $Drive -DriveLetter "S"

        Assigns the "Shared Drive" to the "All Users" group as the S: drive.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-25
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Target,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$NetworkDrive,

        [Parameter(Mandatory = $true)]
        [string]$DriveLetter,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$FilterRule,

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
        if (-not $NetworkDrive.PSObject.Properties['id']) { throw "The provided -NetworkDrive object does not have an 'id' property." }

        $ResolvedFilterId = 1 # Default to "Always True"
        if ($PSBoundParameters.ContainsKey('FilterRule')) {
            if (-not $FilterRule.PSObject.Properties['id']) { throw "The provided -FilterRule object does not have an 'id' property." }
            $ResolvedFilterId = $FilterRule.id
            Write-Verbose "Using specified filter rule '$($FilterRule.Name)' (ID: $ResolvedFilterId)"
        } else {
            Write-Verbose "No filter rule specified, using default 'Always True' (ID: 1)."
        }

        $TargetDescription = "Assign Network Drive '$($NetworkDrive.DisplayName)' (ID: $($NetworkDrive.id)) as $($DriveLetter): to Target '$($Target.Name)' (ID: $($Target.id))"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Create Assignment")) {
            $Body = @{
                siteId      = $ResolvedSiteId
                resourceId  = $NetworkDrive.id
                targetId    = $Target.id
                filterId    = $ResolvedFilterId
                driveLetter = $DriveLetter.Trim(":")
            }

            $UriPath = "services/wem/action/networkDriveAssignment"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

            if ($PassThru.IsPresent) {
                Write-Verbose "PassThru specified, retrieving newly created assignment..."
                $Result = Get-WEMNetworkDriveAssignment -SiteId $ResolvedSiteId | Where-Object { $_.resourceId -eq $NetworkDrive.id -and $_.targetId -eq $Target.id -and $_.filterId -eq $ResolvedFilterId }
            }

            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to create WEM Network Drive Assignment: $($_.Exception.Message)"
        return $null
    }
}