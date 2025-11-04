function Resolve-WEMSid {
    <#
    .SYNOPSIS
        Resolves one or more SIDs to AD objects using the WEM service.
    .DESCRIPTION
        This function takes one or more SIDs and uses the WEM API to resolve them into full
        AD object details, including the account name. It works for both Cloud and On-Premises connections,
        processing SIDs in batches of 25 for stability.
    .PARAMETER Sid
        A single SID or an array of SIDs to resolve. This parameter accepts pipeline input.
    .EXAMPLE
        PS C:\> Resolve-WEMSid -Sid "S-1-5-32-544"

        Resolves the well-known Administrators SID to its corresponding object details.
    .EXAMPLE
        PS C:\> "S-1-5-32-544", "S-1-5-32-545" | Resolve-WEMSid

        Resolves the SIDs for the local Administrators and Users groups via the pipeline.
    .NOTES
        Function  : Resolve-WEMSid
        Author    : John Billekens Consultancy
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.4
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$Sid
    )

    begin {
        $AllSids = [System.Collections.Generic.List[string]]::new()
    }

    process {
        $AllSids.AddRange($Sid)
    }

    end {
        try {
            $Connection = Get-WemApiConnection

            if ($AllSids.Count -eq 0) {
                return @()
            }

            $AllResolvedObjects = @()
            $BatchSize = 25
            $i = 0

            while ($i -lt $AllSids.Count) {
                $Batch = $AllSids.GetRange($i, [System.Math]::Min($BatchSize, $AllSids.Count - $i))
                Write-Verbose "Resolving batch of $($Batch.Count) SIDs (starting at index $($i))..."

                $Body = @{ sids = $Batch }

                $UriPath = ''
                if ($Connection.IsOnPrem) {
                    $UriPath = "services/wem/onPrem/translator"
                } else {
                    $UriPath = "services/wem/forward/translator"
                }

                $Result = Invoke-WemApiRequest -UriPath $UriPath -Method "POST" -Connection $Connection -Body $Body

                $ResolvedBatch = ($Result | Expand-WEMResult) | Where-Object { $null -ne $_ }
                if ($ResolvedBatch) {
                    $AllResolvedObjects += $ResolvedBatch
                }

                $i += $BatchSize
            }

            Write-Output @($AllResolvedObjects)
        } catch {
            Write-Error "Failed to resolve WEM SIDs: $($_.Exception.Message)"
            return $null
        }
    }
}