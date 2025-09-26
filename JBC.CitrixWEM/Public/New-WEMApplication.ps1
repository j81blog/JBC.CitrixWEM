function New-WEMApplication {
    <#
    .SYNOPSIS
        Creates a new application action in a WEM Configuration Set.
    .DESCRIPTION
        This function creates a new application shortcut action within a specified
        WEM Configuration Set (Site). If -SiteId is not specified, it uses the active
        Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) where the application will be created. Defaults to the active site.
    .PARAMETER DisplayName
        The name of the application shortcut to be displayed to the user.
    .PARAMETER CommandLine
        The command line executable path for the application.
    .PARAMETER IconStream
        A base64-encoded string of the icon to be used for the shortcut.
    .PARAMETER IconFile
        A path to an icon file. The file will be automatically converted to a base64 string.
    .EXAMPLE
        PS C:\> New-WEMApplication -DisplayName "My App" -CommandLine "C:\apps\app.exe" -IconFile "C:\icons\myicon.ico"

        Creates a new application shortcut named "My App" in the active Configuration Set, using a local icon file.
    .NOTES
        Version:        1.1
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-12
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'File')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [string]$CommandLine,

        [Parameter(Mandatory = $false, ParameterSetName = 'Stream')]
        [string]$IconStream,

        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [string]$IconFile,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [ValidateSet("InstallerApplication", "FileFolder", "Url")]
        [string]$AppType = "InstallerApplication",

        [Parameter(Mandatory = $false)]
        [string]$StartMenuPath = "Start Menu\Programs",

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Enabled", "Disabled")]
        [string]$State = "Enabled",

        [Parameter(Mandatory = $false)]
        [string]$Parameter,

        [Parameter(Mandatory = $false)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [string]$FolderPath,

        [Parameter(Mandatory = $false)]
        [bool]$SelfHealing = $true,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Normal", "Minimized", "Maximized")]
        [string]$WindowStyle = "Normal",

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
        if ([string]::IsNullOrEmpty($IconStream)) {
            $IconStream = "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"
        }
        if (-not $PSBoundParameters.ContainsKey('Name')) {
            $Name = $DisplayName
        }

        if ($PSCmdlet.ShouldProcess($DisplayName, "Create WEM Application in Site ID '$($ResolvedSiteId)'")) {

            if ($PSCmdlet.ParameterSetName -eq 'File') {
                Write-Verbose "Converting icon file '$($IconFile)' to base64 string..."
                $IconStream = Convert-IconFileToBase64 -Path $IconFile
            }

            $Body = @{
                siteId        = $ResolvedSiteId
                startMenuPath = $StartMenuPath
                state         = $State
                actionType    = "CreateAppShortcut"
                iconStream    = $IconStream
                selfHealing   = $SelfHealing
                name          = $Name
                url           = $Url
                commandLine   = $CommandLine
                displayName   = $DisplayName
                hotKey        = "None"
                appType       = $AppType
                windowsStyle  = $WindowStyle
                folderPath    = $FolderPath
            }
            if ($PSBoundParameters.ContainsKey('WorkingDirectory')) {
                $Body.Add('workingDir', $WorkingDirectory)
            }
            if ($PSBoundParameters.ContainsKey('Parameter')) {
                $Body.Add('parameters', $Parameter)
            }
            if ($PSBoundParameters.ContainsKey('Description')) {
                $Body.Add('description', $Description)
            }
            $UriPath = "services/wem/webApplications"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

            if ($PassThru.IsPresent) {
                $Result = Get-WEMApplication -SiteId $ResolvedSiteId | Where-Object { $_.name -eq $Name -and $_.commandLine -eq $CommandLine -and $_.startMenuPath -eq $StartMenuPath -and $_.Url -eq $Url }
            }
            Write-Output ($Result | Expand-WEMResult -ErrorAction SilentlyContinue)
        }
    } catch {
        Write-Error "Failed to create WEM Application '$($DisplayName)': $($_.Exception.Message)"
        return $null
    }
}