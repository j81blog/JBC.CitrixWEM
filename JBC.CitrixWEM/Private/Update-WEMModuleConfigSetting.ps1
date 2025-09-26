function Update-WEMModuleConfigSetting {
    <#
    .SYNOPSIS
    Updates a specific setting in the WEM module configuration file.
    .DESCRIPTION
    This function updates a specific setting in the WEM module configuration file located in the user's App
    Data directory. If the setting does not exist, it will be added.
    .PARAMETER SettingName
    The name of the setting to update or add.
    .PARAMETER SettingValue
    The value to set for the specified setting.
    .EXAMPLE
    Update-WEMModuleConfigSetting -SettingName "DontShowModuleInfo" -SettingValue $true
    Updates the "DontShowModuleInfo" setting to true in the configuration file.
    .NOTES
    Author: John Billekens Consultancy
    Date: 16-09-2025
    Version: 1.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$SettingName,
        [Parameter(Mandatory = $false)]
        [object]$SettingValue
    )
    try {
        $DefaultConfig = @{
            Config = @{
                ShowModuleInfo     = $true
                ShowConnectApiInfo = $true
            }
        }
        $AppDataPath = [System.IO.Path]::GetDirectoryName($Script:WEMConfigFilePath)
        if (-not (Test-Path -Path $AppDataPath)) {
            New-Item -Path $AppDataPath -ItemType Directory | Out-Null
        }
        if (-not (Test-Path -Path $Script:WEMConfigFilePath)) {
            Write-Verbose -Message "Configuration file not found. Creating default configuration at $Script:WEMConfigFilePath"
            $DefaultConfig | ConvertTo-Json | Set-Content -Path $Script:WEMConfigFilePath
            $Script:WEMModuleConfig = $DefaultConfig
        } else {
            Write-Verbose -Message "Loading existing configuration from $Script:WEMConfigFilePath"
            $Script:WEMModuleConfig = Get-Content -Path $Script:WEMConfigFilePath | ConvertFrom-Json
        }

        if ($Script:WEMModuleConfig.Config.PSObject.Properties.Name -contains $SettingName) {
            $Script:WEMModuleConfig.Config."$SettingName" = $SettingValue
        } else {
            $Script:WEMModuleConfig.Config | Add-Member -MemberType NoteProperty -Name $SettingName -Value $SettingValue
        }
        Write-Verbose -Message "Updating configuration setting '$SettingName' to '$SettingValue'"
        $Script:WEMModuleConfig | ConvertTo-Json | Set-Content -Path $Script:WEMConfigFilePath
    } catch {
        Write-Verbose -Message "Failed to update configuration setting '$SettingName': $_"
    }

}