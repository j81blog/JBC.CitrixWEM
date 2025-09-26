function Set-WEMFileAssociation {
    <#
    .SYNOPSIS
        Updates an existing WEM file association action.
    .DESCRIPTION
        This function updates the properties of an existing file association action. It retrieves the
        current configuration, applies the specified changes, and submits the full object back to the API.
    .PARAMETER Id
        The unique ID of the file association action to update.
    .PARAMETER InputObject
        A file association object (from Get-WEMFileAssociation) to be modified. Can be passed via the pipeline.
    .PARAMETER TargetPath
        The new full path to the application that will open the file.
    .PARAMETER PassThru
        If specified, the command returns the updated file association object.
    .EXAMPLE
        PS C:\> Get-WEMFileAssociation -Name "Old Association" | Set-WEMFileAssociation -Name "New Association Name" -PassThru

        Finds the file association "Old Association", renames it, and returns the modified object.
    .EXAMPLE
        PS C:\> Set-WEMFileAssociation -Id 5 -Enabled $false

        Disables the file association action with ID 5.
    .NOTES
        Function  : Set-WEMFileAssociation
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.1
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
        [string]$FileExtension,

        [Parameter(Mandatory = $false)]
        [string]$TargetPath,

        [Parameter(Mandatory = $false)]
        [string]$TargetCommand,

        [Parameter(Mandatory = $false)]
        [string]$ProgId,

        [Parameter(Mandatory = $false)]
        [string]$Action,

        [Parameter(Mandatory = $false)]
        [bool]$Enabled,

        [Parameter(Mandatory = $false)]
        [bool]$IsDefault,

        [Parameter(Mandatory = $false)]
        [bool]$TargetOverwrite,

        [Parameter(Mandatory = $false)]
        [bool]$RunOnce,

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
                Write-Verbose "Retrieving current settings for File Association with ID '$($Id)'..."
                $CurrentSettings = Get-WEMFileAssociation | Where-Object { $_.Id -eq $Id }
                if (-not $CurrentSettings) {
                    throw "A file association with ID '$($Id)' could not be found in the active or specified site."
                }
            }

            $TargetDescription = "WEM File Association '$($CurrentSettings.Name)' (ID: $($CurrentSettings.Id))"
            if ($PSCmdlet.ShouldProcess($TargetDescription, "Update")) {

                # Modify only the properties that were specified by the user
                $ParametersToUpdate = $PSBoundParameters.Keys | Where-Object { $CurrentSettings.PSObject.Properties.Name -contains $_ }
                foreach ($ParamName in $ParametersToUpdate) {
                    Write-Verbose "Updating property '$($ParamName)' to '$($PSBoundParameters[$ParamName])'."
                    $CurrentSettings.$ParamName = $PSBoundParameters[$ParamName]
                }

                $UriPath = "services/wem/action/fileAssociations"
                Invoke-WemApiRequest -UriPath $UriPath -Method "PUT" -Connection $Connection -Body $CurrentSettings

                if ($PassThru.IsPresent) {
                    Write-Verbose "PassThru specified, retrieving updated file association..."
                    $UpdatedObject = Get-WEMFileAssociation | Where-Object { $_.Id -eq $CurrentSettings.Id }
                    Write-Output $UpdatedObject
                }
            }
        } catch {
            $Identifier = if ($Id) { $Id } else { $InputObject.Name }
            Write-Error "Failed to update WEM File Association '$($Identifier)': $($_.Exception.Message)"
            return $null
        }
    }
}