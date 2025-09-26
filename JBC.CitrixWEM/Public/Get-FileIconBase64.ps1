function Get-FileIconBase64 {
    <#
    .SYNOPSIS
        Extracts an icon from a file using an external tool, resizes it, and returns it as a Base64 string.

    .DESCRIPTION
        This function orchestrates a multi-step process to generate a Base64-encoded icon.
        First, it identifies available icons in a target file using Get-IconInfo. It then calls an
        external executable to extract the selected icon to a temporary .ico file. Finally, it uses
        .NET's System.Drawing library to load, resize, and convert the icon to a Base64-encoded
        PNG string.

    .PARAMETER FilePath
        The full path to the executable file (.exe) or library (.dll) from which to extract the icon.

    .PARAMETER Size
        The desired width and height for the final icon in pixels. The extracted icon will be resized
        to this dimension. The default is 32.

    .PARAMETER Index
        The zero-based index of the icon to extract. You can find the available indices for a file
        by running Get-IconInfo against it. The default is 0.

    .EXAMPLE
        PS C:\> $Script:IconExtractor = "C:\tools\IconExt.exe"
        PS C:\> Get-FileIconBase64 -FilePath "C:\Windows\System32\imageres.dll" -Size 64 -Index 10

        iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQU...

        This command extracts the 11th icon (index 10) from imageres.dll, resizes it to 64x64 pixels,
        and returns the resulting PNG image as a Base64 string.

    .NOTES
        Function  : Get-FileIconBase64
        Author    : John Billekens
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.5

        This function has two main dependencies:
        1. An external icon extraction executable, the path to which must be stored in the
           $Script:IconExtractor variable.
        2. The .NET System.Drawing library, which is available on Windows PowerShell 5.1 and
           Windows-based PowerShell 7+ installations.
#>
    [CmdletBinding()]
    param (
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
                return $true
            })]
        [string]$FilePath,

        [Parameter()]
        [ValidateRange(16, 256)]
        [int]$Size = 32,

        [Parameter()]
        [Alias("IconIndex")]
        [int]$Index = 0
    )

    process {
        if (-not (Test-Path -Path $Script:IconExtractor -PathType Leaf)) {
            throw "The required icon extraction executable was not found. Please set the `$Script:IconExtractor variable to a valid file path."
        }

        Add-Type -AssemblyName System.Drawing

        $ResolvedPath = Convert-Path -Path $FilePath
        if ($ResolvedPath -like "*.ico") {
            Write-Verbose "Input file is already an icon file. Loading and resizing directly: $($ResolvedPath)"
            try {
                $Bitmap = [System.Drawing.Image]::FromFile($ResolvedPath)
                $ResizedBitmap = New-Object System.Drawing.Bitmap $Size, $Size
                $Graphics = [System.Drawing.Graphics]::FromImage($ResizedBitmap)
                $Graphics.DrawImage($Bitmap, 0, 0, $Size, $Size)
                $MemoryStream = New-Object System.IO.MemoryStream
                $ResizedBitmap.Save($MemoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
                $MemoryStream.Position = 0
                [byte[]]$ImageBytes = $MemoryStream.ToArray()
                $Base64String = [Convert]::ToBase64String($ImageBytes)
                Write-Output $Base64String
            } catch {
                Write-Warning "Failed to process icon file: $($ResolvedPath). Error: $_"
            }
        } else {
            $TempPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().guid)

            #region Function-Scoped Variables for Cleanup
            $Bitmap = $null
            $ResizedBitmap = $null
            $Graphics = $null
            $MemoryStream = $null
            #endregion

            try {
                $IconInfo = Get-IconInfo -FilePath $ResolvedPath
                $SelectedIcon = $IconInfo | Where-Object { $_.Index -eq $Index }

                if (-not $SelectedIcon) {
                    throw "No icon found at index $($Index) in file: $($ResolvedPath)"
                }
                Write-Verbose "Selected icon resource: $($SelectedIcon.Index) => $($SelectedIcon.Name)"


                Write-Verbose "Created temporary directory: $($TempPath)"

                $IconMatchPattern = '{0}_{1}.ico' -f [System.IO.Path]::GetFileNameWithoutExtension($ResolvedPath), ($SelectedIcon.Name -replace "#", "")
                Write-Verbose "Looking for icon files matching pattern: $($IconMatchPattern)"

                # Call the external tool to extract the icon
                if (Test-Path -Path $Script:IconExtractor -PathType Leaf) {
                    Write-Verbose "Using external tool at path: $($Script:IconExtractor)"
                    $IconExtPath = $Script:IconExtractor
                } elseif (Test-Path -Path $Global:IconExtPath -PathType Leaf) {
                    Write-Verbose "Using external tool at path: $($Global:IconExtPath)"
                    $IconExtPath = $Global:IconExtPath
                } else {
                    throw "Could not find a valid icon extraction tool (NirSoft IconExt.exe) path."
                }

                New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
                & $IconExtPath /save "$($ResolvedPath)" "$($TempPath)" -icons
                $MaxTrialTime = (Get-Date).AddSeconds(1)
                while ((Get-Date) -lt $MaxTrialTime) {
                    $IconFile = Get-ChildItem -Path $TempPath | Where-Object { $_.Name -like $IconMatchPattern } | Select-Object -First 1
                    if ($IconFile) {
                        break
                    }
                    Start-Sleep -Milliseconds 100
                }

                Write-Verbose "Looking for icon file: $($IconFile.FullName)"
                if (-not $IconFile) {
                    throw "External tool did not create an icon file matching pattern: $($IconMatchPattern)"
                }
                Write-Verbose "Extracted icon to temporary file: $($IconFile.FullName)"

                try {
                    # Load, resize, and convert the extracted icon file
                    $Bitmap = [System.Drawing.Image]::FromFile($IconFile.FullName)
                    $ResizedBitmap = New-Object System.Drawing.Bitmap $Size, $Size
                    $Graphics = [System.Drawing.Graphics]::FromImage($ResizedBitmap)
                    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $Graphics.DrawImage($Bitmap, 0, 0, $Size, $Size)

                    $MemoryStream = New-Object System.IO.MemoryStream
                    $ResizedBitmap.Save($MemoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
                    $MemoryStream.Position = 0

                    return [System.Convert]::ToBase64String($MemoryStream.ToArray())
                } catch {
                    # Fallback: If resizing fails, return the original icon's Base64 representation
                    Write-Warning "Failed to resize icon. Returning the original icon without resizing. Error: $($_.Exception.Message)"
                    Write-Output ([System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($IconFile.FullName)))
                }

            } catch {
                throw "Failed to get file icon as Base64. Error: $($_.Exception.Message)"
            } finally {
                # Clean up all disposable objects and temporary files
                if ($Graphics) { $Graphics.Dispose() }
                if ($ResizedBitmap) { $ResizedBitmap.Dispose() }
                if ($Bitmap) { $Bitmap.Dispose() }
                if ($MemoryStream) { $MemoryStream.Dispose() }

                if (Test-Path -Path $TempPath) {
                    Remove-Item -Path $TempPath -ErrorAction SilentlyContinue -Force -Recurse
                    Write-Verbose "Cleaned up temporary directory: $($TempPath)"
                }
            }
        }
    }
}