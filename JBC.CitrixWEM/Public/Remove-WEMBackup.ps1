function Remove-WEMBackup {
    <#
    .SYNOPSIS
        Removes one or more WEM backups.
    .DESCRIPTION
        This function removes one or more WEM backups from the service. It can take backup names directly
        or backup objects from the pipeline. This is a destructive operation and should be used with caution.
    .PARAMETER BackupName
        The name (or an array of names) of the backup(s) to remove.
    .PARAMETER InputObject
        One or more backup objects, as returned by Get-WEMBackup, to be removed.
    .EXAMPLE
        PS C:\> Remove-WEMBackup -BackupName "OldBackup"

        Removes the backup named "OldBackup" after asking for confirmation.
    .EXAMPLE
        PS C:\> Get-WEMBackup | Where-Object { $_.lastModified -lt (Get-Date).AddDays(-30) } | Remove-WEMBackup -WhatIf

        Shows which backups older than 30 days would be removed, without actually removing them.
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-28
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByName', Position = 0)]
        [string[]]$BackupName,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInputObject', ValueFromPipeline = $true)]
        [PSCustomObject[]]$InputObject
    )

    process {
        try {
            $Connection = Get-WemApiConnection

            $BackupsToDelete = @()
            if ($PSCmdlet.ParameterSetName -eq 'ByInputObject') {
                $BackupsToDelete = $InputObject
            } else {
                # If names are provided, first get the full backup objects to ensure we have the correct fileName
                Write-Verbose "Retrieving details for backup(s): $($BackupName -join ', ')"
                $BackupsToDelete = $BackupName | ForEach-Object { Get-WEMBackup -BackupName $_ }
            }

            if (-not $BackupsToDelete) {
                throw "No matching backups found to remove."
            }

            $TargetDescription = "WEM Backup(s): $($BackupsToDelete.folderName -join ', ')"
            if ($PSCmdlet.ShouldProcess($TargetDescription, "Remove")) {

                # to get the exact path required by the API, e.g., "site/MyBackup/"
                $StringList = $BackupsToDelete | ForEach-Object { $_.fileName.Replace('site.json', '') }

                $Body = @{
                    stringList = $StringList
                }

                $UriPath = "services/wem/export/multiple"

                Invoke-WemApiRequest -UriPath $UriPath -Method "DELETE" -Connection $Connection -Body $Body
                Write-Verbose "Successfully sent request to remove $($TargetDescription)"
            }
        } catch {
            Write-Error "Failed to remove WEM Backup(s): $($_.Exception.Message)"
        }
    }
}