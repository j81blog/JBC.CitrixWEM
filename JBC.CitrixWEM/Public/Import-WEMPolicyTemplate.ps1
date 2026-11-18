function Import-WEMPolicyTemplate {
    <#
    .SYNOPSIS
        Uploads a zip file containing ADMX/ADML policy template files to Citrix WEM Cloud.
    .DESCRIPTION
        Uploads a zip file (containing .admx and .adml policy definition files) to Citrix WEM Cloud
        using the Azure Blob Storage SAS upload workflow:
          1. Requests a SAS write token from the WEM API.
          2. Uploads the zip file to Azure Blob Storage using the Block Blob protocol
             (splitting into 4 MB blocks if necessary).
          3. Commits the block list to finalise the blob.

        This function is Cloud-only; it is not supported on On-Premises WEM deployments.

        After a successful upload the zip is staged on the WEM backend. You can monitor
        progress or trigger further processing through the WEM Admin Console.
    .PARAMETER Path
        Path to the .zip file that contains the ADMX and ADML policy template files.
    .PARAMETER UploadName
        The remote file name used when staging the zip in the cloud storage container.
        Defaults to the base name of the supplied file (e.g. "msedge.zip").
    .EXAMPLE
        PS C:\> Import-WEMPolicyTemplate -Path "C:\Templates\msedge.zip"

        Uploads the Microsoft Edge ADMX/ADML zip to WEM Cloud storage.
    .EXAMPLE
        PS C:\> Import-WEMPolicyTemplate -Path "C:\Templates\custom.zip" -UploadName "custom-policies.zip"

        Uploads the zip using a custom remote file name.
    .NOTES
        Version:        1.0
        Author:         John Billekens Consultancy
        Creation Date:  2026-02-25

        Cloud only - the SAS blob write endpoint is not available for On-Premises deployments.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({
            if (-not (Test-Path $_ -PathType Leaf)) { throw "File not found: $_" }
            if ([System.IO.Path]::GetExtension($_) -ne '.zip') { throw "File must be a .zip archive: $_" }
            $true
        })]
        [Alias("FilePath", "FullName")]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$UploadName
    )

    begin {
        # Maximum Azure Blob block size: 4 MB
        $BlockSizeBytes = 4 * 1024 * 1024
    }

    process {
        try {
            $Connection = Get-WemApiConnection

            if ($Connection.IsOnPrem) {
                throw "Import-WEMPolicyTemplate is only supported for Citrix WEM Cloud deployments."
            }

            $ResolvedPath = (Resolve-Path -Path $Path).Path
            $FileName = if ($PSBoundParameters.ContainsKey('UploadName')) {
                $UploadName
            } else {
                [System.IO.Path]::GetFileName($ResolvedPath)
            }

            if ($PSCmdlet.ShouldProcess($FileName, "Upload Policy Template zip to WEM Cloud")) {

                # -- Step 1 -- Request a SAS write token ---------------------------------
                $EncodedBlobPath = [System.Web.HttpUtility]::UrlEncode("upload/$FileName")
                Write-Verbose "Requesting SAS write token for blob path 'upload/$FileName'..."
                $SasResult = Invoke-WemApiRequest `
                    -UriPath "services/wem/export/sas/blob/write?path=$EncodedBlobPath" `
                    -Method "GET" `
                    -Connection $Connection

                if (-not $SasResult -or [string]::IsNullOrEmpty($SasResult.uri) -or [string]::IsNullOrEmpty($SasResult.token)) {
                    throw "Failed to obtain a valid SAS write token from the WEM API."
                }

                $BlobUri   = $SasResult.uri    # e.g. https://<account>.blob.core.windows.net/<container>/upload/file.zip
                $SasToken  = $SasResult.token  # e.g. ?sv=...&sp=w

                Write-Verbose "SAS token obtained. Blob URI: $BlobUri"

                # -- Step 2 -- Split file into blocks and upload each block ---------------
                $FileBytes = [System.IO.File]::ReadAllBytes($ResolvedPath)
                $TotalBytes = $FileBytes.Length
                Write-Verbose "File size: $TotalBytes bytes."

                $BlockIds    = [System.Collections.Generic.List[string]]::new()
                $BlockIndex  = 0
                $Offset      = 0

                $BlobHeaders = @{
                    "Accept"        = "application/json, text/plain, */*"
                    "Origin"        = "https://wem-productioneu-webconsole-bb.wem.cloud.com"
                    "x-ms-blob-type" = "BlockBlob"
                }

                while ($Offset -lt $TotalBytes) {
                    $Length  = [Math]::Min($BlockSizeBytes, $TotalBytes - $Offset)
                    $Chunk   = $FileBytes[$Offset..($Offset + $Length - 1)]

                    # Block ID: base64("block-NNNNNN") - matches the pattern observed in browser traffic
                    $BlockIdPlain  = "block-{0:D6}" -f $BlockIndex
                    $BlockIdBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($BlockIdPlain))
                    $BlockIds.Add($BlockIdBase64)

                    $BlockUri = "{0}{1}&comp=block&blockid={2}" -f $BlobUri, $SasToken, [System.Web.HttpUtility]::UrlEncode($BlockIdBase64)

                    Write-Verbose "Uploading block $BlockIndex ($Length bytes): $BlockIdPlain..."
                    Invoke-WebRequest `
                        -UseBasicParsing `
                        -Uri        $BlockUri `
                        -Method     "PUT" `
                        -Headers    $BlobHeaders `
                        -Body       $Chunk `
                        -ContentType "application/octet-stream" `
                        -ErrorAction Stop | Out-Null

                    $Offset      += $Length
                    $BlockIndex++
                }

                Write-Verbose "$BlockIndex block(s) uploaded successfully."

                # -- Step 3 -- Commit block list ------------------------------------------
                $BlockListXml = [System.Text.StringBuilder]::new()
                [void]$BlockListXml.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
                [void]$BlockListXml.AppendLine('<BlockList>')
                foreach ($Id in $BlockIds) {
                    [void]$BlockListXml.AppendLine("  <Latest>$Id</Latest>")
                }
                [void]$BlockListXml.AppendLine('</BlockList>')

                $CommitUri = "{0}{1}&comp=blocklist" -f $BlobUri, $SasToken
                Write-Verbose "Committing block list..."
                Invoke-WebRequest `
                    -UseBasicParsing `
                    -Uri        $CommitUri `
                    -Method     "PUT" `
                    -Headers    $BlobHeaders `
                    -Body       $BlockListXml.ToString() `
                    -ContentType "application/xml; charset=utf-8" `
                    -ErrorAction Stop | Out-Null

                Write-Information "Policy template zip '$FileName' uploaded successfully to WEM Cloud storage."
                Write-Information "You can now activate the policy templates via the WEM Admin Console under 'Policies and Templates'."

                return [PSCustomObject]@{
                    FileName   = $FileName
                    BlobUri    = $BlobUri
                    Blocks     = $BlockIndex
                    SizeBytes  = $TotalBytes
                }
            }
        } catch {
            Write-Error "Failed to upload WEM policy template '$Path': $($_.Exception.Message)"
        }
    }
}

# SIG # Begin signature block
# MII6AQYJKoZIhvcNAQcCoII58jCCOe4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAMiot7nXnRqyp2
# Xgmgr7nAwYUovwuMAi98GJ1Rq/M6BqCCIiYwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbAMIIEqKADAgECAhMzAAxah1Vq
# R2NpPKqSAAAADFqHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBBT0MgQ0EgMDMwHhcNMjYxMTE3MDE0NjAwWhcNMjYxMTIw
# MDE0NjAwWjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAkxAgXhorpiKQSF8LYykP38Cn
# DqcRYwHiCpWdAwxYxPR3BuZdTQgkNwy4exDN21zE78rhWrQcnBU+ERBPdRZxHAez
# vyAk7hs2tZm2G+iqgv9+aFf2h1YWeZM1o6gTcCk+CGUddzjUid7B0n9iCUitHfTd
# Ac2DAcLOVQc2eFpOLhgKD2ABbSL7iQPlaHKq1YTmAlnQsovojDlwjCtfJhVFKsBy
# bz4QDT/t6L2J02WG7MJ4Ty2mMi2Ncsq8Jcx1Y91Ab/6TkO3rrLqCV8S2ajZpDKxG
# NzkznH55Uy7a/pSUHIg181hcjx2hkHMhzPeTzbzW5rH5x6SZxti1nRoXfyfna0jN
# iiC5S1IbMgucg3GJ9TQ4McfrO56WbxFJF9QSI1X7dPEPArfabnxwaGXHSnTFMvL6
# A3Mrusbxng9AcAqogWeGtQRZj22ATFAXA+GWKQu+BcZkBRmIiMNaRqx54+iINJAS
# BVv/DLFa+CPoEhf0YgLA1DUfsJ4CpcEewQ0iA3wzAgMBAAGjggHTMIIBzzAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA6BgNVHSUEMzAxBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYZKwYBBAGCN2HK9PELgrHSgxH33KNOluu6MTAdBgNVHQ4EFgQU
# a7vPo3rl7uOyvSVDXOGHQlRWLWEwHwYDVR0jBBgwFoAUpEMMf3ZapYXnPo0oDwwX
# okVpcMYwZwYDVR0fBGAwXjBcoFqgWIZWaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwQU9D
# JTIwQ0ElMjAwMy5jcmwwdAYIKwYBBQUHAQEEaDBmMGQGCCsGAQUFBzAChlhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElE
# JTIwVmVyaWZpZWQlMjBDUyUyMEFPQyUyMENBJTIwMDMuY3J0MFQGA1UdIARNMEsw
# SQYEVR0gADBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wDQYJKoZIhvcNAQEMBQADggIBAKw0
# 3tsE8NphE+cpQtl7MPVz2Lv/qNHE+9Dw0KCFiM2HvRQdRgKQnUq9xpUSvSXLUNEh
# 0MKKRUXalgTz2hNFHk2NyDb10kfq8osU6AOMuZcQEsPsF1wNlexQ/+qZMQN17euD
# d3SSXCJVX5dw7Y7o6Vx95hEaAd+at0DKiueNnKnZzNwPKbRQCQ6FOaOyv8+ueAP5
# om3MoA/dJxsdqKh6oCHx7NljNTOp4bm1E6gDjoB9kjcfm7tVi3fL/A10FDeJwio8
# COhmmx1Ue2i8yNMCyqj7R/dKRlgW/4l69dwI3jxR5kMY/S1V2gqySQTtzRJR8f3x
# JUGidbYUlFb7K51NiakJ62M8xrNL4kjdsOagr+kdxykY78iXNAtFY+R0o7m4T+6S
# wiYnP8eFQe8OqUPHy8N8ifhuKMnfMdHA0sHlE+PFvYOm6Ttc93sJhXD0iFEUjDgg
# 324CHYF6v4rnhn4+5RIH9BTPeOu1ZY9W9U7fa/zCo7dRLQdvxwTaG+rNen2Uj+Hp
# 2NnFkiB/iJD8/FCOp4WFSyIPII/O9em6W1wKxw75e2ABzXc4L4jDRPNY83rO9+q7
# YC4glbGah7Uqf8cLfT+SmOQVFTwQUy33lQ36Y0ltblETR6LEv2rWJybXyckwvh2k
# 4tHQmsuVqMT8F4ScBucZjdMeehoZZOQH8rPApYOiMIIGwDCCBKigAwIBAgITMwAM
# WodVakdjaTyqkgAAAAxahzANBgkqhkiG9w0BAQwFADBaMQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3Nv
# ZnQgSUQgVmVyaWZpZWQgQ1MgQU9DIENBIDAzMB4XDTI2MTExNzAxNDYwMFoXDTI2
# MTEyMDAxNDYwMFowgYMxCzAJBgNVBAYTAk5MMRYwFAYDVQQIEw1Ob29yZC1CcmFi
# YW50MRIwEAYDVQQHEwlTY2hpam5kZWwxIzAhBgNVBAoTGkpvaG4gQmlsbGVrZW5z
# IENvbnN1bHRhbmN5MSMwIQYDVQQDExpKb2huIEJpbGxla2VucyBDb25zdWx0YW5j
# eTCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAJMQIF4aK6YikEhfC2Mp
# D9/Apw6nEWMB4gqVnQMMWMT0dwbmXU0IJDcMuHsQzdtcxO/K4Vq0HJwVPhEQT3UW
# cRwHs78gJO4bNrWZthvoqoL/fmhX9odWFnmTNaOoE3ApPghlHXc41InewdJ/YglI
# rR303QHNgwHCzlUHNnhaTi4YCg9gAW0i+4kD5WhyqtWE5gJZ0LKL6Iw5cIwrXyYV
# RSrAcm8+EA0/7ei9idNlhuzCeE8tpjItjXLKvCXMdWPdQG/+k5Dt66y6glfEtmo2
# aQysRjc5M5x+eVMu2v6UlByINfNYXI8doZBzIcz3k8281uax+cekmcbYtZ0aF38n
# 52tIzYoguUtSGzILnINxifU0ODHH6zuelm8RSRfUEiNV+3TxDwK32m58cGhlx0p0
# xTLy+gNzK7rG8Z4PQHAKqIFnhrUEWY9tgExQFwPhlikLvgXGZAUZiIjDWkaseePo
# iDSQEgVb/wyxWvgj6BIX9GICwNQ1H7CeAqXBHsENIgN8MwIDAQABo4IB0zCCAc8w
# DAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwOgYDVR0lBDMwMQYKKwYBBAGC
# N2EBAAYIKwYBBQUHAwMGGSsGAQQBgjdhyvTxC4Kx0oMR99yjTpbrujEwHQYDVR0O
# BBYEFGu7z6N65e7jsr0lQ1zhh0JUVi1hMB8GA1UdIwQYMBaAFKRDDH92WqWF5z6N
# KA8MF6JFaXDGMGcGA1UdHwRgMF4wXKBaoFiGVmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDUyUy
# MEFPQyUyMENBJTIwMDMuY3JsMHQGCCsGAQUFBwEBBGgwZjBkBggrBgEFBQcwAoZY
# aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQl
# MjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBBT0MlMjBDQSUyMDAzLmNydDBUBgNVHSAE
# TTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMA0GCSqGSIb3DQEBDAUAA4IC
# AQCsNN7bBPDaYRPnKULZezD1c9i7/6jRxPvQ8NCghYjNh70UHUYCkJ1KvcaVEr0l
# y1DRIdDCikVF2pYE89oTRR5Njcg29dJH6vKLFOgDjLmXEBLD7BdcDZXsUP/qmTED
# de3rg3d0klwiVV+XcO2O6OlcfeYRGgHfmrdAyornjZyp2czcDym0UAkOhTmjsr/P
# rngD+aJtzKAP3ScbHaioeqAh8ezZYzUzqeG5tROoA46AfZI3H5u7VYt3y/wNdBQ3
# icIqPAjoZpsdVHtovMjTAsqo+0f3SkZYFv+JevXcCN48UeZDGP0tVdoKskkE7c0S
# UfH98SVBonW2FJRW+yudTYmpCetjPMazS+JI3bDmoK/pHccpGO/IlzQLRWPkdKO5
# uE/uksImJz/HhUHvDqlDx8vDfIn4bijJ3zHRwNLB5RPjxb2Dpuk7XPd7CYVw9IhR
# FIw4IN9uAh2Ber+K54Z+PuUSB/QUz3jrtWWPVvVO32v8wqO3US0Hb8cE2hvqzXp9
# lI/h6djZxZIgf4iQ/PxQjqeFhUsiDyCPzvXpultcCscO+XtgAc13OC+Iw0TzWPN6
# zvfqu2AuIJWxmoe1Kn/HC30/kpjkFRU8EFMt95UN+mNJbW5RE0eixL9q1icm18nJ
# ML4dpOLR0JrLlajE/BeEnAbnGY3THnoaGWTkB/KzwKWDojCCBygwggUQoAMCAQIC
# EzMAAAAYDeuRVamKAJgAAAAAABgwDQYJKoZIhvcNAQEMBQAwYzELMAkGA1UEBhMC
# VVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjE0MDIGA1UEAxMrTWlj
# cm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2lnbmluZyBQQ0EgMjAyMTAeFw0yNjAz
# MjYxODExMzJaFw0zMTAzMjYxODExMzJaMFoxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJRCBW
# ZXJpZmllZCBDUyBBT0MgQ0EgMDMwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQDIgNpgNFaiif2VWeWP5I6PnFXxJ/lB37fJR55GCvR7GLZBMkBijbiKVwgp
# BI3xM5nf484znH/qncJ+OCq6y3jgnQW+R8Zd7U+7LjlrmcskalzSQ0ghMxEpnBW8
# /HHs2V8ZJzQk6HP+SDsbvsL7LdlH/eO2l4mknhDBwr0Z/Q966TvEth5b8kCxj1vq
# iV4YNthLGRqZR9u2fK/yBMWu83p6O4uo2Edg++gEew5IL7vnnnKFqmSh/R9vPJy3
# WF1YcZewAUx8sXZNUnx3ZhVg59l2LpitPiwzE6FMqIsqaEvVe3MzuFd2a/uWDZH6
# VbDyUiRK78mIg1DQYA9zDEyyBFcNI+nxVSzglvL6u7PRuNqgcV3sf6ELxw89ysQM
# /Z4R1hRFWXRpyOWKKAKtfBHTk0UnNiPcxmLMMYs8jeUjOidfVPjTIry/UVwnwxdl
# kK85cZfBEMYZ/DBNOwdomP459Y1n8izKkbhsa+p4lw+cQVxATBFx9ggR79HhryT7
# HDmpPLvkJvBZ4wW4CW32UT2SMyDe28nIOU3m+hfHlVeKcLBQcym5VoRDjIcCVI7u
# qgGW2PNME0cfei8zCwCy6HCsssJWFS7eg/YbFhnATJcyWfMrkNuAbMfMN8Npg8cr
# S6jVVowyD0GG5zdgi+uQVcSK/638mA1xEYK3pnIoQgO09uuDBwIDAQABo4IB3DCC
# AdgwDgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBSk
# Qwx/dlqlhec+jSgPDBeiRWlwxjBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9z
# aXRvcnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwHwYDVR0jBBgwFoAU2UEpsA8PY2zvadf1zSmepEhqMOYwcAYDVR0f
# BGkwZzBloGOgYYZfaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENvZGUlMjBTaWduaW5nJTIwUENB
# JTIwMjAyMS5jcmwwfQYIKwYBBQUHAQEEcTBvMG0GCCsGAQUFBzAChmFodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElEJTIw
# VmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3J0MA0GCSqG
# SIb3DQEBDAUAA4ICAQBxxyBW+X6mhdRiSwD9PMMWcGUAnx5/QUwnNvZdFGEX+4DR
# DIr9WCh4C87wHtw+lg1D3uzK10DstPX0LFLBFAC3vWMYX4ImXwoLhoR0xlN8mUdo
# rJ3bgnpCJWuI1531Z1rCwPuUrSkBxfOIGDk3p2ECb3Ho/xHi5PRSR/OUrWuQHwXi
# aXMTuXu3IRLezwVkZpFmNwYRD57R9Nx2F/yM7tzOY0Hh0hGCaYEK38/6FrS0SXad
# XWyDUCfn5XOGACRjUCnHx+JQUG0f4SHD+iblpAI0gl+ZHnVmdXXxHTZeTa0CYCIh
# FxKP2922s0g6zLmeiV13LWUmtt/UF7TrWXpMi2/0UNniaDoH7rnPGRV5xVX8uXy4
# sZii4aswzqPM7Y7+mzcranqZ8EjZk5gjLhQ3A2sZaprlOu8CaRmyfcIiVH7zVfgA
# vm81MWXFziAf7my7QOvnyEFPGddq8MSfPtfRyw/Uq3uH6KpoaJNIfPYH6fceZSi5
# 3Rat1A9grExq3ROjhhSpTcchuBItAMNVPxoKNbUm+iR/X3XkL+9WQginjyHe+hXL
# clY8vAGXFD1p40PqMIpAYsmEJBFKW9df4//1N5oQDr/FY9IBJl/oSS979i5rtT7N
# Zz9KvYraCPRBGs0QCy+sWvgQa0coM70QJVLeVwmSxUO/0od0w9Qry7bSLrxGoDCC
# B54wggWGoAMCAQICEzMAAAAHh6M0o3uljhwAAAAAAAcwDQYJKoZIhvcNAQEMBQAw
# dzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjFI
# MEYGA1UEAxM/TWljcm9zb2Z0IElkZW50aXR5IFZlcmlmaWNhdGlvbiBSb290IENl
# cnRpZmljYXRlIEF1dGhvcml0eSAyMDIwMB4XDTIxMDQwMTIwMDUyMFoXDTM2MDQw
# MTIwMTUyMFowYzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjE0MDIGA1UEAxMrTWljcm9zb2Z0IElEIFZlcmlmaWVkIENvZGUgU2ln
# bmluZyBQQ0EgMjAyMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALLw
# wK8ZiCji3VR6TElsaQhVCbRS/3pK+MHrJSj3Zxd3KU3rlfL3qrZilYKJNqztA9OQ
# acr1AwoNcHbKBLbsQAhBnIB34zxf52bDpIO3NJlfIaTE/xrweLoQ71lzCHkD7A4A
# s1Bs076Iu+mA6cQzsYYH/Cbl1icwQ6C65rU4V9NQhNUwgrx9rGQ//h890Q8JdjLL
# w0nV+ayQ2Fbkd242o9kH82RZsH3HEyqjAB5a8+Ae2nPIPc8sZU6ZE7iRrRZywRmr
# KDp5+TcmJX9MRff241UaOBs4NmHOyke8oU1TYrkxh+YeHgfWo5tTgkoSMoayqoDp
# HOLJs+qG8Tvh8SnifW2Jj3+ii11TS8/FGngEaNAWrbyfNrC69oKpRQXY9bGH6jn9
# NEJv9weFxhTwyvx9OJLXmRGbAUXN1U9nf4lXezky6Uh/cgjkVd6CGUAf0K+Jw+GE
# /5VpIVbcNr9rNE50Sbmy/4RTCEGvOq3GhjITbCa4crCzTTHgYYjHs1NbOc6brH+e
# KpWLtr+bGecy9CrwQyx7S/BfYJ+ozst7+yZtG2wR461uckFu0t+gCwLdN0A6cFtS
# RtR8bvxVFyWwTtgMMFRuBa3vmUOTnfKLsLefRaQcVTgRnzeLzdpt32cdYKp+dhr2
# ogc+qM6K4CBI5/j4VFyC4QFeUP2YAidLtvpXRRo3AgMBAAGjggI1MIICMTAOBgNV
# HQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNlBKbAPD2Ns
# 72nX9c0pnqRIajDmMFQGA1UdIARNMEswSQYEVR0gADBBMD8GCCsGAQUFBwIBFjNo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5o
# dG0wGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAf
# BgNVHSMEGDAWgBTIftJqhSobyhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHeg
# dYZzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwSWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUl
# MjBBdXRob3JpdHklMjAyMDIwLmNybDCBwwYIKwYBBQUHAQEEgbYwgbMwgYEGCCsG
# AQUFBzAChnVodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRp
# ZmljYXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcnQwLQYIKwYBBQUHMAGGIWh0dHA6
# Ly9vbmVvY3NwLm1pY3Jvc29mdC5jb20vb2NzcDANBgkqhkiG9w0BAQwFAAOCAgEA
# fyUqnv7Uq+rdZgrbVyNMul5skONbhls5fccPlmIbzi+OwVdPQ4H55v7VOInnmezQ
# EeW4LqK0wja+fBznANbXLB0KrdMCbHQpbLvG6UA/Xv2pfpVIE1CRFfNF4XKO8XYE
# a3oW8oVH+KZHgIQRIwAbyFKQ9iyj4aOWeAzwk+f9E5StNp5T8FG7/VEURIVWArbA
# zPt9ThVN3w1fAZkF7+YU9kbq1bCR2YD+MtunSQ1Rft6XG7b4e0ejRA7mB2IoX5hN
# h3UEauY0byxNRG+fT2MCEhQl9g2i2fs6VOG19CNep7SquKaBjhWmirYyANb0RJSL
# WjinMLXNOAga10n8i9jqeprzSMU5ODmrMCJE12xS/NWShg/tuLjAsKP6SzYZ+1Ry
# 358ZTFcx0FS/mx2vSoU8s8HRvy+rnXqyUJ9HBqS0DErVLjQwK8VtsBdekBmdTbQV
# oCgPCqr+PDPB3xajYnzevs7eidBsM71PINK2BoE2UfMwxCCX3mccFgx6UsQeRSdV
# VVNSyALQe6PT12418xon2iDGE81OGCreLzDcMAZnrUAx4XQLUz6ZTl65yPUiOh3k
# 7Yww94lDf+8oG2oZmDh5O1Qe38E+M3vhKwmzIeoB1dVLlz4i3IpaDcR+iuGjH2Td
# aC1ZOmBXiCRKJLj4DT2uhJ04ji+tHD6n58vhavFIrmcxghcxMIIXLQIBATBxMFox
# CzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzAp
# BgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBBT0MgQ0EgMDMCEzMADFqH
# VWpHY2k8qpIAAAAMWocwDQYJYIZIAWUDBAIBBQCgXjAQBgorBgEEAYI3AgEMMQIw
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAvBgkqhkiG9w0BCQQxIgQgTQc+
# LEBarWOCXQTGuX03d6IsBjWdDXBpTf8JPAtFoNUwDQYJKoZIhvcNAQEBBQAEggGA
# TZa/84aNt87OMOcNR5VmfbUqvXyIUZ/3W3B34k4Vxjs4EYCcNuGnHHEpHwHBYOoT
# Y8yC+VtqAbaTbUW60dd2qe/e9vKwkuM2WGkhsPBc1TDoJF1IjqYZvT2GaZV5aL+j
# IxOIZlxSJv3viTTM+njv1Q16SGJMUiQvqOg8Y2CZ3pp6LNpw80GBnLNwq3WlgXar
# cZPFFB4KvQFdQLOq0jZ4z67ZH+D9/+JOyP/GNRd2Wx4nCD0qiNPVN2LkRGi1EhKE
# uml2+i73Qtriwh87K9znpyKviPir4M6c/s87ivgYwWs5CxB4SAENkKh5B+1weUPt
# BGSDopWGJ44HDJSjPEqUyWycxaz9a9hlycvVzEddwcEGqD6EdLFJcoTYQRFDeDQB
# qElZzNZxAqKs8ZsKkuSn+XJIkFooJMeIc5KrP44w13uYDdMpoJmBx7ae8jt6NKWz
# WTOnO+tJVo7SnhCZ/HNawe4Qw6phi49fEgv9jlG8VnKO93I7kUOX3lp80mbCT8+L
# oYIUsTCCFK0GCisGAQQBgjcDAwExghSdMIIUmQYJKoZIhvcNAQcCoIIUijCCFIYC
# AQMxDzANBglghkgBZQMEAgEFADCCAWkGCyqGSIb3DQEJEAEEoIIBWASCAVQwggFQ
# AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAEIJnS1YdTZk8nlSW6HKTl
# T1F6Xwy1VlIFOwXqk0NLsEzmAgZq80s29MgYEjIwMjYxMTE4MTM0NDMwLjIzWjAE
# gAIB9KCB6aSB5jCB4zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVk
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046N0ExQS0wNUUwLUQ5NDcxNTAzBgNV
# BAMTLE1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWUgU3RhbXBpbmcgQXV0aG9yaXR5
# oIIPKTCCB4IwggVqoAMCAQICEzMAAAAF5c8P/2YuyYcAAAAAAAUwDQYJKoZIhvcN
# AQEMBQAwdzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjFIMEYGA1UEAxM/TWljcm9zb2Z0IElkZW50aXR5IFZlcmlmaWNhdGlvbiBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDIwMB4XDTIwMTExOTIwMzIzMVoX
# DTM1MTExOTIwNDIzMVowYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGlt
# ZXN0YW1waW5nIENBIDIwMjAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCefOdSY/3gxZ8FfWO1BiKjHB7X55cz0RMFvWVGR3eRwV1wb3+yq0OXDEqhUhxq
# oNv6iYWKjkMcLhEFxvJAeNcLAyT+XdM5i2CgGPGcb95WJLiw7HzLiBKrxmDj1EQB
# /mG5eEiRBEp7dDGzxKCnTYocDOcRr9KxqHydajmEkzXHOeRGwU+7qt8Md5l4bVZr
# XAhK+WSk5CihNQsWbzT1nRliVDwunuLkX1hyIWXIArCfrKM3+RHh+Sq5RZ8aYyik
# 2r8HxT+l2hmRllBvE2Wok6IEaAJanHr24qoqFM9WLeBUSudz+qL51HwDYyIDPSQ3
# SeHtKog0ZubDk4hELQSxnfVYXdTGncaBnB60QrEuazvcob9n4yR65pUNBCF5qeA4
# QwYnilBkfnmeAjRN3LVuLr0g0FXkqfYdUmj1fFFhH8k8YBozrEaXnsSL3kdTD01X
# +4LfIWOuFzTzuoslBrBILfHNj8RfOxPgjuwNvE6YzauXi4orp4Sm6tF245DaFOSY
# bWFK5ZgG6cUY2/bUq3g3bQAqZt65KcaewEJ3ZyNEobv35Nf6xN6FrA6jF9447+NH
# vCjeWLCQZ3M8lgeCcnnhTFtyQX3XgCoc6IRXvFOcPVrr3D9RPHCMS6Ckg8wggTrt
# IVnY8yjbvGOUsAdZbeXUIQAWMs0d3cRDv09SvwVRd61evQIDAQABo4ICGzCCAhcw
# DgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRraSg6
# NS9IY0DPe9ivSek+2T3bITBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1
# AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUyH7SaoUqG8oZmAQH
# J89QEE9oqKIwgYQGA1UdHwR9MHsweaB3oHWGc2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0
# aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcmww
# gZQGCCsGAQUFBwEBBIGHMIGEMIGBBggrBgEFBQcwAoZ1aHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZl
# cmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIw
# MjAuY3J0MA0GCSqGSIb3DQEBDAUAA4ICAQBfiHbHfm21WhV150x4aPpO4dhEmSUV
# pbixNDmv6TvuIHv1xIs174bNGO/ilWMm+Jx5boAXrJxagRhHQtiFprSjMktTliL4
# sKZyt2i+SXncM23gRezzsoOiBhv14YSd1Klnlkzvgs29XNjT+c8hIfPRe9rvVCMP
# iH7zPZcw5nNjthDQ+zD563I1nUJ6y59TbXWsuyUsqw7wXZoGzZwijWT5oc6GvD3H
# DokJY401uhnj3ubBhbkR83RbfMvmzdp3he2bvIUztSOuFzRqrLfEvsPkVHYnvH1w
# tYyrt5vShiKheGpXa2AWpsod4OJyT4/y0dggWi8g/tgbhmQlZqDUf3UqUQsZaLdI
# u/XSjgoZqDjamzCPJtOLi2hBwL+KsCh0Nbwc21f5xvPSwym0Ukr4o5sCcMUcSy6T
# EP7uMV8RX0eH/4JLEpGyae6Ki8JYg5v4fsNGif1OXHJ2IWG+7zyjTDfkmQ1snFOT
# gyEX8qBpefQbF0fx6URrYiarjmBprwP6ZObwtZXJ23jK3Fg/9uqM3j0P01nzVygT
# ppBabzxPAh/hHhhls6kwo3QLJ6No803jUsZcd4JQxiYHHc+Q/wAMcPUnYKv/q2O4
# 44LO1+n6j01z5mggCSlRwD9faBIySAcA9S8h22hIAcRQqIGEjolCK9F6nK9ZyX4l
# hthsGHumaABdWzCCB58wggWHoAMCAQICEzMAAABbSrWNQTJt3HQAAAAAAFswDQYJ
# KoZIhvcNAQEMBQAwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjAwHhcNMjYwMTA4MTg1OTA1WhcNMjcwMTA3MTg1OTA1WjCB
# 4zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMk
# TWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5u
# U2hpZWxkIFRTUyBFU046N0ExQS0wNUUwLUQ5NDcxNTAzBgNVBAMTLE1pY3Jvc29m
# dCBQdWJsaWMgUlNBIFRpbWUgU3RhbXBpbmcgQXV0aG9yaXR5MIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAkFTMFtueUNd57QHQoPkbj/jvm2EXJ9y0LK4R
# JNZBe+UuLhbH+13apR16riJ156DpVaGI4d+7fAlXhNQZJG2qH0JyvUGaIEq/2K4W
# mAfIgG7lDHfxmzHCUV5dVL5mokkqddFsM1B1xhKgL/pzSFAn88fnQMFENCQ9dXDI
# WLMutEf0CWsl5SDsEp5PbfN+1Lz8o4ku8QRsc4XqlI5jdlWmtlRZtaNbBFOagdpD
# 8Ty+ta0s3IQn5vTz1VbUiStre3gZMHlZvLcIvUrbNicDEEi9p+wowXKP065cdxM8
# owOgVIx5qYb0wo4xvq6gbU+N2cOCws/oQ4xFLOssvuMQPWZsH1FJ31+G3L4dCvq9
# mCwGfqhTL5hOk1UuyTB21QzzZZgCQ/O2U63cCIvSrJXv9TeP+6re8cyM8zTDTfjQ
# zns16LSDgEJwy3R1uqhz3VWAJvf/fqwdAA2ie2fUc4XaguTzX3RBFLjeKwdWtrwf
# yx/n4aWohixiIIpfTgdmI7NlbzbqdUjp377yXJN5aamP3RRr249smFWPATeiHq07
# nXTJKqZIxIsQ3Tuncht7cToEBvbD3etbNvbr52lK2FsoXiQCmh+oGxY9fgwS0cpI
# 5+0+ZVMJDju2CGtW4eJr2Nj4eyPTWbgpbha2SZWbcvqExkQIxriyMzEBfP5tf8Am
# FZN7pNkCAwEAAaOCAcswggHHMB0GA1UdDgQWBBTv8upSVZZiFcl1fCBgrHhvwa/S
# tjAfBgNVHSMEGDAWgBRraSg6NS9IY0DPe9ivSek+2T3bITBsBgNVHR8EZTBjMGGg
# X6BdhltodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3Nv
# ZnQlMjBQdWJsaWMlMjBSU0ElMjBUaW1lc3RhbXBpbmclMjBDQSUyMDIwMjAuY3Js
# MHkGCCsGAQUFBwEBBG0wazBpBggrBgEFBQcwAoZdaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBQdWJsaWMlMjBSU0ElMjBU
# aW1lc3RhbXBpbmclMjBDQSUyMDIwMjAuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0l
# AQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMGYGA1UdIARfMF0wUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAIBgZngQwBBAIwDQYJKoZI
# hvcNAQEMBQADggIBAAAf7N35cqHg7FdgxYWa2CKVcBAZy06MJQHXD+4GIL85dwfc
# hrj9dt1SErMVtqJNsgTq9hkp3Wni7uco4uRrDKYAxXK47stKXqssq21kjIuFaNMr
# TNc7PS7jEur35tG0EQom8DqwPmcnAfUg7rPViLPK4hGhqUwKdutSLF9bFCfhMCY3
# u326T5fYVROERrd7DNHCG0b7HBoBssyTFGZHbgmd9d3VXEqj3T6btbO6i/3pS6DH
# nBl17CIgibVlZOPiUIke6nrv0tw5ru0DEkyKlVpKW1Af1+b1M4pzOV/G1a4FwtTh
# 25l+rCCwguwfs8yRxfXPBDNAPTIC0+GdjP0o0bXbltf6KKU57VLxEeq/ZtsGkylq
# jiRxS9Ajp0yApG8WabV4tuFI05CmUMxMYPW01V00aQj3qNS762uhSNYwyLjpNB8E
# AfG0NOlGEi7/zu8BVDxnpEeEXF6zPgR3klOFohBEDLoZw78mT5DMPOhnRqtEiQiw
# YnutmA5UCPH1y1/DyUf1F+NzAHfB0YFg0w1UmpClRqLZNp11/mlfNNkQciosQXnd
# KsGMh4iehCs/tTlWVeIxCzF7At0g2sATaXZNHcoGKRv5FBHKBtOnyOPbKILQ0JTA
# b4r6d2CU3lExteMVbpoprn1er5vxfMr8Mr4Am2A6keAm/xCuTrYD63A5Us6mMYID
# 1DCCA9ACAQEweDBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBUaW1lc3Rh
# bXBpbmcgQ0EgMjAyMAITMwAAAFtKtY1BMm3cdAAAAAAAWzANBglghkgBZQMEAgEF
# AKCCAS0wGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
# BCDmrSpwP0zcFbBFATLUvP5YQjXetajBNKWyZVT2uzpZtjCB3QYLKoZIhvcNAQkQ
# Ai8xgc0wgcowgccwgaAEIC8xA1VdnRvTHGUbDxf/cgTJs5u5PprlbV3rUJb5wYPv
# MHwwZaRjMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVzdGFtcGlu
# ZyBDQSAyMDIwAhMzAAAAW0q1jUEybdx0AAAAAABbMCIEIC8Ffjs3fmwb3wDMqi3o
# sg8A2dkXbhcphJgH7BRdg99RMA0GCSqGSIb3DQEBCwUABIICAIR+4sKSBdXewf6M
# QO2tP8JwKDT01kOtK7WRQTCFqshYPwKbnRDREjqKxmipN4n0olhxRQUJp52sIhEI
# 5qPJVD+DDx8EU0DGZh781HICGZ/dgthq+NVt5MbiCnqqN/HQprysKae9koPbqj57
# HDOhwJprZVciGhJGJN3wi2NHegjIUFm3Xsil5MZqa8ixgNWNUuYpipyP7Fq3WHeQ
# BvEbGR04Jl8x1EkqTUluf4qocubqXSjNJtNXyXKAli9IZmnvMWzM9WOcpRrgovbD
# kDSCIO9+tP//aYfL2pV/+8cpT+tl64esZ6t2qRRTAUioFv4BtHUHc1EqkrIjZH6u
# I1fwjcguTUE6WLUhgw8R3jHjRPWkRx84xY2BI2pEB645dF6igK7CUE849IOlwIP5
# WhxTd7KH54lY2ZXIgLxYiGJR9bXcZqFCWhyfornGVlRbjUzWfGJKd3DaDQCzObrx
# ZyX9/xg0Pe9yKr7c4uemMrmnKiSqL6R+iUenvwtZmrl43YN9bhZQPucIZOVXFRDf
# QouMONbNWBuxw6yKgru3T8iWGTUxC0Lo84YCmZkQGlZ4Z9yl1mcr5DBpCPCuWauK
# P50lusIlZPvdVGXpKy2ZMzfkdjC3BYGodXlMyuF1BWpvrLpgApMC75ARB6UPtOp2
# ELKqGH3k3t5HFJwxXVp3dbnPXEPg
# SIG # End signature block
