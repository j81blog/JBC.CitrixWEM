function New-WEMApplication {
    <#
    .SYNOPSIS
        Creates a new application action in a WEM Configuration Set.

    .DESCRIPTION
        This function creates a new application shortcut action within a specified WEM Configuration Set (Site).
        It supports three application types: InstallerApplication (executables), Url (web shortcuts), and
        FileFolder (folder shortcuts). Icons can be provided either as a file path (automatically converted
        to base64) or as a pre-encoded base64 string.

        If -SiteId is not specified, the function uses the active Configuration Set defined by
        Set-WEMActiveConfigurationSite. The function supports WhatIf and Confirm for safe testing.

    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) where the application will be created.
        If not specified, uses the active Configuration Set from Set-WEMActiveConfigurationSite.

    .PARAMETER DisplayName
        The display name of the application shortcut as shown to users. This is a required parameter.

    .PARAMETER CommandLine
        The executable path or command line for the application. Used with InstallerApplication type.
        Example: "C:\Program Files\MyApp\app.exe"

    .PARAMETER IconStream
        A base64-encoded string representing the icon for the application shortcut.
        Use this parameter when you already have a base64-encoded icon. This parameter
        belongs to the 'Stream' parameter set.

    .PARAMETER IconFile
        The file path to an icon file (.ico, .exe, .dll). The icon will be automatically
        extracted and converted to a base64 string. This parameter belongs to the 'File'
        parameter set and is the default method for providing icons.

    .PARAMETER Name
        The internal name for the application action. If not specified, defaults to the DisplayName value.

    .PARAMETER Description
        An optional description for the application action.

    .PARAMETER AppType
        The type of application being created. Valid values:
        - InstallerApplication: Standard executable application (default)
        - Url: Web URL shortcut
        - FileFolder: Folder or file shortcut

    .PARAMETER StartMenuPath
        The Start Menu path where the shortcut will be created.
        Default: "Start Menu\Programs"

    .PARAMETER WorkingDirectory
        The working directory for the application when launched.

    .PARAMETER State
        The state of the application action. Valid values:
        - Enabled: Application is active and available (default)
        - Disabled: Application is inactive

    .PARAMETER Parameter
        Additional command-line parameters to pass to the application.

    .PARAMETER Url
        The URL for web shortcuts. Used when AppType is set to "Url".
        Example: "https://www.example.com"

    .PARAMETER FolderPath
        The folder path for folder shortcuts. Used when AppType is set to "FileFolder".
        Example: "C:\Users\Public\Documents"

    .PARAMETER SelfHealing
        Enables or disables self-healing for the application shortcut.
        Default: $true

    .PARAMETER ActionType
        The action type for the application. Currently only "CreateAppShortcut" is supported.
        Default: "CreateAppShortcut"

    .PARAMETER Hotkey
        The keyboard hotkey for launching the application.
        Default: "None"

    .PARAMETER WindowStyle
        The window style when the application launches. Valid values:
        - Normal: Standard window (default)
        - Minimized: Start minimized
        - Maximized: Start maximized

    .PARAMETER PassThru
        Returns the created application object. By default, this function does not return output.

    .EXAMPLE
        PS C:\> New-WEMApplication -DisplayName "Notepad" -CommandLine "C:\Windows\System32\notepad.exe" -IconFile "C:\Windows\System32\notepad.exe"

        Creates a new application shortcut for Notepad in the active Configuration Set, extracting the icon from notepad.exe.

    .EXAMPLE
        PS C:\> New-WEMApplication -DisplayName "Company Portal" -AppType Url -Url "https://portal.company.com" -IconFile "C:\icons\portal.ico" -PassThru

        Creates a URL shortcut to the company portal with a custom icon and returns the created object.

    .EXAMPLE
        PS C:\> New-WEMApplication -DisplayName "Shared Documents" -AppType FileFolder -FolderPath "\\server\share\documents" -IconFile "C:\icons\folder.ico" -SiteId 42

        Creates a folder shortcut to a network share in Configuration Set with ID 42.

    .EXAMPLE
        PS C:\> New-WEMApplication -DisplayName "Chrome" -CommandLine "C:\Program Files\Google\Chrome\Application\chrome.exe" -Parameter "--incognito" -WorkingDirectory "%USERPROFILE%" -IconFile "C:\Program Files\Google\Chrome\Application\chrome.exe" -WindowStyle Maximized

        Creates a Chrome application shortcut that launches in incognito mode, maximized, with a custom working directory.

    .EXAMPLE
        PS C:\> New-WEMApplication -DisplayName "MyApp" -CommandLine "C:\apps\myapp.exe" -IconStream $Base64Icon -WhatIf

        Tests creating an application using a pre-encoded icon without actually creating it (WhatIf).

    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Claude Code
        Creation Date:  2025-08-12
        Updated:        2025-11-06

        The function uses parameter sets to ensure either IconFile or IconStream is provided, but not both.
        If no icon is provided via IconStream, a default WEM icon is used.
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
        [ValidateSet("CreateAppShortcut")]
        [string]$ActionType = "CreateAppShortcut",

        [Parameter(Mandatory = $false)]
        [string]$Hotkey = "None",

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
                $IconStream = Export-FileIcon -FilePath $IconFile -Size 32 -AsBase64
            }

            $Body = @{
                siteId        = $ResolvedSiteId
                startMenuPath = $StartMenuPath
                state         = $State
                actionType    = $ActionType
                iconStream    = $IconStream
                selfHealing   = $SelfHealing
                name          = $Name
                url           = $Url
                commandLine   = $CommandLine
                displayName   = $DisplayName
                hotKey        = $Hotkey
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