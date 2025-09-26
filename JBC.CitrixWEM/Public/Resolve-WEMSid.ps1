function Resolve-WEMSid {
    <#
    .SYNOPSIS
        Translates one or more SIDs to their corresponding names using the WEM service.
    .DESCRIPTION
        This function takes an array of Security Identifiers (SIDs) and uses the On-Premises WEM API
        to resolve them to their friendly names (e.g., user or group names).
        This command is only applicable for On-Premises connections.
    .PARAMETER Sid
        An array of SID strings to be resolved. This parameter accepts input from the pipeline.
    .EXAMPLE
        PS C:\> Resolve-WEMSid -Sid "S-1-5-21-1111111111-222222222-333333333-44444"

        Resolves the specified SID to its corresponding account name.
    .EXAMPLE
        PS C:\> "S-1-5-32-544", "S-1-5-32-545" | Resolve-WEMSid

        Resolves the SIDs for the local Administrators and Users groups via the pipeline.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Co-Author:      Gemini
        Creation Date:  2025-08-11
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Sid
    )

    try {
        # Get connection details. Throws an error if not connected.
        $Connection = Get-WemApiConnection

        # This command is only valid for On-Premises connections.
        if (-not $Connection.IsOnPrem) {
            throw "This command is only supported for On-Premises WEM deployments."
        }

        $Body = @{
            sids = $Sid
        }

        if ($Connection.IsOnPrem) {
            $UriPath = "services/wem/onPrem/translator"
        } else {
            $UriPath = "/services/wem/forward/translator"
        }

        $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

        # The API returns the results in an 'Items' property.
        Write-Output ($Result | Expand-WEMResult)
    } catch {
        Write-Error "Failed to resolve SIDs: $($_.Exception.Message)"
        return $null
    }
}