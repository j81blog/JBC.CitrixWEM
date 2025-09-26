function Set-WEMModuleConfiguration {
    <#
    .SYNOPSIS
    Sets the configuration for the WEM module.
    .DESCRIPTION
    This function allows you to set various configuration options for the WEM module.
    .PARAMETER ShowModuleInfo
    If specified, the module information will be displayed.
    .PARAMETER ShowConnectApiInfo
    If specified, the Connect API information will be displayed.
    .EXAMPLE
    Set-WEMModuleConfiguration -ShowModuleInfo $false -ShowConnectApiInfo $false
    Sets both options to not show module and Connect API information.
    .NOTES
    Author: John Billekens Consultancy
    Date: 16-09-2025
    Version: 1.0
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [bool]$ShowModuleInfo,

        [Parameter()]
        [bool]$ShowConnectApiInfo
    )
    if ($PSBoundParameters.ContainsKey('ShowModuleInfo')) {
        Write-Verbose -Message "Setting ShowModuleInfo to $ShowModuleInfo"
        Update-WEMModuleConfigSetting -SettingName "ShowModuleInfo" -SettingValue $ShowModuleInfo
    }
    if ($PSBoundParameters.ContainsKey('ShowConnectApiInfo')) {
        Write-Verbose -Message "Setting ShowConnectApiInfo to $ShowConnectApiInfo"
        Update-WEMModuleConfigSetting -SettingName "ShowConnectApiInfo" -SettingValue $ShowConnectApiInfo
    }
}