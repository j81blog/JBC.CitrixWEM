function Set-WEMNetworkDrive {
    <#
    .SYNOPSIS
        Updates an existing WEM network drive action.
    .DESCRIPTION
        This function updates the properties of an existing network drive action. It retrieves the
        current configuration, applies the specified changes, and submits the full object back to the API.
    .PARAMETER Id
        The unique ID of the network drive action to update.
    .PARAMETER InputObject
        A network drive object (from Get-WEMNetworkDrive) to be modified. Can be passed via the pipeline.
    .PARAMETER TargetPath
        The new UNC path for the network drive.
    .PARAMETER DisplayName
        The new display name for the network drive.
    .PARAMETER PassThru
        If specified, the command returns the updated network drive object.
    .EXAMPLE
        PS C:\> Get-WEMNetworkDrive -Name "Old Share" | Set-WEMNetworkDrive -TargetPath "\\new-server\share" -PassThru

        Finds the network drive "Old Share", updates its target path, and returns the modified object.
    .EXAMPLE
        PS C:\> Set-WEMNetworkDrive -Id 3 -Enabled $false

        Disables the network drive action with ID 3.
    .NOTES
        Function  : Set-WEMNetworkDrive
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.0
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
        [string]$TargetPath,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [bool]$Enabled,

        [Parameter(Mandatory = $false)]
        [bool]$SelfHealing,

        [Parameter(Mandatory = $false)]
        [bool]$SetAsHomeDrive,

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
                Write-Verbose "Retrieving current settings for Network Drive with ID '$($Id)'..."
                # Get-WEMNetworkDrive uses the active site by default if one is set.
                $CurrentSettings = Get-WEMNetworkDrive | Where-Object { $_.Id -eq $Id }
                if (-not $CurrentSettings) {
                    throw "A network drive with ID '$($Id)' could not be found in the active or specified site."
                }
            }

            $TargetDescription = "WEM Network Drive '$($CurrentSettings.Name)' (ID: $($CurrentSettings.Id))"
            if ($PSCmdlet.ShouldProcess($TargetDescription, "Update")) {

                # Modify only the properties that were specified by the user
                $ParametersToUpdate = $PSBoundParameters.Keys | Where-Object { $CurrentSettings.PSObject.Properties.Name -contains $_ }
                foreach ($ParamName in $ParametersToUpdate) {
                    Write-Verbose "Updating property '$($ParamName)' to '$($PSBoundParameters[$ParamName])'."
                    $CurrentSettings.$ParamName = $PSBoundParameters[$ParamName]
                }

                # The API expects the entire object in the body for a PUT request.
                $UriPath = "services/wem/action/networkDrives"
                Invoke-WemApiRequest -UriPath $UriPath -Method "PUT" -Connection $Connection -Body $CurrentSettings

                if ($PassThru.IsPresent) {
                    Write-Verbose "PassThru specified, retrieving updated network drive..."
                    $UpdatedObject = Get-WEMNetworkDrive | Where-Object { $_.Id -eq $CurrentSettings.Id }
                    Write-Output $UpdatedObject
                }
            }
        } catch {
            $Identifier = if ($Id) { $Id } else { $InputObject.Name }
            Write-Error "Failed to update WEM Network Drive '$($Identifier)': $($_.Exception.Message)"
            return $null
        }
    }
}