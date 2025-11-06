function New-WEMApplicationAssignment {
    <#
    .SYNOPSIS
        Creates a new WEM application assignment to a target with optional placement settings.
    .DESCRIPTION
        This function creates a new assignment for a WEM application, linking a target (user/group),
        a resource (the application), and an optional filter rule. You can also specify where the
        application shortcut should be placed (Desktop, Start Menu, Taskbar, etc.) and whether it
        should auto-start. If -SiteId is not specified, it uses the active Configuration Set
        defined by Set-WEMActiveConfigurationSite.
    .PARAMETER Target
        The assignment target object (e.g., from Get-WEMADGroup or Get-WEMADUser) to which the application will be assigned.
    .PARAMETER Application
        The application action object (from Get-WEMApplication) that you want to assign.
    .PARAMETER FilterRule
        An optional filter rule object (from Get-WEMFilterRule) to apply to this assignment.
        If not provided, the "Always True" filter is used by default.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set. Defaults to the active site.
    .PARAMETER PassThru
        If specified, the command returns the newly created assignment object.
    .PARAMETER IsAutoStart
        If specified, the application will automatically start when the user logs on.
    .PARAMETER IsPinToStartMenu
        If specified, the application shortcut will be pinned to the Start Menu.
    .PARAMETER IsPinToTaskBar
        If specified, the application shortcut will be pinned to the Taskbar.
    .PARAMETER IsDesktop
        If specified, the application shortcut will be placed on the Desktop.
    .PARAMETER IsQuickLaunch
        If specified, the application shortcut will be placed in the Quick Launch area.
    .PARAMETER IsStartMenu
        If specified, the application shortcut will be placed in the Start Menu.
    .EXAMPLE
        PS C:\> $App = Get-WEMApplication -DisplayName "Notepad++"
        PS C:\> $Group = Get-WEMADGroup -Filter "Developers"
        PS C:\> New-WEMApplicationAssignment -Target $Group -Application $App -PassThru

        Assigns the "Notepad++" application to the "Developers" group and returns the new assignment object.
    .EXAMPLE
        PS C:\> $App = Get-WEMApplication -DisplayName "Chrome"
        PS C:\> $Users = Get-WEMADGroup -Filter "All Users"
        PS C:\> New-WEMApplicationAssignment -Target $Users -Application $App -IsDesktop -IsPinToTaskBar

        Assigns Chrome to all users with shortcuts on the Desktop and pinned to the Taskbar.
    .NOTES
        Function  : New-WEMApplicationAssignment
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.0
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
        [Switch]$IsAutoStart,

        [Parameter(Mandatory = $false)]
        [Switch]$IsPinToStartMenu,

        [Parameter(Mandatory = $false)]
        [Switch]$IsPinToTaskBar,

        [Parameter(Mandatory = $false)]
        [Switch]$IsDesktop,

        [Parameter(Mandatory = $false)]
        [Switch]$IsQuickLaunch,

        [Parameter(Mandatory = $false)]
        [Switch]$IsStartMenu
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
            $Body = @{
                siteId           = $ResolvedSiteId
                resourceId       = $Application.id
                targetId         = $Target.id
                filterId         = $ResolvedFilterId
                isAutoStart      = $false
                isDesktop        = $false
                isQuickLaunch    = $false
                isStartMenu      = $false
                isPinToStartMenu = $false
                isPinToTaskBar   = $false
            }
            if ($IsAutoStart.IsPresent) { $Body.isAutoStart = $true }
            if ($IsDesktop.IsPresent) { $Body.isDesktop = $true }
            if ($IsQuickLaunch.IsPresent) { $Body.isQuickLaunch = $true }
            if ($IsStartMenu.IsPresent) { $Body.isStartMenu = $true }
            if ($IsPinToStartMenu.IsPresent) { $Body.isPinToStartMenu = $true }
            if ($IsPinToTaskBar.IsPresent) { $Body.isPinToTaskBar = $true }

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