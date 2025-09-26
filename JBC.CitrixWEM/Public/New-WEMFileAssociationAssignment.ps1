function New-WEMFileAssociationAssignment {
    <#
    .SYNOPSIS
        Assigns a WEM file association action to a target.
    .DESCRIPTION
        This function creates a new assignment for a WEM file association, linking a target (user/group),
        a resource (the file association), and an optional filter rule. If -SiteId is not specified, it uses
        the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER Target
        The assignment target object (e.g., from Get-WEMADGroup or Get-WEMADUser) to which the action will be assigned.
    .PARAMETER FileAssociation
        The file association action object (from Get-WEMFileAssociation) that you want to assign.
    .PARAMETER FilterRule
        An optional filter rule object (from Get-WEMFilterRule) to apply to this assignment.
        If not provided, the "Always True" filter is used by default.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set. Defaults to the active site.
    .PARAMETER PassThru
        If specified, the command returns the newly created assignment object.
    .EXAMPLE
        PS C:\> $Fta = Get-WEMFileAssociation -Name "ImageGlass TIFF"
        PS C:\> $AssignmentTarget = Get-WEMAssignmentTarget | Where-Object { $_.name -like "Everyone" }
        PS C:\> New-WEMFileAssociationAssignment -Target $AssignmentTarget -FileAssociation $Fta

        Assigns the "ImageGlass TIFF" file association to the "Everyone" group.
    .NOTES
        Function  : New-WEMFileAssociationAssignment
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.1
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Target,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$FileAssociation,

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
        if (-not $FileAssociation.PSObject.Properties['id']) { throw "The provided -FileAssociation object does not have an 'id' property." }

        $ResolvedFilterId = 1 # Default to "Always True"
        if ($PSBoundParameters.ContainsKey('FilterRule')) {
            if (-not $FilterRule.PSObject.Properties['id']) { throw "The provided -FilterRule object does not have an 'id' property." }
            $ResolvedFilterId = $FilterRule.id
            Write-Verbose "Using specified filter rule '$($FilterRule.Name)' (ID: $ResolvedFilterId)"
        } else {
            Write-Verbose "No filter rule specified, using default 'Always True' (ID: 1)."
        }

        $TargetDescription = "Assign File Association '$($FileAssociation.Name)' (ID: $($FileAssociation.id)) to Target '$($Target.Name)' (ID: $($Target.id))"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Create Assignment")) {
            $Body = @{
                siteId     = $ResolvedSiteId
                resourceId = $FileAssociation.id
                targetId   = $Target.id
                filterId   = $ResolvedFilterId
            }

            $UriPath = "services/wem/action/fileAssociationAssignment"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

            if ($PassThru.IsPresent) {
                Write-Verbose "PassThru specified, retrieving newly created assignment..."
                $Result = Get-WEMFileAssociationAssignment -SiteId $ResolvedSiteId | Where-Object { $_.resourceId -eq $FileAssociation.id -and $_.targetId -eq $Target.id -and $_.filterId -eq $ResolvedFilterId }
            }

            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to create WEM File Association Assignment: $($_.Exception.Message)"
        return $null
    }
}