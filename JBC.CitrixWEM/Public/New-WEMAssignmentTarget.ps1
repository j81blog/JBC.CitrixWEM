function New-WEMAssignmentTarget {
    <#
    .SYNOPSIS
        Creates a new WEM assignment target from an Active Directory object.
    .DESCRIPTION
        This function registers a new Active Directory user or group as an assignment target within a specified
        WEM Configuration Set. This allows actions, such as printers or applications, to be assigned to it.
        Requires an active session established by Connect-WemApi.
    .PARAMETER Sid
        The Security Identifier (SID) of the Active Directory user or group.
    .PARAMETER Name
        The name of the AD object <forest name>/<domain name>/<group name> (e.g., 'domain.local/domain.local/Domain Users').
    .PARAMETER SiteId
        The ID of the WEM Configuration Set where this target will be created.
    .PARAMETER ForestName
        The FQDN of the Active Directory forest where the object resides.
    .PARAMETER Type
        The type of the object. Can be either 'Group' or 'User'. Defaults to 'Group'.
    .PARAMETER DomainName
        The FQDN of the Active Directory domain. If not provided, it defaults to the same value as ForestName.
    .PARAMETER Description
        An optional description for the assignment target.
    .PARAMETER Enabled
        Specifies whether the assignment target is enabled. Defaults to $true.
    .PARAMETER Priority
        Sets the priority for this target. Defaults to 100.
    .EXAMPLE
        PS C:\> $AdGroup = Search-WEMActiveDirectoryObject -ForestName "domain.local" -Filter "ad_group_name"
        PS C:\> New-WEMAssignmentTarget -SiteId 19 -Name $AdGroup.name -Sid $AdGroup.sid -ForestName "domain.local" -Type "Group"

        First finds an AD group and then uses its properties to create a new assignment target in Site 19.
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-11-06
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Sid,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [int]$SiteId,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$ForestName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet("Group", "User")]
        [string]$Type = "Group",

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$DomainName,

        [Parameter(Mandatory = $false)]
        [string]$Description = "",

        [Parameter(Mandatory = $false)]
        [bool]$Enabled = $true,

        [Parameter(Mandatory = $false)]
        [int]$Priority = 100,

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

        # Default the DomainName to the ForestName if it's not explicitly provided
        if (-not $PSBoundParameters.ContainsKey('DomainName')) {
            $DomainName = $ForestName
        }

        if ($PSCmdlet.ShouldProcess($Name, "Create WEM Assignment Target")) {
            # Construct the nested directoryContext object
            $DirectoryContext = [PSCustomObject]@{
                forest           = $ForestName
                domain           = $DomainName
                identityProvider = "AD"
                tenantId         = ""
            }

            # Construct the main request body
            $Body = @{
                sid              = $Sid
                type             = $Type
                description      = $Description
                siteId           = $ResolvedSiteId
                enabled          = $Enabled
                priority         = $Priority
                directoryContext = $DirectoryContext
            }

            if ($Connection.IsOnPrem) {
                $UriPath = "services/wem/users"
            } else {
                $UriPath = "services/wem/assignmentTarget"
                $Body.name = $Name
            }
            Write-Verbose "Creating WEM Assignment Target '$($Name)' in Configuration Set ID '$($ResolvedSiteId)'..."
            Write-Verbose "Request Body: $(ConvertTo-Json $Body -Depth 5)"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body
            if ($PassThru.IsPresent) {
                $Result = Get-WEMAssignmentTarget -SiteId $ResolvedSiteId | Where-Object { $_.sid -eq $Sid }
            }
            Write-Output ($Result | Expand-WEMResult -ErrorAction SilentlyContinue)
        }
    } catch {
        Write-Error "Failed to create WEM Assignment Target '$($Name)': $($_.Exception.Message)"
        return $null
    }
}