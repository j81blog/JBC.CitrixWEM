function Save-WEMBackup {
    <#
    .SYNOPSIS
        Downloads a WEM backup file to a local path.
    .DESCRIPTION
        This function handles the logic for downloading a specific WEM backup file for both
        Cloud and On-Premises environments.
    .PARAMETER BackupName
        The name of the backup file to download.
    .PARAMETER Path
        The local directory where the backup file will be saved.
    .EXAMPLE
        PS C:\> Save-WEMBackup -BackupName "WeeklyBackup" -Path "C:\WEM-Backups"

        Finds the "WeeklyBackup" and downloads it to the C:\WEM-Backups folder.
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-27
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BackupName,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $Connection = Get-WemApiConnection
        $Backup = Get-WEMBackup -BackupName $BackupName

        if (-not $Backup) {
            throw "A backup with the name '$($BackupName)' could not be found."
        }

        if (-not (Test-Path -Path $Path -PathType Container)) {
            Write-Verbose "Download path '$($Path)' does not exist. Creating it."
            New-Item -Path $Path -ItemType Directory -ErrorAction Stop | Out-Null
        }

        $FullOutPath = Join-Path -Path $Path -ChildPath "$($BackupName).json"

        if ($PSCmdlet.ShouldProcess($FullOutPath, "Save Backup '$($BackupName)'")) {
            $DownloadUri = ''

            if ($Connection.IsOnPrem) {
                Write-Verbose "Constructing On-Premises download URI..."
                $EncodedFileName = [System.Web.HttpUtility]::UrlEncode($Backup.fileName)
                $DownloadUri = '{0}/services/wem/onPrem/download/{1}' -f $Connection.BaseUrl, $EncodedFileName
            } else {
                Write-Verbose "Retrieving Cloud download SAS token..."
                $SasResult = Invoke-WemApiRequest -UriPath "services/wem/export/sas?isReadonly=true" -Method "GET" -Connection $Connection
                $DownloadUri = '{0}/{1}{2}' -f $SasResult.uri, $Backup.fileName, $SasResult.token
            }

            Write-Verbose "Downloading backup from '$($DownloadUri)'..."
            Invoke-WebRequest -UseBasicParsing -Uri $DownloadUri -WebSession $Connection.WebSession -OutFile $FullOutPath
            Write-Verbose "Backup successfully saved to '$($FullOutPath)'"
        }
    } catch {
        Write-Error "Failed to save WEM Backup '$($BackupName)': $($_.Exception.Message)"
    }
}