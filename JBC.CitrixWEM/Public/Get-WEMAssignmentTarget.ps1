function Get-WEMAssignmentTarget {
    <#
    .SYNOPSIS
        Retrieves assignment targets (users/groups) from a WEM Configuration Set.
    .DESCRIPTION
        This function gets a list of all configured assignment targets. It intelligently uses the correct
        API method (GET for Cloud, POST for On-Premises). For On-Premises connections, it also
        automatically resolves SIDs to their proper names.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set to query. Defaults to the active site.
    .EXAMPLE
        PS C:\> # After setting the active site
        PS C:\> Get-WEMAssignmentTarget

        Retrieves all assignment targets from the active Configuration Set, regardless of environment.
    .NOTES
        Function  : Get-WEMAssignmentTarget
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.2
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId
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

        $UriPath = ''
        $Method = ''
        $Body = $null

        if ($Connection.IsOnPrem) {
            $UriPath = "services/wem/cachedAdObject/assignmentTarget/`$query"
            $Method = "POST"
            $Body = @{
                filters = @(
                    @{
                        param    = "SiteId"
                        operator = "Equals"
                        value    = $ResolvedSiteId
                    }
                )
            }
        } else {
            $UriPath = "services/wem/assignmentTarget/`$query"
            $Method = "POST"
            $Body = @{
                filters = @(
                    @{
                        param    = "SiteId"
                        operator = "Equals"
                        value    = $ResolvedSiteId
                    }
                )
            }
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method $Method -Connection $Connection -Body $Body
        $InitialTargets = @($Result | Expand-WEMResult)

        if ($Connection.IsOnPrem -and $InitialTargets.Count -gt 0) {
            # --- On-Premises SID Resolution Logic ---
            Write-Verbose "On-Premises connection detected. Resolving SIDs to names..."
            $SidsToResolve = $InitialTargets.sid
            $ResolvedObjects = Resolve-WEMSid -Sid $SidsToResolve

            $ResolvedLookup = $ResolvedObjects | Group-Object -Property { $_.identity.sid } -AsHashTable -AsString

            foreach ($Target in $InitialTargets) {
                if ($ResolvedLookup.ContainsKey($Target.sid)) {
                    $ResolvedData = $ResolvedLookup[$Target.sid]
                    $Target.name = $ResolvedData.propertiesEx.accountName
                    $Target.type = $ResolvedData.type
                }
            }
            Write-Output $InitialTargets
        } else {
            # --- Cloud Logic (or empty On-Prem result) ---
            Write-Output $InitialTargets
        }
    } catch {
        Write-Error "Failed to retrieve WEM Assignment Targets for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}