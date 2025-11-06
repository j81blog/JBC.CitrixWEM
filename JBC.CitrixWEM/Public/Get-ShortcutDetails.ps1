function Get-ShortcutDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Single')]
        [string]$filename,

        [Parameter(Mandatory = $true, ParameterSetName = 'Multiple')]
        [string]$Path,

        [Parameter(ParameterSetName = 'Multiple')]
        [Switch]$Recurse,

        [Parameter(ParameterSetName = 'Multiple')]
        [Parameter(ParameterSetName = 'Single')]
        [String]$ExtractIcon
    )
    if ($PSCmdlet.ParameterSetName -eq 'Single') {
        $Shortcuts = @(Get-ChildItem -Path $filename)
        $Recurse = $false
    } else {
        $ShortcutPath = Join-Path -Path ([System.IO.Path]::GetFullPath($Path)) -ChildPath "\*"
        $Shortcuts = Get-ChildItem -Recurse:$Recurse -Path $ShortcutPath -Include *.lnk
    }
    $Shell = New-Object -ComObject WScript.Shell
    $WindowStyleMap = @{
        1 = "Normal"
        3 = "Maximized"
        7 = "Minimized"
    }
    foreach ($Shortcut in $Shortcuts.Fullname) {
        $Icon
        $Name = [System.IO.Path]::GetFileNameWithoutExtension($Shortcut)
        $sc = $Shell.CreateShortcut($Shortcut)
        $IconFile, $IconIndex = $sc.IconLocation -split ","
        if ([String]::IsNullOrEmpty($IconFile)) {
            $IconFile = $sc.TargetPath
        }
        if ($ExtractIcon) {
            $IconStream = Export-FileIcon -FilePath $IconFile -Size 32 -Index $IconIndex -AsBase64
        }

        Write-Output ([PSCustomObject]@{
            ShortcutFilename = $Name
            ShortcutFullName = $Shortcut
            ShortcutPath     = [System.IO.Path]::GetDirectoryName($Shortcut)
            TargetName       = [System.IO.Path]::GetFileName($sc.TargetPath)
            Description      = $sc.Description
            TargetPath       = $sc.TargetPath
            TargetArguments  = $sc.Arguments
            IconStream       = $IconStream
            IconFile         = $IconFile
            IconIndex        = $IconIndex
            WindowStyle      = $sc.WindowStyle
            WindowStyleText  = $WindowStyleMap[$sc.WindowStyle]
            Hotkey           = $sc.Hotkey
            WorkingDirectory = $sc.WorkingDirectory
        })
    }
    [Runtime.InteropServices.Marshal]::ReleaseComObject($Shell) | Out-Null
}
