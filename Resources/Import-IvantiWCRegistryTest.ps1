function Import-IvantiWCRegistryTest {
    <#
    .SYNOPSIS
        Test version of Import-IvantiWCRegistry -- adds registry entries one by one to isolate API errors.
    .DESCRIPTION
        Reads a single registry set from an Ivanti WC Building Block XML, creates a WEM Group Policy
        Object with only the first entry, then adds each subsequent entry one at a time via
        Add-WEMGroupPolicyRegistryItem + Set-WEMGroupPolicyObject.

        On every step, the entry details and result are logged. Errors are reported in detail but
        processing continues so you can see which entries succeed and which fail.

        If a GPO with the specified name already exists in WEM, the function stops with a warning --
        remove it manually before re-running.
    .PARAMETER XmlFilePath
        Path to the Ivanti Workspace Control Building Block XML file.
    .PARAMETER RegistrySetName
        The name of the registry set within the XML to test. If not specified, the first enabled set is used.
    .PARAMETER GPOName
        The name to use for the test GPO in WEM. Defaults to the registry set name.
    .PARAMETER SiteId
        The ID of the WEM Configuration Set. Defaults to the active site.
    .EXAMPLE
        Import-IvantiWCRegistryTest -XmlFilePath 'C:\temp\LAB-BB.xml' -RegistrySetName 'Reg Test'
    .EXAMPLE
        Import-IvantiWCRegistryTest -XmlFilePath 'C:\temp\LAB-BB.xml' -RegistrySetName 'Reg Test' -GPOName 'Reg Test DEBUG'
    .NOTES
        Function  : Import-IvantiWCRegistryTest
        Author    : John Billekens Consultancy
        Version   : 2026.0412.2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$XmlFilePath,

        [Parameter(Mandatory = $false)]
        [string]$RegistrySetName,

        [Parameter(Mandatory = $false)]
        [string]$GPOName,

        [Parameter(Mandatory = $false)]
        [Alias("ConfigurationSiteId")]
        [int]$SiteId
    )

    if ($script:WemApiConnection.IsConnected -ne $true) {
        throw "Not connected to WEM API. Please run Connect-WEMApi first."
    }

    $Connection = Get-WemApiConnection
    if (-not $Connection) {
        throw "Failed to retrieve WEM API connection details."
    }

    $ResolvedSiteId = 0
    if ($PSBoundParameters.ContainsKey('SiteId')) {
        $ResolvedSiteId = $SiteId
    } elseif ($Connection.ActiveSiteId) {
        $ResolvedSiteId = $Connection.ActiveSiteId
        Write-Verbose "Using active Configuration Set '$($Connection.ActiveSiteName)' (ID: $ResolvedSiteId)"
    } else {
        throw "No -SiteId was provided and no active Configuration Set has been set."
    }

    # Load and filter registry sets
    $AllSets = @(Get-IvantiWCRegistry -Path $XmlFilePath -ExportFor WEM)

    $TargetSet = $null
    if ($PSBoundParameters.ContainsKey('RegistrySetName')) {
        $TargetSet = $AllSets | Where-Object { $_.Name -ieq $RegistrySetName } | Select-Object -First 1
        if (-not $TargetSet) {
            throw "No registry set named '$RegistrySetName' found in '$XmlFilePath'."
        }
    } else {
        $TargetSet = $AllSets | Where-Object { $_.Enabled -eq $true } | Select-Object -First 1
        if (-not $TargetSet) {
            throw "No enabled registry sets found in '$XmlFilePath'."
        }
        Write-Host "No -RegistrySetName specified. Using first enabled set: '$($TargetSet.Name)'" -ForegroundColor Cyan
    }

    if (-not $TargetSet.Enabled) {
        Write-Warning "Registry set '$($TargetSet.Name)' is disabled in Ivanti WC. Continuing anyway for test purposes."
    }

    $Ops = @($TargetSet.WEMParams.RegistryOperations)
    if ($Ops.Count -eq 0) {
        throw "Registry set '$($TargetSet.Name)' contains no registry operations."
    }

    $ResolvedGPOName = if ($PSBoundParameters.ContainsKey('GPOName')) { $GPOName } else { $TargetSet.WEMParams.Name }

    # Check for existing GPO
    $ExistingGPO = Get-WEMGroupPolicyObject -SiteId $ResolvedSiteId -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq $ResolvedGPOName }
    if ($ExistingGPO) {
        Write-Warning "A GPO named '$ResolvedGPOName' already exists in WEM (ID: $($ExistingGPO.id)). Remove it first and re-run."
        return
    }

    Write-Host ""
    Write-Host "=== Import-IvantiWCRegistryTest ===" -ForegroundColor Cyan
    Write-Host "Registry set : $($TargetSet.Name)" -ForegroundColor Cyan
    Write-Host "GPO name     : $ResolvedGPOName" -ForegroundColor Cyan
    Write-Host "Total entries: $($Ops.Count)" -ForegroundColor Cyan
    Write-Host ""

    # Helper scriptblock: format one entry for display
    $FormatOpEntry = {
        param([PSCustomObject]$Op, [int]$Index, [int]$Total)
        $TypePart = if ($Op.regType) { " [$($Op.regType)]" } else { "" }
        $DataPart = if ($null -ne $Op.regData -and "$($Op.regData)" -ne "") {
            $raw = "$($Op.regData)"
            if ($raw.Length -gt 80) { " = $($raw.Substring(0, 80))..." } else { " = $raw" }
        } else { "" }
        "  [{0,3}/{1}] {2} | {3} | {4}\{5}{6}{7}" -f $Index, $Total, $Op.action, $Op.scope, $Op.key, $Op.value, $TypePart, $DataPart
    }

    $WEMGPO = $null
    $SuccessCount = 0
    $FailCount = 0

    # --- Step 1: Create GPO with first entry ---
    $FirstOp = $Ops[0]
    Write-Host "STEP 1 - Creating GPO with first entry:" -ForegroundColor Yellow
    Write-Host (& $FormatOpEntry -Op $FirstOp -Index 1 -Total $Ops.Count)

    try {
        $WEMGPO = New-WEMGroupPolicyObject `
            -SiteId             $ResolvedSiteId `
            -Name               $ResolvedGPOName `
            -Description        $TargetSet.WEMParams.Description `
            -RegistryOperations @($FirstOp) `
            -PassThru -ErrorAction Stop

        if ($WEMGPO) {
            Write-Host "  OK - GPO created (ID: $($WEMGPO.id))" -ForegroundColor Green
            $SuccessCount++
        } else {
            Write-Host "  FAILED - GPO was not returned after creation." -ForegroundColor Red
            $FailCount++
            return
        }
    } catch {
        Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Entry details:" -ForegroundColor Red
        $FirstOp | Format-List | Out-String | Write-Host
        return
    }

    if ($Ops.Count -eq 1) {
        Write-Host ""
        Write-Host "Only 1 entry in this registry set. Done." -ForegroundColor Cyan
        return
    }

    # --- Step 2+: Add remaining entries one by one ---
    Write-Host ""
    Write-Host "STEP 2+ - Adding remaining entries one by one:" -ForegroundColor Yellow

    for ($i = 1; $i -lt $Ops.Count; $i++) {
        $Op = $Ops[$i]
        $EntryNum = $i + 1
        Write-Host (& $FormatOpEntry -Op $Op -Index $EntryNum -Total $Ops.Count)

        try {
            # Fetch current state with registry operations included
            $CurrentGPO = Get-WEMGroupPolicyObject -SiteId $ResolvedSiteId -IncludeRegOperations -ErrorAction Stop |
                Where-Object { $_.id -eq $WEMGPO.id }

            if (-not $CurrentGPO) {
                Write-Host "  FAILED - Could not retrieve GPO (ID: $($WEMGPO.id)) from WEM." -ForegroundColor Red
                $FailCount++
                continue
            }

            # Add entry in memory, then push to API
            if ($Op.action -eq "SetValue") {
                $UpdatedGPO = $CurrentGPO | Add-WEMGroupPolicyRegistryItem `
                    -Action    $Op.action `
                    -Scope     $Op.scope `
                    -Key       $Op.key `
                    -ValueName $Op.value `
                    -RegType   $Op.regType `
                    -RegData   $Op.regData
            } else {
                $UpdatedGPO = $CurrentGPO | Add-WEMGroupPolicyRegistryItem `
                    -Action    $Op.action `
                    -Scope     $Op.scope `
                    -Key       $Op.key `
                    -ValueName $Op.value
            }

            $UpdatedGPO | Set-WEMGroupPolicyObject -ErrorAction Stop

            Write-Host "  OK" -ForegroundColor Green
            $SuccessCount++
        } catch {
            Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Entry details:" -ForegroundColor Red
            $Op | Format-List | Out-String | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            $FailCount++
        }
    }

    # --- Summary ---
    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "  Total entries : $($Ops.Count)" -ForegroundColor Cyan
    Write-Host "  Succeeded     : $SuccessCount" -ForegroundColor Green
    $FailColor = if ($FailCount -gt 0) { 'Red' } else { 'Green' }
    Write-Host "  Failed        : $FailCount" -ForegroundColor $FailColor
    Write-Host ""
}

# SIG # Begin signature block
# MII6BgYJKoZIhvcNAQcCoII59zCCOfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDTn2nSpITER4cu
# OG6e8WohBtHzJVQtry4lhGish5XksKCCIiowggXMMIIDtKADAgECAhBUmNLR1FsZ
# lUgTecgRwIeZMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDA0MTYxODM2MTZaFw00NTA0MTYxODQ0NDBaMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALORKgeD
# Bmf9np3gx8C3pOZCBH8Ppttf+9Va10Wg+3cL8IDzpm1aTXlT2KCGhFdFIMeiVPvH
# or+Kx24186IVxC9O40qFlkkN/76Z2BT2vCcH7kKbK/ULkgbk/WkTZaiRcvKYhOuD
# PQ7k13ESSCHLDe32R0m3m/nJxxe2hE//uKya13NnSYXjhr03QNAlhtTetcJtYmrV
# qXi8LW9J+eVsFBT9FMfTZRY33stuvF4pjf1imxUs1gXmuYkyM6Nix9fWUmcIxC70
# ViueC4fM7Ke0pqrrBc0ZV6U6CwQnHJFnni1iLS8evtrAIMsEGcoz+4m+mOJyoHI1
# vnnhnINv5G0Xb5DzPQCGdTiO0OBJmrvb0/gwytVXiGhNctO/bX9x2P29Da6SZEi3
# W295JrXNm5UhhNHvDzI9e1eM80UHTHzgXhgONXaLbZ7LNnSrBfjgc10yVpRnlyUK
# xjU9lJfnwUSLgP3B+PR0GeUw9gb7IVc+BhyLaxWGJ0l7gpPKWeh1R+g/OPTHU3mg
# trTiXFHvvV84wRPmeAyVWi7FQFkozA8kwOy6CXcjmTimthzax7ogttc32H83rwjj
# O3HbbnMbfZlysOSGM1l0tRYAe1BtxoYT2v3EOYI9JACaYNq6lMAFUSw0rFCZE4e7
# swWAsk0wAly4JoNdtGNz764jlU9gKL431VulAgMBAAGjVDBSMA4GA1UdDwEB/wQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTIftJqhSobyhmYBAcnz1AQ
# T2ioojAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQwFAAOCAgEAr2rd5hnn
# LZRDGU7L6VCVZKUDkQKL4jaAOxWiUsIWGbZqWl10QzD0m/9gdAmxIR6QFm3FJI9c
# Zohj9E/MffISTEAQiwGf2qnIrvKVG8+dBetJPnSgaFvlVixlHIJ+U9pW2UYXeZJF
# xBA2CFIpF8svpvJ+1Gkkih6PsHMNzBxKq7Kq7aeRYwFkIqgyuH4yKLNncy2RtNwx
# AQv3Rwqm8ddK7VZgxCwIo3tAsLx0J1KH1r6I3TeKiW5niB31yV2g/rarOoDXGpc8
# FzYiQR6sTdWD5jw4vU8w6VSp07YEwzJ2YbuwGMUrGLPAgNW3lbBeUU0i/OxYqujY
# lLSlLu2S3ucYfCFX3VVj979tzR/SpncocMfiWzpbCNJbTsgAlrPhgzavhgplXHT2
# 6ux6anSg8Evu75SjrFDyh+3XOjCDyft9V77l4/hByuVkrrOj7FjshZrM77nq81YY
# uVxzmq/FdxeDWds3GhhyVKVB0rYjdaNDmuV3fJZ5t0GNv+zcgKCf0Xd1WF81E+Al
# GmcLfc4l+gcK5GEh2NQc5QfGNpn0ltDGFf5Ozdeui53bFv0ExpK91IjmqaOqu/dk
# ODtfzAzQNb50GQOmxapMomE2gj4d8yu8l13bS3g7LfU772Aj6PXsCyM2la+YZr9T
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbCMIIEqqADAgECAhMzAAA0pFzP
# fx1cRYbGAAAAADSkMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDMwHhcNMjYwNDExMjEzMDMwWhcNMjYwNDE0
# MjEzMDMwWjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAtv0fBtzay4ssEBwAN6LP4G44
# Ss8V/YoU/Ee1/JTMF2ClwYsGY1LZyvjtWN+WMrqAnqhbL5jzl7xI2fhxd+n9ef9I
# rdg5JoeRV2SA44BQlWoI8GirbBJ+JMMP9gAesQj6ZJAPdRPq75OSJFf2QyuEYX78
# 3k39MqnYCNf61Lj8I1+Ea20Ay8aWv5AnyMrGitbhJbw8jwIXBQU0jBNf350KxfiK
# sjP4LsMxHmzX+ERP71vWQJ4npBZjA/B3KHMjkLAfw4V4AIzz+dGTV0UDz+NdXz82
# q+3up/ABi/mSj2cTU2wzozbXE2EnItJu3BugF+sbXTD+VzJgu3TfSNJnIg8sxLWb
# MXMmfeBfyMQ2tkLiLwuEzm8HDsXOIrm1AG6fLHUKA22NUGUVztZBpMIAuYeF53vN
# BnhHzwx4pRfQYrSydT51bfkAGp+qMzaLAAJecRvA3OuSBz+3FP6is8+KKLR/kygF
# PhPZyOcsqwyl5UP/BfLsbG8hoJ2tGYbrTqT+64ZfAgMBAAGjggHVMIIB0TAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0GA1UdDgQW
# BBQMhU5TAtfEg2O0yA1upzLaiygg1jAfBgNVHSMEGDAWgBRrXqU0wwXFYkohWo6r
# c2Bi1KxjhTBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBF
# T0MlMjBDQSUyMDAzLmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUHMAKGWGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# SUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwMy5jcnQwVAYDVR0gBE0w
# SzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwFAAOCAgEA
# csq+7QdueM0Tj9U/6GSgcu8deARMqQQocv7qJKAhhxWCWtFVVTVY86jFTvgP9dJj
# utYhmZFalIsw3pZtat7DhWQlHR3qDEjRWrLROYMeOejukS8V81FAomprocUGSfrm
# BwBJvobAQnrP54XeZdq5yS+aLcKt7/kqnxd/f0FiDDhFM0JJFNW2ecW1AdB3WzkW
# 7gF7hlFJisnG5c1On4RXkJbSGurdVQFjASbmpFifsQh62By6XmdFWnVWkTWSkCHo
# zVp6QlNOCLJnCKY73q0ism+MAtVaOrnU4HfeHv5FyzzgaDZ255dFPhuR/xghYM1j
# KRZF3LF06irhlMeXmobI3fBnyOT8QsQwhgzZ7lW8CPzPlxQn31d7PI85ZIvkGCP1
# qk4D5uWJPg4MhSax6GD9HKHLOW4VRtMwNQuZoEYjf6315CtfD9/YisXI/FbaUTh4
# 8fc6ZcYksn3pgFuO/e7dXCjCxDPJtjrbL6Yq59BEww6C0K/HUdhGV5KD41w/7pUx
# IR67EsXaH1rOcKQZjsfri6L2qthoEcYOEL3xblgjAGpvXsmzDVzSVcuxdYrrwXgR
# VQFLegpXeYP5r7GPFd5XY/he2G27SDzPFFZb6X+861U45XQhqm9n6GvmYFRDP38B
# C+RcOIC6ajDe+tB6SsvqM0VX3akzMpG0k88gf04LMh8wggbCMIIEqqADAgECAhMz
# AAA0pFzPfx1cRYbGAAAAADSkMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jv
# c29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0EgMDMwHhcNMjYwNDExMjEzMDMwWhcN
# MjYwNDE0MjEzMDMwWjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJy
# YWJhbnQxEjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtl
# bnMgQ29uc3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRh
# bmN5MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAtv0fBtzay4ssEBwA
# N6LP4G44Ss8V/YoU/Ee1/JTMF2ClwYsGY1LZyvjtWN+WMrqAnqhbL5jzl7xI2fhx
# d+n9ef9Irdg5JoeRV2SA44BQlWoI8GirbBJ+JMMP9gAesQj6ZJAPdRPq75OSJFf2
# QyuEYX783k39MqnYCNf61Lj8I1+Ea20Ay8aWv5AnyMrGitbhJbw8jwIXBQU0jBNf
# 350KxfiKsjP4LsMxHmzX+ERP71vWQJ4npBZjA/B3KHMjkLAfw4V4AIzz+dGTV0UD
# z+NdXz82q+3up/ABi/mSj2cTU2wzozbXE2EnItJu3BugF+sbXTD+VzJgu3TfSNJn
# Ig8sxLWbMXMmfeBfyMQ2tkLiLwuEzm8HDsXOIrm1AG6fLHUKA22NUGUVztZBpMIA
# uYeF53vNBnhHzwx4pRfQYrSydT51bfkAGp+qMzaLAAJecRvA3OuSBz+3FP6is8+K
# KLR/kygFPhPZyOcsqwyl5UP/BfLsbG8hoJ2tGYbrTqT+64ZfAgMBAAGjggHVMIIB
# 0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEE
# AYI3YQEABggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0G
# A1UdDgQWBBQMhU5TAtfEg2O0yA1upzLaiygg1jAfBgNVHSMEGDAWgBRrXqU0wwXF
# YkohWo6rc2Bi1KxjhTBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIw
# Q1MlMjBFT0MlMjBDQSUyMDAzLmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUH
# MAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9z
# b2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwMy5jcnQwVAYD
# VR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwF
# AAOCAgEAcsq+7QdueM0Tj9U/6GSgcu8deARMqQQocv7qJKAhhxWCWtFVVTVY86jF
# TvgP9dJjutYhmZFalIsw3pZtat7DhWQlHR3qDEjRWrLROYMeOejukS8V81FAompr
# ocUGSfrmBwBJvobAQnrP54XeZdq5yS+aLcKt7/kqnxd/f0FiDDhFM0JJFNW2ecW1
# AdB3WzkW7gF7hlFJisnG5c1On4RXkJbSGurdVQFjASbmpFifsQh62By6XmdFWnVW
# kTWSkCHozVp6QlNOCLJnCKY73q0ism+MAtVaOrnU4HfeHv5FyzzgaDZ255dFPhuR
# /xghYM1jKRZF3LF06irhlMeXmobI3fBnyOT8QsQwhgzZ7lW8CPzPlxQn31d7PI85
# ZIvkGCP1qk4D5uWJPg4MhSax6GD9HKHLOW4VRtMwNQuZoEYjf6315CtfD9/YisXI
# /FbaUTh48fc6ZcYksn3pgFuO/e7dXCjCxDPJtjrbL6Yq59BEww6C0K/HUdhGV5KD
# 41w/7pUxIR67EsXaH1rOcKQZjsfri6L2qthoEcYOEL3xblgjAGpvXsmzDVzSVcux
# dYrrwXgRVQFLegpXeYP5r7GPFd5XY/he2G27SDzPFFZb6X+861U45XQhqm9n6Gvm
# YFRDP38BC+RcOIC6ajDe+tB6SsvqM0VX3akzMpG0k88gf04LMh8wggcoMIIFEKAD
# AgECAhMzAAAAFQU+bhmOkynZAAAAAAAVMA0GCSqGSIb3DQEBDAUAMGMxCzAJBgNV
# BAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMT
# K01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2RlIFNpZ25pbmcgUENBIDIwMjEwHhcN
# MjYwMzI2MTgxMTI4WhcNMzEwMzI2MTgxMTI4WjBaMQswCQYDVQQGEwJVUzEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQg
# SUQgVmVyaWZpZWQgQ1MgRU9DIENBIDAzMIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEA4PTLPQKqLw5zHj7zDnvism4QnfPpaJM2DkZUt5AVV7HnnG8hsAXL
# Hp5ZuWy7TBj44iBS8wUBfoIZVVf1NvauRnHXhBAQh00xoS9pKCKy3OFK5YjEXG7/
# ZjjLUf5e/8QJr9BceASR59XR7d+376wal5ioynxn+Q6cjv/oZ1e0xK3jLUtfYjvm
# 42f/R56YNzwpNHu2Em0UxZMfexWcEVqQuLNzXqUX0V0If1jAI+yZrGHlWaIYuExe
# cltiTKyWasB3MsyWWLQ9h5Z6OWRCZHYmXBGsRzqG5sDtOmdSfXNt6bPTxiIRmqtb
# CixAM/Q6HOay5GFhrXg67HCoQKdpCHP6GJR/SI+gZDqqoFiDRJBLQvGTRtTGpPod
# 6OuWo9IkCpncVuyGWhzuXLsqDIvirWH13iCIN7FSG0thC/JFLbAxnRKjagKv4rKk
# 4tY16i3uoiqdZ4tUj3bz1vRtNwk7GBevG/8riEEcG3aAQl3pjDSQktHaKwkWOG9l
# gAMuJ4O0gDXBIKwYGX+d+fkHy1OYRs6yoyKWzGm2rlm+RSllCpDLD3FxZF0VjuJ6
# Cj5uClpRcqajqWyfyjjVUXiJcR0EXoADgcyIUQe4K/SA0NbHNjIDoEPsVRluKKuB
# w9JnwIsIsi7JGa5GkOyaGp2IwTXEfUUtumMQFW3AbS4rRU8wiBIOWXUCAwEAAaOC
# AdwwggHYMA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4E
# FgQUa16lNMMFxWJKIVqOq3NgYtSsY4UwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYI
# KwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9S
# ZXBvc2l0b3J5Lmh0bTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTASBgNVHRMB
# Af8ECDAGAQH/AgEAMB8GA1UdIwQYMBaAFNlBKbAPD2Ns72nX9c0pnqRIajDmMHAG
# A1UdHwRpMGcwZaBjoGGGX2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUy
# MFBDQSUyMDIwMjEuY3JsMH0GCCsGAQUFBwEBBHEwbzBtBggrBgEFBQcwAoZhaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJ
# RCUyMFZlcmlmaWVkJTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDIxLmNydDAN
# BgkqhkiG9w0BAQwFAAOCAgEAXW4iPM8Fy1/IJSRIf/ENtlDAlIVgTuOmfRT4cDkd
# 5nZakVS5GDqJ/zHM1MK4w4cd1/fUjx+T0n5ZBqE75zvWVhzOWBVWKTuzWLgfpn1U
# hgBmcIhjgElpNItge75/ZxJSSZqIl8boHx+WHQbK1IE7dABTV5M5qk4JPktR8W9b
# v9BwqhB1WT5NgP+niV2G7aUTORXM9NI4rFJfQUWYEnmzg1fOWwczr3qsgt39D5xw
# sUSTYTG/MT/7Af1SO6X9q4Xkle86lEr/L5/3yDG5V3mlSJaaqKvEj/QSTIxPwqFV
# ycZ5GUETNRWu5Dfcs7b0XjocUoD4KWcf15f45MMhBVSUwXwad7E4HyHP6Zqr9nob
# WpC9gBI+/BJjj0KIcSU98Ml/j+/BgNubS6QL8490TDB3fM9fGbrlYvutDAMxqTgE
# h9S/DZa932UWZ0Dvqcsntgwr2Jh2iH3VIGCap+56McRlb/PfkWhE4dbYAg78DaRQ
# khu75eQOGpKPtn8eNPa/U1o1wuzon9SEOWScweEX/BrwYh2I7zJh6ZXnadRRkS3U
# kRVaQt/ziqWWOmryKmae/vKT/1kD/dNw3YK7wE+luMTzgcVz2uLRpLDd0rqiWohW
# B0jcngbn5/IrHro1uCGwUmxw+AT6mxd6mfu5xvXf3fxtvy8eJB/XApgX5rGXUpB5
# rpAwggeeMIIFhqADAgECAhMzAAAAB4ejNKN7pY4cAAAAAAAHMA0GCSqGSIb3DQEB
# DAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAyMDAeFw0yMTA0MDEyMDA1MjBaFw0z
# NjA0MDEyMDE1MjBaMGMxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xNDAyBgNVBAMTK01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2Rl
# IFNpZ25pbmcgUENBIDIwMjEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCy8MCvGYgo4t1UekxJbGkIVQm0Uv96SvjB6yUo92cXdylN65Xy96q2YpWCiTas
# 7QPTkGnK9QMKDXB2ygS27EAIQZyAd+M8X+dmw6SDtzSZXyGkxP8a8Hi6EO9Zcwh5
# A+wOALNQbNO+iLvpgOnEM7GGB/wm5dYnMEOguua1OFfTUITVMIK8faxkP/4fPdEP
# CXYyy8NJ1fmskNhW5HduNqPZB/NkWbB9xxMqowAeWvPgHtpzyD3PLGVOmRO4ka0W
# csEZqyg6efk3JiV/TEX39uNVGjgbODZhzspHvKFNU2K5MYfmHh4H1qObU4JKEjKG
# sqqA6RziybPqhvE74fEp4n1tiY9/ootdU0vPxRp4BGjQFq28nzawuvaCqUUF2PWx
# h+o5/TRCb/cHhcYU8Mr8fTiS15kRmwFFzdVPZ3+JV3s5MulIf3II5FXeghlAH9Cv
# icPhhP+VaSFW3Da/azROdEm5sv+EUwhBrzqtxoYyE2wmuHKws00x4GGIx7NTWznO
# m6x/niqVi7a/mxnnMvQq8EMse0vwX2CfqM7Le/smbRtsEeOtbnJBbtLfoAsC3TdA
# OnBbUkbUfG78VRclsE7YDDBUbgWt75lDk53yi7C3n0WkHFU4EZ83i83abd9nHWCq
# fnYa9qIHPqjOiuAgSOf4+FRcguEBXlD9mAInS7b6V0UaNwIDAQABo4ICNTCCAjEw
# DgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBTZQSmw
# Dw9jbO9p1/XNKZ6kSGow5jBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUyH7SaoUqG8oZmAQHJ89QEE9oqKIwgYQGA1UdHwR9MHsw
# eaB3oHWGc2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jv
# c29mdCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmlj
# YXRlJTIwQXV0aG9yaXR5JTIwMjAyMC5jcmwwgcMGCCsGAQUFBwEBBIG2MIGzMIGB
# BggrBgEFBQcwAoZ1aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0
# cy9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBD
# ZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3J0MC0GCCsGAQUFBzABhiFo
# dHRwOi8vb25lb2NzcC5taWNyb3NvZnQuY29tL29jc3AwDQYJKoZIhvcNAQEMBQAD
# ggIBAH8lKp7+1Kvq3WYK21cjTLpebJDjW4ZbOX3HD5ZiG84vjsFXT0OB+eb+1TiJ
# 55ns0BHluC6itMI2vnwc5wDW1ywdCq3TAmx0KWy7xulAP179qX6VSBNQkRXzReFy
# jvF2BGt6FvKFR/imR4CEESMAG8hSkPYso+GjlngM8JPn/ROUrTaeU/BRu/1RFESF
# VgK2wMz7fU4VTd8NXwGZBe/mFPZG6tWwkdmA/jLbp0kNUX7elxu2+HtHo0QO5gdi
# KF+YTYd1BGrmNG8sTURvn09jAhIUJfYNotn7OlThtfQjXqe0qrimgY4Vpoq2MgDW
# 9ESUi1o4pzC1zTgIGtdJ/IvY6nqa80jFOTg5qzAiRNdsUvzVkoYP7bi4wLCj+ks2
# GftUct+fGUxXMdBUv5sdr0qFPLPB0b8vq516slCfRwaktAxK1S40MCvFbbAXXpAZ
# nU20FaAoDwqq/jwzwd8Wo2J83r7O3onQbDO9TyDStgaBNlHzMMQgl95nHBYMelLE
# HkUnVVVTUsgC0Huj09duNfMaJ9ogxhPNThgq3i8w3DAGZ61AMeF0C1M+mU5eucj1
# Ijod5O2MMPeJQ3/vKBtqGZg4eTtUHt/BPjN74SsJsyHqAdXVS5c+ItyKWg3Eforh
# ox9k3WgtWTpgV4gkSiS4+A09roSdOI4vrRw+p+fL4WrxSK5nMYIXMjCCFy4CAQEw
# cTBaMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSswKQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDAzAhMz
# AAA0pFzPfx1cRYbGAAAAADSkMA0GCWCGSAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIB
# DDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IAMYKJfjFYCTJM4oPT2Mw9ctwfnXXCZZ8lL0IAtYeHB1MA0GCSqGSIb3DQEBAQUA
# BIIBgA2Ud7NPntzG8SL3FLjXGmM/ps2AgeAvGVPpI6ZyqlpKFG9RAOE5ERk86V7T
# 8WYmtJmXENe7ikTghGJU9KOZJwFbSctbBa41BGVNQ4AYqarVRce/91a2qQROI7kh
# YYa3hZt0lAGyuhEbiy7+CKQZj77WWzM0ivQLO70qlbU8jxhdktfQKNXkkhbyK0G3
# qntMXZopE61mu+vdvmdwmi6rgxypGi4645Q2Kbux1OH1pabZ52DcMTz3ShRNotKn
# OFDvBlyR+jrcQrPXYJIDXGzWRqOaWCNkGMZjUD/p68meREyMPqzST6ULOxuvySNc
# ci+GhBxZ1bj39PFzUMptx7hFy7FkOzae2rgQizilG4jLL3AA4L2kMc4jfe6cGKUf
# hkgkWYPYxBdqRXAKoNqOWTBigL3THkv50QycrWQZ5TupDPhjtu8lCt5D9KQTfSha
# P9enZuuKfs3afyDLzEXu6crHbP+SVj3rj5HBrRQ2ddW205ZYF5LdgTyHt7aqDpJs
# LlLPi6GCFLIwghSuBgorBgEEAYI3AwMBMYIUnjCCFJoGCSqGSIb3DQEHAqCCFIsw
# ghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFqBgsqhkiG9w0BCRABBKCCAVkEggFV
# MIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCC9wus0U7nXWD8V
# 6dwY8azNDIS8ferxU9A5JT8oUn0e9QIGacZoCsXWGBMyMDI2MDQxMjE1MjczNS4y
# MTlaMASAAgH0oIHppIHmMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3QjFBLTA1RTAtRDk0NzE1
# MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRo
# b3JpdHmggg8pMIIHgjCCBWqgAwIBAgITMwAAAAXlzw//Zi7JhwAAAAAABTANBgkq
# hkiG9w0BAQwFADB3MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMUgwRgYDVQQDEz9NaWNyb3NvZnQgSWRlbnRpdHkgVmVyaWZpY2F0
# aW9uIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMjAwHhcNMjAxMTE5MjAz
# MjMxWhcNMzUxMTE5MjA0MjMxWjBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJT
# QSBUaW1lc3RhbXBpbmcgQ0EgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBAJ5851Jj/eDFnwV9Y7UGIqMcHtfnlzPREwW9ZUZHd5HBXXBvf7KrQ5cM
# SqFSHGqg2/qJhYqOQxwuEQXG8kB41wsDJP5d0zmLYKAY8Zxv3lYkuLDsfMuIEqvG
# YOPURAH+Ybl4SJEESnt0MbPEoKdNihwM5xGv0rGofJ1qOYSTNcc55EbBT7uq3wx3
# mXhtVmtcCEr5ZKTkKKE1CxZvNPWdGWJUPC6e4uRfWHIhZcgCsJ+sozf5EeH5KrlF
# nxpjKKTavwfFP6XaGZGWUG8TZaiTogRoAlqcevbiqioUz1Yt4FRK53P6ovnUfANj
# IgM9JDdJ4e0qiDRm5sOTiEQtBLGd9Vhd1MadxoGcHrRCsS5rO9yhv2fjJHrmlQ0E
# IXmp4DhDBieKUGR+eZ4CNE3ctW4uvSDQVeSp9h1SaPV8UWEfyTxgGjOsRpeexIve
# R1MPTVf7gt8hY64XNPO6iyUGsEgt8c2PxF87E+CO7A28TpjNq5eLiiunhKbq0Xbj
# kNoU5JhtYUrlmAbpxRjb9tSreDdtACpm3rkpxp7AQndnI0Shu/fk1/rE3oWsDqMX
# 3jjv40e8KN5YsJBnczyWB4JyeeFMW3JBfdeAKhzohFe8U5w9WuvcP1E8cIxLoKSD
# zCCBOu0hWdjzKNu8Y5SwB1lt5dQhABYyzR3dxEO/T1K/BVF3rV69AgMBAAGjggIb
# MIICFzAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYE
# FGtpKDo1L0hjQM972K9J6T7ZPdshMFQGA1UdIARNMEswSQYEVR0gADBBMD8GCCsG
# AQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVw
# b3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAwe
# CgBTAHUAYgBDAEEwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTIftJqhSob
# yhmYBAcnz1AQT2ioojCBhAYDVR0fBH0wezB5oHegdYZzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSWRlbnRpdHklMjBWZXJp
# ZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBBdXRob3JpdHklMjAyMDIw
# LmNybDCBlAYIKwYBBQUHAQEEgYcwgYQwgYEGCCsGAQUFBzAChnVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElkZW50aXR5
# JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmljYXRlJTIwQXV0aG9yaXR5
# JTIwMjAyMC5jcnQwDQYJKoZIhvcNAQEMBQADggIBAF+Idsd+bbVaFXXnTHho+k7h
# 2ESZJRWluLE0Oa/pO+4ge/XEizXvhs0Y7+KVYyb4nHlugBesnFqBGEdC2IWmtKMy
# S1OWIviwpnK3aL5JedwzbeBF7POyg6IGG/XhhJ3UqWeWTO+Czb1c2NP5zyEh89F7
# 2u9UIw+IfvM9lzDmc2O2END7MPnrcjWdQnrLn1Ntday7JSyrDvBdmgbNnCKNZPmh
# zoa8PccOiQljjTW6GePe5sGFuRHzdFt8y+bN2neF7Zu8hTO1I64XNGqst8S+w+RU
# die8fXC1jKu3m9KGIqF4aldrYBamyh3g4nJPj/LR2CBaLyD+2BuGZCVmoNR/dSpR
# Cxlot0i79dKOChmoONqbMI8m04uLaEHAv4qwKHQ1vBzbV/nG89LDKbRSSvijmwJw
# xRxLLpMQ/u4xXxFfR4f/gksSkbJp7oqLwliDm/h+w0aJ/U5ccnYhYb7vPKNMN+SZ
# DWycU5ODIRfyoGl59BsXR/HpRGtiJquOYGmvA/pk5vC1lcnbeMrcWD/26ozePQ/T
# WfNXKBOmkFpvPE8CH+EeGGWzqTCjdAsno2jzTeNSxlx3glDGJgcdz5D/AAxw9Sdg
# q/+rY7jjgs7X6fqPTXPmaCAJKVHAP19oEjJIBwD1LyHbaEgBxFCogYSOiUIr0Xqc
# r1nJfiWG2GwYe6ZoAF1bMIIHnzCCBYegAwIBAgITMwAAAFl82nHpjV71wAAAAAAA
# WTANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBU
# aW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjAxMDgxODU5MDFaFw0yNzAxMDcxODU5
# MDFaMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo3QjFBLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHkwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCmLuf+NHhF/oU/uYxWteOm4nd3QOC5
# 12J7b5D9whsOCxgERYZ7yzEif1bbLm8w2nhZ5u8m9ikjO9Fph0Ka3Qlaqb1B+5dL
# geIzcO7qy6AEfZChyxNFZTJQ0rQ0sVASN6sLHa473Zr1dJPvf547gxIkpcyU3+w6
# MHdSt2zuG3kcmhYUfmPLcphAjqpTgH32KxtsGXVTOdfkEgUnvjxMpK/Aujp56koq
# bhfH2bwm+v4bpNGZumcLGosUhyAE9iBBr0u3OtyJvI1d2vEdCuotsosNDTZZ00qc
# Mv2X7+4sLCwcIX24wU5/lzpepj8w10EN1fkkT/cV2xijrAU8cxone2igB8N6OAIZ
# fVBlix/ZDT91VKJBOiWJI5X6blBmeoEMqg3sH8Q+FaGCJaKbeB2dMUL6mo7icfnK
# /C0fyGeeoCy5sMjM3Xufr7YwaIpa8v4EmcFRsIJL5CIKSjwUBxrEgdMt7M6+2O8B
# G+r9MmWpdV1L1p5894p02klrAhayz1cFZl8t53GOf3duVaTpIbfpuvexljW77DTo
# QDh0Wn7RPY/4YZKDOkbMiXwS54ajHAP8HGr3+aI+TXskUHRmXiynJbPXLCkt7AVM
# z4nccdoojR/Qj2g6v2yyRDl2rGKIVzJ0Yp7vn1JPNbPFTuw0Ehen35+aKkh6FfJX
# 9QMervpHUoW/AQIDAQABo4IByzCCAccwHQYDVR0OBBYEFI+W5wtfA9L5Z0kYQjoj
# gxhrlzZ2MB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7ZPdshMGwGA1UdHwRl
# MGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAy
# MC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJT
# QSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwZgYDVR0gBF8w
# XTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMAgGBmeBDAEEAjAN
# BgkqhkiG9w0BAQwFAAOCAgEARDIcwv2XI6Rv81ERO89mKeb61MVI7BOV2t7f9kRr
# xEsL25rJN2yx4UhQGo4KNl0PMaBgz97FISgiz3iAkm5Fb+lfLEqfHyfCaLOsq2sH
# 9mFYrPLXFfjju1PUuiRj0M6Zj53H80HOJ3tX6mePh4immyAxKBXXXUE9hIJJPX88
# QmPxGedmrydu3Un6yPyA5sp/VddDt4kKYNhfgvbzU65O51YKA6B2vfkN6WK9CBxp
# 0preYq4Bk+N+s6OVp1z/BcTIbMB9WosokmYlc4aK9dAvQudnD9wvPzxKDClF7LS4
# 6DztEzJHlv9Ra9fOilw+OUEYAaNMSJoLVk3c1hZ5Q/qe/ogwSLkqzXEVw0WLqv2m
# GWg4VkiNEmHTyFlYeV717lgN9WvKENEjvqD2tzZPNJNPOuMIosidSrG0p2mnn4Pb
# 7KXoIa6WPJYwsMXwlLceR0ETYACTiPCCgAiuHdNeDJNIZUTtJUFUR3oKiINvSul6
# pHN+tFtmSRlHLLZSqJJFY+igB4xsqy0T83qWH4mVCauIF8sW6bym9VydhTduvNml
# KDV6PUckStXIdH+upOvso/PJM77gu/ryVrTQ7P1KSDOh4ZtJFOuCVCezDBEHAHO5
# KX7expu2HkSvqCoKlIGFwn5s21/JyVyWZz2vAA1lbCKrLjQMQiNAmV5FC6H6qOQX
# us8xggPUMIID0AIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAWXzacemNXvXAAAAAAABZMA0GCWCGSAFl
# AwQCAQUAoIIBLTAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIPA0p88Sz2gqfS5nRUpUDGFFlutndWc42AtjXKA6h1TIMIHdBgsqhkiG
# 9w0BCRACLzGBzTCByjCBxzCBoAQgy0W6sduG6bHFxCfh44/ca3FFcO0fDssjH0gd
# mBit/rwwfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABZfNpx6Y1e9cAAAAAAAFkwIgQgghra8qTb3fMf
# 0y9fbviB+aFug42m0jeNJmJ5Yj/GtT4wDQYJKoZIhvcNAQELBQAEggIAhyb4GxOE
# o3UEhclZ+iSmjonYAiJwbSNHgpcEjOzSTVr1sKaBdLqAI/D8QaJdrZ7q4VZt6YEM
# SveBfNOPUOHkb2Ixqm33VKLBlLZSWH5UHVFTW/iv/iH1DjrXDvqp6bwQd4+TENqH
# HKaMSh2Ejt4vNxZJl+edAzvIjAlDVxYdxZNrKz0ghj2HQ425iQMPE7cH+ZvxFV+V
# xfM8z3ke4AefyOxBzDlFmjugmAvMBa7Om8KCqA8zbnJoH9NYMfDzRGm9e5rV3ZAL
# kPCz/J6+4PUZWTb3b9tapRRReudyX2F8JYlcfRTNZjijcG1rqTDW9Iqk2qtNtkVO
# iix1omzgdatUGciOAWJerbX2ITCbpS+bpHmj+nMLmSvhlTznxmKFrLGnzEGvYo+l
# 3Kv/h/w8cjjAv+wd7Nl9IW8Ml/KOzfo2r9VUemLjNLYhpK9rKWv1pQBuAAbp4rN1
# kpAYf+roEACM8Rkxazc9SblMmHyloNgR9U4N3M1siekNuPeF5qJigmuPPRORUDet
# NcVMVbTnJbZPqO0KitmdmJftENaZl8FKLD4V9vE54WO0g/04TjWyJ6TuO54O+5uX
# xdK6jW/ycv5wzkJpQuPoPuFLg+zGwGxBhwDh0wrDEVZqIrubtDDYvP8KQG5A0MBU
# HkFZ/EmO/p6J/0QzAQ8aekjL4+FzVcbOqD8=
# SIG # End signature block
