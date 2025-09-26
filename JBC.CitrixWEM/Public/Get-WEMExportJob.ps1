function Get-WEMExportJob {
    <#
    .SYNOPSIS
        Retrieves the status of recent WEM import/export jobs.
    .DESCRIPTION
        This function gets a list of recent asynchronous jobs, such as Configuration Set exports (backups)
        or restores, and their current status.
    .PARAMETER JobType
        Filters the results to a specific type of job. Defaults to "All".
    .EXAMPLE
        PS C:\> Get-WEMExportJob -JobType Backup

        Returns a list of recent backup (export) jobs.
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-27
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("All", "Backup", "Restore")]
        [string]$JobType = "All"
    )

    try {
        $Connection = Get-WemApiConnection

        $UriPath = "services/wem/export/site/recentJobs"

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # The API returns a specific object with 'backup' and 'restore' properties
        switch ($JobType) {
            "Backup" { Write-Output $Result.backup }
            "Restore" { Write-Output $Result.restore }
            default { Write-Output ($Result.backup + $Result.restore) }
        }
    } catch {
        Write-Error "Failed to retrieve WEM export jobs: $($_.Exception.Message)"
        return $null
    }
}