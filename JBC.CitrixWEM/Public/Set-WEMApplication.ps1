function Set-WEMApplication {
    <#
    .SYNOPSIS
        Updates an existing WEM application action.
    .DESCRIPTION
        This function updates the properties of an existing application action. It retrieves the
        current configuration, applies the specified changes, and submits the full object back to the API.
    .PARAMETER Id
        The unique ID of the application action to update.
    .PARAMETER InputObject
        An application object (from Get-WEMApplication) to be modified. Can be passed via the pipeline.
    .PARAMETER DisplayName
        The new display name for the application.
    .PARAMETER CommandLine
        The new command line path for the application executable.
    .PARAMETER Parameter
        The new command line parameters for the application.
    .PARAMETER StartMenuPath
        The new Start Menu path for the application shortcut.
    .PARAMETER WorkingDirectory
        The new working directory for the application.
    .PARAMETER State
        The new state for the application (Enabled or Disabled).
    .PARAMETER SelfHealing
        Enable or disable self-healing for the application.
    .PARAMETER WindowStyle
        The new window style for the application (Normal, Minimized, or Maximized).
    .PARAMETER Name
        The new internal name for the application.
    .PARAMETER Description
        The new description for the application.
    .PARAMETER IconFile
        A path to an icon file. The file will be automatically converted to a base64 string.
    .PARAMETER IconStream
        A base64-encoded string of the icon to be used for the application.
    .PARAMETER PassThru
        If specified, the command returns the updated application object.
    .EXAMPLE
        PS C:\> Get-WEMApplication -Name "Old App" | Set-WEMApplication -DisplayName "New App Name" -PassThru

        Finds the application "Old App", renames it, and returns the modified object.
    .EXAMPLE
        PS C:\> Set-WEMApplication -Id 459 -State "Disabled"

        Disables the application action with ID 459.
    .EXAMPLE
        PS C:\> Get-WEMApplication -Id 459 | Set-WEMApplication -IconFile "C:\icons\new_icon.ico"

        Updates the icon for application 459 using a local file.
    .NOTES
        Function  : Set-WEMApplication
        Author    : John Billekens Consultancy
        Co-Author : Claude Code
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 2.0
        Date      : 2025-11-04
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ById')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [int]$Id,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByInputObject', ValueFromPipeline = $true)]
        [PSCustomObject]$InputObject,

        # Add all other modifiable properties as optional parameters
        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [string]$CommandLine,

        [Parameter(Mandatory = $false)]
        [string]$Parameter,

        [Parameter(Mandatory = $false)]
        [string]$StartMenuPath,

        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Enabled", "Disabled")]
        [string]$State,

        [Parameter(Mandatory = $false)]
        [bool]$SelfHealing,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Normal", "Minimized", "Maximized")]
        [string]$WindowStyle,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $false, ParameterSetName = 'ById')]
        [Parameter(Mandatory = $false, ParameterSetName = 'ByInputObject')]
        [string]$IconFile,

        [Parameter(Mandatory = $false)]
        [string]$IconStream,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    process {
        try {
            $Connection = Get-WemApiConnection

            $CurrentSettings = $null
            if ($PSCmdlet.ParameterSetName -eq 'ByInputObject') {
                $CurrentSettings = $InputObject
            } else {
                # If only an ID is provided, we must first get the object.
                Write-Verbose "Retrieving current settings for Application with ID '$($Id)'..."
                # Get-WEMApplication uses the active site by default if one is set.
                $CurrentSettings = Get-WEMApplication | Where-Object { $_.Id -eq $Id }
                if (-not $CurrentSettings) {
                    throw "An application with ID '$($Id)' could not be found in the active or specified site."
                }
            }

            $TargetDescription = "WEM Application '$($CurrentSettings.Name)' (ID: $($CurrentSettings.Id))"
            if ($PSCmdlet.ShouldProcess($TargetDescription, "Update")) {

                # If -IconFile was used, convert it and populate the IconStream parameter
                if ($PSBoundParameters.ContainsKey('IconFile')) {
                    Write-Verbose "Converting icon file '$($IconFile)' to base64 string..."
                    $IconStream = Export-FileIcon -FilePath $IconFile -Size 32 -AsBase64
                    # Add IconStream to PSBoundParameters so it gets updated below
                    $PSBoundParameters['IconStream'] = $IconStream
                }

                # Modify only the properties that were specified by the user
                $ParametersToUpdate = $PSBoundParameters.Keys | Where-Object { $CurrentSettings.PSObject.Properties.Name -contains $_ }
                foreach ($ParamName in $ParametersToUpdate) {
                    Write-Verbose "Updating property '$($ParamName)' to '$($PSBoundParameters[$ParamName])'."
                    $CurrentSettings.$ParamName = $PSBoundParameters[$ParamName]
                }

                # The API expects the entire object wrapped in an applicationList array for a PUT request.
                $Body = @{ applicationList = @($CurrentSettings) }
                $UriPath = "services/wem/webApplications"
                Invoke-WemApiRequest -UriPath $UriPath -Method "PUT" -Connection $Connection -Body $Body

                if ($PassThru.IsPresent) {
                    Write-Verbose "PassThru specified, retrieving updated application..."
                    $UpdatedObject = Get-WEMApplication | Where-Object { $_.Id -eq $CurrentSettings.Id }
                    Write-Output $UpdatedObject
                }
            }
        } catch {
            $Identifier = if ($Id) { $Id } else { $InputObject.Name }
            Write-Error "Failed to update WEM Application '$($Identifier)': $($_.Exception.Message)"
            return $null
        }
    }
}
