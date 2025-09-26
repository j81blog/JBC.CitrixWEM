function Set-WEMActiveConfigurationSite {
    <#
    .SYNOPSIS
        Sets the active WEM Configuration Set for the current session.
    .DESCRIPTION
        This function sets a specific WEM Configuration Set (Site) as the active context.
        Subsequent cmdlets that require a Site ID will automatically use this value if the -SiteId
        parameter is not explicitly provided.
    .PARAMETER Id
        The ID of the Configuration Set to set as active.
    .EXAMPLE
        PS C:\> Set-WEMActiveConfigurationSite -Id 19

        Sets the Configuration Set with ID 19 as the active context for the session.
    .EXAMPLE
        PS C:\> Get-WEMConfigurationSite | Where-Object Name -eq "Default Site" | Set-WEMActiveConfigurationSite

        Finds the 'Default Site' and sets it as the active context via the pipeline.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-07
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Alias("Set-WEMActiveSite")]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [int]$Id
    )

    try {
        Write-Verbose "Verifying that Configuration Set with ID '$($Id)' exists..."

        # Verify the site exists before setting it as active.
        $Site = Get-WEMConfigurationSite | Where-Object { $_.Id -eq $Id }

        if (-not $Site) {
            throw "A Configuration Set with ID '$($Id)' could not be found."
        }

        if ($PSCmdlet.ShouldProcess("'$($Site.Name)' (ID: $($Site.Id))", "Set as Active Configuration Site")) {
            # Add/update the active site details on our connection object
            $script:WemApiConnection | Add-Member -MemberType NoteProperty -Name "ActiveSiteId" -Value $Site.Id -Force
            $script:WemApiConnection | Add-Member -MemberType NoteProperty -Name "ActiveSiteName" -Value $Site.Name -Force

            Write-Host "Active WEM Configuration Set is now: '$($Site.Name)' (ID: $($Site.Id))"
        }
    } catch {
        Write-Error "Failed to set active Configuration Set: $($_.Exception.Message)"
    }
}