## Example: Export-FileIcon

`Export-FileIcon` is a native PowerShell function that extracts high-quality icons from EXE, DLL, or ICO files without requiring external tools. It supports multiple output formats and preserves all quality variants when exporting to ICO format.

## Basic Usage

### 1. Extract ICO with all quality variants (default)
```powershell
# Extract to specific path
Export-FileIcon -FilePath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -OutputPath "C:\temp\edge.ico"

# Extract to same directory as source file
Export-FileIcon -FilePath "C:\Windows\explorer.exe"
# Creates: C:\Windows\explorer_icon0.ico
```

### 2. Extract as PNG (single resolution)
```powershell
# High-quality 256x256 PNG
Export-FileIcon -FilePath "C:\Program Files\MyApp\app.exe" -AsPNG -Size 256 -OutputPath "C:\temp\app.png"

# Smaller size for web use
Export-FileIcon -FilePath "C:\Windows\System32\calc.exe" -AsPNG -Size 64 -OutputPath "C:\temp\calc_64.png"
```

### 3. Get Base64 string directly (for WEM API)
```powershell
# ICO format (all variants) as Base64 - RECOMMENDED for WEM
$iconBase64 = Export-FileIcon -FilePath "C:\Program Files\MyApp\app.exe" -AsBase64

# PNG format as Base64
$iconBase64Png = Export-FileIcon -FilePath "C:\Program Files\MyApp\app.exe" -AsPNG -Size 256 -AsBase64
```

### 4. Extract specific icon by index
```powershell
# First, discover available icons
$icons = Get-IconInfo -FilePath "C:\Windows\System32\shell32.dll"
$icons | Format-Table

# Extract a specific icon (e.g., folder icon at index 3)
Export-FileIcon -FilePath "C:\Windows\System32\shell32.dll" -Index 3 -OutputPath "C:\temp\folder.ico"
```

## Integration with Citrix WEM

### Scenario 1: Replace external IconExt.exe dependency

```powershell
# Direct Base64 for WEM API
$iconBase64 = Export-FileIcon -FilePath "C:\Program Files\MyApp\app.exe" -AsBase64

# Or if you need PNG at specific size
$iconBase64 = Export-FileIcon -FilePath "C:\Program Files\MyApp\app.exe" -AsPNG -Size 32 -AsBase64
```

### Scenario 2: Create WEM Application with icon
```powershell
# Extract icon and prepare for WEM
$appPath = "C:\Program Files\MyApp\MyApp.exe"
$iconBase64 = Export-FileIcon -FilePath $appPath -AsBase64

# Use with WEM API (example)
$appParams = @{
    Name = "My Application"
    Path = $appPath
    Icon = $iconBase64
    # ... other parameters
}
# New-WEMApplication @appParams
```

### Scenario 3: Batch extract icons from multiple applications
```powershell
$applications = @(
    @{ Path = "C:\Program Files\App1\app1.exe"; Name = "App1" }
    @{ Path = "C:\Program Files\App2\app2.exe"; Name = "App2" }
    @{ Path = "C:\Program Files\App3\app3.exe"; Name = "App3" }
)

$results = foreach ($app in $applications) {
    try {
        $iconBase64 = Export-FileIcon -FilePath $app.Path -AsBase64
        [PSCustomObject]@{
            Name = $app.Name
            Path = $app.Path
            IconBase64 = $iconBase64
            Status = "Success"
            IconSize = $iconBase64.Length
        }
    } catch {
        [PSCustomObject]@{
            Name = $app.Name
            Path = $app.Path
            IconBase64 = $null
            Status = "Failed: $($_.Exception.Message)"
            IconSize = 0
        }
    }
}

$results | Format-Table -AutoSize
```

## Advanced Usage

### Working with ICO files
```powershell
# Convert ICO to PNG at different sizes
$icoPath = "C:\temp\myicon.ico"
Export-FileIcon -FilePath $icoPath -AsPNG -Size 256 -OutputPath "C:\temp\myicon_256.png"
Export-FileIcon -FilePath $icoPath -AsPNG -Size 128 -OutputPath "C:\temp\myicon_128.png"
Export-FileIcon -FilePath $icoPath -AsPNG -Size 64 -OutputPath "C:\temp\myicon_64.png"

# Get Base64 from existing ICO
$base64 = Export-FileIcon -FilePath $icoPath -AsBase64
```

### Pipeline usage
```powershell
# Extract icons from all EXE files in a directory
Get-ChildItem "C:\Program Files\MyApp" -Filter "*.exe" | ForEach-Object {
    $outputPath = Join-Path "C:\temp\icons" "$($_.BaseName).ico"
    Export-FileIcon -FilePath $_.FullName -OutputPath $outputPath
}
```

### Error handling
```powershell
try {
    $iconBase64 = Export-FileIcon -FilePath $appPath -AsBase64 -ErrorAction Stop
    Write-Host "Successfully extracted icon ($($iconBase64.Length) characters)"
} catch {
    Write-Warning "Failed to extract icon: $($_.Exception.Message)"
    # Fallback to default icon
    $iconBase64 = $null
}
```

## Quality Comparison

### ICO vs PNG
| Format | Pros | Cons | Best For |
|--------|------|------|----------|
| **ICO** | - Multiple resolutions in one file<br>- Windows native format<br>- Preserves all quality variants | - Larger file size<br>- Less web-compatible | Windows applications, WEM, Desktop shortcuts |
| **PNG** | - Single resolution<br>- Smaller file size<br>- Web-compatible<br>- Transparency support | - Only one resolution<br>- May require resizing | Web apps, Documentation, Specific size requirements |

### Size recommendations
- **16x16**: Taskbar, context menus (legacy)
- **32x32**: Default desktop icons, file explorer
- **48x48**: Large icons view
- **64x64**: Extra large icons
- **128x128**: High DPI displays
- **256x256**: Highest quality, jumbo icons, modern Windows
