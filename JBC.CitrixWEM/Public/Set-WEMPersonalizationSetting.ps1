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

# SIG # Begin signature block
# MIImdwYJKoZIhvcNAQcCoIImaDCCJmQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAWpPMTydbdlx0J
# mjQDXuPH5T5XfVtj6Ng3Bi3Qi+yHBaCCIAowggYUMIID/KADAgECAhB6I67aU2mW
# D5HIPlz0x+M/MA0GCSqGSIb3DQEBDAUAMFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQK
# Ew9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28gUHVibGljIFRpbWUg
# U3RhbXBpbmcgUm9vdCBSNDYwHhcNMjEwMzIyMDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYD
# VQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNjCCAaIwDQYJ
# KoZIhvcNAQEBBQADggGPADCCAYoCggGBAM2Y2ENBq26CK+z2M34mNOSJjNPvIhKA
# VD7vJq+MDoGD46IiM+b83+3ecLvBhStSVjeYXIjfa3ajoW3cS3ElcJzkyZlBnwDE
# JuHlzpbN4kMH2qRBVrjrGJgSlzzUqcGQBaCxpectRGhhnOSwcjPMI3G0hedv2eNm
# GiUbD12OeORN0ADzdpsQ4dDi6M4YhoGE9cbY11XxM2AVZn0GiOUC9+XE0wI7CQKf
# OUfigLDn7i/WeyxZ43XLj5GVo7LDBExSLnh+va8WxTlA+uBvq1KO8RSHUQLgzb1g
# bL9Ihgzxmkdp2ZWNuLc+XyEmJNbD2OIIq/fWlwBp6KNL19zpHsODLIsgZ+WZ1AzC
# s1HEK6VWrxmnKyJJg2Lv23DlEdZlQSGdF+z+Gyn9/CRezKe7WNyxRf4e4bwUtrYE
# 2F5Q+05yDD68clwnweckKtxRaF0VzN/w76kOLIaFVhf5sMM/caEZLtOYqYadtn03
# 4ykSFaZuIBU9uCSrKRKTPJhWvXk4CllgrwIDAQABo4IBXDCCAVgwHwYDVR0jBBgw
# FoAU9ndq3T/9ARP/FqFsggIv0Ao9FCUwHQYDVR0OBBYEFF9Y7UwxeqJhQo1SgLqz
# YZcZojKbMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBDMEGg
# P6A9hjtodHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNUaW1lU3Rh
# bXBpbmdSb290UjQ2LmNybDB8BggrBgEFBQcBAQRwMG4wRwYIKwYBBQUHMAKGO2h0
# dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jv
# b3RSNDYucDdjMCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTAN
# BgkqhkiG9w0BAQwFAAOCAgEAEtd7IK0ONVgMnoEdJVj9TC1ndK/HYiYh9lVUacah
# RoZ2W2hfiEOyQExnHk1jkvpIJzAMxmEc6ZvIyHI5UkPCbXKspioYMdbOnBWQUn73
# 3qMooBfIghpR/klUqNxx6/fDXqY0hSU1OSkkSivt51UlmJElUICZYBodzD3M/SFj
# eCP59anwxs6hwj1mfvzG+b1coYGnqsSz2wSKr+nDO+Db8qNcTbJZRAiSazr7KyUJ
# Go1c+MScGfG5QHV+bps8BX5Oyv9Ct36Y4Il6ajTqV2ifikkVtB3RNBUgwu/mSiSU
# ice/Jp/q8BMk/gN8+0rNIE+QqU63JoVMCMPY2752LmESsRVVoypJVt8/N3qQ1c6F
# ibbcRabo3azZkcIdWGVSAdoLgAIxEKBeNh9AQO1gQrnh1TA8ldXuJzPSuALOz1Uj
# b0PCyNVkWk7hkhVHfcvBfI8NtgWQupiaAeNHe0pWSGH2opXZYKYG4Lbukg7HpNi/
# KqJhue2Keak6qH9A8CeEOB7Eob0Zf+fU+CCQaL0cJqlmnx9HCDxF+3BLbUufrV64
# EbTI40zqegPZdA+sXCmbcZy6okx/SjwsusWRItFA3DE8MORZeFb6BmzBtqKJ7l93
# 9bbKBy2jvxcJI98Va95Q5JnlKor3m0E7xpMeYRriWklUPsetMSf2NvUQa/E5vVye
# fQIwggZFMIIELaADAgECAhAIMk+dt9qRb2Pk8qM8Xl1RMA0GCSqGSIb3DQEBCwUA
# MFYxCzAJBgNVBAYTAlBMMSEwHwYDVQQKExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMu
# QS4xJDAiBgNVBAMTG0NlcnR1bSBDb2RlIFNpZ25pbmcgMjAyMSBDQTAeFw0yNDA0
# MDQxNDA0MjRaFw0yNzA0MDQxNDA0MjNaMGsxCzAJBgNVBAYTAk5MMRIwEAYDVQQH
# DAlTY2hpam5kZWwxIzAhBgNVBAoMGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5
# MSMwIQYDVQQDDBpKb2huIEJpbGxla2VucyBDb25zdWx0YW5jeTCCAaIwDQYJKoZI
# hvcNAQEBBQADggGPADCCAYoCggGBAMslntDbSQwHZXwFhmibivbnd0Qfn6sqe/6f
# os3pKzKxEsR907RkDMet2x6RRg3eJkiIr3TFPwqBooyXXgK3zxxpyhGOcuIqyM9J
# 28DVf4kUyZHsjGO/8HFjrr3K1hABNUszP0o7H3o6J31eqV1UmCXYhQlNoW9FOmRC
# 1amlquBmh7w4EKYEytqdmdOBavAD5Xq4vLPxNP6kyA+B2YTtk/xM27TghtbwFGKn
# u9Vwnm7dFcpLxans4ONt2OxDQOMA5NwgcUv/YTpjhq9qoz6ivG55NRJGNvUXsM3w
# 2o7dR6Xh4MuEGrTSrOWGg2A5EcLH1XqQtkF5cZnAPM8W/9HUp8ggornWnFVQ9/6M
# ga+ermy5wy5XrmQpN+x3u6tit7xlHk1Hc+4XY4a4ie3BPXG2PhJhmZAn4ebNSBwN
# Hh8z7WTT9X9OFERepGSytZVeEP7hgyptSLcuhpwWeR4QdBb7dV++4p3PsAUQVHFp
# wkSbrRTv4EiJ0Lcz9P1HPGFoHiFAQQIDAQABo4IBeDCCAXQwDAYDVR0TAQH/BAIw
# ADA9BgNVHR8ENjA0MDKgMKAuhixodHRwOi8vY2NzY2EyMDIxLmNybC5jZXJ0dW0u
# cGwvY2NzY2EyMDIxLmNybDBzBggrBgEFBQcBAQRnMGUwLAYIKwYBBQUHMAGGIGh0
# dHA6Ly9jY3NjYTIwMjEub2NzcC1jZXJ0dW0uY29tMDUGCCsGAQUFBzAChilodHRw
# Oi8vcmVwb3NpdG9yeS5jZXJ0dW0ucGwvY2NzY2EyMDIxLmNlcjAfBgNVHSMEGDAW
# gBTddF1MANt7n6B0yrFu9zzAMsBwzTAdBgNVHQ4EFgQUO6KtBpOBgmrlANVAnyiQ
# C6W6lJwwSwYDVR0gBEQwQjAIBgZngQwBBAEwNgYLKoRoAYb2dwIFAQQwJzAlBggr
# BgEFBQcCARYZaHR0cHM6Ly93d3cuY2VydHVtLnBsL0NQUzATBgNVHSUEDDAKBggr
# BgEFBQcDAzAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAEQsN8wg
# PMdWVkwHPPTN+jKpdns5AKVFjcn00psf2NGVVgWWNQBIQc9lEuTBWb54IK6Ga3hx
# QRZfnPNo5HGl73YLmFgdFQrFzZ1lnaMdIcyh8LTWv6+XNWfoyCM9wCp4zMIDPOs8
# LKSMQqA/wRgqiACWnOS4a6fyd5GUIAm4CuaptpFYr90l4Dn/wAdXOdY32UhgzmSu
# xpUbhD8gVJUaBNVmQaRqeU8y49MxiVrUKJXde1BCrtR9awXbqembc7Nqvmi60tYK
# lD27hlpKtj6eGPjkht0hHEsgzU0Fxw7ZJghYG2wXfpF2ziN893ak9Mi/1dmCNmor
# GOnybKYfT6ff6YTCDDNkod4egcMZdOSv+/Qv+HAeIgEvrxE9QsGlzTwbRtbm6gwY
# YcVBs/SsVUdBn/TSB35MMxRhHE5iC3aUTkDbceo/XP3uFhVL4g2JZHpFfCSu2TQr
# rzRn2sn07jfMvzeHArCOJgBW1gPqR3WrJ4hUxL06Rbg1gs9tU5HGGz9KNQMfQFQ7
# 0Wz7UIhezGcFcRfkIfSkMmQYYpsc7rfzj+z0ThfDVzzJr2dMOFsMlfj1T6l22GBq
# 9XQx0A4lcc5Fl9pRxbOuHHWFqIBD/BCEhwniOCySzqENd2N+oz8znKooSISStnkN
# aYXt6xblJF2dx9Dn89FK7d1IquNxOwt0tI5dMIIGYjCCBMqgAwIBAgIRAKQpO24e
# 3denNAiHrXpOtyQwDQYJKoZIhvcNAQEMBQAwVTELMAkGA1UEBhMCR0IxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEsMCoGA1UEAxMjU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBDQSBSMzYwHhcNMjUwMzI3MDAwMDAwWhcNMzYwMzIxMjM1OTU5
# WjByMQswCQYDVQQGEwJHQjEXMBUGA1UECBMOV2VzdCBZb3Jrc2hpcmUxGDAWBgNV
# BAoTD1NlY3RpZ28gTGltaXRlZDEwMC4GA1UEAxMnU2VjdGlnbyBQdWJsaWMgVGlt
# ZSBTdGFtcGluZyBTaWduZXIgUjM2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEA04SV9G6kU3jyPRBLeBIHPNyUgVNnYayfsGOyYEXrn3+SkDYTLs1crcw/
# ol2swE1TzB2aR/5JIjKNf75QBha2Ddj+4NEPKDxHEd4dEn7RTWMcTIfm492TW22I
# 8LfH+A7Ehz0/safc6BbsNBzjHTt7FngNfhfJoYOrkugSaT8F0IzUh6VUwoHdYDpi
# ln9dh0n0m545d5A5tJD92iFAIbKHQWGbCQNYplqpAFasHBn77OqW37P9BhOASdmj
# p3IijYiFdcA0WQIe60vzvrk0HG+iVcwVZjz+t5OcXGTcxqOAzk1frDNZ1aw8nFhG
# EvG0ktJQknnJZE3D40GofV7O8WzgaAnZmoUn4PCpvH36vD4XaAF2CjiPsJWiY/j2
# xLsJuqx3JtuI4akH0MmGzlBUylhXvdNVXcjAuIEcEQKtOBR9lU4wXQpISrbOT8ux
# +96GzBq8TdbhoFcmYaOBZKlwPP7pOp5Mzx/UMhyBA93PQhiCdPfIVOCINsUY4U23
# p4KJ3F1HqP3H6Slw3lHACnLilGETXRg5X/Fp8G8qlG5Y+M49ZEGUp2bneRLZoyHT
# yynHvFISpefhBCV0KdRZHPcuSL5OAGWnBjAlRtHvsMBrI3AAA0Tu1oGvPa/4yeei
# Ayu+9y3SLC98gDVbySnXnkujjhIh+oaatsk/oyf5R2vcxHahajMCAwEAAaOCAY4w
# ggGKMB8GA1UdIwQYMBaAFF9Y7UwxeqJhQo1SgLqzYZcZojKbMB0GA1UdDgQWBBSI
# YYyhKjdkgShgoZsx0Iz9LALOTzAOBgNVHQ8BAf8EBAMCBsAwDAYDVR0TAQH/BAIw
# ADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDBKBgNVHSAEQzBBMDUGDCsGAQQBsjEB
# AgEDCDAlMCMGCCsGAQUFBwIBFhdodHRwczovL3NlY3RpZ28uY29tL0NQUzAIBgZn
# gQwBBAIwSgYDVR0fBEMwQTA/oD2gO4Y5aHR0cDovL2NybC5zZWN0aWdvLmNvbS9T
# ZWN0aWdvUHVibGljVGltZVN0YW1waW5nQ0FSMzYuY3JsMHoGCCsGAQUFBwEBBG4w
# bDBFBggrBgEFBQcwAoY5aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUHVi
# bGljVGltZVN0YW1waW5nQ0FSMzYuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2Nz
# cC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAYEAAoE+pIZyUSH5ZakuPVKK
# 4eWbzEsTRJOEjbIu6r7vmzXXLpJx4FyGmcqnFZoa1dzx3JrUCrdG5b//LfAxOGy9
# Ph9JtrYChJaVHrusDh9NgYwiGDOhyyJ2zRy3+kdqhwtUlLCdNjFjakTSE+hkC9F5
# ty1uxOoQ2ZkfI5WM4WXA3ZHcNHB4V42zi7Jk3ktEnkSdViVxM6rduXW0jmmiu71Z
# pBFZDh7Kdens+PQXPgMqvzodgQJEkxaION5XRCoBxAwWwiMm2thPDuZTzWp/gUFz
# i7izCmEt4pE3Kf0MOt3ccgwn4Kl2FIcQaV55nkjv1gODcHcD9+ZVjYZoyKTVWb4V
# qMQy/j8Q3aaYd/jOQ66Fhk3NWbg2tYl5jhQCuIsE55Vg4N0DUbEWvXJxtxQQaVR5
# xzhEI+BjJKzh3TQ026JxHhr2fuJ0mV68AluFr9qshgwS5SpN5FFtaSEnAwqZv3IS
# +mlG50rK7W3qXbWwi4hmpylUfygtYLEdLQukNEX1jiOKMIIGgjCCBGqgAwIBAgIQ
# NsKwvXwbOuejs902y8l1aDANBgkqhkiG9w0BAQwFADCBiDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYD
# VQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBS
# U0EgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMjEwMzIyMDAwMDAwWhcNMzgw
# MTE4MjM1OTU5WjBXMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1p
# dGVkMS4wLAYDVQQDEyVTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIFJvb3Qg
# UjQ2MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAiJ3YuUVnnR3d6Lkm
# gZpUVMB8SQWbzFoVD9mUEES0QUCBdxSZqdTkdizICFNeINCSJS+lV1ipnW5ihkQy
# C0cRLWXUJzodqpnMRs46npiJPHrfLBOifjfhpdXJ2aHHsPHggGsCi7uE0awqKggE
# /LkYw3sqaBia67h/3awoqNvGqiFRJ+OTWYmUCO2GAXsePHi+/JUNAax3kpqstbl3
# vcTdOGhtKShvZIvjwulRH87rbukNyHGWX5tNK/WABKf+Gnoi4cmisS7oSimgHUI0
# Wn/4elNd40BFdSZ1EwpuddZ+Wr7+Dfo0lcHflm/FDDrOJ3rWqauUP8hsokDoI7D/
# yUVI9DAE/WK3Jl3C4LKwIpn1mNzMyptRwsXKrop06m7NUNHdlTDEMovXAIDGAvYy
# nPt5lutv8lZeI5w3MOlCybAZDpK3Dy1MKo+6aEtE9vtiTMzz/o2dYfdP0KWZwZIX
# bYsTIlg1YIetCpi5s14qiXOpRsKqFKqav9R1R5vj3NgevsAsvxsAnI8Oa5s2oy25
# qhsoBIGo/zi6GpxFj+mOdh35Xn91y72J4RGOJEoqzEIbW3q0b2iPuWLA911cRxgY
# 5SJYubvjay3nSMbBPPFsyl6mY4/WYucmyS9lo3l7jk27MAe145GWxK4O3m3gEFEI
# kv7kRmefDR7Oe2T1HxAnICQvr9sCAwEAAaOCARYwggESMB8GA1UdIwQYMBaAFFN5
# v1qqK0rPVIDh2JvAnfKyA2bLMB0GA1UdDgQWBBT2d2rdP/0BE/8WoWyCAi/QCj0U
# JTAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zATBgNVHSUEDDAKBggr
# BgEFBQcDCDARBgNVHSAECjAIMAYGBFUdIAAwUAYDVR0fBEkwRzBFoEOgQYY/aHR0
# cDovL2NybC51c2VydHJ1c3QuY29tL1VTRVJUcnVzdFJTQUNlcnRpZmljYXRpb25B
# dXRob3JpdHkuY3JsMDUGCCsGAQUFBwEBBCkwJzAlBggrBgEFBQcwAYYZaHR0cDov
# L29jc3AudXNlcnRydXN0LmNvbTANBgkqhkiG9w0BAQwFAAOCAgEADr5lQe1oRLjl
# ocXUEYfktzsljOt+2sgXke3Y8UPEooU5y39rAARaAdAxUeiX1ktLJ3+lgxtoLQhn
# 5cFb3GF2SSZRX8ptQ6IvuD3wz/LNHKpQ5nX8hjsDLRhsyeIiJsms9yAWnvdYOdEM
# q1W61KE9JlBkB20XBee6JaXx4UBErc+YuoSb1SxVf7nkNtUjPfcxuFtrQdRMRi/f
# InV/AobE8Gw/8yBMQKKaHt5eia8ybT8Y/Ffa6HAJyz9gvEOcF1VWXG8OMeM7Vy7B
# s6mSIkYeYtddU1ux1dQLbEGur18ut97wgGwDiGinCwKPyFO7ApcmVJOtlw9FVJxw
# /mL1TbyBns4zOgkaXFnnfzg4qbSvnrwyj1NiurMp4pmAWjR+Pb/SIduPnmFzbSN/
# G8reZCL4fvGlvPFk4Uab/JVCSmj59+/mB2Gn6G/UYOy8k60mKcmaAZsEVkhOFuoj
# 4we8CYyaR9vd9PGZKSinaZIkvVjbH/3nlLb0a7SBIkiRzfPfS9T+JesylbHa1LtR
# V9U/7m0q7Ma2CQ/t392ioOssXW7oKLdOmMBl14suVFBmbzrt5V5cQPnwtd3UOTpS
# 9oCG+ZZheiIvPgkDmA8FzPsnfXW5qHELB43ET7HHFHeRPRYrMBKjkb8/IN7Po0d0
# hQoF4TeMM+zYAJzoKQnVKOLg8pZVPT8wgga5MIIEoaADAgECAhEAmaOACiZVO2Wr
# 3G6EprPqOTANBgkqhkiG9w0BAQwFADCBgDELMAkGA1UEBhMCUEwxIjAgBgNVBAoT
# GVVuaXpldG8gVGVjaG5vbG9naWVzIFMuQS4xJzAlBgNVBAsTHkNlcnR1bSBDZXJ0
# aWZpY2F0aW9uIEF1dGhvcml0eTEkMCIGA1UEAxMbQ2VydHVtIFRydXN0ZWQgTmV0
# d29yayBDQSAyMB4XDTIxMDUxOTA1MzIxOFoXDTM2MDUxODA1MzIxOFowVjELMAkG
# A1UEBhMCUEwxITAfBgNVBAoTGEFzc2VjbyBEYXRhIFN5c3RlbXMgUy5BLjEkMCIG
# A1UEAxMbQ2VydHVtIENvZGUgU2lnbmluZyAyMDIxIENBMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAnSPPBDAjO8FGLOczcz5jXXp1ur5cTbq96y34vuTm
# flN4mSAfgLKTvggv24/rWiVGzGxT9YEASVMw1Aj8ewTS4IndU8s7VS5+djSoMcbv
# IKck6+hI1shsylP4JyLvmxwLHtSworV9wmjhNd627h27a8RdrT1PH9ud0IF+njvM
# k2xqbNTIPsnWtw3E7DmDoUmDQiYi/ucJ42fcHqBkbbxYDB7SYOouu9Tj1yHIohzu
# C8KNqfcYf7Z4/iZgkBJ+UFNDcc6zokZ2uJIxWgPWXMEmhu1gMXgv8aGUsRdaCtVD
# 2bSlbfsq7BiqljjaCun+RJgTgFRCtsuAEw0pG9+FA+yQN9n/kZtMLK+Wo837Q4QO
# ZgYqVWQ4x6cM7/G0yswg1ElLlJj6NYKLw9EcBXE7TF3HybZtYvj9lDV2nT8mFSkc
# SkAExzd4prHwYjUXTeZIlVXqj+eaYqoMTpMrfh5MCAOIG5knN4Q/JHuurfTI5XDY
# O962WZayx7ACFf5ydJpoEowSP07YaBiQ8nXpDkNrUA9g7qf/rCkKbWpQ5boufUnq
# 1UiYPIAHlezf4muJqxqIns/kqld6JVX8cixbd6PzkDpwZo4SlADaCi2JSplKShBS
# ND36E/ENVv8urPS0yOnpG4tIoBGxVCARPCg1BnyMJ4rBJAcOSnAWd18Jx5n858JS
# qPECAwEAAaOCAVUwggFRMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFN10XUwA
# 23ufoHTKsW73PMAywHDNMB8GA1UdIwQYMBaAFLahVDkCw6A/joq8+tT4HKbROg79
# MA4GA1UdDwEB/wQEAwIBBjATBgNVHSUEDDAKBggrBgEFBQcDAzAwBgNVHR8EKTAn
# MCWgI6Ahhh9odHRwOi8vY3JsLmNlcnR1bS5wbC9jdG5jYTIuY3JsMGwGCCsGAQUF
# BwEBBGAwXjAoBggrBgEFBQcwAYYcaHR0cDovL3N1YmNhLm9jc3AtY2VydHVtLmNv
# bTAyBggrBgEFBQcwAoYmaHR0cDovL3JlcG9zaXRvcnkuY2VydHVtLnBsL2N0bmNh
# Mi5jZXIwOQYDVR0gBDIwMDAuBgRVHSAAMCYwJAYIKwYBBQUHAgEWGGh0dHA6Ly93
# d3cuY2VydHVtLnBsL0NQUzANBgkqhkiG9w0BAQwFAAOCAgEAdYhYD+WPUCiaU58Q
# 7EP89DttyZqGYn2XRDhJkL6P+/T0IPZyxfxiXumYlARMgwRzLRUStJl490L94C9L
# GF3vjzzH8Jq3iR74BRlkO18J3zIdmCKQa5LyZ48IfICJTZVJeChDUyuQy6rGDxLU
# UAsO0eqeLNhLVsgw6/zOfImNlARKn1FP7o0fTbj8ipNGxHBIutiRsWrhWM2f8pXd
# d3x2mbJCKKtl2s42g9KUJHEIiLni9ByoqIUul4GblLQigO0ugh7bWRLDm0CdY9rN
# LqyA3ahe8WlxVWkxyrQLjH8ItI17RdySaYayX3PhRSC4Am1/7mATwZWwSD+B7eMc
# ZNhpn8zJ+6MTyE6YoEBSRVrs0zFFIHUR08Wk0ikSf+lIe5Iv6RY3/bFAEloMU+vU
# BfSouCReZwSLo8WdrDlPXtR0gicDnytO7eZ5827NS2x7gCBibESYkOh1/w1tVxTp
# V2Na3PR7nxYVlPu1JPoRZCbH86gc96UTvuWiOruWmyOEMLOGGniR+x+zPF/2DaGg
# K2W1eEJfo2qyrBNPvF7wuAyQfiFXLwvWHamoYtPZo0LHuH8X3n9C+xN4YaNjt2yw
# zOr+tKyEVAotnyU9vyEVOaIYMk3IeBrmFnn0gbKeTTyYeEEUz/Qwt4HOUBCrW602
# NCmvO1nm+/80nLy5r0AZvCQxaQ4xggXDMIIFvwIBATBqMFYxCzAJBgNVBAYTAlBM
# MSEwHwYDVQQKExhBc3NlY28gRGF0YSBTeXN0ZW1zIFMuQS4xJDAiBgNVBAMTG0Nl
# cnR1bSBDb2RlIFNpZ25pbmcgMjAyMSBDQQIQCDJPnbfakW9j5PKjPF5dUTANBglg
# hkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3
# DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEV
# MC8GCSqGSIb3DQEJBDEiBCBPdCH48+9yyeeVkfEbEB3eU+NqO/yRuJokdjRO8HHA
# 0jANBgkqhkiG9w0BAQEFAASCAYADt++RvvgsK0lPR1BsFsbVyGAMZZXP+xrFuCvQ
# K5X33HBkgu81IkoummOteswMAdEyyP0r1qjGWkEMwVpe6l6g7upzC57Iy7gDHkfM
# 53kpx+WdD9I1g7SDM8BYk1SRPi45ftZhkky6jupG5n1fFYaFK/FMY+AXSKdp+sIo
# C3VVS5MCqbG1uVH/BLeUk83UPMtDbIHHOZl1P2HzGA/k3pZU+d9M10oGwsQrn7IK
# M82RwxRX/efOal6R2a5hQyB4i/4Bol6q/6C1/MYvhwjDbYUMCiWRB5pKXDChGx4j
# DRMRjyEVIV1d0JtSLmgywK4aOLp34WeRUJ1eyVCUFaoqhcXZX1WPrfZFqeubm5K2
# ZUtMC7fv12kJ8rDpXgETKTTqVt8piVnCAmK5mP15sBpMQFrsVMpcIQ7/+M28vIL6
# 05YZVypYxuxlwmjwNes7ufoAdegJAyvdkti1pSKK9lL5UB6Buvj3pdIXjpQZeais
# cQ+shmwtpoaJLpCbiDxdsu331L2hggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwC
# AQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQp
# O24e3denNAiHrXpOtyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNTExMTEwOTU5NDRaMD8GCSqGSIb3
# DQEJBDEyBDC0PRajkKQlv2H5EW6pbyEQNLQGqqc/2XVJJbHhcfpkEFM5/dzKDhHX
# kHB7Q2vL9eMwDQYJKoZIhvcNAQEBBQAEggIAwV3GOrx4Opr6h3wulC9jqvzB5k+d
# CA6wnwvUpiTDXIhVYiq9wCiN+nTRasxtgk+AnwlqDQQwlm6BQqlCEyVwa/8c1lb3
# dXgTIE6AAwp96yGF/ruxWOhHt+FMXawkDG7q1gWTKMvfnGqGqoCpwxhfLOT856QT
# RzB0vVWzO0z6ZXRHxR17cMHc5tgEKMymA4l4vdUUNc/Cry+rthsY6A9bcwO48v84
# K1zkUwSqt1WYMXRqa7WPJuvYshxq7pYuyTFiHuPhxrRujaSe4gtW0nZmFxF5UuDs
# t1jXvvCQB5NleO2HA2EyW9B1dctcXhZuWmqzPIKgPS5YY0tMx3TItPiEF4qMx2Wf
# ImG7f38MRTzxTEQ7s9RSW2L/WXjK4ZRG0/wRvaQviw5C34Ezw0O2F4kyMxlmtbFL
# xB01TPbUQxfRG2k2UEaQ4erp9P+duUb/m0nqntu/X9WrzQlGPsT1pKzBQSZuimMN
# 1gDhPiOJ404KRUg+rTgT5t5G4nx+LD2KR8xrLRN7Gke0J1fBVz5Gocia/AsIod5+
# vvdBWqcTrtGRKrWUKUTsl3t/4Z0xL0Flc1TPpxCgJNygCOoKBYv3PWzy/Q9oYsSL
# oXpROF3G6YNPLqBtrnHgabKMwbxunJwXu7Db07xuSdYSHJO0/EL/4FiMvKVsNd87
# GXbEHwK7yoy8OsQ=
# SIG # End signature block
