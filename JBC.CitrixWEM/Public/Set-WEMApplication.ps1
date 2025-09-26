function Set-WEMApplication {
    <#
    .SYNOPSIS
        Updates an existing application action in a WEM Configuration Set.
    .DESCRIPTION
        This function updates the properties of an existing application action. You can provide the ID
        and properties directly as parameters, or pipe application objects from Get-WEMApplication to
        extract the Id automatically. Only explicitly specified parameters will be updated - no properties
        are extracted from piped objects except for the Id. If -SiteId is not specified, it uses the
        active Configuration Set defined by Set-WEMActiveConfigurationSite.
    .PARAMETER InputObject
        An application object (from Get-WEMApplication) or any object with an Id property.
        Only the Id will be extracted from this object - all other changes must be specified explicitly.
    .PARAMETER Id
        The unique ID of the application action to update. Can be provided directly or extracted from InputObject.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set where the application exists. Defaults to the active site.
    .PARAMETER IconStream
        A base64-encoded string of the icon to be used for the shortcut.
    .PARAMETER IconFile
        A path to an icon file. The file will be automatically converted to a base64 string.
    .EXAMPLE
        PS C:\> Set-WEMApplication -Id 459 -IconFile "C:\icons\new_icon.ico"

        Updates the icon for the application with ID 459 using a local file.
    .EXAMPLE
        PS C:\> Get-WEMApplication | Where-Object {$_.Name -like "*Office*"} | Set-WEMApplication -State "Disabled"

        Gets all applications with "Office" in the name and disables them via pipeline.
    .EXAMPLE
        PS C:\> Get-WEMApplication -Id 459 | Set-WEMApplication -DisplayName "New Display Name"

        Uses pipeline to get the application Id and explicitly sets a new DisplayName.
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-12
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Stream')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [object]$InputObject,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [int]$Id,

        [int]$SiteId,

        [Parameter(ParameterSetName = 'Stream', ValueFromPipelineByPropertyName = $true)]
        [string]$IconStream,

        [Parameter(ParameterSetName = 'File')]
        [string]$IconFile,

        [string]$DisplayName,

        [string]$CommandLine,

        [string]$StartMenuPath,

        [string]$Parameter,

        [string]$WorkingDirectory,

        [ValidateSet("Enabled", "Disabled")]
        [string]$State,

        [bool]$SelfHealing,

        [ValidateSet("Normal", "Minimized", "Maximized")]
        [string]$WindowStyle,

        [string]$Name,

        [string]$Description
    )

    process {
        try {
            # Handle InputObject - only extract the Id if not explicitly provided
            if ($InputObject -and -not $PSBoundParameters.ContainsKey('Id')) {
                # If InputObject is provided and no explicit Id, try to get Id from InputObject
                if ($InputObject.Id) { $Id = $InputObject.Id }
                elseif ($InputObject.id) { $Id = $InputObject.id }
                else { throw "InputObject must have an 'Id' or 'id' property" }
            }

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

            $TargetDescription = "WEM Application with ID '$($Id)' in Site ID '$($ResolvedSiteId)'"
            if ($PSCmdlet.ShouldProcess($TargetDescription, "Update")) {

                # If -IconFile was used, convert it and populate the $IconStream variable
                if ($PSCmdlet.ParameterSetName -eq 'File') {
                    Write-Verbose "Converting icon file '$($IconFile)' to base64 string..."
                    $IconStream = Convert-IconFileToBase64 -Path $IconFile
                }

                # Build the application object with only the properties that were explicitly provided
                $AppObject = @{
                    id     = $Id
                    siteId = $ResolvedSiteId
                }
                if ($PSBoundParameters.ContainsKey('DisplayName')) { $AppObject.Add('displayName', $DisplayName) }
                if ($PSBoundParameters.ContainsKey('CommandLine')) { $AppObject.Add('commandLine', $CommandLine) }
                if ($PSBoundParameters.ContainsKey('Parameter')) { $AppObject.Add('parameter', $Parameter) }
                if ($PSBoundParameters.ContainsKey('IconStream') -or $PSBoundParameters.ContainsKey('IconFile')) { $AppObject.Add('iconStream', $IconStream) }
                if ($PSBoundParameters.ContainsKey('StartMenuPath')) { $AppObject.Add('startMenuPath', $StartMenuPath) }
                if ($PSBoundParameters.ContainsKey('WorkingDirectory')) { $AppObject.Add('workingDir', $WorkingDirectory) }
                if ($PSBoundParameters.ContainsKey('State')) { $AppObject.Add('state', $State) }
                if ($PSBoundParameters.ContainsKey('SelfHealing')) { $AppObject.Add('selfHealing', $SelfHealing) }
                if ($PSBoundParameters.ContainsKey('WindowStyle')) { $AppObject.Add('windowsStyle', $WindowStyle) }
                if ($PSBoundParameters.ContainsKey('Name')) { $AppObject.Add('name', $Name) }
                if ($PSBoundParameters.ContainsKey('Description')) { $AppObject.Add('description', $Description) }

                $Body = @{ applicationList = @($AppObject) }

                $UriPath = "services/wem/webApplications"
                $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "PUT" -Connection $Connection -Body $Body
                Write-Output ($Result | Expand-WEMResult)
            }
        } catch {
            Write-Error "Failed to update WEM Application with ID '$($Id)': $($_.Exception.Message)"
        }
    }
}