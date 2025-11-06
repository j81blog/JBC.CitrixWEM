function Get-IconResourceBytes {
    <#
    .SYNOPSIS
        Private helper function to extract icon resource bytes from executable files.

    .DESCRIPTION
        This internal function extracts a single icon variant at the specified size from an EXE or DLL file.
        It uses Get-IconInfo to enumerate available icons and then extracts the icon resource data directly
        from the PE file using Win32 API calls.

        This function intelligently selects the best matching icon variant:
        1. Exact size match (e.g., 32x32 for -Size 32)
        2. Closest larger size (e.g., 48x48 for -Size 32 if 32x32 doesn't exist)
        3. Largest available size

    .PARAMETER FilePath
        The full path to the executable or DLL file.

    .PARAMETER IconIndex
        The zero-based index of the icon to extract.

    .PARAMETER Size
        The desired icon size in pixels (width and height). Valid range: 16-256.
        The function will select the closest matching variant from available sizes.

    .NOTES
        This is a private helper function used by Export-FileIcon.
        It requires Get-IconInfo to be available and Win32.NativeMethods to be loaded.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [int]$IconIndex,

        [Parameter(Mandatory = $true)]
        [ValidateRange(16, 256)]
        [int]$Size
    )

    # Use Get-IconInfo to enumerate icons (this already handles the complexity)
    $iconInfo = Get-IconInfo -FilePath $FilePath

    if ($iconInfo.Count -eq 0) {
        throw "No icons found in file"
    }

    if ($IconIndex -ge $iconInfo.Count) {
        throw "Icon index $IconIndex is out of range. File contains $($iconInfo.Count) icon(s) (indices 0-$($iconInfo.Count - 1))"
    }

    $selectedIcon = $iconInfo[$IconIndex]
    $iconName = $selectedIcon.Name
    Write-Verbose "Selected icon at index ${IconIndex}: $iconName"

    # Now load the icon resource using the name from Get-IconInfo
    $hModule = [Win32.NativeMethods]::LoadLibraryEx(
        $FilePath,
        [IntPtr]::Zero,
        [Win32.NativeMethods]::LOAD_LIBRARY_AS_DATAFILE
    )

    if ($hModule -eq [IntPtr]::Zero) {
        throw "Failed to load library: $FilePath"
    }

    try {
        # Check if this is an integer ID or string name
        if ($selectedIcon.IsInteger) {
            # Integer resource ID
            $resourceId = $selectedIcon.ResourceId
            Write-Verbose "Loading icon resource ID: $resourceId"

            $hResInfo = [Win32.NativeMethods]::FindResource(
                $hModule,
                [IntPtr]$resourceId,
                [IntPtr][Win32.NativeMethods]::RT_GROUP_ICON
            )
        } else {
            # String resource name
            Write-Verbose "Loading icon resource by name: $iconName"

            $hResInfo = [Win32.NativeMethods]::FindResource(
                $hModule,
                $iconName,
                [IntPtr][Win32.NativeMethods]::RT_GROUP_ICON
            )
        }

        if ($hResInfo -eq [IntPtr]::Zero) {
            throw "Failed to find icon group resource: $iconName"
        }

        $hResData = [Win32.NativeMethods]::LoadResource($hModule, $hResInfo)
        $pResData = [Win32.NativeMethods]::LockResource($hResData)
        $resSize = [Win32.NativeMethods]::SizeofResource($hModule, $hResInfo)

        # Read icon group data
        $groupData = New-Object byte[] $resSize
        [System.Runtime.InteropServices.Marshal]::Copy($pResData, $groupData, 0, $resSize)

        # Parse icon group directory
        $iconCount = [BitConverter]::ToUInt16($groupData, 4)
        Write-Verbose "Icon group contains $iconCount variant(s)"

        # Parse all available icon variants and select the best match for requested size
        $variants = @()
        for ($i = 0; $i -lt $iconCount; $i++) {
            $entryOffset = 6 + ($i * 14)  # GRPICONDIRENTRY is 14 bytes

            $width = $groupData[$entryOffset]
            $height = $groupData[$entryOffset + 1]
            $colorCount = $groupData[$entryOffset + 2]
            $reserved = $groupData[$entryOffset + 3]
            $planes = [BitConverter]::ToUInt16($groupData, $entryOffset + 4)
            $bitCount = [BitConverter]::ToUInt16($groupData, $entryOffset + 6)
            $bytesInRes = [BitConverter]::ToUInt32($groupData, $entryOffset + 8)
            $iconId = [BitConverter]::ToUInt16($groupData, $entryOffset + 12)

            $displayWidth = if ($width -eq 0) { 256 } else { $width }
            $displayHeight = if ($height -eq 0) { 256 } else { $height }

            $variants += [PSCustomObject]@{
                Width      = $displayWidth
                Height     = $displayHeight
                ColorCount = $colorCount
                Reserved   = $reserved
                Planes     = $planes
                BitCount   = $bitCount
                BytesInRes = $bytesInRes
                IconId     = $iconId
                RawWidth   = $width
                RawHeight  = $height
            }

            Write-Verbose "  Available variant: ${displayWidth}x${displayHeight}, ${bitCount}-bit, $bytesInRes bytes"
        }

        # Find the best matching variant for the requested size
        # 1. Try exact match
        # 2. Try closest larger size
        # 3. Use largest available
        $selectedVariant = $variants | Where-Object { $_.Width -eq $Size } | Select-Object -First 1

        if (-not $selectedVariant) {
            # Find closest larger size
            $selectedVariant = $variants | Where-Object { $_.Width -ge $Size } | Sort-Object Width | Select-Object -First 1
        }

        if (-not $selectedVariant) {
            # Use largest available
            $selectedVariant = $variants | Sort-Object Width -Descending | Select-Object -First 1
        }

        Write-Verbose "Selected variant: $($selectedVariant.Width)x$($selectedVariant.Height), $($selectedVariant.BitCount)-bit for requested size ${Size}x${Size}"

        # Load the selected icon image data
        $hIconRes = [Win32.NativeMethods]::FindResource($hModule, [IntPtr]$selectedVariant.IconId, [IntPtr][Win32.NativeMethods]::RT_ICON)
        if ($hIconRes -eq [IntPtr]::Zero) {
            throw "Failed to find selected icon resource ID $($selectedVariant.IconId)"
        }

        $hIconData = [Win32.NativeMethods]::LoadResource($hModule, $hIconRes)
        $pIconData = [Win32.NativeMethods]::LockResource($hIconData)
        $iconSize = [Win32.NativeMethods]::SizeofResource($hModule, $hIconRes)

        $iconImageBytes = New-Object byte[] $iconSize
        [System.Runtime.InteropServices.Marshal]::Copy($pIconData, $iconImageBytes, 0, $iconSize)

        # Build single-size ICO file
        $icoStream = New-Object System.IO.MemoryStream
        $writer = New-Object System.IO.BinaryWriter($icoStream)

        # Write ICO header (1 icon)
        $writer.Write([UInt16]0)  # Reserved
        $writer.Write([UInt16]1)  # Type (1 = ICO)
        $writer.Write([UInt16]1)  # Count (1 icon)

        # Write ICONDIRENTRY
        $writer.Write($selectedVariant.RawWidth)
        $writer.Write($selectedVariant.RawHeight)
        $writer.Write($selectedVariant.ColorCount)
        $writer.Write($selectedVariant.Reserved)
        $writer.Write($selectedVariant.Planes)
        $writer.Write($selectedVariant.BitCount)
        $writer.Write([UInt32]$iconImageBytes.Length)
        $writer.Write([UInt32]22)  # Offset: 6 (header) + 16 (dir entry) = 22

        # Write icon image data
        $writer.Write($iconImageBytes)

        $writer.Flush()
        $icoBytes = $icoStream.ToArray()
        $writer.Dispose()
        $icoStream.Dispose()

        return $icoBytes

    } finally {
        [Win32.NativeMethods]::FreeLibrary($hModule) | Out-Null
    }
}
