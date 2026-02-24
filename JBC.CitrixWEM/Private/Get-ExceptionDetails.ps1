function Get-ExceptionDetails {
    <#
    .SYNOPSIS
        Extracts detailed information from a PowerShell ErrorRecord object.

    .DESCRIPTION
        The Get-ExceptionDetails function processes a PowerShell ErrorRecord object
        and extracts comprehensive error information including exception messages,
        stack traces, location details, command context, parameter bindings, and
        nested inner exceptions. This is useful for detailed error logging and debugging.

    .PARAMETER ErrorRecord
        The ErrorRecord object to extract details from. This is typically obtained
        from $_ in a catch block or from $Error[0].

    .PARAMETER AsPlainText
        If specified, returns the error details as a formatted text string instead
        of a PSCustomObject.

    .PARAMETER IncludeEnvironment
        If specified, includes host and environment context information such as
        PowerShell version, computer name, and user name.

    .PARAMETER ExcludeBoundParameters
        If specified, excludes bound parameters from the output. Use this when
        parameters may contain sensitive data like passwords or API keys.

    .PARAMETER AsStringValues
        If specified, converts complex objects (BoundParameters, TargetObject,
        ExceptionData) to string representations. Useful for logging to flat files
        or systems that do not support nested objects.

    .EXAMPLE
        try {
            Get-Item "C:\NonExistent\Path" -ErrorAction Stop
        }
        catch {
            $details = Get-ExceptionDetails -ErrorRecord $_
            $details | Format-List
        }

        Captures an error and extracts detailed information from it.

    .EXAMPLE
        $details = Get-ExceptionDetails -ErrorRecord $Error[0] -IncludeEnvironment
        Write-Host "Error occurred at line $($details.LineNumber) in $($details.ScriptName)"

        Processes the most recent error from the $Error automatic variable with environment info.

    .EXAMPLE
        try {
            Invoke-RestMethod -Uri "https://invalid.url" -ErrorAction Stop
        }
        catch {
            Get-ExceptionDetails -ErrorRecord $_ -AsPlainText | Out-File "C:\Logs\error.log" -Append
        }

        Logs detailed error information to a file in plain text format.

    .EXAMPLE
        try {
            Get-ADUser -Identity "nonexistent" -ErrorAction Stop
        }
        catch {
            $details = Get-ExceptionDetails -ErrorRecord $_ -AsStringValues
            $details | ConvertTo-Json | Out-File "C:\Logs\error.json"
        }

        Exports error details as JSON with all values converted to strings.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Returns a PSCustomObject containing detailed error information.

        System.String
        When -AsPlainText is specified, returns a formatted string.

    .NOTES
        Function  : Get-ExceptionDetails
        Author    : John Billekens
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 2026.129.945
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorRecord]
        $ErrorRecord,

        [Parameter(Mandatory = $false)]
        [Alias("AsString", "AsText")]
        [switch]
        $AsPlainText,

        [Parameter(Mandatory = $false)]
        [switch]
        $IncludeEnvironment,

        [Parameter(Mandatory = $false)]
        [switch]
        $ExcludeBoundParameters,

        [Parameter(Mandatory = $false)]
        [Alias("Flatten")]
        [switch]
        $AsStringValues
    )

    process {
        # Recursively collect all inner exceptions
        $innerExceptions = [System.Collections.ArrayList]::new()
        $currentException = $ErrorRecord.Exception.InnerException
        while ($null -ne $currentException) {
            [void]$innerExceptions.Add([ordered]@{
                    Message    = $currentException.Message
                    Type       = $currentException.GetType().FullName
                    Source     = $currentException.Source
                    HResult    = $currentException.HResult
                    StackTrace = $currentException.StackTrace
                })
            $currentException = $currentException.InnerException
        }

        # Build formatted PS error message
        $formattedFields = @(
            $ErrorRecord.InvocationInfo.MyCommand.Name
            $ErrorRecord.Exception.Message
            $ErrorRecord.InvocationInfo.PositionMessage
            $ErrorRecord.CategoryInfo.ToString()
            $ErrorRecord.FullyQualifiedErrorId
        )
        $PSError = "{0} : {1}`n{2}`n    + CategoryInfo          : {3}`n    + FullyQualifiedErrorId : {4}`n" -f $formattedFields

        # Parse call stack into array for easier processing
        $callStack = $null
        if ($ErrorRecord.ScriptStackTrace) {
            $callStack = $ErrorRecord.ScriptStackTrace -split "`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ }
        }

        # Extract error code properties (present on some exception types)
        $errorCode = $null
        $nativeErrorCode = $null
        if ($ErrorRecord.Exception.PSObject.Properties['ErrorCode']) {
            $errorCode = $ErrorRecord.Exception.ErrorCode
        }
        if ($ErrorRecord.Exception.PSObject.Properties['NativeErrorCode']) {
            $nativeErrorCode = $ErrorRecord.Exception.NativeErrorCode
        }

        # Get bound parameters unless excluded
        $boundParams = $null
        if (-not $ExcludeBoundParameters -and $ErrorRecord.InvocationInfo.BoundParameters) {
            if ($AsStringValues) {
                $paramStrings = $ErrorRecord.InvocationInfo.BoundParameters.GetEnumerator() | ForEach-Object {
                    "$($_.Key)='$($_.Value)'"
                }
                $boundParams = $paramStrings -join '; '
            } else {
                $boundParams = $ErrorRecord.InvocationInfo.BoundParameters
            }
        }

        # Get unbound arguments
        $unboundArgs = $null
        if ($ErrorRecord.InvocationInfo.UnboundArguments) {
            if ($AsStringValues) {
                $unboundArgs = $ErrorRecord.InvocationInfo.UnboundArguments -join '; '
            } else {
                $unboundArgs = $ErrorRecord.InvocationInfo.UnboundArguments
            }
        }

        # Extract Exception Data dictionary
        $exceptionData = $null
        if ($ErrorRecord.Exception.Data -and $ErrorRecord.Exception.Data.Count -gt 0) {
            if ($AsStringValues) {
                $dataStrings = $ErrorRecord.Exception.Data.GetEnumerator() | ForEach-Object {
                    "$($_.Key)='$($_.Value)'"
                }
                $exceptionData = $dataStrings -join '; '
            } else {
                $exceptionData = [ordered]@{}
                foreach ($key in $ErrorRecord.Exception.Data.Keys) {
                    $exceptionData[$key] = $ErrorRecord.Exception.Data[$key]
                }
            }
        }

        # Get target object
        $targetObject = $ErrorRecord.TargetObject
        if ($AsStringValues -and $null -ne $targetObject) {
            $targetObject = "$($targetObject)"
        }

        # Build the error details object
        $errorDetails = [ordered]@{
            # Timestamp
            Timestamp           = Get-Date -Format "o"

            # Formatted error message
            PSError             = $PSError

            # Exception details
            Message             = $ErrorRecord.Exception.Message
            ExceptionType       = $ErrorRecord.Exception.GetType().FullName
            ExceptionSource     = $ErrorRecord.Exception.Source
            HResult             = $ErrorRecord.Exception.HResult
            ErrorCode           = $errorCode
            NativeErrorCode     = $nativeErrorCode

            # Error action context
            ErrorActionPref     = [string]$ErrorActionPreference

            # Error identification
            ErrorId             = $ErrorRecord.FullyQualifiedErrorId
            Category            = $ErrorRecord.CategoryInfo.Category
            Activity            = $ErrorRecord.CategoryInfo.Activity
            Reason              = $ErrorRecord.CategoryInfo.Reason
            TargetName          = $ErrorRecord.CategoryInfo.TargetName
            TargetType          = $ErrorRecord.CategoryInfo.TargetType
            CategoryInfo        = $ErrorRecord.CategoryInfo.ToString()

            # Target object
            TargetObject        = $targetObject

            # Command context
            CommandName         = $ErrorRecord.InvocationInfo.MyCommand.Name
            CommandType         = if ($ErrorRecord.InvocationInfo.MyCommand) {
                [string]$ErrorRecord.InvocationInfo.MyCommand.CommandType
            } else { $null }
            ModuleName          = $ErrorRecord.InvocationInfo.MyCommand.ModuleName
            ModuleVersion       = if ($ErrorRecord.InvocationInfo.MyCommand.Module) {
                $ErrorRecord.InvocationInfo.MyCommand.Module.Version.ToString()
            } else { $null }
            InvocationName      = $ErrorRecord.InvocationInfo.InvocationName

            # Script location
            ScriptName          = $ErrorRecord.InvocationInfo.ScriptName
            PSScriptRoot        = $ErrorRecord.InvocationInfo.PSScriptRoot
            PSCommandPath       = $ErrorRecord.InvocationInfo.PSCommandPath
            LineNumber          = $ErrorRecord.InvocationInfo.ScriptLineNumber
            CharacterPosition   = $ErrorRecord.InvocationInfo.OffsetInLine
            Line                = if ($ErrorRecord.InvocationInfo.Line) {
                "$($ErrorRecord.InvocationInfo.Line)".Trim()
            } else { $null }
            PositionMessage     = $ErrorRecord.InvocationInfo.PositionMessage

            # Pipeline context
            PipelineLength      = $ErrorRecord.InvocationInfo.PipelineLength
            PipelinePosition    = $ErrorRecord.InvocationInfo.PipelinePosition
            HistoryId           = $ErrorRecord.InvocationInfo.HistoryId

            # Parameter binding
            BoundParameters     = $boundParams
            UnboundArguments    = $unboundArgs

            # Exception data dictionary
            ExceptionData       = $exceptionData

            # ErrorDetails object (cmdlet-provided additional info)
            ErrorDetailsMessage = $ErrorRecord.ErrorDetails.Message
            RecommendedAction   = $ErrorRecord.ErrorDetails.RecommendedAction

            # Stack traces
            ScriptStackTrace    = $ErrorRecord.ScriptStackTrace
            CallStack           = $callStack
            ExceptionStackTrace = $ErrorRecord.Exception.StackTrace

            # Inner exceptions
            InnerExceptions     = if ($innerExceptions.Count -gt 0) {
                $innerExceptions.ToArray()
            } else { $null }
        }

        # Add environment context if requested
        if ($IncludeEnvironment) {
            $errorDetails['HostName'] = $Host.Name
            $errorDetails['PSVersion'] = $PSVersionTable.PSVersion.ToString()
            $errorDetails['PSEdition'] = $PSVersionTable.PSEdition
            $errorDetails['CLRVersion'] = if ($PSVersionTable.CLRVersion) {
                $PSVersionTable.CLRVersion.ToString()
            } else { $null }
            $errorDetails['ComputerName'] = $env:COMPUTERNAME
            $errorDetails['UserName'] = "$($env:USERDOMAIN)\$($env:USERNAME)"
            $errorDetails['ProcessId'] = $PID
        }

        if ($AsPlainText) {
            $output = [System.Text.StringBuilder]::new()
            [void]$output.AppendLine("")
            [void]$output.AppendLine("=" * 80)
            [void]$output.AppendLine("ERROR DETAILS - $($errorDetails.Timestamp)")
            [void]$output.AppendLine("=" * 80)

            foreach ($key in $errorDetails.Keys) {
                $value = $errorDetails[$key]
                if ($null -eq $value) {
                    continue
                }

                if ($key -eq 'InnerExceptions') {
                    [void]$output.AppendLine("")
                    [void]$output.AppendLine("--- Inner Exceptions ---")
                    $index = 0
                    foreach ($inner in $value) {
                        [void]$output.AppendLine("  [$($index)]: $($inner.Type)")
                        [void]$output.AppendLine("       Message : $($inner.Message)")
                        [void]$output.AppendLine("       Source  : $($inner.Source)")
                        [void]$output.AppendLine("       HResult : $($inner.HResult)")
                        $index++
                    }
                } elseif ($key -eq 'CallStack') {
                    [void]$output.AppendLine("")
                    [void]$output.AppendLine("--- Call Stack ---")
                    foreach ($frame in $value) {
                        [void]$output.AppendLine("  $($frame)")
                    }
                } elseif ($key -eq 'BoundParameters' -and $value -is [hashtable]) {
                    [void]$output.AppendLine("")
                    [void]$output.AppendLine("--- Bound Parameters ---")
                    foreach ($param in $value.GetEnumerator()) {
                        [void]$output.AppendLine("  $($param.Key): $($param.Value)")
                    }
                } elseif ($key -eq 'ExceptionData' -and $value -is [System.Collections.Specialized.OrderedDictionary]) {
                    [void]$output.AppendLine("")
                    [void]$output.AppendLine("--- Exception Data ---")
                    foreach ($item in $value.GetEnumerator()) {
                        [void]$output.AppendLine("  $($item.Key): $($item.Value)")
                    }
                } elseif ($value -is [string] -and $value.Contains("`n")) {
                    [void]$output.AppendLine("")
                    [void]$output.AppendLine("--- $($key) ---")
                    [void]$output.AppendLine($value)
                } else {
                    [void]$output.AppendLine("$($key.PadRight(20)): $($value)")
                }
            }

            [void]$output.AppendLine("=" * 80)
            return $output.ToString()
        } else {
            return [PSCustomObject]$errorDetails
        }
    }
}

# SIG # Begin signature block
# MIImdwYJKoZIhvcNAQcCoIImaDCCJmQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAnguTMzCWNM2kg
# s59xfpVYfST8RnA2RYYw0vfqXQyb7KCCIAowggYUMIID/KADAgECAhB6I67aU2mW
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
# MC8GCSqGSIb3DQEJBDEiBCCZAsBiDxDwTCzQWtCQLdayTHzm7Ylrn+0/5LPu4KK7
# uTANBgkqhkiG9w0BAQEFAASCAYBV8O2cwg6WGa/eBQN/IrfdXJSoJrYKK203sh5o
# f21eTDVxykpAM/aCKJWfkVHsdcdCe1NYR2vsdLSIVXRz6bUni2s9yfgVdYsNHO2F
# /aoniXkK5NlwF05hJRs8wu0/vnOm2Pq2IeZ+hU3hEK6yKFPGbZ2CDxXJIZL0kHl4
# u+lhk5PSteKV8td6liqg1bprWlJC5uGBIMbhqPOBpp3Fvae6rxeHzOs86BqwGOmm
# fZjPjN7cdoCyLPMAXH2mFKZ9nmxvQela+KvM2lLRZ7V7SMV28UqfqHl8ad46Nah9
# h+lu9V2IJkEckfMyCf+0RhIbu1O4rKrdZP4p5trDCpynmyqxg+fPgyD1KozLmodX
# 9ryuyCcNkEdVP4mWpUcSTilAD4GblmwwrgqCy5qnj8IGXnj0NQsg4xRCu2CFss32
# iXetWxfBf4Ux9EAyvJXHxQY5Z8e6apdf0/6TRuIXP/yfMX16AlvIF8wE4RDO2557
# uG2F2Lr0fY3ENaM+4vbP1Bdp8XOhggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwC
# AQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQp
# O24e3denNAiHrXpOtyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAyMjQwODMwMDFaMD8GCSqGSIb3
# DQEJBDEyBDDNTlGsI3nNYCAuPikOrHT+HzbxrzGeqg9Y0rog1n5OXcziixbULAje
# V9+PfB4hBR4wDQYJKoZIhvcNAQEBBQAEggIAcF/NTt3L0foerhgv7LxmlMchR/zd
# ++r+nLum5cOIOvcOKOYeK/fWp64bJw7068G4C3D5vN+RJYbBG3kh45XaXd00ukpe
# en4NScW8Tg3WVWMCDt0DlhFTCPpAJPaiBD0M05AH2cU+2L500rJZp6cWPohUAKj+
# vSj0rinuHRN/SDzhuxpeITXRfcwWyvOeOfwp2NOuGRdeBb3gp8r9NhEyyesTyUaI
# 8ab4IDocZwtNzRwUhADyJsYCWPX7HNYBulwoWNU74Ig3K1Tu/1+1gcWFE7MT0qyH
# O2zPrGTLq2og/C8SopGWsTzmfiS0JFxGM+XouN9NkiYoIs8Zh2krginsePkthKx4
# dcOSTMIO4kn8nkJ3EWvGKJCFFKv6IbO2VOgR4SAY1ri3tiWQZ4+U4J7A6tmTINUF
# PbFGO0LTN0l4r4Fv/fELVCIxWZZnkQkJiFPK90zv4vH8DZxcuJSBD9DL0/cVYgJp
# jKFSw49Kn07C/RyPf9Cl3aZVsn6OScXyHYNhjhaFKGsUKBJvxdoEbpF+P0C9A2V1
# pMIKSpPAHKLqhzdjBHFbDrwDb2+Dv/3gVS4v4TtctF/Zpj07elKbSqY5Dun8LAn8
# eLyDrYRmy86fZCS8EyRY0HNwVF+fA3DcnmKqVuoGHWCvYmixOxt814zAWesW8GzB
# jZrvY7dHv8uA6sk=
# SIG # End signature block
