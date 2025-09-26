function New-WEMBackup {
    <#
    .SYNOPSIS
        Creates a new backup of a WEM Configuration Set and optionally downloads it.
    .DESCRIPTION
        This function starts an asynchronous job to create a backup (export) of a WEM Configuration Set.
        By default, it will not overwrite an existing backup with the same name.
    .PARAMETER SiteId
        The ID of the Configuration Set to be backed up. Defaults to the active site.
    .PARAMETER BackupName
        The name for the backup.
    .PARAMETER Force
        If specified, the command will proceed even if a backup with the same name already exists.
    .PARAMETER Wait
        If specified, the function will wait for the backup job to complete or fail.
    .PARAMETER DownloadPath
        Specifies a local directory path to save the backup file. This parameter requires -Wait.
    .EXAMPLE
        PS C:\> New-WEMBackup -SiteId 1 -BackupName "WeeklyBackup" -Wait

        Creates a new backup, but will fail if "WeeklyBackup" already exists.
    .EXAMPLE
        PS C:\> New-WEMBackup -SiteId 1 -BackupName "DailyBackup" -Force

        Creates a new backup named "DailyBackup", overwriting it if it already exists.
    .NOTES
        Version:        1.3
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-27
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Wait')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$BackupName,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $true, ParameterSetName = 'Download')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Wait')]
        [switch]$Wait,

        [Parameter(Mandatory = $true, ParameterSetName = 'Download')]
        [string]$DownloadPath,

        [Parameter(Mandatory = $false)]
        [int]$PollingIntervalSeconds = 5,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300
    )

    if (-not $PSBoundParameters.ContainsKey('InformationAction')) {
        $InformationPreference = 'Continue'
    }

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

        # Check if a backup with the same name already exists, unless -Force is specified.
        if (-not $Force.IsPresent) {
            Write-Verbose "Checking for existing backup named '$($BackupName)'..."
            $ExistingBackup = Get-WEMBackup -BackupName $BackupName
            if ($ExistingBackup) {
                throw "A backup with the name '$($BackupName)' already exists. Use the -Force switch to overwrite."
            }
        }

        Write-Verbose "Retrieving details for Configuration Set with ID $ResolvedSiteId..."
        $Site = Get-WEMConfigurationSite | Where-Object { $_.Id -eq $ResolvedSiteId }
        if (-not $Site) { throw "A Configuration Set with ID '$($ResolvedSiteId)' could not be found." }

        $TargetDescription = "Configuration Set '$($Site.Name)' (ID: $($Site.Id)) to backup '$($BackupName)'"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Create Backup")) {

            $Body = @{ id = $Site.Id; name = $Site.Name; folderName = $BackupName; type = "Configuration set" }
            Invoke-WemApiRequest -UriPath "services/wem/export/site?async=true" -Method "POST" -Connection $Connection -Body $Body
            Write-Verbose "Backup job initiated successfully."

            if (-not $Wait.IsPresent) {
                Write-Information "Backup job for '$($BackupName)' started. Use Get-WEMExportJob to monitor its status."
                return
            }

            Write-Information "Waiting for backup job to complete... (Timeout: $($TimeoutSeconds)s)"
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $FinalJob = $null
            do {
                $Job = Get-WEMExportJob -JobType Backup | Where-Object { $_.name -eq $Site.Name } | Sort-Object -Property timestamp -Descending | Select-Object -First 1
                Write-Verbose "Current job status: $($Job.status)"
                if ($Job -and $Job.status -in 'Completed', 'Failed') {
                    $FinalJob = $Job
                    break
                }
                Start-Sleep -Seconds $PollingIntervalSeconds
            } while ($Stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
            $Stopwatch.Stop()

            if (-not $FinalJob) { throw "Timed out after $($TimeoutSeconds) seconds waiting for the backup job to complete." }
            if ($FinalJob.status -in 'Fail', 'Failed') { throw "The backup job failed. Final status: $($FinalJob | ConvertTo-Json -Depth 3)" }

            Write-Information "Backup job completed successfully in $('{0:n2}' -f $Stopwatch.Elapsed.TotalSeconds) seconds."

            if ($PSCmdlet.ParameterSetName -eq 'Download') {
                if (Get-WEMBackup -BackupName $BackupName) {
                    Save-WEMBackup -Path $DownloadPath -BackupName $BackupName
                } else {
                    Write-Warning "Could not find backup file '$($BackupName)' to download."
                }
            }

            Write-Output $FinalJob
        }
    } catch {
        Write-Error "Failed to create WEM Backup: $($_.Exception.Message)"
        return $null
    }
}