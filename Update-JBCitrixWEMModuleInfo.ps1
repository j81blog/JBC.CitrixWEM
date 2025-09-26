[CmdletBinding()]
Param()

$CmdLets = Get-ChildItem -Path "$PSScriptRoot\JBC.CitrixWEM\Public\*" -Filter *.ps1 | Select-Object -ExpandProperty BaseName | Sort-Object

$DateTime = Get-Date
if ($DateTime.Minute -le 15) {
    $Minutes = 15
} elseif ($DateTime.Minute -le 30) {
    $Minutes = 30
} elseif ($DateTime.Minute -le 45) {
    $Minutes = 45
} else {
    $Minutes = 0
}
$NewVersion = '{0}{1:d2}' -f (Get-Date -Format "yyyy.Mdd.H"), $Minutes

Update-ModuleManifest -Path "$PSScriptRoot\JBC.CitrixWEM\JBC.CitrixWEM.psd1" `
    -ModuleVersion $NewVersion `
    -FunctionsToExport $CmdLets

Write-Host "`r`nUpdated JBC.CitrixWEM module manifest to version $NewVersion with $($CmdLets.Count) functions.`r`n" -ForegroundColor Green
