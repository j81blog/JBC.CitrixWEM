function New-WEMApplicationAssignment {
    <#
    .SYNOPSIS
        Assigns a WEM application action to a target and configures its shortcuts.
    .DESCRIPTION
        This function creates a new assignment for a WEM application, linking a target (user/group),
        a resource (the application), and an optional filter rule. It also allows for the initial
        configuration of shortcut locations (Desktop, Start Menu, etc.).
    .PARAMETER Target
        The assignment target object (from Get-WEMAssignmentTarget or Get-WEMADGroup) to which the application will be assigned.
    .PARAMETER Application
        The application action object (from Get-WEMApplication) that you want to assign.
    .PARAMETER CreateDesktopShortcut
        If specified, a shortcut for the application will be created on the desktop.
    .PARAMETER PinToTaskbar
        If specified, the application will be pinned to the taskbar.
    .NOTES
        Function  : New-WEMApplicationAssignment
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.2
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Target,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Application,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$FilterRule,

        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru,

        [Parameter(Mandatory = $false)]
        [Switch]$AutoStart,

        [Parameter(Mandatory = $false)]
        [Switch]$PinToStartMenu,

        [Parameter(Mandatory = $false)]
        [Switch]$PinToTaskbar,

        [Parameter(Mandatory = $false)]
        [Switch]$CreateDesktopShortcut,

        [Parameter(Mandatory = $false)]
        [Switch]$CreateQuickLaunchShortcut,

        [Parameter(Mandatory = $false)]
        [Switch]$CreateStartMenuShortcut
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
        if (-not $Application.PSObject.Properties['id']) { throw "The provided -Application object does not have an 'id' property." }

        $ResolvedFilterId = 1 # Default to "Always True"
        if ($PSBoundParameters.ContainsKey('FilterRule')) {
            if (-not $FilterRule.PSObject.Properties['id']) { throw "The provided -FilterRule object does not have an 'id' property." }
            $ResolvedFilterId = $FilterRule.id
            Write-Verbose "Using specified filter rule '$($FilterRule.Name)' (ID: $ResolvedFilterId)"
        } else {
            Write-Verbose "No filter rule specified, using default 'Always True' (ID: 1)."
        }

        $TargetDescription = "Assign Application '$($Application.DisplayName)' (ID: $($Application.id)) to Target '$($Target.Name)' (ID: $($Target.id))"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Create Assignment")) {

            # REFINED: Assign the boolean value of the switch's IsPresent property directly.
            $Body = @{
                siteId           = $ResolvedSiteId
                resourceId       = $Application.id
                targetId         = $Target.id
                filterId         = $ResolvedFilterId
                isAutoStart      = $AutoStart.IsPresent
                isDesktop        = $CreateDesktopShortcut.IsPresent
                isQuickLaunch    = $CreateQuickLaunchShortcut.IsPresent
                isStartMenu      = $CreateStartMenuShortcut.IsPresent
                isPinToStartMenu = $PinToStartMenu.IsPresent
                isPinToTaskBar   = $PinToTaskbar.IsPresent
            }

            $UriPath = "services/wem/applicationAssignment"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

            if ($PassThru.IsPresent) {
                Write-Verbose "PassThru specified, retrieving newly created assignment..."
                $Result = Get-WEMApplicationAssignment -SiteId $ResolvedSiteId | Where-Object { $_.resourceId -eq $Application.id -and $_.targetId -eq $Target.id -and $_.filterId -eq $ResolvedFilterId }
            }

            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to create WEM Application Assignment: $($_.Exception.Message)"
        return $null
    }
}