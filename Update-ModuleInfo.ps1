[CmdletBinding()]
Param(
    [Parameter()]
    [string]$ModuleName = "JBC.CitrixWEM"
)

$CmdLets = Get-ChildItem -Path "$PSScriptRoot\$ModuleName\Public\*" -Filter *.ps1 | Select-Object -ExpandProperty BaseName | Sort-Object

function Get-DateTimeVersionString {
    param (
        [datetime]$DateTime = [DateTime]::Now
    )
    $Hour = [Int]$DateTime.ToString("HH")
    if ($DateTime.Minute -eq 0) {
        $Minutes = 0
    } elseif ($DateTime.Minute -gt 0 -and $DateTime.Minute -le 15) {
        $Minutes = 15
    } elseif ($DateTime.Minute -le 30) {
        $Minutes = 30
    } elseif ($DateTime.Minute -le 45) {
        $Minutes = 45
    } else {
        $Minutes = 0
        if ($Hour -lt 23) {
            $Hour++
        } else {
            $DateTime = $DateTime.AddHours(1)
            $Hour = 0
        }
    }
    return '{0}{1:d2}{2:d2}' -f $DateTime.ToString("yyyy.Mdd."), $Hour, $Minutes
}

$NewVersion = Get-DateTimeVersionString

Update-ModuleManifest -Path "$PSScriptRoot\$ModuleName\$ModuleName.psd1" `
    -ModuleVersion $NewVersion `
    -FunctionsToExport $CmdLets

Write-Host "`r`nUpdated $ModuleName module manifest to version $NewVersion with $($CmdLets.Count) functions.`r`n" -ForegroundColor Green
