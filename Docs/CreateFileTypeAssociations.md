## Example: Creating File Type Associations

This document outlines the process of adding multiple File Type Associations

---

### 1. Add Associations for ImageGlass and assign them to everyone

```PowerShell
$Extensions = @("3FR",
    "ARI",
    "ARW",
    "AVIF",
    "B64",
    "BAY",
    "BMP",
    "CAP",
    "CR2",
    "CR3",
    "CRW",
    "CUR",
    "CUT",
    "DATA",
    "DCR",
    "DCS",
    "DDS",
    "DIB",
    "DNG",
    "DRF",
    "EIP",
    "EMF",
    "ERF",
    "EXIF",
    "EXR",
    "FFF",
    "GIF",
    "GPR",
    "HDR",
    "HEIC",
    "HEIF",
    "ICO",
    "IIQ",
    "JFIF",
    "JPE",
    "JPEG",
    "JPG",
    "JXL",
    "K25",
    "KDC",
    "MDC",
    "MEF",
    "MOS",
    "MRW",
    "NEF",
    "NRW",
    "OBM",
    "ORF",
    "PBM",
    "PCX",
    "PEF",
    "PGM",
    "PNG",
    "PPM",
    "PSD",
    "PTX",
    "PXN",
    "QOI",
    "R3D",
    "RAF",
    "RAW",
    "RW2",
    "RWL",
    "RWZ",
    "SR2",
    "SRF",
    "SRW",
    "SVG",
    "TGA",
    "TIF",
    "TIFF",
    "WEBP",
    "WIC",
    "WMF",
    "WPG",
    "X3F",
    "XBM",
    "XPM")

$FileExtensions = @()
$FileExtensions = $Extensions | ForEach-Object { @{
        Name            = "ImageGlass $_"
        FileExtension   = ".$_"
        TargetPath      = "C:\Program Files\ImageGlass\ImageGlass.exe"
        TargetCommand   = '"%1"'
        ProgId          = "ImageGlass.AssocFile.$_"
        SetAsDefault    = $true
        OverwriteTarget = $true
        PassThru        = $true
    }
}
$EveryoneGroup = Get-WEMAssignmentTarget | Where-Object { $_.name -like "Everyone" }
$FileExtensions | ForEach-Object {
    $params = $_
    $Fta = New-WEMFileAssociation @params
    if ($Fta) {
        Write-Host "Successfully created file association for extension $($params.FileExtension)"
    } else {
        Write-Error "Failed to create file association for extension $($params.FileExtension)."
    }
    New-WEMFileAssociationAssignment -Target $EveryoneGroup -FileAssociation $Fta
}
```