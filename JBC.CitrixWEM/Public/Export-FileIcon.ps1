function Export-FileIcon {
    <#
    .SYNOPSIS
        Extracts high-quality icons from executable files, DLLs, or icon files using native PowerShell.

    .DESCRIPTION
        This function extracts icons from .exe, .dll, or .ico files without requiring external tools.
        It reads icon resources directly from the PE file to preserve all quality variants
        (multiple resolutions and color depths) that are embedded in the source file.

        By default, it exports as .ico format to preserve all variants. It can also export as PNG
        for single-resolution high-quality images, or directly return a Base64 encoded string.

    .PARAMETER FilePath
        The full path to the executable file (.exe), library (.dll), or icon file (.ico) from which
        to extract the icon.

    .PARAMETER OutputPath
        The full path where the extracted icon should be saved. If not specified and -AsBase64 is not
        used, the function will create a file in the same directory as the source file with a .ico
        extension.

    .PARAMETER Index
        The zero-based index of the icon to extract. Use Get-IconInfo to discover available icon
        indices in a file. The default is 0.

    .PARAMETER AsPNG
        Switch parameter. When specified, the icon is exported as a PNG file instead of ICO format.
        PNG export will use the highest quality variant available at the specified size with proper
        transparency preservation.

    .PARAMETER AsIco
        Switch parameter. When specified, the icon is explicitly exported as an ICO file.
        This ensures the output is in ICO format with the specified size variant.

    .PARAMETER AsBase64
        Switch parameter. When specified, the function returns a Base64-encoded string of the icon
        data instead of saving it to a file. The encoding includes the icon data in the format
        specified by -AsPNG or -AsIco parameters.

    .PARAMETER Size
        The desired width and height for the icon in pixels. Valid range is 16-256 pixels.

        If not specified when processing ICO files, the actual icon size from the file is automatically detected
        and used, preserving the original dimensions.

        If not specified when processing EXE/DLL files, defaults to 32x32.

        For ICO format, extracts the closest matching size from available variants. If the exact size is not
        available, selects the closest larger size and resizes it.
        For PNG format, always creates a PNG at exactly the specified size.

    .EXAMPLE
        PS C:\> Export-FileIcon -FilePath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -OutputPath "C:\temp\edge.ico"

        Extracts the first icon from Microsoft Edge at default size (32x32) and saves it as edge.ico.
        Output: C:\temp\edge.ico (single 32x32 variant, ~4 KB)

    .EXAMPLE
        PS C:\> Export-FileIcon -FilePath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -Size 64

        Extracts the 64x64 variant and saves with automatic filename in temp directory.
        Output: %TEMP%\msedge_exe_0_64.ico (single 64x64 variant, ~16 KB)

    .EXAMPLE
        PS C:\> Export-FileIcon -FilePath "C:\Windows\System32\shell32.dll" -Index 3 -AsPNG -OutputPath "C:\temp\folder.png" -Size 128

        Extracts the 4th icon (index 3) from shell32.dll, converts to high-quality PNG at 128x128 with transparency.
        Output: C:\temp\folder.png (~11 KB)

    .EXAMPLE
        PS C:\> Export-FileIcon -FilePath "C:\temp\myicon.ico" -AsPNG -OutputPath "C:\temp\myicon.png"

        Converts an existing ICO file to PNG, automatically detecting and preserving the original icon size.
        For example, if myicon.ico is 256x256, the output PNG will be 256x256 with transparency.

    .EXAMPLE
        PS C:\> Export-FileIcon -FilePath "C:\temp\myicon.ico" -AsPNG -Size 32 -OutputPath "C:\temp\myicon_32.png"

        Converts an existing ICO file to a 32x32 PNG with high quality and transparency preservation.
        The icon will be resized if the requested size is not available in the source ICO file.

    .EXAMPLE
        PS C:\> Export-FileIcon -FilePath "C:\temp\largeicon.ico" -AsIco -Size 64 -OutputPath "C:\temp\icon_64.ico"

        Resizes an existing ICO file from 256x256 to 64x64 with high quality rendering.
        Useful for creating smaller variants from large source icons.

    .EXAMPLE
        PS C:\> $base64Icon = Export-FileIcon -FilePath "C:\Program Files\MyApp\app.exe" -Size 32 -AsBase64

        Extracts the 32x32 icon variant and returns it as a Base64 string (ICO format).
        Perfect for Citrix WEM API usage.

    .EXAMPLE
        PS C:\> $base64Png = Export-FileIcon -FilePath "C:\Windows\explorer.exe" -AsPNG -AsBase64 -Size 256

        Extracts the icon, converts to 256x256 PNG with high quality and transparency, returns as Base64 string.

    .EXAMPLE
        PS C:\> $base64Ico = Export-FileIcon -FilePath "C:\Windows\System32\imageres.dll" -Index 5 -AsIco -AsBase64 -Size 48

        Extracts icon at index 5, creates a high-quality 48x48 ICO file and returns as Base64 string.

    .NOTES
        Function  : Export-FileIcon
        Author    : John Billekens
        Co-Author : Claude (Anthropic)
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 4.0

        This function uses Windows API calls and requires Windows PowerShell 5.1 or PowerShell 7+
        running on Windows. It does not require any external tools.

    #>
    [CmdletBinding(DefaultParameterSetName = 'ToFile')]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateScript({
                if (-not (Test-Path -Path $_ -PathType Leaf)) {
                    throw "File not found at path: $_"
                }
                $extension = [System.IO.Path]::GetExtension($_).ToLower()
                if ($extension -notin @('.exe', '.dll', '.ico', '.cpl', '.ocx', '.scr')) {
                    throw "File must be an executable file (.exe, .dll, .cpl, .ocx, .scr) or icon file (.ico). Got: $extension"
                }
                return $true
            })]
        [string]$FilePath,

        [Parameter(ParameterSetName = 'ToFile')]
        [string]$OutputPath,

        [Parameter()]
        [Alias("IconIndex")]
        [ValidateRange(0, 1000)]
        [int]$Index = 0,

        [Parameter()]
        [switch]$AsPNG,

        [Parameter()]
        [switch]$AsIco,

        [Parameter(ParameterSetName = 'ToBase64')]
        [switch]$AsBase64,

        [Parameter()]
        [ValidateRange(16, 256)]
        [int]$Size = 32
    )

    begin {
        Add-Type -AssemblyName System.Drawing
    }

    process {
        $resolvedPath = Convert-Path -Path $FilePath
        Write-Verbose "Processing file: $resolvedPath"

        try {
            # Handle .ico files directly
            if ($resolvedPath -like "*.ico") {
                Write-Verbose "Input file is already an icon file"

                # Determine the size to use
                # If user didn't explicitly specify a size, use the actual icon size
                $sourceSize = Get-IconActualSize -FilePath $resolvedPath
                $targetSize = $Size
                if ($AsPNG.IsPresent -and $PSBoundParameters.ContainsKey('Size') -eq $false) {
                    # User didn't specify size - use actual icon size
                    $targetSize = $sourceSize
                    Write-Verbose "Detected actual icon size: ${targetSize}x${targetSize}"
                    Write-Verbose "Size not specified, using actual icon size: ${targetSize}x${targetSize}"
                } else {
                    Write-Verbose "Using user-specified size: ${targetSize}x${targetSize}"
                }

                # Load the icon at the target size (this will select the closest available size from the ICO file)
                $icon = New-Object System.Drawing.Icon($resolvedPath, $targetSize, $targetSize)
                Write-Verbose "Loaded icon at size ${targetSize}x${targetSize}"

                if ($AsPNG) {
                    Write-Verbose "Converting ICO to PNG at size ${targetSize}x${targetSize} with high quality"

                    if ($AsBase64) {
                        $base64String = ConvertTo-PngFormat -Icon $icon -Size $targetSize -AsBase64
                        $icon.Dispose()
                        return $base64String
                    } else {
                        if (-not $OutputPath) {
                            $OutputPath = [System.IO.Path]::ChangeExtension($resolvedPath, ".png")
                        }
                        $pngBytes = ConvertTo-PngFormat -Icon $icon -Size $targetSize
                        [System.IO.File]::WriteAllBytes($OutputPath, $pngBytes)
                        $icon.Dispose()
                        Write-Verbose "High-quality PNG saved to: $OutputPath"
                        return $OutputPath
                    }
                } elseif ($AsIco) {
                    Write-Verbose "Converting to ICO format at size ${targetSize}x${targetSize}"

                    if ($AsBase64) {
                        $base64String = ConvertTo-IconFormat -Icon $icon -Size $targetSize -AsBase64
                        $icon.Dispose()
                        return $base64String
                    } else {
                        if (-not $OutputPath) {
                            $fileName = [System.IO.Path]::GetFileName($resolvedPath)
                            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                            $OutputPath = Join-Path ([System.IO.Path]::GetDirectoryName($resolvedPath)) "${baseName}_${targetSize}.ico"
                        }
                        $icoBytes = ConvertTo-IconFormat -Icon $icon -Size $targetSize
                        [System.IO.File]::WriteAllBytes($OutputPath, $icoBytes)
                        $icon.Dispose()
                        Write-Verbose "ICO file saved to: $OutputPath"
                        return $OutputPath
                    }
                } else {
                    # Default behavior: convert to ICO format at the specified/detected size

                    if ($AsBase64) {
                        Write-Verbose "Converting ICO to ICO format at size ${targetSize}x${targetSize} with high quality"
                        $base64String = ConvertTo-IconFormat -Icon $icon -Size $targetSize -AsBase64
                        $icon.Dispose()
                        return $base64String
                    } else {
                        if (-not $OutputPath) {
                            $fileName = [System.IO.Path]::GetFileName($resolvedPath)
                            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                            $OutputPath = Join-Path ([System.IO.Path]::GetDirectoryName($resolvedPath)) "${baseName}_${targetSize}.ico"
                        }
                        $icoBytes = ConvertTo-IconFormat -Icon $icon -Size $targetSize
                        [System.IO.File]::WriteAllBytes($OutputPath, $icoBytes)
                        $icon.Dispose()
                        Write-Verbose "ICO file saved to: $OutputPath"
                        return $OutputPath
                    }
                }
            }

            # Extract icon from EXE/DLL using private helper function
            Write-Verbose "Extracting icon at size ${Size}x${Size} from EXE/DLL"
            $iconBytes = Get-IconResourceBytes -FilePath $resolvedPath -IconIndex $Index -Size $Size

            # Generate or complete output filename
            if (-not $AsBase64) {
                $fileName = [System.IO.Path]::GetFileName($resolvedPath)
                $baseName = $fileName.Replace('.', '_')  # Replace dots with underscores
                $extension = if ($AsPNG) { "png" } elseif ($AsIco) { "ico" } else { "ico" }
                $generatedFileName = "${baseName}_${Index}_${Size}.${extension}"

                if (-not $OutputPath) {
                    # No output path specified - use temp directory
                    $OutputPath = Join-Path $env:TEMP $generatedFileName
                    Write-Verbose "No output path specified, using: $OutputPath"
                } elseif (Test-Path $OutputPath -PathType Container) {
                    # Output path is a directory - generate filename in that directory
                    $OutputPath = Join-Path $OutputPath $generatedFileName
                    Write-Verbose "Output path is a directory, using filename: $OutputPath"
                } elseif ([string]::IsNullOrEmpty([System.IO.Path]::GetFileName($OutputPath))) {
                    # Output path ends with \ but directory doesn't exist yet - create it and add filename
                    if (-not (Test-Path $OutputPath)) {
                        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
                        Write-Verbose "Created output directory: $OutputPath"
                    }
                    $OutputPath = Join-Path $OutputPath $generatedFileName
                    Write-Verbose "Generated filename in directory: $OutputPath"
                }
                # else: OutputPath is a complete file path, use as-is
            }

            if ($AsPNG) {
                Write-Verbose "Converting to PNG format at size ${Size}x${Size}"

                # Load icon from bytes
                $memStream = New-Object System.IO.MemoryStream($iconBytes, 0, $iconBytes.Length)
                $icon = New-Object System.Drawing.Icon($memStream, $Size, $Size)

                if ($AsBase64) {
                    $base64String = ConvertTo-PngFormat -Icon $icon -Size $Size -AsBase64
                    $icon.Dispose()
                    $memStream.Dispose()
                    return $base64String
                } else {
                    $pngBytes = ConvertTo-PngFormat -Icon $icon -Size $Size
                    [System.IO.File]::WriteAllBytes($OutputPath, $pngBytes)
                    $icon.Dispose()
                    $memStream.Dispose()
                    Write-Verbose "High-quality PNG saved to: $OutputPath"
                    return $OutputPath
                }
            } elseif ($AsIco) {
                Write-Verbose "Converting to ICO format at size ${Size}x${Size}"

                # Load icon from bytes and create high-quality ICO
                $memStream = New-Object System.IO.MemoryStream($iconBytes, 0, $iconBytes.Length)
                $icon = New-Object System.Drawing.Icon($memStream, $Size, $Size)

                if ($AsBase64) {
                    $base64String = ConvertTo-IconFormat -Icon $icon -Size $Size -AsBase64
                    $icon.Dispose()
                    $memStream.Dispose()
                    return $base64String
                } else {
                    $icoBytes = ConvertTo-IconFormat -Icon $icon -Size $Size
                    [System.IO.File]::WriteAllBytes($OutputPath, $icoBytes)
                    $icon.Dispose()
                    $memStream.Dispose()
                    Write-Verbose "High-quality ICO saved to: $OutputPath"
                    return $OutputPath
                }
            } else {
                # Return ICO format (single size) - default behavior
                Write-Verbose "Returning ICO format with single size variant ($($iconBytes.Length) bytes)"

                if ($AsBase64) {
                    $base64String = [Convert]::ToBase64String($iconBytes)
                    Write-Verbose "Converted to Base64: $($base64String.Length) characters"
                    return $base64String
                } else {
                    [System.IO.File]::WriteAllBytes($OutputPath, $iconBytes)
                    Write-Verbose "Icon saved to: $OutputPath"
                    return $OutputPath
                }
            }

        } catch {
            throw "Failed to export icon: $($_.Exception.Message)"
        }
    }
}

# SIG # Begin signature block
# MIImdwYJKoZIhvcNAQcCoIImaDCCJmQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCsPnpJpIeNZL3v
# lbYLRWtpkBkZ0MiscKmrNoAL3JGi9qCCIAowggYUMIID/KADAgECAhB6I67aU2mW
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
# MC8GCSqGSIb3DQEJBDEiBCBjzTjJpaow4aVt3kEH2jyiLXyFUH7si2kdG5B78vaf
# KzANBgkqhkiG9w0BAQEFAASCAYCrqcYA9m3EoGuK+vanB1S8TG/RKhMSqqJNvZiw
# Qsd3EioFgqr8yliB+lIafEqjrHiW5uiAMohSxZVUD0fjfEz9OcOf88Ro8C2o2VtO
# RHFuf80OJ/Dnsa/8VuGhBaapmtWb9suSs80fArER5QL2ISeaIdu2YajTJQ0uNqEn
# joXSwIOudRBp5PoPdsYgETiH7yQZD5HpyrQ76ZPcZCsZcg72xj2IaCmp9slJ1POm
# tXz43rUs8p94e+hTbpduQK8oiy4osmu1Fhz/8a3M2GKBagKPznG++gnjjdP3oBUt
# hNJKh1Ppxk8RNzBmLc2+N2B102yf1lO3Lc9bh+RumQ0wXAFxdQht9YPXRn+g0mX0
# w7wtH1lwcBOHCdoe8q6N6yduZb52cnWITSN8Yff+s0NCm59blneZwd/UDPEKjhO1
# ZPO4oetqXXdIRMbNGriJdnmgTmMs+EkyiUfL9uVu3sqwGELEMs9bKWZwFVnSlkhm
# TuO7sWpcbkgxr1pKUuvrhu9jt42hggMjMIIDHwYJKoZIhvcNAQkGMYIDEDCCAwwC
# AQEwajBVMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMSww
# KgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1lIFN0YW1waW5nIENBIFIzNgIRAKQp
# O24e3denNAiHrXpOtyQwDQYJYIZIAWUDBAICBQCgeTAYBgkqhkiG9w0BCQMxCwYJ
# KoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNTExMTExNDIzNTNaMD8GCSqGSIb3
# DQEJBDEyBDA5x82tNHsMxsya8ohHHSnSV3aPZdHJ4o4JmYRmnJ3BfFxZWIMNO4z7
# phKkP+K4LVcwDQYJKoZIhvcNAQEBBQAEggIATei2G6bQnTUTEDnt2mwwuCICPHos
# 2AAndP3nwynpSTcGIEGv2VZLLYnyDosnF/mPex4M2jXE5BkqEv05AveqOypDC/cg
# tCJjXUqJVtCtQVyStUjFr10kCk1FSC3xrxv8miYz38n6opNGMhgJ+X+DPGmgUv9z
# U8k2y6B8Z3J5PSSvuWa7FACAk1Vfb7TXU9Lq+//wj3z/7HTjgA8rdwloIQRT4OPk
# OEn7GzUBkv49SyaBUJW+sdFxw1WLm3x5etn6BkgyTpor2LRlSSIIYG2B7avn23zD
# OrVsun7LIf68rRyFkCRuHdWIq0WhRBZ0QCa0Bof5EEmAX8IPEc0qnTb1tTimwoFL
# p86HZZPJmWQqdjmcS7xUhzhDeXDfQ1CzAh4gFzr9EiXs9K3RMr919KET2BnvbNSg
# vAzxSZtsgUBPo8RymlfGlDMS0798EaOAsql62EfLXIeUKMn3S0HTvorURlkLSbjq
# bmIiaC7/X0nCStkQpq88n6o5aFoVEvEylZrH+3pX5jgd5Lu9dKqyPp3SglubXj5e
# x2SxTQdXMYtuhTDP5iVCpSgGTQBOpNlzZ6aVXO76MDXJPseqoGCx5kT72CMt/Fal
# gPzrzuoN5TbNny+FYzj1YCHQxzJ+nIeS2yOa9CZrLf/IET/y2/PWpEnNEwvQcaSQ
# Na+Y1PPUArbFLF0=
# SIG # End signature block
