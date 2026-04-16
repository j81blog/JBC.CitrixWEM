function Get-IvantiWCApplication {
    <#
    .SYNOPSIS
        Retrieves Ivanti Workspace Control application configurations from XML files.

    .DESCRIPTION
        Processes Ivanti Workspace Control XML building block file(s) and extracts application
        settings, assignments, and metadata. Supports both single large XML files and
        directories containing multiple separate XML files (one per application).

    .PARAMETER XmlFilePath
        (Legacy parameter) Path to a single Ivanti Workspace Control XML building block file.
        This parameter is maintained for backward compatibility. Use -XmlPath instead.

    .PARAMETER XmlPath
        Path to either:
        - A single XML file containing all application configurations
        - A directory containing multiple XML files (one per application)

    .PARAMETER AsJson
        Switch to output the results as JSON format instead of PowerShell objects.

    .EXAMPLE
        Get-IvantiWCApplication -XmlFilePath "C:\Config\IvantiApps.xml"

        Processes a single XML file (legacy parameter usage).

    .EXAMPLE
        Get-IvantiWCApplication -XmlPath "C:\Config\IvantiApps.xml"

        Processes a single XML file containing all applications.

    .EXAMPLE
        Get-IvantiWCApplication -XmlPath "C:\Config\Applications\" -AsJson

        Processes all XML files in the specified directory and outputs as JSON.

    .NOTES
        Function  : Get-IvantiWCApplication
        Author    : John Billekens
        Copyright : (c) John Billekens Consultancy
        Version   : 2026.224.915
    #>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByFilePath',
            HelpMessage = "Path to the Ivanti Workspace Control XML building block file."
        )]
        [ValidateScript({
                if (-not (Test-Path $_ -PathType Leaf)) {
                    throw "File '$_' does not exist."
                }
                return $true
            })]
        [string]$XmlFilePath,

        [Parameter(
            Mandatory = $true,
            ParameterSetName = 'ByPath',
            HelpMessage = "Path to the Ivanti Workspace Control XML building block file or directory containing XML files."
        )]
        [ValidateScript({
                if (-not (Test-Path $_)) {
                    throw "Path '$_' does not exist."
                }
                return $true
            })]
        [string]$XmlPath,

        [Parameter(
            Mandatory = $false,
            HelpMessage = "Output the results as JSON."
        )]
        [switch]$AsJson,

        [ValidateSet("AppVentiX", "WEM")]
        [string]$ExportFor = "WEM"
    )

    $JsonOutput = @()
    $ApplicationsToProcess = @()

    if ($PSCmdlet.ParameterSetName -eq 'ByFilePath') {
        $XmlPath = $XmlFilePath
    }

    # Determine if XmlPath is a file or directory
    if (Test-Path -Path $XmlPath -PathType Leaf) {
        # Single XML file mode

        try {
            Write-Verbose "Reading and parsing the Ivanti XML file at '$($XmlPath)'."
            [xml]$IvantiXmlData = ConvertFrom-IvantiBB -XmlFilePath $XmlPath
        } catch {
            Write-Error "Failed to read or parse the XML file '$($XmlPath)'. Error: $($_.Exception.Message)"
            return # Stop execution if file can't be read
        }
        Write-Verbose "Retrieving application nodes from the XML data."
        $ApplicationsToProcess = @($IvantiXmlData.SelectNodes("//application"))

    } elseif (Test-Path -Path $XmlPath -PathType Container) {
        # Directory with multiple XML files mode
        Write-Verbose "Processing directory containing multiple XML files: $XmlPath"
        $XmlFiles = Get-ChildItem -Path $XmlPath -Filter "*.xml" -File

        if ($XmlFiles.Count -eq 0) {
            Write-Warning "No XML files found in directory: $XmlPath"
            return
        }

        Write-Verbose "Found $($XmlFiles.Count) XML file(s) in directory."

        foreach ($XmlFile in $XmlFiles) {
            try {
                [xml]$XmlData = ConvertFrom-IvantiBB -XmlFilePath $XmlFile.FullName
                $Apps = @($XmlData.SelectNodes("//application"))

                if ($Apps.Count -gt 0) {
                    $ApplicationsToProcess += $Apps
                    Write-Verbose "Loaded $($Apps.Count) application(s) from '$($XmlFile.Name)'"
                } else {
                    Write-Warning "No application nodes found in file: $($XmlFile.Name)"
                }
            } catch {
                Write-Warning "Failed to load XML file '$($XmlFile.Name)': $_"
                continue
            }
        }
    } else {
        Write-Error "XmlPath must be either a file or a directory."
        return
    }
    if (-not [string]::IsNullOrEmpty($DomainFqdn)) {
        Write-Verbose "Using Domain FQDN: $DomainFqdn"
        $DomainNetBIOS = Get-ADDomainNetBIOS -FQDN $DomainFqdn
    }

    if ($ApplicationsToProcess.Count -eq 0) {
        Write-Warning "No applications found to process."
        return
    }

    $TotalNumberOfItems = $ApplicationsToProcess.Count
    $Counter = 0
    Write-Verbose "Found $TotalNumberOfItems applications to process in the Ivanti Workspace Control XML."
    for ($i = 0; $i -lt $ApplicationsToProcess.Count; $i++) {
        $Script:Warning = $false
        $Counter++
        $Application = $ApplicationsToProcess[$i]
        Write-Progress -Activity "Processing Applications" -Status "Processing item $($Counter) of $($TotalNumberOfItems)" -CurrentOperation "Application: `"$($Application.configuration.title)`"" -PercentComplete (($Counter / $TotalNumberOfItems) * 100)
        $Enabled = $false
        $State = "Disabled"
        if ($Application.settings.enabled -eq "yes") {
            $Enabled = $true
            $State = "Enabled"
        }
        if ($Application.settings.enabled -eq "no" -or [string]::IsNullOrEmpty($Application.settings.enabled)) {
            $Enabled = $false
            $State = "Disabled"
        }
        $URL = ""
        $Parameters = "$($Application.configuration.parameters)"
        $CommandLine = "$($Application.configuration.commandline)"
        $WorkingDir = "$($Application.configuration.workingdir)"
        $DisplayName = "$($Application.configuration.title)"
        $Description = "$($Application.configuration.description)"
        $AppID = "$($Application.appid)"
        if ($CommandLine -like '*"%*%"*') {
            #Replace ..."%...%"... to ...%...%... to prevent issues with environment variables in the command line
            $CommandLine = $CommandLine -replace '"%([^%]+)%"', '%$1%'
            Write-Warning "[$($Application.appid)] $($DisplayName): Application command line contained environment variables wrapped in quotes. These have been adjusted to ensure proper variable expansion. Original: `"$($Application.configuration.commandline)`", Adjusted: `"$CommandLine`""
            $Script:Warning = $true
        }

        if ($CommandLine -like "*.cmd" -or $CommandLine -like "*.bat") {
            Write-Warning "[$($Application.appid)] $($DisplayName): Application has a command line that points to a batch file."
            Write-Warning "This is not supported and will be skipped. Consider changing the command line to point to the actual executable and use the batch file for any necessary setup or parameter handling."
            Write-Warning "Example: `cmd.exe /C `"$CommandLine`""
            Write-Warning "********************************************************************************************************"
            continue
        }
        if ($CommandLine -like "*.ps1") {
            Write-Warning "[$($Application.appid)] $($DisplayName): Application has a command line that points to a PowerShell script."
            Write-Warning "This is not supported and will be skipped. Consider changing the command line to point to `powershell.exe` and use the `-File` parameter to specify the script."
            Write-Warning "Example: `powershell.exe -ExecutionPolicy Bypass -File `"$CommandLine`""
            Write-Warning "********************************************************************************************************"
            continue
        }
        if ($CommandLine -like "*.vbs") {
            Write-Warning "[$($Application.appid)] $($DisplayName): Application has a command line that points to a VBScript file."
            Write-Warning "This is not supported and will be skipped. Consider changing the command line to point to `cscript.exe` and use the appropriate parameters to specify the script."
            Write-Warning "Example: `cscript.exe //B //Nologo `"$CommandLine`""
            Write-Warning "********************************************************************************************************"
            continue
        }
        $BinaryIconData = $null
        if (-not [string]::IsNullOrEmpty($($Application.configuration.icon32x256))) {
            $BinaryIconData = $($Application.configuration.icon32x256)
        } elseif (-not [string]::IsNullOrEmpty($($Application.configuration.icon32x16))) {
            $BinaryIconData = $($Application.configuration.icon32x16)
        } elseif (-not [string]::IsNullOrEmpty($($Application.configuration.icon16x16))) {
            $BinaryIconData = $($Application.configuration.icon16x16)
        }
        try {
            $IconStream16 = "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAC5ElEQVR4AYyRa0hTYRyHf27WGl5mQ9fU1PBGWEYpoeWlTMTSELUC/aAucZFfpA/eFZsGfkgQDXReKMtLKIqXFMksuoCXlFBnlMoUTZdNy1tzO1vurHfTbJRQh/c5HA48z/s/52XgP6603IcuWXfqkkvFnbWNrX1rd0ta3hGNT8CegXTRfTu9UFL2pKalo18eEe4jvR4bUh4W6hsXTI9wHJzsvIgcSNgOiEQi05yC2pR7FV1VHd2Dsqhwf5kw/mJ5dGSAwPOYC8/CwhJV0yyUzpmDofoGMEz0Llt/M0ywxXTJTU25Uhp6wVtoy+PZSaeW0dzUj+KiDmwq1VBRFM6x5RDwliA/K4QZy1TvGjAE9E8qagvi8h401L3G5KQMlgfZCArxgFb3AzZ8SwSccYWbhyP4zrZgs1l6xcBuQK1W41LEKcTE+yE2zg9XY/wRHHYa7iecwbW3xvzTSKzMdoEimo7wa+0GVlc34Bd4HJ5ebjjsag+mORsrC28gH86HfCgfHAsWOGttWOxOwJ4BWqeDhsmACjCgkL2C2fpLuNkqcfTQIhwc94OjeQAtJQNtVNidgCZvl4ZyoehPxcZwIQ58fQ4u6y2+SIrR3zeKuQkJ3k/zofSuB02TXXaWUYAGRe/DEdsFuNlIYWMmwZykF1P8NmhDBiFdPQmZexs2wQcZdkcHjAI6aLhBGB78iKmBGkiGBjDBrYaadxnflcCmTz22rHzBYehAa7V/B7TkEyirQCjOj2E2QIcFv2WoHQTQaAAuk4YjcwPszx/Q19pEVVdUjJDCCsF4Atqwk3437Y7kwFiHycwoehvqFKK09NHEuGhxxq1YYWdrZQKRXxB+B0xMmLA23YITYw3MT+N4VvdIUZCRM3YzKUaclylI7mipjJ+fm8wi0mPCOEFJ2A6oVdSMdGYRPfUNClFG9liS4Jr4dnZicntzWdwf0jqRjM5g5ycWFQobM9MTo/KyBDfam8X/lEhkd/0EAAD//8lbgwMAAAAGSURBVAMA4942bU+gERIAAAAASUVORK5CYII="
            $IconStream48 = "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"
            $IconStream256 = "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"
            if (-not [string]::IsNullOrEmpty($BinaryIconData)) {
                $IconStream = Convert-BinaryIconToBase64 -IconData $BinaryIconData -Size 32
                $IconStream16 = Convert-BinaryIconToBase64 -IconData $BinaryIconData -Size 16
                $IconStream48 = Convert-BinaryIconToBase64 -IconData $BinaryIconData -Size 48
                $IconStream256 = Convert-BinaryIconToBase64 -IconData $BinaryIconData -Size 256
            } else {
                $IconStream = "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"
            }
        } catch {
            Write-Warning "[$($Application.appid)] $($DisplayName): Failed to process icon data, Using default icon. Error: $($_.Exception.Message)"
            $Script:Warning = $true
            $IconStream = "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"
        }
        $StartMenuPath = "$($Application.configuration.menu)"
        if ($StartMenuPath -eq "") {
            $StartMenuPath = "Start Menu\Programs"
        } elseif ($StartMenuPath -like "Start\*") {
            $StartMenuPath = "Start Menu\Programs$($StartMenuPath.Substring(5))"
        }

        $Assignments = @(ConvertFrom-IvantiAccessControl -AccessControl $Application.accesscontrol -IWCComponentName "[$($Application.appid)] $($Application.configuration.title)" -IWCComponent "Application")
        $IsDesktop = $false
        if ($Application.configuration.desktop -ine "none" -and -not [string]::IsNullOrEmpty($($Application.configuration.desktop))) {
            $IsDesktop = $true
        }
        $isQuickLaunch = $false
        if ($Application.configuration.quicklaunch -ine "none" -and -not [string]::IsNullOrEmpty($($Application.configuration.quicklaunch))) {
            $isQuickLaunch = $true
        }

        $isStartMenu = $false
        if ($Application.configuration.createmenushortcut -ieq "yes") {
            $isStartMenu = $true
        }
        if ([string]::IsNullOrEmpty($workingDir)) {
            $workingDir = Split-Path -Path $CommandLine -Parent
        }

        $isAutoStart = $false
        if ($Application.settings.autoall -ine "no" -and -not [string]::IsNullOrEmpty($($Application.settings.autoall))) {
            $isAutoStart = $true
        }
        $WindowStyle = $Application.settings.startstyle
        if ([string]::IsNullOrEmpty($WindowStyle) -or $WindowStyle -like "nor*") {
            $WindowStyle = "Normal"
        } elseif ($WindowStyle -like "max*") {
            $WindowStyle = "Maximized"
        } elseif ($WindowStyle -like "min*") {
            $WindowStyle = "Minimized"
        } else {
            $WindowStyle = "Normal"
        }

        $Output = [PSCustomObject]@{
            Name    = $DisplayName
            AppID   = $AppID
            Enabled = $Enabled
        }
        switch ($ExportFor) {
            "WEM" {
                $WEMAssignments = @($Assignments)
                $Output | Add-Member -MemberType NoteProperty -Name "WEMAssignments" -Value $WEMAssignments
                $WEMAssignmentParams = [PSCustomObject]@{
                    isAutoStart   = $IsAutoStart
                    isDesktop     = $IsDesktop
                    isQuickLaunch = $IsQuickLaunch
                    isStartMenu   = $IsStartMenu
                }
                $Output | Add-Member -MemberType NoteProperty -Name "WEMAssignmentParams" -Value $WEMAssignmentParams
                $WEMApplicationParams = [PSCustomObject]@{
                    StartMenuPath = $StartMenuPath
                    AppType       = "InstallerApplication"
                    State         = $State
                    IconStream    = $IconStream
                    Parameter     = $Parameters
                    Description   = $Description
                    Name          = $DisplayName
                    CommandLine   = $CommandLine
                    WorkingDir    = $WorkingDir
                    URL           = $URL
                    DisplayName   = $DisplayName
                    WindowStyle   = $WindowStyle
                    ActionType    = "CreateAppShortcut"
                }
                $Output | Add-Member -MemberType NoteProperty -Name "WEMApplicationParams" -Value $WEMApplicationParams
            }
            "AppVentiX" {
                $AppVentiXAssignments = @($Assignments | Select-Object Sid, Name, Type, DomainFQDN)
                $Output | Add-Member -MemberType NoteProperty -Name "AppVentiXAssignments" -Value $AppVentiXAssignments
                $AppVentiXStartMenuPath = $StartMenuPath -replace '(?i)^Start Menu\\Programs(?:\\)?', ""
                $ShortcutName = $AppVentiXStartMenuPath, $DisplayName -join "\"
                $AppVentiXParams = [PSCustomObject]@{
                    FriendlyName                = $DisplayName
                    Description                 = $Description
                    ShortcutEntries             = @(
                        [PSCustomObject]@{
                            ShortcutName     = $ShortcutName
                            Arguments        = $Parameters
                            ExecutablePath   = $CommandLine
                            WorkingDirectory = $WorkingDir
                            PlaceOnDesktop   = $IsDesktop
                            IconData         = $IconStream
                            IconData16       = $IconStream16
                            IconData32       = $IconStream
                            IconData48       = $IconStream48
                            IconData256      = $IconStream256
                        }
                    )
                }
                $Output | Add-Member -MemberType NoteProperty -Name "AppVentiXParams" -Value $AppVentiXParams
            }
        }
        if ($Script:Warning -eq $true) {
            # New line after warnings for better readability in the console output
            Write-Warning "********************************************************************************************************"
        }

        if ($AsJson) {
            $JsonOutput += $Output
        } else {
            Write-Output $Output
        }
    }
    Write-Progress -Activity "Processing Applications" -Completed
    Write-Verbose "Processing completed. Processed $TotalNumberOfItems applications."
    if ($AsJson) {
        Write-Verbose "Converting output to JSON format."
        return ($JsonOutput | ConvertTo-Json -Depth 5)
    }
}

# SIG # Begin signature block
# MII6BgYJKoZIhvcNAQcCoII59zCCOfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAaHrir5pjoxhoP
# v4TVx8LEsq2OwWM9/WRaw+nUrI3tCaCCIiowggXMMIIDtKADAgECAhBUmNLR1FsZ
# lUgTecgRwIeZMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDA0MTYxODM2MTZaFw00NTA0MTYxODQ0NDBaMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALORKgeD
# Bmf9np3gx8C3pOZCBH8Ppttf+9Va10Wg+3cL8IDzpm1aTXlT2KCGhFdFIMeiVPvH
# or+Kx24186IVxC9O40qFlkkN/76Z2BT2vCcH7kKbK/ULkgbk/WkTZaiRcvKYhOuD
# PQ7k13ESSCHLDe32R0m3m/nJxxe2hE//uKya13NnSYXjhr03QNAlhtTetcJtYmrV
# qXi8LW9J+eVsFBT9FMfTZRY33stuvF4pjf1imxUs1gXmuYkyM6Nix9fWUmcIxC70
# ViueC4fM7Ke0pqrrBc0ZV6U6CwQnHJFnni1iLS8evtrAIMsEGcoz+4m+mOJyoHI1
# vnnhnINv5G0Xb5DzPQCGdTiO0OBJmrvb0/gwytVXiGhNctO/bX9x2P29Da6SZEi3
# W295JrXNm5UhhNHvDzI9e1eM80UHTHzgXhgONXaLbZ7LNnSrBfjgc10yVpRnlyUK
# xjU9lJfnwUSLgP3B+PR0GeUw9gb7IVc+BhyLaxWGJ0l7gpPKWeh1R+g/OPTHU3mg
# trTiXFHvvV84wRPmeAyVWi7FQFkozA8kwOy6CXcjmTimthzax7ogttc32H83rwjj
# O3HbbnMbfZlysOSGM1l0tRYAe1BtxoYT2v3EOYI9JACaYNq6lMAFUSw0rFCZE4e7
# swWAsk0wAly4JoNdtGNz764jlU9gKL431VulAgMBAAGjVDBSMA4GA1UdDwEB/wQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTIftJqhSobyhmYBAcnz1AQ
# T2ioojAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQwFAAOCAgEAr2rd5hnn
# LZRDGU7L6VCVZKUDkQKL4jaAOxWiUsIWGbZqWl10QzD0m/9gdAmxIR6QFm3FJI9c
# Zohj9E/MffISTEAQiwGf2qnIrvKVG8+dBetJPnSgaFvlVixlHIJ+U9pW2UYXeZJF
# xBA2CFIpF8svpvJ+1Gkkih6PsHMNzBxKq7Kq7aeRYwFkIqgyuH4yKLNncy2RtNwx
# AQv3Rwqm8ddK7VZgxCwIo3tAsLx0J1KH1r6I3TeKiW5niB31yV2g/rarOoDXGpc8
# FzYiQR6sTdWD5jw4vU8w6VSp07YEwzJ2YbuwGMUrGLPAgNW3lbBeUU0i/OxYqujY
# lLSlLu2S3ucYfCFX3VVj979tzR/SpncocMfiWzpbCNJbTsgAlrPhgzavhgplXHT2
# 6ux6anSg8Evu75SjrFDyh+3XOjCDyft9V77l4/hByuVkrrOj7FjshZrM77nq81YY
# uVxzmq/FdxeDWds3GhhyVKVB0rYjdaNDmuV3fJZ5t0GNv+zcgKCf0Xd1WF81E+Al
# GmcLfc4l+gcK5GEh2NQc5QfGNpn0ltDGFf5Ozdeui53bFv0ExpK91IjmqaOqu/dk
# ODtfzAzQNb50GQOmxapMomE2gj4d8yu8l13bS3g7LfU772Aj6PXsCyM2la+YZr9T
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbCMIIEqqADAgECAhMzAABWh4wS
# B8KYYL2uAAAAAFaHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNDE0MjExOTE0WhcNMjYwNDE3
# MjExOTE0WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Y6MEBzN5XmjmQCUBmrWP3Xv
# 3kqEH4vtMaEMUsDJnl9lgweqe71Z5LQiuq0PapngjF/YRk95c8rqxtQJRMFvsnkv
# snlFeBZCsPPOzSbRUnlkyHLDQmOc9nKI/KFbqmkds70bB2z+gLQVkEZepiMgApJH
# y/eODoUZTXv58Yl4DFFdEvwW/TyC0vOI112mqqFCyN653yeBLDJ8LMvTvEvEaBih
# OXU0zNV1y52HvqIWg2h+e5WWaB2yL7locAD4dub1ZinnnRYochg5egSx41hHZDwe
# dcDyvzihq5IdqB3IeFnN5+kByQbLajYmXK+xy8G1QnIjMorDLx2+xWFBdzkOeKdF
# lPnHTAEFqlpqBFlNSU2axvcXUCJmgMVLjNW2lDNVzdpD1pgJpg+SBz7XBQ96IxVj
# TBKmLcoAlurLXPN0nzyDaAhja17p1zSFBR0idEi/T6Pr++HanksyVQLIpe0A/k8F
# zkLtGLeLOknRmsOC5gOT7nvGa8fUyWTptZJ3JohPAgMBAAGjggHVMIIB0TAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0GA1UdDgQW
# BBRPZasnKEZjDvsbRxzbBI296OsPPzAfBgNVHSMEGDAWgBSa8VR3dQyHFjdGoKze
# efn0f8F46TBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBF
# T0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUHMAKGWGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# SUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwNC5jcnQwVAYDVR0gBE0w
# SzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwFAAOCAgEA
# PH2f5SqSZRvE8G4BSeLiAJmu6YZ9MjnxZuMLlgjBRPX1/NF2oQ3U6OOK16b9Z6Cd
# Y/LCzdhDI1Dtvp36745TzKhUt3jCxONo5zFKbDlja/nR7Vly3qeKyQqop5hxzlEM
# xv3jSBBOLJUa5MppzjnYJEX7zInegb9213At3+fjYRNE2ZN5PwAdgo3jx2jHKIUE
# RVp3zMB2nwFEa6WPSL0rL5Qgu+jSXZDcZzBn8knxUTuMIHEAm3inxSsc7Kuy0Xw7
# eIPVndyZMC44RAbuMKWN2wv6FZJzecIfglGRamh/lpmgZLTHiTHmdkK/2mvAfQ6v
# cSHcngb3LYNGXkB0/BZf4PwTKL/vMLeaetQqyA+LuNXN20A6NSsE859WMNT/JjUU
# UJvF+3WUJ0mn2ufw79pLQyWAdXCHPaaDFLBlnGnN68eQ6w5tBOIxaFaPEtvCkBQ2
# c3QqHaiZS4FfLvP/XraDGEo8zALrYdWRaQxfUO+x2lo0/rn+d0BQoZPlc6c8KaIC
# RjzZDx6YqVlY1r4rWGzzWUkabduS7hsr1XM8l+OsD9gKI59ISz154ksW3NKtraSj
# z5GZFvgZB81TfXfbQmvdjXApiflx2HQ/ny3uLTiQGov+Zu5trrNTZsEJc3OGnVii
# Xx/vHOTUzGM4VgleXuALu9LifQxcgrVbZ39bw7vMGLowggbCMIIEqqADAgECAhMz
# AABWh4wSB8KYYL2uAAAAAFaHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jv
# c29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNDE0MjExOTE0WhcN
# MjYwNDE3MjExOTE0WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJy
# YWJhbnQxEjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtl
# bnMgQ29uc3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRh
# bmN5MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Y6MEBzN5XmjmQCU
# BmrWP3Xv3kqEH4vtMaEMUsDJnl9lgweqe71Z5LQiuq0PapngjF/YRk95c8rqxtQJ
# RMFvsnkvsnlFeBZCsPPOzSbRUnlkyHLDQmOc9nKI/KFbqmkds70bB2z+gLQVkEZe
# piMgApJHy/eODoUZTXv58Yl4DFFdEvwW/TyC0vOI112mqqFCyN653yeBLDJ8LMvT
# vEvEaBihOXU0zNV1y52HvqIWg2h+e5WWaB2yL7locAD4dub1ZinnnRYochg5egSx
# 41hHZDwedcDyvzihq5IdqB3IeFnN5+kByQbLajYmXK+xy8G1QnIjMorDLx2+xWFB
# dzkOeKdFlPnHTAEFqlpqBFlNSU2axvcXUCJmgMVLjNW2lDNVzdpD1pgJpg+SBz7X
# BQ96IxVjTBKmLcoAlurLXPN0nzyDaAhja17p1zSFBR0idEi/T6Pr++HanksyVQLI
# pe0A/k8FzkLtGLeLOknRmsOC5gOT7nvGa8fUyWTptZJ3JohPAgMBAAGjggHVMIIB
# 0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEE
# AYI3YQEABggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0G
# A1UdDgQWBBRPZasnKEZjDvsbRxzbBI296OsPPzAfBgNVHSMEGDAWgBSa8VR3dQyH
# FjdGoKzeefn0f8F46TBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIw
# Q1MlMjBFT0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUH
# MAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9z
# b2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwNC5jcnQwVAYD
# VR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwF
# AAOCAgEAPH2f5SqSZRvE8G4BSeLiAJmu6YZ9MjnxZuMLlgjBRPX1/NF2oQ3U6OOK
# 16b9Z6CdY/LCzdhDI1Dtvp36745TzKhUt3jCxONo5zFKbDlja/nR7Vly3qeKyQqo
# p5hxzlEMxv3jSBBOLJUa5MppzjnYJEX7zInegb9213At3+fjYRNE2ZN5PwAdgo3j
# x2jHKIUERVp3zMB2nwFEa6WPSL0rL5Qgu+jSXZDcZzBn8knxUTuMIHEAm3inxSsc
# 7Kuy0Xw7eIPVndyZMC44RAbuMKWN2wv6FZJzecIfglGRamh/lpmgZLTHiTHmdkK/
# 2mvAfQ6vcSHcngb3LYNGXkB0/BZf4PwTKL/vMLeaetQqyA+LuNXN20A6NSsE859W
# MNT/JjUUUJvF+3WUJ0mn2ufw79pLQyWAdXCHPaaDFLBlnGnN68eQ6w5tBOIxaFaP
# EtvCkBQ2c3QqHaiZS4FfLvP/XraDGEo8zALrYdWRaQxfUO+x2lo0/rn+d0BQoZPl
# c6c8KaICRjzZDx6YqVlY1r4rWGzzWUkabduS7hsr1XM8l+OsD9gKI59ISz154ksW
# 3NKtraSjz5GZFvgZB81TfXfbQmvdjXApiflx2HQ/ny3uLTiQGov+Zu5trrNTZsEJ
# c3OGnViiXx/vHOTUzGM4VgleXuALu9LifQxcgrVbZ39bw7vMGLowggcoMIIFEKAD
# AgECAhMzAAAAFydFCQuLh6/GAAAAAAAXMA0GCSqGSIb3DQEBDAUAMGMxCzAJBgNV
# BAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMT
# K01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2RlIFNpZ25pbmcgUENBIDIwMjEwHhcN
# MjYwMzI2MTgxMTMxWhcNMzEwMzI2MTgxMTMxWjBaMQswCQYDVQQGEwJVUzEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQg
# SUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEAgsdk/gMPZioBlcyfk6tDzJ+PRt4rSLGKW8ewpS0kRxXtURC3T3Gd
# bCKljobEn8ussqhGqQpRh/SXvRVwNXEIGb76UG5IPkCJ1S6/9BD61QQsKzPepW0S
# Nj8TXgsFxvS7MltoRuikIIp7Q5jQgaOM6QyK9++6ZVXUpYmZulAe6x8JrwZ0dNkE
# +rZ66lqtoocwepUSVUxM7odDmn8yDHjJ2DNPsfr3uRDix3X4qvh14jH/SW+2Cx7W
# IMhyIiQO201i6hUixmk4e2ZW8W7C1wPdTjq6BKb+zo8xbrt7ZKQvRX5QOA6dhLqu
# Pqj5sVKnxqfk19IC0SafTSTs8yC43Ew965BRRW8VL9ccoOmr4rxQy7aCgYTNk3dd
# /LphNaTTmnGp7kmLTxyHkB5geoWhYuuGrywS8E0wJv0W4rfOtHBV0e9sKvuUIeIU
# pnsx6ilxEVj6VQXvgD6yeCKnPmj3jJiJKAlmUDtth5yzRVBUl44sMiG4L5R/yyAC
# RKk2n088Q2YCoZS1O86+oMLKt1jaXGECOjbsVp8Id1VQw8he6J0KirOS5e25XlTd
# GPFb6oBOOaacgW78Kjf0bp+XzAgkc92mDGNJGYSjvdnj+7eMx6meW0DAIGdLRNj8
# /429MIspFBfz3KDqqpN71S4kQ2LLer3dxhDDczKVFL0HLwRuOvgjiG8CAwEAAaOC
# AdwwggHYMA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4E
# FgQUmvFUd3UMhxY3RqCs3nn59H/BeOkwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYI
# KwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9S
# ZXBvc2l0b3J5Lmh0bTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTASBgNVHRMB
# Af8ECDAGAQH/AgEAMB8GA1UdIwQYMBaAFNlBKbAPD2Ns72nX9c0pnqRIajDmMHAG
# A1UdHwRpMGcwZaBjoGGGX2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUy
# MFBDQSUyMDIwMjEuY3JsMH0GCCsGAQUFBwEBBHEwbzBtBggrBgEFBQcwAoZhaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJ
# RCUyMFZlcmlmaWVkJTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDIxLmNydDAN
# BgkqhkiG9w0BAQwFAAOCAgEAkHVaGf1NJt/JdoimmRZbMWr6baaDi8mkdWvWStk0
# hdZDpxSYTA7HuipAoLL3qIhI101XOl7fOiCh5++jZOamQdAV79ojEUNoIgCZmL2X
# JrLaGanwdjNynecJyYVCTrRf2+h7KknpWOp4axdOs6K9ZQ5g0IsQWXCwfc0dfkSk
# LKNY3pDcWLlJPh2jd5NUue6pNDv/2G5MFNJhCwltODebyAjGceU+XOzav+7i721Y
# QnQ+39m2aQOFO7zpAdaKAeAGhEd6Y6CdDGneSxcoujWvafWbv4ay3jo1ORSLUuWM
# bKr5X18QE4Sde+gppGLLSkZsrUh2eyYSkX1envWX7ZPzg2/wiuKRlQFarDn+N9+2
# 0BqzhxwkNyLzfYJp1Lg4fCXb24XqFjx8SDdRgebFImOfOLVze8XQ/CwkrEaib0PH
# u2t4GVk4FYroEbNUFqvjdBvTY3uiR5TdQoyXoYHvh+TxpLSY2vo7hhK9D/rpEpHC
# +qmmcRUE4d0gyO9Zb1vvt25fxM3ekjvDfVHcPq3qMr0Rwsk4krKZWUEgU1SXT5qN
# 6gqRrshxbT6OQgZ9/xT04qiXdzPQR6KindBvSpoOnxnALxcJyzVwNpKL+9u8EZYy
# 98qX6i+4gE/2J6cbpekcB0ZXDn/XQxoNUUb6/djT/wllVyG+vIHkdq71PzbH5rYx
# dcAwggeeMIIFhqADAgECAhMzAAAAB4ejNKN7pY4cAAAAAAAHMA0GCSqGSIb3DQEB
# DAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAyMDAeFw0yMTA0MDEyMDA1MjBaFw0z
# NjA0MDEyMDE1MjBaMGMxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xNDAyBgNVBAMTK01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2Rl
# IFNpZ25pbmcgUENBIDIwMjEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCy8MCvGYgo4t1UekxJbGkIVQm0Uv96SvjB6yUo92cXdylN65Xy96q2YpWCiTas
# 7QPTkGnK9QMKDXB2ygS27EAIQZyAd+M8X+dmw6SDtzSZXyGkxP8a8Hi6EO9Zcwh5
# A+wOALNQbNO+iLvpgOnEM7GGB/wm5dYnMEOguua1OFfTUITVMIK8faxkP/4fPdEP
# CXYyy8NJ1fmskNhW5HduNqPZB/NkWbB9xxMqowAeWvPgHtpzyD3PLGVOmRO4ka0W
# csEZqyg6efk3JiV/TEX39uNVGjgbODZhzspHvKFNU2K5MYfmHh4H1qObU4JKEjKG
# sqqA6RziybPqhvE74fEp4n1tiY9/ootdU0vPxRp4BGjQFq28nzawuvaCqUUF2PWx
# h+o5/TRCb/cHhcYU8Mr8fTiS15kRmwFFzdVPZ3+JV3s5MulIf3II5FXeghlAH9Cv
# icPhhP+VaSFW3Da/azROdEm5sv+EUwhBrzqtxoYyE2wmuHKws00x4GGIx7NTWznO
# m6x/niqVi7a/mxnnMvQq8EMse0vwX2CfqM7Le/smbRtsEeOtbnJBbtLfoAsC3TdA
# OnBbUkbUfG78VRclsE7YDDBUbgWt75lDk53yi7C3n0WkHFU4EZ83i83abd9nHWCq
# fnYa9qIHPqjOiuAgSOf4+FRcguEBXlD9mAInS7b6V0UaNwIDAQABo4ICNTCCAjEw
# DgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTZQSmw
# Dw9jbO9p1/XNKZ6kSGow5jBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUyH7SaoUqG8oZmAQHJ89QEE9oqKIwgYQGA1UdHwR9MHsw
# eaB3oHWGc2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jv
# c29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmlj
# YXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcmwwgcMGCCsGAQUFBwEBBIG2MIGzMIGB
# BggrBgEFBQcwAoZ1aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0
# cy9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBD
# ZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3J0MC0GCCsGAQUFBzABhiFo
# dHRwOi8vb25lb2NzcC5taWNyb3NvZnQuY29tL29jc3AwDQYJKoZIhvcNAQEMBQAD
# ggIBAH8lKp7+1Kvq3WYK21cjTLpebJDjW4ZbOX3HD5ZiG84vjsFXT0OB+eb+1TiJ
# 55ns0BHluC6itMI2vnwc5wDW1ywdCq3TAmx0KWy7xulAP179qX6VSBNQkRXzReFy
# jvF2BGt6FvKFR/imR4CEESMAG8hSkPYso+GjlngM8JPn/ROUrTaeU/BRu/1RFESF
# VgK2wMz7fU4VTd8NXwGZBe/mFPZG6tWwkdmA/jLbp0kNUX7elxu2+HtHo0QO5gdi
# KF+YTYd1BGrmNG8sTURvn09jAhIUJfYNotn7OlThtfQjXqe0qrimgY4Vpoq2MgDW
# 9ESUi1o4pzC1zTgIGtdJ/IvY6nqa80jFOTg5qzAiRNdsUvzVkoYP7bi4wLCj+ks2
# GftUct+fGUxXMdBUv5sdr0qFPLPB0b8vq516slCfRwaktAxK1S40MCvFbbAXXpAZ
# nU20FaAoDwqq/jwzwd8Wo2J83r7O3onQbDO9TyDStgaBNlHzMMQgl95nHBYMelLE
# HkUnVVVTUsgC0Huj09duNfMaJ9ogxhPNThgq3i8w3DAGZ61AMeF0C1M+mU5eucj1
# Ijod5O2MMPeJQ3/vKBtqGZg4eTtUHt/BPjN74SsJsyHqAdXVS5c+ItyKWg3Eforh
# ox9k3WgtWTpgV4gkSiS4+A09roSdOI4vrRw+p+fL4WrxSK5nMYIXMjCCFy4CAQEw
# cTBaMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSswKQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0AhMz
# AABWh4wSB8KYYL2uAAAAAFaHMA0GCWCGSAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIB
# DDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IMuwXk2c7ken9DrCnxuu5477zdHf4IYS9iMsisu4df2YMA0GCSqGSIb3DQEBAQUA
# BIIBgAlkf1imKyvdoXMo0AOTU2hacBgiaGnqqaR9akLkuwIsjb9mTRnSkj17imIv
# jP2ZaCziGd4WZhZiXG9B9rhICmv9M3/kOz6rtpewY3KGAsEwDTRWI8fqMR3f4Ovf
# LnFqX4GFZjqG8RCkE6Li4E79/Ova69qFfiwR4yRBUja2WUcs5yBqO80ynZEB/yNa
# 6KILXRWYkmw4kvxHwVNRHjBZ9K70sp63lxHncZ+KPSeTFY/9rChpxF+89FTZZttG
# ZPJhGKm7GRWKQ7zOtk2NuwQfIoyaZsnlWHH8l3RXGif5yB8vOfrgiuGAm+h9MJg1
# HBA3YHLF7AOPCsB5x9ZVhy6gYf3JRVo+vxiP3M+olKP5Qvhsn+czM4bqpLmLwW+H
# bqoIdw4CnCmPECn8sGqKD8QgvCmaqEijVcr9nhJxpDJSJsO94zghcryS5Fxq+Ek6
# PhzUfK46pHtY2YghAfwIZxejMaMYLZUo2Snrpr05fX0gu021uwwkZ3Gurs4HZlwr
# 5xka7qGCFLIwghSuBgorBgEEAYI3AwMBMYIUnjCCFJoGCSqGSIb3DQEHAqCCFIsw
# ghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFqBgsqhkiG9w0BCRABBKCCAVkEggFV
# MIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCgaKZok1bCPclg
# jk6ECKiIbKnP1nACFk5QZ75zuXi26QIGacZuNOtDGBMyMDI2MDQxNTE5NDQ1OC45
# MTJaMASAAgH0oIHppIHmMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3QTFBLTA1RTAtRDk0NzE1
# MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRo
# b3JpdHmggg8pMIIHgjCCBWqgAwIBAgITMwAAAAXlzw//Zi7JhwAAAAAABTANBgkq
# hkiG9w0BAQwFADB3MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMUgwRgYDVQQDEz9NaWNyb3NvZnQgSWRlbnRpdHkgVmVyaWZpY2F0
# aW9uIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMjAwHhcNMjAxMTE5MjAz
# MjMxWhcNMzUxMTE5MjA0MjMxWjBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJT
# QSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBAJ5851Jj/eDFnwV9Y7UGIqMcHtfnlzPREwW9ZUZHd5HBXXBvf7KrQ5cM
# SqFSHGqg2/qJhYqOQxwuEQXG8kB41wsDJP5d0zmLYKAY8Zxv3lYkuLDsfMuIEqvG
# YOPURAH+Ybl4SJEESnt0MbPEoKdNihwM5xGv0rGofJ1qOYSTNcc55EbBT7uq3wx3
# mXhtVmtcCEr5ZKTkKKE1CxZvNPWdGWJUPC6e4uRfWHIhZcgCsJ+sozf5EeH5KrlF
# nxpjKKTavwfFP6XaGZGWUG8TZaiTogRoAlqcevbiqioUz1Yt4FRK53P6ovnUfANj
# IgM9JDdJ4e0qiDRm5sOTiEQtBLGd9Vhd1MadxoGcHrRCsS5rO9yhv2fjJHrmlQ0E
# IXmp4DhDBieKUGR+eZ4CNE3ctW4uvSDQVeSp9h1SaPV8UWEfyTxgGjOsRpeexIve
# R1MPTVf7gt8hY64XNPO6iyUGsEgt8c2PxF87E+CO7A28TpjNq5eLiiunhKbq0Xbj
# kNoU5JhtYUrlmAbpxRjb9tSreDdtACpm3rkpxp7AQndnI0Shu/fk1/rE3oWsDqMX
# 3jjv40e8KN5YsJBnczyWB4JyeeFMW3JBfdeAKhzohFe8U5w9WuvcP1E8cIxLoKSD
# zCCBOu0hWdjzKNu8Y5SwB1lt5dQhABYyzR3dxEO/T1K/BVF3rV69AgMBAAGjggIb
# MIICFzAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYE
# FGtpKDo1L0hjQM972K9J6T7ZPdshMFQGA1UdIARNMEswSQYEVR0gADBBMD8GCCsG
# AQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVw
# b3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAwe
# CgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTIftJqhSob
# yhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHegdYZzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSWRlbnRpdHklMjBWZXJp
# ZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBBdXRob3JpdHklMjAyMDIw
# LmNybDCBlAYIKwYBBQUHAQEEgYcwgYQwgYEGCCsGAQUFBzAChnVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElkZW50aXR5
# JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5
# JTIwMjAyMC5jcnQwDQYJKoZIhvcNAQEMBQADggIBAF+Idsd+bbVaFXXnTHho+k7h
# 2ESZJRWluLE0Oa/pO+4ge/XEizXvhs0Y7+KVYyb4nHlugBesnFqBGEdC2IWmtKMy
# S1OWIviwpnK3aL5JedwzbeBF7POyg6IGG/XhhJ3UqWeWTO+Czb1c2NP5zyEh89F7
# 2u9UIw+IfvM9lzDmc2O2END7MPnrcjWdQnrLn1Ntday7JSyrDvBdmgbNnCKNZPmh
# zoa8PccOiQljjTW6GePe5sGFuRHzdFt8y+bN2neF7Zu8hTO1I64XNGqst8S+w+RU
# die8fXC1jKu3m9KGIqF4aldrYBamyh3g4nJPj/LR2CBaLyD+2BuGZCVmoNR/dSpR
# Cxlot0i79dKOChmoONqbMI8m04uLaEHAv4qwKHQ1vBzbV/nG89LDKbRSSvijmwJw
# xRxLLpMQ/u4xXxFfR4f/gksSkbJp7oqLwliDm/h+w0aJ/U5ccnYhYb7vPKNMN+SZ
# DWycU5ODIRfyoGl59BsXR/HpRGtiJquOYGmvA/pk5vC1lcnbeMrcWD/26ozePQ/T
# WfNXKBOmkFpvPE8CH+EeGGWzqTCjdAsno2jzTeNSxlx3glDGJgcdz5D/AAxw9Sdg
# q/+rY7jjgs7X6fqPTXPmaCAJKVHAP19oEjJIBwD1LyHbaEgBxFCogYSOiUIr0Xqc
# r1nJfiWG2GwYe6ZoAF1bMIIHnzCCBYegAwIBAgITMwAAAFtKtY1BMm3cdAAAAAAA
# WzANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBU
# aW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjAxMDgxODU5MDVaFw0yNzAxMDcxODU5
# MDVaMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo3QTFBLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHkwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCQVMwW255Q13ntAdCg+RuP+O+bYRcn
# 3LQsrhEk1kF75S4uFsf7XdqlHXquInXnoOlVoYjh37t8CVeE1BkkbaofQnK9QZog
# Sr/YrhaYB8iAbuUMd/GbMcJRXl1UvmaiSSp10WwzUHXGEqAv+nNIUCfzx+dAwUQ0
# JD11cMhYsy60R/QJayXlIOwSnk9t837UvPyjiS7xBGxzheqUjmN2Vaa2VFm1o1sE
# U5qB2kPxPL61rSzchCfm9PPVVtSJK2t7eBkweVm8twi9Sts2JwMQSL2n7CjBco/T
# rlx3EzyjA6BUjHmphvTCjjG+rqBtT43Zw4LCz+hDjEUs6yy+4xA9ZmwfUUnfX4bc
# vh0K+r2YLAZ+qFMvmE6TVS7JMHbVDPNlmAJD87ZTrdwIi9Ksle/1N4/7qt7xzIzz
# NMNN+NDOezXotIOAQnDLdHW6qHPdVYAm9/9+rB0ADaJ7Z9RzhdqC5PNfdEEUuN4r
# B1a2vB/LH+fhpaiGLGIgil9OB2Yjs2VvNup1SOnfvvJck3lpqY/dFGvbj2yYVY8B
# N6IerTuddMkqpkjEixDdO6dyG3txOgQG9sPd61s29uvnaUrYWyheJAKaH6gbFj1+
# DBLRykjn7T5lUwkOO7YIa1bh4mvY2Ph7I9NZuCluFrZJlZty+oTGRAjGuLIzMQF8
# /m1/wCYVk3uk2QIDAQABo4IByzCCAccwHQYDVR0OBBYEFO/y6lJVlmIVyXV8IGCs
# eG/Br9K2MB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7ZPdshMGwGA1UdHwRl
# MGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAy
# MC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJT
# QSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwZgYDVR0gBF8w
# XTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMAgGBmeBDAEEAjAN
# BgkqhkiG9w0BAQwFAAOCAgEAAB/s3flyoeDsV2DFhZrYIpVwEBnLTowlAdcP7gYg
# vzl3B9yGuP123VISsxW2ok2yBOr2GSndaeLu5yji5GsMpgDFcrjuy0peqyyrbWSM
# i4Vo0ytM1zs9LuMS6vfm0bQRCibwOrA+ZycB9SDus9WIs8riEaGpTAp261IsX1sU
# J+EwJje7fbpPl9hVE4RGt3sM0cIbRvscGgGyzJMUZkduCZ313dVcSqPdPpu1s7qL
# /elLoMecGXXsIiCJtWVk4+JQiR7qeu/S3Dmu7QMSTIqVWkpbUB/X5vUzinM5X8bV
# rgXC1OHbmX6sILCC7B+zzJHF9c8EM0A9MgLT4Z2M/SjRtduW1/oopTntUvER6r9m
# 2waTKWqOJHFL0COnTICkbxZptXi24UjTkKZQzExg9bTVXTRpCPeo1Lvra6FI1jDI
# uOk0HwQB8bQ06UYSLv/O7wFUPGekR4RcXrM+BHeSU4WiEEQMuhnDvyZPkMw86GdG
# q0SJCLBie62YDlQI8fXLX8PJR/UX43MAd8HRgWDTDVSakKVGotk2nXX+aV802RBy
# KixBed0qwYyHiJ6EKz+1OVZV4jELMXsC3SDawBNpdk0dygYpG/kUEcoG06fI49so
# gtDQlMBvivp3YJTeUTG14xVumimufV6vm/F8yvwyvgCbYDqR4Cb/EK5OtgPrcDlS
# zqYxggPUMIID0AIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAW0q1jUEybdx0AAAAAABbMA0GCWCGSAFl
# AwQCAQUAoIIBLTAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIGmsHW9yQEN5+qig90iHrwebSeJPTRDrX6fHWF+ir/GmMIHdBgsqhkiG
# 9w0BCRACLzGBzTCByjCBxzCBoAQgLzEDVV2dG9McZRsPF/9yBMmzm7k+muVtXetQ
# lvnBg+8wfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABbSrWNQTJt3HQAAAAAAFswIgQgcIcDmRdK2VhC
# 7uWUtl7jNMn9x8zfnOBTl8hH91XjZiAwDQYJKoZIhvcNAQELBQAEggIAIzkypGpr
# VLI+L1ThJgLmSMasRh3NqaEpkg7eB2+AEQaps81UfuE4U0/ZWGJMQ+GRJb87Ohfp
# GfwNZ4+sWTBAXbkAt8cshEoRHgkZdOJNW6pHzlbwZLbdcBk/psY0s2rYaR6/urBS
# KszGFE+yUQzZCLzMju7QAviVhx5LduPvNBSkwtHcQq/4MGdz/dn2hOEBlbY9GI9X
# OTwBQZzfYu5oV3mMk0t+2xi+3OJRWF2IdsRadJGsvHd4dQUzhF3Ezc9QtdGX+u16
# M613CniFf0hvuTUKzDuuBEGCiKXrTDWxyPJ23FLmOlm3+3Uy1G82R/PHhMI1Qwhg
# ZHw3pwGRSV+5l2Q0yNCh8SOwNk/tgSXl3dcgvmlvQPzFVjaEc0PtyTPBaRd8v9+v
# g9Lo/0eSx9LNojvtLl6YZU8ziJt32lpUtZAvKhc3+/xxBE/DNzaJkYM4fNg3qyR9
# HadtH4VIldF/EGzaNML+6MGDxSFI2D2kluHCTjPLdhv1UbDJfjNJG9ITzue55kgJ
# ixAGG+HtQc/oy2N77SpX2ygNKBrcLKLvS61Xopa2tX/G9xHqnVaTKbxWN/UfKGV9
# 7Es2ENAdc+DTy24BaVSqyKBbkLGytu/+ntUcc/VOCsxtsz9JkZKGel4/TGiMeGU/
# kd1Mf61k4Z+zthM9tWJJ7a1Vvbhf6ve7eBE=
# SIG # End signature block
