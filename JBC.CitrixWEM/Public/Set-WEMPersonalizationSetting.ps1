function Set-WEMPersonalizationSetting {
    <#
    .SYNOPSIS
        Updates personalization settings (UI Agent settings) for a WEM Configuration Set.
    .DESCRIPTION
        This function updates the UI Agent personalization settings for a specific WEM Configuration Set (Site).
        These settings control the appearance and behavior of the WEM UI Agent, including splash screen,
        theme, colors, email settings, and other visual and functional customization options.

        Only parameters that are explicitly provided will be updated. To retrieve current settings first,
        use Get-WEMPersonalizationSetting.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set (Site) to update. If not specified, uses the active site.
    .PARAMETER UIAgentSplashScreenLogo
        UNC path to the splash screen logo image file (e.g., "\\server\share\logo.png").
    .PARAMETER UIAgentLoadingCircleColor
        Color of the loading circle. Uses standard .NET color names (e.g., White, Black, Red, Blue, MediumTurquoise).
    .PARAMETER UIAgentTextColor
        Color of the UI text. Uses standard .NET color names (e.g., White, Black, Red, Blue, MediumTurquoise).
    .PARAMETER UIAgentHelpLink
        URL for the Help link in the UI Agent.
    .PARAMETER UIAgentSupportLink
        URL for the Support link in the UI Agent.
    .PARAMETER UIAgentThemeName
        Theme name for the UI Agent. Common values: "Seven", "Modern", etc.
    .PARAMETER AllowUsersToManageApplications
        Allow users to manage their own applications.
    .PARAMETER HideUIAgentIconInPublishedApplications
        Hide the UI Agent icon when running in published applications.
    .PARAMETER HideUIAgentSplashScreen
        Hide the UI Agent splash screen on startup.
    .PARAMETER HideUIAgentSplashScreenInPublishedApplications
        Hide the UI Agent splash screen in published applications.
    .PARAMETER HideUIAgentSplashScreenOnReconnect
        Hide the UI Agent splash screen on reconnect.
    .PARAMETER AllowScreenCapture
        Enable screen capture functionality.
    .PARAMETER ScreenCaptureEnableSendSupportEmail
        Enable sending support emails with screen captures.
    .PARAMETER ScreenCaptureSupportEmailAddress
        Email address for screen capture support emails.
    .PARAMETER ScreenCaptureSupportEmailTemplate
        Email template for screen capture support emails.
    .PARAMETER ApplicationsShortcutsEnabled
        Enable application shortcuts.
    .PARAMETER MailEnableUseSMTP
        Enable SMTP for email functionality.
    .PARAMETER MailEnableSMTPSSL
        Enable SSL for SMTP connections.
    .PARAMETER MailSMTPPort
        SMTP server port number.
    .PARAMETER MailEnableUseSMTPCredentials
        Enable authentication for SMTP.
    .PARAMETER MailSMTPServer
        SMTP server address.
    .PARAMETER MailSMTPFromAddress
        From address for SMTP emails.
    .PARAMETER MailCustomSubject
        Custom subject line for emails.
    .PARAMETER ShutdownAfterIdleEnabled
        Enable automatic shutdown after idle period.
    .PARAMETER ShutdownAfterIdleTime
        Idle time in seconds before shutdown (e.g., 1800 for 30 minutes).
    .PARAMETER ShutdownAfterEnabled
        Enable scheduled shutdown.
    .PARAMETER ShutdownAfter
        Time for scheduled shutdown (e.g., "02:00" for 2 AM).
    .PARAMETER SuspendInsteadOfShutdown
        Suspend the system instead of shutting down.
    .PARAMETER AllowAgentInsightsManagement
        Allow management of Agent Insights.
    .EXAMPLE
        PS C:\> Set-WEMPersonalizationSetting -SiteId 16 -UIAgentTextColor "MediumTurquoise" -UIAgentLoadingCircleColor "White"

        Updates the text color and loading circle color for Site ID 16.
    .EXAMPLE
        PS C:\> Set-WEMPersonalizationSetting -UIAgentSplashScreenLogo "\\server\netlogon\company-logo.png" -UIAgentThemeName "Seven"

        Updates the splash screen logo and theme for the active Configuration Set.
    .EXAMPLE
        PS C:\> Set-WEMPersonalizationSetting -HideUIAgentSplashScreen $true -AllowUsersToManageApplications $false

        Hides the splash screen and disables user application management.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Claude Code
        Creation Date:  2025-10-28
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$SiteId,

        # UI Appearance Settings
        [Parameter(Mandatory = $false)]
        [string]$UIAgentSplashScreenLogo,

        [Parameter(Mandatory = $false)]
        [ValidateSet("AliceBlue", "AntiqueWhite", "Aqua", "Aquamarine", "Azure", "Beige", "Bisque", "Black", "BlanchedAlmond",
                     "Blue", "BlueViolet", "Brown", "BurlyWood", "CadetBlue", "Chartreuse", "Chocolate", "Coral", "CornflowerBlue",
                     "Cornsilk", "Crimson", "Cyan", "DarkBlue", "DarkCyan", "DarkGoldenrod", "DarkGray", "DarkGreen", "DarkKhaki",
                     "DarkMagenta", "DarkOliveGreen", "DarkOrange", "DarkOrchid", "DarkRed", "DarkSalmon", "DarkSeaGreen",
                     "DarkSlateBlue", "DarkSlateGray", "DarkTurquoise", "DarkViolet", "DeepPink", "DeepSkyBlue", "DimGray",
                     "DodgerBlue", "Firebrick", "FloralWhite", "ForestGreen", "Fuchsia", "Gainsboro", "GhostWhite", "Gold",
                     "Goldenrod", "Gray", "Green", "GreenYellow", "Honeydew", "HotPink", "IndianRed", "Indigo", "Ivory", "Khaki",
                     "Lavender", "LavenderBlush", "LawnGreen", "LemonChiffon", "LightBlue", "LightCoral", "LightCyan",
                     "LightGoldenrodYellow", "LightGray", "LightGreen", "LightPink", "LightSalmon", "LightSeaGreen", "LightSkyBlue",
                     "LightSlateGray", "LightSteelBlue", "LightYellow", "Lime", "LimeGreen", "Linen", "Magenta", "Maroon",
                     "MediumAquamarine", "MediumBlue", "MediumOrchid", "MediumPurple", "MediumSeaGreen", "MediumSlateBlue",
                     "MediumSpringGreen", "MediumTurquoise", "MediumVioletRed", "MidnightBlue", "MintCream", "MistyRose", "Moccasin",
                     "NavajoWhite", "Navy", "OldLace", "Olive", "OliveDrab", "Orange", "OrangeRed", "Orchid", "PaleGoldenrod",
                     "PaleGreen", "PaleTurquoise", "PaleVioletRed", "PapayaWhip", "PeachPuff", "Peru", "Pink", "Plum", "PowderBlue",
                     "Purple", "Red", "RosyBrown", "RoyalBlue", "SaddleBrown", "Salmon", "SandyBrown", "SeaGreen", "SeaShell", "Sienna",
                     "Silver", "SkyBlue", "SlateBlue", "SlateGray", "Snow", "SpringGreen", "SteelBlue", "Tan", "Teal", "Thistle",
                     "Tomato", "Transparent", "Turquoise", "Violet", "Wheat", "White", "WhiteSmoke", "Yellow", "YellowGreen")]
        [string]$UIAgentLoadingCircleColor,

        [Parameter(Mandatory = $false)]
        [ValidateSet("AliceBlue", "AntiqueWhite", "Aqua", "Aquamarine", "Azure", "Beige", "Bisque", "Black", "BlanchedAlmond",
                     "Blue", "BlueViolet", "Brown", "BurlyWood", "CadetBlue", "Chartreuse", "Chocolate", "Coral", "CornflowerBlue",
                     "Cornsilk", "Crimson", "Cyan", "DarkBlue", "DarkCyan", "DarkGoldenrod", "DarkGray", "DarkGreen", "DarkKhaki",
                     "DarkMagenta", "DarkOliveGreen", "DarkOrange", "DarkOrchid", "DarkRed", "DarkSalmon", "DarkSeaGreen",
                     "DarkSlateBlue", "DarkSlateGray", "DarkTurquoise", "DarkViolet", "DeepPink", "DeepSkyBlue", "DimGray",
                     "DodgerBlue", "Firebrick", "FloralWhite", "ForestGreen", "Fuchsia", "Gainsboro", "GhostWhite", "Gold",
                     "Goldenrod", "Gray", "Green", "GreenYellow", "Honeydew", "HotPink", "IndianRed", "Indigo", "Ivory", "Khaki",
                     "Lavender", "LavenderBlush", "LawnGreen", "LemonChiffon", "LightBlue", "LightCoral", "LightCyan",
                     "LightGoldenrodYellow", "LightGray", "LightGreen", "LightPink", "LightSalmon", "LightSeaGreen", "LightSkyBlue",
                     "LightSlateGray", "LightSteelBlue", "LightYellow", "Lime", "LimeGreen", "Linen", "Magenta", "Maroon",
                     "MediumAquamarine", "MediumBlue", "MediumOrchid", "MediumPurple", "MediumSeaGreen", "MediumSlateBlue",
                     "MediumSpringGreen", "MediumTurquoise", "MediumVioletRed", "MidnightBlue", "MintCream", "MistyRose", "Moccasin",
                     "NavajoWhite", "Navy", "OldLace", "Olive", "OliveDrab", "Orange", "OrangeRed", "Orchid", "PaleGoldenrod",
                     "PaleGreen", "PaleTurquoise", "PaleVioletRed", "PapayaWhip", "PeachPuff", "Peru", "Pink", "Plum", "PowderBlue",
                     "Purple", "Red", "RosyBrown", "RoyalBlue", "SaddleBrown", "Salmon", "SandyBrown", "SeaGreen", "SeaShell", "Sienna",
                     "Silver", "SkyBlue", "SlateBlue", "SlateGray", "Snow", "SpringGreen", "SteelBlue", "Tan", "Teal", "Thistle",
                     "Tomato", "Transparent", "Turquoise", "Violet", "Wheat", "White", "WhiteSmoke", "Yellow", "YellowGreen")]
        [string]$UIAgentTextColor,

        [Parameter(Mandatory = $false)]
        [string]$UIAgentHelpLink,

        [Parameter(Mandatory = $false)]
        [string]$UIAgentSupportLink,

        [Parameter(Mandatory = $false)]
        [string]$UIAgentThemeName,

        # UI Behavior Settings
        [Parameter(Mandatory = $false)]
        [bool]$AllowUsersToManageApplications,

        [Parameter(Mandatory = $false)]
        [bool]$HideUIAgentIconInPublishedApplications,

        [Parameter(Mandatory = $false)]
        [bool]$HideUIAgentSplashScreen,

        [Parameter(Mandatory = $false)]
        [bool]$HideUIAgentSplashScreenInPublishedApplications,

        [Parameter(Mandatory = $false)]
        [bool]$HideUIAgentSplashScreenOnReconnect,

        # Screen Capture Settings
        [Parameter(Mandatory = $false)]
        [bool]$AllowScreenCapture,

        [Parameter(Mandatory = $false)]
        [bool]$ScreenCaptureEnableSendSupportEmail,

        [Parameter(Mandatory = $false)]
        [string]$ScreenCaptureSupportEmailAddress,

        [Parameter(Mandatory = $false)]
        [string]$ScreenCaptureSupportEmailTemplate,

        # Application Settings
        [Parameter(Mandatory = $false)]
        [bool]$ApplicationsShortcutsEnabled,

        # Email Settings
        [Parameter(Mandatory = $false)]
        [bool]$MailEnableUseSMTP,

        [Parameter(Mandatory = $false)]
        [bool]$MailEnableSMTPSSL,

        [Parameter(Mandatory = $false)]
        [int]$MailSMTPPort,

        [Parameter(Mandatory = $false)]
        [bool]$MailEnableUseSMTPCredentials,

        [Parameter(Mandatory = $false)]
        [string]$MailSMTPServer,

        [Parameter(Mandatory = $false)]
        [string]$MailSMTPFromAddress,

        [Parameter(Mandatory = $false)]
        [string]$MailCustomSubject,

        # Shutdown Settings
        [Parameter(Mandatory = $false)]
        [bool]$ShutdownAfterIdleEnabled,

        [Parameter(Mandatory = $false)]
        [int]$ShutdownAfterIdleTime,

        [Parameter(Mandatory = $false)]
        [bool]$ShutdownAfterEnabled,

        [Parameter(Mandatory = $false)]
        [string]$ShutdownAfter,

        [Parameter(Mandatory = $false)]
        [bool]$SuspendInsteadOfShutdown,

        # Agent Insights
        [Parameter(Mandatory = $false)]
        [bool]$AllowAgentInsightsManagement
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

        $TargetDescription = "WEM Personalization Settings for Site ID '$($ResolvedSiteId)'"
        if ($PSCmdlet.ShouldProcess($TargetDescription, "Update")) {

            # First, retrieve the current settings to ensure we have all required fields
            Write-Verbose "Retrieving current personalization settings for Site ID '$($ResolvedSiteId)'..."
            $CurrentSettings = Get-WEMPersonalizationSetting -SiteId $ResolvedSiteId

            if (-not $CurrentSettings) {
                throw "Failed to retrieve current personalization settings. Cannot proceed with update."
            }

            # Convert current settings to hashtable for easy manipulation
            $SettingsObject = $CurrentSettings | ConvertTo-Hashtable

            # Update only the properties that were explicitly provided
            if ($PSBoundParameters.ContainsKey('UIAgentSplashScreenLogo')) {
                $SettingsObject['uiAgentSplashScreenLogo'] = $UIAgentSplashScreenLogo
            }
            if ($PSBoundParameters.ContainsKey('UIAgentLoadingCircleColor')) {
                $SettingsObject['uiAgentLoadingCircleColor'] = $UIAgentLoadingCircleColor
            }
            if ($PSBoundParameters.ContainsKey('UIAgentTextColor')) {
                $SettingsObject['uiAgentTextColor'] = $UIAgentTextColor
            }
            if ($PSBoundParameters.ContainsKey('UIAgentHelpLink')) {
                $SettingsObject['uiAgentHelpLink'] = $UIAgentHelpLink
            }
            if ($PSBoundParameters.ContainsKey('UIAgentSupportLink')) {
                $SettingsObject['uiAgentSupportLink'] = $UIAgentSupportLink
            }
            if ($PSBoundParameters.ContainsKey('UIAgentThemeName')) {
                $SettingsObject['uiAgentThemeName'] = $UIAgentThemeName
            }
            if ($PSBoundParameters.ContainsKey('AllowUsersToManageApplications')) {
                $SettingsObject['allowUsersToManageApplications'] = $AllowUsersToManageApplications
            }
            if ($PSBoundParameters.ContainsKey('HideUIAgentIconInPublishedApplications')) {
                $SettingsObject['hideUIAgentIconInPublishedApplications'] = $HideUIAgentIconInPublishedApplications
            }
            if ($PSBoundParameters.ContainsKey('HideUIAgentSplashScreen')) {
                $SettingsObject['hideUIAgentSplashScreen'] = $HideUIAgentSplashScreen
            }
            if ($PSBoundParameters.ContainsKey('HideUIAgentSplashScreenInPublishedApplications')) {
                $SettingsObject['hideUIAgentSplashScreenInPublishedApplications'] = $HideUIAgentSplashScreenInPublishedApplications
            }
            if ($PSBoundParameters.ContainsKey('HideUIAgentSplashScreenOnReconnect')) {
                $SettingsObject['hideUIAgentSplashScreenOnReconnect'] = $HideUIAgentSplashScreenOnReconnect
            }
            if ($PSBoundParameters.ContainsKey('AllowScreenCapture')) {
                $SettingsObject['allowScreenCapture'] = $AllowScreenCapture
            }
            if ($PSBoundParameters.ContainsKey('ScreenCaptureEnableSendSupportEmail')) {
                $SettingsObject['screenCaptureEnableSendSupportEmail'] = $ScreenCaptureEnableSendSupportEmail
            }
            if ($PSBoundParameters.ContainsKey('ScreenCaptureSupportEmailAddress')) {
                $SettingsObject['screenCaptureSupportEmailAddress'] = $ScreenCaptureSupportEmailAddress
            }
            if ($PSBoundParameters.ContainsKey('ScreenCaptureSupportEmailTemplate')) {
                $SettingsObject['screenCaptureSupportEmailTemplate'] = $ScreenCaptureSupportEmailTemplate
            }
            if ($PSBoundParameters.ContainsKey('ApplicationsShortcutsEnabled')) {
                $SettingsObject['applicationsShortcutsEnabled'] = $ApplicationsShortcutsEnabled
            }
            if ($PSBoundParameters.ContainsKey('MailEnableUseSMTP')) {
                $SettingsObject['mailEnableUseSMTP'] = $MailEnableUseSMTP
            }
            if ($PSBoundParameters.ContainsKey('MailEnableSMTPSSL')) {
                $SettingsObject['mailEnableSMTPSSL'] = $MailEnableSMTPSSL
            }
            if ($PSBoundParameters.ContainsKey('MailSMTPPort')) {
                $SettingsObject['mailSMTPPort'] = $MailSMTPPort
            }
            if ($PSBoundParameters.ContainsKey('MailEnableUseSMTPCredentials')) {
                $SettingsObject['mailEnableUseSMTPCredentials'] = $MailEnableUseSMTPCredentials
            }
            if ($PSBoundParameters.ContainsKey('MailSMTPServer')) {
                $SettingsObject['mailSMTPServer'] = $MailSMTPServer
            }
            if ($PSBoundParameters.ContainsKey('MailSMTPFromAddress')) {
                $SettingsObject['mailSMTPFromAddress'] = $MailSMTPFromAddress
            }
            if ($PSBoundParameters.ContainsKey('MailCustomSubject')) {
                $SettingsObject['mailCustomSubject'] = $MailCustomSubject
            }
            if ($PSBoundParameters.ContainsKey('ShutdownAfterIdleEnabled')) {
                $SettingsObject['shutdownAfterIdleEnabled'] = $ShutdownAfterIdleEnabled
            }
            if ($PSBoundParameters.ContainsKey('ShutdownAfterIdleTime')) {
                $SettingsObject['shutdownAfterIdleTime'] = $ShutdownAfterIdleTime
            }
            if ($PSBoundParameters.ContainsKey('ShutdownAfterEnabled')) {
                $SettingsObject['shutdownAfterEnabled'] = $ShutdownAfterEnabled
            }
            if ($PSBoundParameters.ContainsKey('ShutdownAfter')) {
                $SettingsObject['shutdownAfter'] = $ShutdownAfter
            }
            if ($PSBoundParameters.ContainsKey('SuspendInsteadOfShutdown')) {
                $SettingsObject['suspendInsteadOfShutdown'] = $SuspendInsteadOfShutdown
            }
            if ($PSBoundParameters.ContainsKey('AllowAgentInsightsManagement')) {
                $SettingsObject['allowAgentInsightsManagement'] = $AllowAgentInsightsManagement
            }

            # The API expects the entire settings object
            $UriPath = "services/wem/advancedSetting/personalizationSettings"
            $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "PUT" -Connection $Connection -Body $SettingsObject

            Write-Output ($Result | Expand-WEMResult)
        }
    } catch {
        Write-Error "Failed to update WEM Personalization Settings for Site ID '$($ResolvedSiteId)': $($_.Exception.Message)"
        return $null
    }
}
