function Get-WEMBackup {
    <#
    .SYNOPSIS
        Retrieves a list of available WEM backup files.
    .DESCRIPTION
        This function retrieves the list of available backups from the WEM service. If a BackupName is provided,
        it filters for that specific backup. Otherwise, it returns all backups.
        The function always returns an array.
    .PARAMETER BackupName
        The optional name of the backup folder to find.
    .EXAMPLE
        PS C:\> Get-WEMBackup

        Returns all available WEM backups.
    .EXAMPLE
        PS C:\> Get-WEMBackup -BackupName "WeeklyBackup"

        Returns the specific backup details for "WeeklyBackup".
    .NOTES
        Version:        1.4
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-27
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param (
        [Parameter(Mandatory = $false)]
        [string]$BackupName
    )

    try {
        $Connection = Get-WemApiConnection
        $UriPath = "services/wem/export?includeExtra=true"
        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "GET" -Connection $Connection

        # REFINED: Removed -ErrorAction SilentlyContinue to avoid hiding potential errors.
        $BackupList = $Result | Expand-WEMResult

        if ($PSBoundParameters.ContainsKey('BackupName')) {
            $BackupFile = $BackupList | Where-Object { $_.fileName -like "*/$($BackupName)/*" }

            if (-not $BackupFile) {
                return @()
            }
            return @($BackupFile)
        } else {
            return @($BackupList)
        }
    } catch {
        Write-Error "Failed to get WEM backup details: $($_.Exception.Message)"
        return $null
    }
}