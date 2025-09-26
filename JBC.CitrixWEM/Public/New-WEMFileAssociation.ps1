function New-WEMFileAssociation {
    <#
    .SYNOPSIS
        Creates a new file type association action in a WEM Configuration Set.
    .DESCRIPTION
        This function adds a new file type association. If -SiteId is not specified, it uses
        the active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER Name
        The unique name for the file association action.
    .PARAMETER FileExtension
        The file extension to associate (e.g., ".txt", ".pdf").
    .PARAMETER TargetPath
        The full path to the application that will open the file.
    .PARAMETER TargetCommand
        The command-line arguments for the target application (e.g., '"%1"').
    .PARAMETER SiteId
        The ID of the WEM Configuration Set. Defaults to the active site.
    .PARAMETER PassThru
        If specified, the command returns the newly created file association object.
    .EXAMPLE
        PS C:\> New-WEMFileAssociation -Name "Notepad++ TXT" -FileExtension ".txt" -TargetPath "C:\Program Files\Notepad++\notepad++.exe" -TargetCommand "`"%1`""

        Creates a file association to open .txt files with Notepad++.
    .NOTES
        Function  : New-WEMFileAssociation
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.0
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FileExtension,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetCommand,

        [Parameter(Mandatory = $false)]
        [string]$ProgId,

        [Parameter(Mandatory = $false)]
        [string]$Action = "Open",

        [Parameter(Mandatory = $false)]
        [bool]$Enabled = $true,

        [Parameter(Mandatory = $false)]
        [switch]$IsDefault,

        [Parameter(Mandatory = $false)]
        [switch]$TargetOverwrite,

        [Parameter(Mandatory = $false)]
        [switch]$RunOnce,

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

        if ($PSCmdlet.ShouldProcess($FileExtension, "Create WEM File Association for '$($Name)' in Site ID '$($ResolvedSiteId)'")) {
            $Body = @{
                siteId          = $ResolvedSiteId
                enabled         = $Enabled
                isDefault       = $IsDefault.IsPresent
                targetOverwrite = $TargetOverwrite.IsPresent
                runOnce         = $RunOnce.IsPresent
                targetPath      = $TargetPath
                targetCommand   = $TargetCommand
                name            = $Name
                fileExtension   = $FileExtension
                action          = $Action
            }
            if ($PSBoundParameters.ContainsKey('ProgId')) {
                $Body.Add('progId', $ProgId)
            }

            $UriPath = "services/wem/action/fileAssociations"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

            if ($PassThru.IsPresent) {
                Write-Verbose "PassThru specified, retrieving newly created file association..."
                # Assuming Get-WEMFileAssociation exists
                $Result = Get-WEMFileAssociation -SiteId $ResolvedSiteId | Where-Object { $_.Name -ieq $Name }
            }

            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to create WEM File Association '$($Name)': $($_.Exception.Message)"
        return $null
    }
}