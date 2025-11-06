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
        PNG export will use the highest quality variant available at the specified size.

    .PARAMETER AsBase64
        Switch parameter. When specified, the function returns a Base64-encoded string of the icon
        data instead of saving it to a file. The encoding includes all icon variants if ICO format
        is used, or a single PNG image if -AsPNG is specified.

    .PARAMETER Size
        The desired width and height for the icon in pixels. Valid range is 16-256 pixels. The default is 32.
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

        Extracts the 4th icon (index 3) from shell32.dll, converts to PNG at 128x128.
        Output: C:\temp\folder.png (~11 KB)

    .EXAMPLE
        PS C:\> $base64Icon = Export-FileIcon -FilePath "C:\Program Files\MyApp\app.exe" -Size 32 -AsBase64

        Extracts the 32x32 icon variant and returns it as a Base64 string (ICO format).
        Perfect for Citrix WEM API usage.

    .EXAMPLE
        PS C:\> $base64Png = Export-FileIcon -FilePath "C:\Windows\explorer.exe" -AsPNG -AsBase64 -Size 256

        Extracts the icon, converts to 256x256 PNG and returns as Base64 string.

    .NOTES
        Function  : Export-FileIcon
        Author    : John Billekens
        Co-Author : Claude (Anthropic)
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 3.0

        This function uses Windows API calls and requires Windows PowerShell 5.1 or PowerShell 7+
        running on Windows. It does not require any external tools.

        The function preserves all icon variants (different sizes and color depths) when exporting
        to ICO format, ensuring maximum quality and compatibility across different display contexts.

        This version integrates with Get-IconInfo to properly handle both integer and string resource names.
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

                if ($AsPNG) {
                    Write-Verbose "Converting ICO to PNG at size ${Size}x${Size}"
                    $icon = New-Object System.Drawing.Icon($resolvedPath, $Size, $Size)
                    $bitmap = $icon.ToBitmap()

                    if ($AsBase64) {
                        $memoryStream = New-Object System.IO.MemoryStream
                        $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
                        $base64String = [Convert]::ToBase64String($memoryStream.ToArray())
                        $memoryStream.Dispose()
                        $bitmap.Dispose()
                        $icon.Dispose()
                        return $base64String
                    } else {
                        if (-not $OutputPath) {
                            $OutputPath = [System.IO.Path]::ChangeExtension($resolvedPath, ".png")
                        }
                        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
                        $bitmap.Dispose()
                        $icon.Dispose()
                        Write-Verbose "Icon saved to: $OutputPath"
                        return $OutputPath
                    }
                } else {
                    if ($AsBase64) {
                        $fileBytes = [System.IO.File]::ReadAllBytes($resolvedPath)
                        return [Convert]::ToBase64String($fileBytes)
                    } else {
                        if (-not $OutputPath) {
                            $OutputPath = $resolvedPath
                        } elseif ($OutputPath -ne $resolvedPath) {
                            Copy-Item -Path $resolvedPath -Destination $OutputPath -Force
                        }
                        Write-Verbose "Icon file: $OutputPath"
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
                $extension = if ($AsPNG) { "png" } else { "ico" }
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

                # Create high-quality bitmap
                $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $graphics.DrawIcon($icon, 0, 0)

                if ($AsBase64) {
                    $outputStream = New-Object System.IO.MemoryStream
                    $bitmap.Save($outputStream, [System.Drawing.Imaging.ImageFormat]::Png)
                    $base64String = [Convert]::ToBase64String($outputStream.ToArray())
                    $outputStream.Dispose()
                    $graphics.Dispose()
                    $bitmap.Dispose()
                    $icon.Dispose()
                    $memStream.Dispose()
                    return $base64String
                } else {
                    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
                    $graphics.Dispose()
                    $bitmap.Dispose()
                    $icon.Dispose()
                    $memStream.Dispose()
                    Write-Verbose "High-quality PNG saved to: $OutputPath"
                    return $OutputPath
                }
            } else {
                # Return ICO format (single size)
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
