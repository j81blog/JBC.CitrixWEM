## Example: Create Applications and assignments from existing shortcuts

```PowerShell
$Shortcuts = Get-ShortcutDetails -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\AutoCAD Map 3D 2026 - English" -ExtractIcon

$ADGroup = Get-WEMADGroup -Filter "DL_Software_AutoCAD"
$WEMAssignmentTargets = Get-WEMAssignmentTarget
$WEMAssignmentTarget = $WEMAssignmentTargets | Where-Object { $_.name -ieq $ADGroup.AccountName }

$WEMFilterRules = Get-WEMFilterRule
$WEMFilterRule = $WEMFilterRules | Where-Object name -ieq "Production-CAD"

$WEMAssignmentParams = @{
    isAutoStart   = $false
    isDesktop     = $false
    isQuickLaunch = $false
    isStartMenu   = $true
}

$WEMApplicationAssignments = @()

foreach ($Shortcut in $Shortcuts) {
    $WEMParams = @{
        Displayname      = $Shortcut.ShortcutFilename
        Name             = $Shortcut.ShortcutFilename
        Description      = $Shortcut.Description
        Commandline      = $Shortcut.TargetPath
        StartMenuPath    = "Start Menu\Programs\AutoCAD Map 3D 2026 - English"
        WorkingDirectory = $Shortcut.WorkingDirectory
        Parameter        = $Shortcut.TargetArguments
        IconStream       = $Shortcut.IconStream
        WindowStyle      = $Shortcut.WindowStyleText
        PassThru         = $true
    }
    $NewWEMApp = New-WEMApplication @WEMParams
    $WEMApplicationAssignments += New-WEMApplicationAssignment -FilterRule $WEMFilterRule -Target $WEMAssignmentTarget -Application $NewWEMApp -PassThru @WEMAssignmentParams
}
```