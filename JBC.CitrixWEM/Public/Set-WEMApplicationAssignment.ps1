function Set-WEMApplicationAssignment {
    <#
    .SYNOPSIS
        Updates an existing WEM application assignment's placement settings.
    .DESCRIPTION
        This function updates the placement settings of an existing WEM application assignment,
        including where shortcuts should appear (Desktop, Start Menu, Taskbar, etc.) and whether
        the application should auto-start. You can specify the assignment by ID or pass an
        assignment object from Get-WEMApplicationAssignment via the pipeline.
    .PARAMETER Id
        The unique ID of the application assignment to update.
    .PARAMETER InputObject
        An application assignment object (from Get-WEMApplicationAssignment) to be modified.
        Can be passed via the pipeline.
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
    .PARAMETER PassThru
        If specified, the command returns the updated assignment object.
    .EXAMPLE
        PS C:\> Set-WEMApplicationAssignment -Id 248 -IsDesktop -IsPinToTaskBar

        Updates assignment 248 to place shortcuts on the Desktop and pin to the Taskbar.
    .EXAMPLE
        PS C:\> Get-WEMApplicationAssignment -SiteId 3 | Where-Object { $_.resourceId -eq 698 } | Set-WEMApplicationAssignment -IsAutoStart -PassThru

        Finds the assignment for application 698 and sets it to auto-start, returning the updated object.
    .EXAMPLE
        PS C:\> Set-WEMApplicationAssignment -Id 248 -IsDesktop:$false -IsStartMenu:$false

        Explicitly removes Desktop and Start Menu shortcuts from assignment 248.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Claude
        Creation Date:  2025-11-06
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ById')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [int]$Id,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInputObject', ValueFromPipeline = $true)]
        [PSCustomObject]$InputObject,

        [Parameter(Mandatory = $false)]
        [bool]$IsAutoStart,

        [Parameter(Mandatory = $false)]
        [bool]$IsPinToStartMenu,

        [Parameter(Mandatory = $false)]
        [bool]$IsPinToTaskBar,

        [Parameter(Mandatory = $false)]
        [bool]$IsDesktop,

        [Parameter(Mandatory = $false)]
        [bool]$IsQuickLaunch,

        [Parameter(Mandatory = $false)]
        [bool]$IsStartMenu,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    try {
        $Connection = Get-WemApiConnection

        # Determine the assignment ID and retrieve the current assignment
        $AssignmentId = if ($PSCmdlet.ParameterSetName -eq 'ById') { $Id } else { $InputObject.id }

        if (-not $AssignmentId) {
            throw "Could not determine assignment ID. Ensure the InputObject has an 'id' property."
        }

        Write-Verbose "Retrieving current assignment with ID $AssignmentId..."

        # Get the current assignment to preserve all properties
        $CurrentAssignment = if ($PSCmdlet.ParameterSetName -eq 'ByInputObject' -and $InputObject) {
            $InputObject
        } else {
            # Need to find the assignment - we'll need to check all sites or use the active site
            $Connection = Get-WemApiConnection
            $SiteId = if ($Connection.ActiveSiteId) {
                $Connection.ActiveSiteId
            } else {
                throw "No active Configuration Set has been set. Please use Set-WEMActiveConfigurationSite first."
            }

            $AllAssignments = Get-WEMApplicationAssignment -SiteId $SiteId
            $Assignment = $AllAssignments | Where-Object { $_.id -eq $AssignmentId }

            if (-not $Assignment) {
                throw "Could not find application assignment with ID $AssignmentId in site $SiteId."
            }
            $Assignment
        }

        # Build the body with all required fields from the current assignment
        $Body = @{
            id                  = $CurrentAssignment.id
            siteId              = $CurrentAssignment.siteId
            resourceId          = $CurrentAssignment.resourceId
            targetId            = $CurrentAssignment.targetId
            filterId            = $CurrentAssignment.filterId
            isAutoStart         = if ($PSBoundParameters.ContainsKey('IsAutoStart')) { $IsAutoStart } else { [bool]$CurrentAssignment.isAutoStart }
            isDesktop           = if ($PSBoundParameters.ContainsKey('IsDesktop')) { $IsDesktop } else { [bool]$CurrentAssignment.isDesktop }
            isQuickLaunch       = if ($PSBoundParameters.ContainsKey('IsQuickLaunch')) { $IsQuickLaunch } else { [bool]$CurrentAssignment.isQuickLaunch }
            isStartMenu         = if ($PSBoundParameters.ContainsKey('IsStartMenu')) { $IsStartMenu } else { [bool]$CurrentAssignment.isStartMenu }
            isPinToStartMenu    = if ($PSBoundParameters.ContainsKey('IsPinToStartMenu')) { $IsPinToStartMenu } else { [bool]$CurrentAssignment.isPinToStartMenu }
            isPinToTaskBar      = if ($PSBoundParameters.ContainsKey('IsPinToTaskBar')) { $IsPinToTaskBar } else { [bool]$CurrentAssignment.isPinToTaskBar }
        }

        # Include groupingInfo if it exists
        if ($CurrentAssignment.PSObject.Properties['groupingInfo']) {
            $Body.groupingInfo = $CurrentAssignment.groupingInfo
        }
        if ($CurrentAssignment.PSObject.Properties['lastModifiedByActionGroup']) {
            $Body.lastModifiedByActionGroup = $CurrentAssignment.lastModifiedByActionGroup
        }

        $TargetDescription = "Application Assignment ID $AssignmentId"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Update Assignment")) {
            $UriPath = "services/wem/applicationAssignment"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "PUT" -Connection $Connection -Body $Body
            Write-Verbose "Application assignment $AssignmentId updated successfully."

            if ($PassThru.IsPresent) {
                Write-Verbose "PassThru specified, retrieving updated assignment..."
                $UpdatedAssignment = Get-WEMApplicationAssignment -SiteId $Body.siteId | Where-Object { $_.id -eq $AssignmentId }
                Write-Output $UpdatedAssignment
            } else {
                Write-Output ($Result | Expand-WEMResult)
            }
        }
    } catch {
        Write-Error "Failed to update WEM Application Assignment: $($_.Exception.Message)"
        return $null
    }
}
