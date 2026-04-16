function Connect-WEMApi {
    <#
.SYNOPSIS
    Authenticates to the Citrix WEM API (Cloud or On-Premises) and establishes a session.
.DESCRIPTION
    This function authenticates against the Citrix WEM API and supports three methods:
    1. Cloud with API credentials (ClientId and ClientSecret).
    2. Cloud with an existing Citrix DaaS PowerShell SDK session (checks for a cached session first).
    3. On-Premises with user credentials.

    On success, it stores the connection details for use by other functions in the module.
.PARAMETER CustomerId
    The Citrix Customer ID. Required for all Cloud authentication methods.
.PARAMETER ClientId
    The Client ID of the Secure Client for API credential authentication.
.PARAMETER ClientSecret
    The Client Secret for the specified Client ID.
.PARAMETER WEMServer
    The URI of the On-Premises WEM Infrastructure Server (e.g., http://wemserver.domain.local).
.PARAMETER Credential
    A PSCredential object for On-Premises authentication. The username should be in format 'DOMAIN\user' or 'user@domain.com'.
.PARAMETER ApiRegion
    Specifies the Citrix Cloud API region to connect to. Defaults to 'eu'.

.EXAMPLE
    PS C:\> # Cloud: Connect using an existing or new Citrix SDK session
    PS C:\> Connect-WemApi -CustomerId "mycustomerid"

    .EXAMPLE
    PS C:\> # Cloud: Connect using API credentials
    PS C:\> $SecPassword = ConvertTo-SecureString "myclientsecret" -AsPlainText -Force
    PS C:\> Connect-WemApi -CustomerId "ABCDEFG123" -ClientId "myclientid" -ClientSecret $SecPassword

.EXAMPLE
    PS C:\> # On-Premises: Connect using a credential object
    PS C:\> $Cred = Get-Credential
    PS C:\> Connect-WEMApi -WEMServer "http://wem.corp.local" -Credential $Cred

.NOTES
    Version:        1.4
    Author:         John Billekens Consultancy
    Creation Date:  2025-08-05
#>
    [CmdletBinding(DefaultParameterSetName = 'Sdk')]
    param(
        # --- Cloud Parameters ---
        [Parameter(Mandatory = $true, ParameterSetName = 'ApiCredentials')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Sdk')]
        [string]$CustomerId,

        [Parameter(Mandatory = $false, ParameterSetName = 'ApiCredentials')]
        [string]$ClientId,

        [Parameter(Mandatory = $false, ParameterSetName = 'ApiCredentials')]
        [System.Security.SecureString]$ClientSecret,

        [Parameter(Mandatory = $false, ParameterSetName = 'ApiCredentials')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Sdk')]
        [ValidateSet("eu", "us", "jp", "ap")]
        [string]$ApiRegion = "eu",

        # --- On-Premises Parameters ---
        [Parameter(Mandatory = $true, ParameterSetName = 'OnPremCredential')]
        [ValidateScript({
                if ($_ -match '^(https?)://') {
                    return $true
                } else {
                    throw "Invalid format! Please provide a valid address. E.g. https://wemserver.domain.local"
                }
            })]
        [uri]$WEMServer,

        [Parameter(Mandatory = $false, ParameterSetName = 'ApiCredentials')]
        [Parameter(Mandatory = $false, ParameterSetName = 'Sdk')]
        [Parameter(Mandatory = $false, ParameterSetName = 'OnPremCredential')]
        [switch]$PassThru,

        [switch]$IgnoreCertificateErrors,

        [Parameter(Mandatory = $true, ParameterSetName = 'OnPremCredential')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty
    )

    if ($IgnoreCertificateErrors.IsPresent) {
        if ('PSEdition' -notin $PSVersionTable.Keys -or $PSVersionTable.PSEdition -eq 'Desktop') {
            if (-not ("TrustAllCertsPolicy" -as [type])) {
                Add-Type -TypeDefinition @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
    ServicePoint srvPoint, X509Certificate certificate,
    WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
            }
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }
        $currentMaxTls = [Math]::Max([Net.ServicePointManager]::SecurityProtocol.value__, [Net.SecurityProtocolType]::Tls.value__)
        $newTlsTypes = [enum]::GetValues('Net.SecurityProtocolType') | Where-Object { $_ -gt $currentMaxTls }
        $newTlsTypes | ForEach-Object {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $_
        }
    }

    $LocalConnection = [PSCustomObject]@{
        IsOnPrem     = $false
        BaseUrl      = $null
        CustomerId   = $null
        BearerToken  = $null
        WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        CloudProfile = $null
        Expiry       = [datetime]::Now.AddSeconds(-1)
        IsConnected  = $false
    }
    $LocalConnection.WebSession.UserAgent = "CitrixWEMPoShApi/1.4)"
    $ApiRegionMap = @{
        "eu" = "api-eu.cloud.com"
        "us" = "api-us.cloud.com"
        "jp" = "api.citrixcloud.jp"
        "ap" = "api-ap.cloud.com"
    }

    try {
        # Disconnect any existing session before creating a new one
        if ($script:WemApiConnection) {
            Disconnect-WEMApi
        }
        $IsConnected = $false
        if ($PSCmdlet.ParameterSetName -eq 'OnPremCredential') {
            # --- On-Premises Logic ---
            Write-Verbose "Attempting to connect to On-Premises WEM Server: $($WEMServer)"
            $LocalConnection.IsOnPrem = $true
            $LocalConnection.BaseUrl = "$($WEMServer.Scheme)://$($WEMServer.Host)"

            $NetCredential = $Credential.GetNetworkCredential()
            $Username = $NetCredential.UserName
            $Domain = $NetCredential.Domain

            if ([string]::IsNullOrWhiteSpace($Domain)) {
                if ($Username -like "*\*") { $Domain, $Username = $Username.Split('\', 2) }
                elseif ($Username -like "*@*") { $Username, $Domain = $Username.Split('@', 2) }
                else { throw "Username must be in 'DOMAIN\user' or 'user@domain.com' format if domain is not specified in the credential." }
            }

            $AuthString = "$Domain\$Username`:$($NetCredential.Password)"
            $Bytes = [System.Text.Encoding]::ASCII.GetBytes($AuthString)
            $Base64Auth = [Convert]::ToBase64String($bytes)

            $LocalConnection.WebSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $InitialBearerToken = "basic $base64Auth"

            $LoginUri = "$($LocalConnection.BaseUrl)/services/wem/onPrem/LogIn"
            $LoginHeaders = @{ "Accept" = "application/json"; "Authorization" = $InitialBearerToken }
            $LoginResponse = Invoke-WebRequest -UseBasicParsing -Uri $LoginUri -Method POST -WebSession $LocalConnection.WebSession -Headers $LoginHeaders
            $LoginJson = $LoginResponse.Content | ConvertFrom-Json

            if (-not $LoginJson.SessionId) {
                throw "On-Premises login succeeded but did not return a Session ID."
            }

            $LocalConnection.BearerToken = "session $($LoginJson.SessionId)"
            Write-Verbose "Successfully connected to On-Premises WEM Server: $($WEMServer.Host)"
            $IsConnected = $true
        } else {
            # --- Cloud Logic ---
            $LocalConnection.BaseUrl = "https://{0}-api-webconsole.wem.cloud.com" -f $ApiRegion
            $LocalConnection.CustomerId = "$CustomerId"

            if ($PSCmdlet.ParameterSetName -eq 'Sdk') {
                # YOUR CORRECTED SDK LOGIC
                if (-not (Get-Module -ListAvailable -Name 'Citrix.PoshSdkProxy.Commands')) {
                    throw "Module 'Citrix.PoshSdkProxy.Commands' is not installed."
                }

                $ApiCredentials = $null
                try {
                    if ($CustomerId) {
                        Write-Verbose "Attempting to find existing cached Citrix SDK session for Customer ID: $CustomerId."
                        $ApiCredentials = Get-XDCredentials | Where-Object CustomerId -EQ $CustomerId -ErrorAction Stop
                    } else {
                        Write-Verbose "No Customer ID specified. Attempting to use any existing cached Citrix SDK session."
                        $ApiCredentials = Get-XDCredentials -ErrorAction Stop
                    }
                    Write-Verbose "Using existing cached Citrix SDK session for Customer ID: $CustomerId."
                } catch {
                    Write-Verbose "No existing cached session found. Attempting to authenticate via Get-XDAuthentication."
                    Clear-XDCredentials
                    Get-XDAuthentication -CustomerId $CustomerId -ErrorAction Stop
                    $ApiCredentials = Get-XDCredentials -ErrorAction Stop
                }

                if (-not $ApiCredentials.BearerToken) {
                    throw "Could not retrieve a valid Bearer Token from the Citrix SDK."
                }
                if ("$($ApiCredentials.BearerToken)" -notlike "CWSAuth bearer=*") {
                    $LocalConnection.BearerToken = "CWSAuth bearer=$($ApiCredentials.BearerToken)"
                    $LocalConnection.CustomerId = "$($ApiCredentials.CustomerId)"
                    $LocalConnection.CloudProfile = $ApiCredentials.ProfileName
                } else {
                    $LocalConnection.BearerToken = $ApiCredentials.BearerToken
                    $LocalConnection.CustomerId = "$($ApiCredentials.CustomerId)"
                    $LocalConnection.CloudProfile = $ApiCredentials.ProfileName
                }
                if (-not [string]::IsNullOrEmpty($($TokenResponse.expires_in))) {
                    $LocalConnection.Expiry = [datetime]::Now.AddSeconds($TokenResponse.expires_in)
                } else {
                    $LocalConnection.Expiry = [datetime]::Now.AddMinutes(15)
                }
                Write-Verbose "Successfully connected using Citrix SDK session for Customer ID: $($LocalConnection.CustomerId) in region $($ApiRegion.ToUpper())"
                $IsConnected = $true
            } else {
                # ApiCredentials
                Write-Verbose "Attempting to connect using API Credentials."
                if (-not $PSBoundParameters.ContainsKey('ClientId') -or -not $PSBoundParameters.ContainsKey('ClientSecret')) {
                    $CredentialPopup = Get-Credential -UserName $ClientId -Message "Enter Citrix Cloud API Client ID and Secret"
                    $ClientId = $CredentialPopup.UserName
                    $ClientSecret = $CredentialPopup.Password
                }

                $tokenUrl = "https://{0}/cctrustoauth2/root/tokens/clients" -f $ApiRegionMap[$ApiRegion.ToLower()]
                $TokenResponse = $null
                $response = $null

                $response = Invoke-WebRequest $tokenUrl -Method POST -UseBasicParsing -Body @{
                    grant_type    = "client_credentials"
                    client_id     = $ClientId
                    client_secret = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)))
                }
                if ($response.StatusCode -ne 200) {
                    throw "Failed to obtain Bearer Token from Citrix Cloud API. Status Code: $($response.StatusCode)"
                }
                try {
                    $TokenResponse = $response.Content | ConvertFrom-Json
                } catch {
                    throw "Failed to parse Bearer Token response from Citrix Cloud API."
                }

                if ($TokenResponse.access_token -notlike "CWSAuth bearer=*") {
                    $LocalConnection.BearerToken = "CWSAuth bearer=$($TokenResponse.access_token)"
                } else {
                    $LocalConnection.BearerToken = $($TokenResponse.access_token)
                }
                Write-Verbose "Successfully connected using API Credentials for Customer ID: $($LocalConnection.CustomerId) in region $($ApiRegion.ToUpper())"
                $IsConnected = $true
            }
        }

        if ($IsConnected) {
            $LocalConnection.IsConnected = $true
        }
        $script:WemApiConnection = $LocalConnection

        try {
            Set-WEMActiveDomain
        } catch {
            Write-Verbose "Could not set active WEM AD Domain: $($_.Exception.Message)"
            Write-Warning "No active WEM AD Domain has been set. Please use Set-WEMActiveDomain [-ForestName <ForestName> -DomainName <DomainName>] to set one."
        }
        if ($Script:WEMModuleConfig.Config.ShowWEMApiInfo -ne $false) {
            Write-InformationColored -Message "`r`nTo make changes to a configuration set, make sure you select one using" -ForegroundColor "White"
            Write-InformationColored -Message "Set-WEMActiveConfigurationSite -Id <Configuration Set ID>" -ForegroundColor "Cyan"
            Write-InformationColored -Message "`r`nYou can view all available configuration sets by running:" -ForegroundColor "White"
            Write-InformationColored -Message "Get-WemConfigurationSite." -ForegroundColor "Cyan"
            Write-InformationColored -Message "`r`nNOTE: To suppress this message in the future run: Set-WEMModuleConfiguration -ShowWEMApiInfo `$false`r`n" -ForegroundColor "Yellow"
        }
    } catch {
        Write-Error "Failed to connect to WEM API. Details: $($_.Exception.Message)"
        throw
    } finally {
        if (-not $IsConnected) {
            Write-Warning "Connection to WEM API was not established."
        } elseif ($PassThru.IsPresent -eq $true) {
            $output = @{
                Message     = "Successfully connected to Citrix WEM Cloud API."
                IsOnPrem    = $LocalConnection.IsOnPrem
                IsCloud     = -not $LocalConnection.IsOnPrem
                IsConnected = $IsConnected
            }
            if ($LocalConnection.IsOnPrem) {
                $output.Server = $WEMServer.Host
            } else {
                $output.ApiRegion = $ApiRegion.ToUpper()
                $output.CustomerId = $LocalConnection.CustomerId
            }

            Write-Output ([PSCustomObject]$output)
        } else {
            Write-Verbose "Silent mode enabled; suppressing connection success output."
        }
    }
}

# SIG # Begin signature block
# MII6BgYJKoZIhvcNAQcCoII59zCCOfMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCdUqpSbOfaKUCh
# Gfz7YUfQAlx9Og9zdSug5tj3+oJmRaCCIiowggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggbCMIIEqqADAgECAhMzAABWh4wS
# B8KYYL2uAAAAAFaHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNDE0MjExOTE0WhcNMjYwNDE3
# MjExOTE0WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJyYWJhbnQx
# EjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtlbnMgQ29u
# c3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRhbmN5MIIB
# ojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Y6MEBzN5XmjmQCUBmrWP3Xv
# 3kqEH4vtMaEMUsDJnl9lgweqe71Z5LQiuq0PapngjF/YRk95c8rqxtQJRMFvsnkv
# snlFeBZCsPPOzSbRUnlkyHLDQmOc9nKI/KFbqmkds70bB2z+gLQVkEZepiMgApJH
# y/eODoUZTXv58Yl4DFFdEvwW/TyC0vOI112mqqFCyN653yeBLDJ8LMvTvEvEaBih
# OXU0zNV1y52HvqIWg2h+e5WWaB2yL7locAD4dub1ZinnnRYochg5egSx41hHZDwe
# dcDyvzihq5IdqB3IeFnN5+kByQbLajYmXK+xy8G1QnIjMorDLx2+xWFBdzkOeKdF
# lPnHTAEFqlpqBFlNSU2axvcXUCJmgMVLjNW2lDNVzdpD1pgJpg+SBz7XBQ96IxVj
# TBKmLcoAlurLXPN0nzyDaAhja17p1zSFBR0idEi/T6Pr++HanksyVQLIpe0A/k8F
# zkLtGLeLOknRmsOC5gOT7nvGa8fUyWTptZJ3JohPAgMBAAGjggHVMIIB0TAMBgNV
# HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEEAYI3YQEA
# BggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0GA1UdDgQW
# BBRPZasnKEZjDvsbRxzbBI296OsPPzAfBgNVHSMEGDAWgBSa8VR3dQyHFjdGoKze
# efn0f8F46TBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIwQ1MlMjBF
# T0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUHMAKGWGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# SUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwNC5jcnQwVAYDVR0gBE0w
# SzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwFAAOCAgEA
# PH2f5SqSZRvE8G4BSeLiAJmu6YZ9MjnxZuMLlgjBRPX1/NF2oQ3U6OOK16b9Z6Cd
# Y/LCzdhDI1Dtvp36745TzKhUt3jCxONo5zFKbDlja/nR7Vly3qeKyQqop5hxzlEM
# xv3jSBBOLJUa5MppzjnYJEX7zInegb9213At3+fjYRNE2ZN5PwAdgo3jx2jHKIUE
# RVp3zMB2nwFEa6WPSL0rL5Qgu+jSXZDcZzBn8knxUTuMIHEAm3inxSsc7Kuy0Xw7
# eIPVndyZMC44RAbuMKWN2wv6FZJzecIfglGRamh/lpmgZLTHiTHmdkK/2mvAfQ6v
# cSHcngb3LYNGXkB0/BZf4PwTKL/vMLeaetQqyA+LuNXN20A6NSsE859WMNT/JjUU
# UJvF+3WUJ0mn2ufw79pLQyWAdXCHPaaDFLBlnGnN68eQ6w5tBOIxaFaPEtvCkBQ2
# c3QqHaiZS4FfLvP/XraDGEo8zALrYdWRaQxfUO+x2lo0/rn+d0BQoZPlc6c8KaIC
# RjzZDx6YqVlY1r4rWGzzWUkabduS7hsr1XM8l+OsD9gKI59ISz154ksW3NKtraSj
# z5GZFvgZB81TfXfbQmvdjXApiflx2HQ/ny3uLTiQGov+Zu5trrNTZsEJc3OGnVii
# Xx/vHOTUzGM4VgleXuALu9LifQxcgrVbZ39bw7vMGLowggbCMIIEqqADAgECAhMz
# AABWh4wSB8KYYL2uAAAAAFaHMA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jv
# c29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0EgMDQwHhcNMjYwNDE0MjExOTE0WhcN
# MjYwNDE3MjExOTE0WjCBgzELMAkGA1UEBhMCTkwxFjAUBgNVBAgTDU5vb3JkLUJy
# YWJhbnQxEjAQBgNVBAcTCVNjaGlqbmRlbDEjMCEGA1UEChMaSm9obiBCaWxsZWtl
# bnMgQ29uc3VsdGFuY3kxIzAhBgNVBAMTGkpvaG4gQmlsbGVrZW5zIENvbnN1bHRh
# bmN5MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Y6MEBzN5XmjmQCU
# BmrWP3Xv3kqEH4vtMaEMUsDJnl9lgweqe71Z5LQiuq0PapngjF/YRk95c8rqxtQJ
# RMFvsnkvsnlFeBZCsPPOzSbRUnlkyHLDQmOc9nKI/KFbqmkds70bB2z+gLQVkEZe
# piMgApJHy/eODoUZTXv58Yl4DFFdEvwW/TyC0vOI112mqqFCyN653yeBLDJ8LMvT
# vEvEaBihOXU0zNV1y52HvqIWg2h+e5WWaB2yL7locAD4dub1ZinnnRYochg5egSx
# 41hHZDwedcDyvzihq5IdqB3IeFnN5+kByQbLajYmXK+xy8G1QnIjMorDLx2+xWFB
# dzkOeKdFlPnHTAEFqlpqBFlNSU2axvcXUCJmgMVLjNW2lDNVzdpD1pgJpg+SBz7X
# BQ96IxVjTBKmLcoAlurLXPN0nzyDaAhja17p1zSFBR0idEi/T6Pr++HanksyVQLI
# pe0A/k8FzkLtGLeLOknRmsOC5gOT7nvGa8fUyWTptZJ3JohPAgMBAAGjggHVMIIB
# 0TAMBgNVHRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDA8BgNVHSUENTAzBgorBgEE
# AYI3YQEABggrBgEFBQcDAwYbKwYBBAGCN2G789NTgYr4ukmC0/31KIOytcN0MB0G
# A1UdDgQWBBRPZasnKEZjDvsbRxzbBI296OsPPzAfBgNVHSMEGDAWgBSa8VR3dQyH
# FjdGoKzeefn0f8F46TBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlmaWVkJTIw
# Q1MlMjBFT0MlMjBDQSUyMDA0LmNybDB0BggrBgEFBQcBAQRoMGYwZAYIKwYBBQUH
# MAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9z
# b2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAwNC5jcnQwVAYD
# VR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTANBgkqhkiG9w0BAQwF
# AAOCAgEAPH2f5SqSZRvE8G4BSeLiAJmu6YZ9MjnxZuMLlgjBRPX1/NF2oQ3U6OOK
# 16b9Z6CdY/LCzdhDI1Dtvp36745TzKhUt3jCxONo5zFKbDlja/nR7Vly3qeKyQqo
# p5hxzlEMxv3jSBBOLJUa5MppzjnYJEX7zInegb9213At3+fjYRNE2ZN5PwAdgo3j
# x2jHKIUERVp3zMB2nwFEa6WPSL0rL5Qgu+jSXZDcZzBn8knxUTuMIHEAm3inxSsc
# 7Kuy0Xw7eIPVndyZMC44RAbuMKWN2wv6FZJzecIfglGRamh/lpmgZLTHiTHmdkK/
# 2mvAfQ6vcSHcngb3LYNGXkB0/BZf4PwTKL/vMLeaetQqyA+LuNXN20A6NSsE859W
# MNT/JjUUUJvF+3WUJ0mn2ufw79pLQyWAdXCHPaaDFLBlnGnN68eQ6w5tBOIxaFaP
# EtvCkBQ2c3QqHaiZS4FfLvP/XraDGEo8zALrYdWRaQxfUO+x2lo0/rn+d0BQoZPl
# c6c8KaICRjzZDx6YqVlY1r4rWGzzWUkabduS7hsr1XM8l+OsD9gKI59ISz154ksW
# 3NKtraSjz5GZFvgZB81TfXfbQmvdjXApiflx2HQ/ny3uLTiQGov+Zu5trrNTZsEJ
# c3OGnViiXx/vHOTUzGM4VgleXuALu9LifQxcgrVbZ39bw7vMGLowggcoMIIFEKAD
# AgECAhMzAAAAFydFCQuLh6/GAAAAAAAXMA0GCSqGSIb3DQEBDAUAMGMxCzAJBgNV
# BAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xNDAyBgNVBAMT
# K01pY3Jvc29mdCBJRCBWZXJpZmllZCBDb2RlIFNpZ25pbmcgUENBIDIwMjEwHhcN
# MjYwMzI2MTgxMTMxWhcNMzEwMzI2MTgxMTMxWjBaMQswCQYDVQQGEwJVUzEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSswKQYDVQQDEyJNaWNyb3NvZnQg
# SUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEAgsdk/gMPZioBlcyfk6tDzJ+PRt4rSLGKW8ewpS0kRxXtURC3T3Gd
# bCKljobEn8ussqhGqQpRh/SXvRVwNXEIGb76UG5IPkCJ1S6/9BD61QQsKzPepW0S
# Nj8TXgsFxvS7MltoRuikIIp7Q5jQgaOM6QyK9++6ZVXUpYmZulAe6x8JrwZ0dNkE
# +rZ66lqtoocwepUSVUxM7odDmn8yDHjJ2DNPsfr3uRDix3X4qvh14jH/SW+2Cx7W
# IMhyIiQO201i6hUixmk4e2ZW8W7C1wPdTjq6BKb+zo8xbrt7ZKQvRX5QOA6dhLqu
# Pqj5sVKnxqfk19IC0SafTSTs8yC43Ew965BRRW8VL9ccoOmr4rxQy7aCgYTNk3dd
# /LphNaTTmnGp7kmLTxyHkB5geoWhYuuGrywS8E0wJv0W4rfOtHBV0e9sKvuUIeIU
# pnsx6ilxEVj6VQXvgD6yeCKnPmj3jJiJKAlmUDtth5yzRVBUl44sMiG4L5R/yyAC
# RKk2n088Q2YCoZS1O86+oMLKt1jaXGECOjbsVp8Id1VQw8he6J0KirOS5e25XlTd
# GPFb6oBOOaacgW78Kjf0bp+XzAgkc92mDGNJGYSjvdnj+7eMx6meW0DAIGdLRNj8
# /429MIspFBfz3KDqqpN71S4kQ2LLer3dxhDDczKVFL0HLwRuOvgjiG8CAwEAAaOC
# AdwwggHYMA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4E
# FgQUmvFUd3UMhxY3RqCs3nn59H/BeOkwVAYDVR0gBE0wSzBJBgRVHSAAMEEwPwYI
# KwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9S
# ZXBvc2l0b3J5Lmh0bTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTASBgNVHRMB
# Af8ECDAGAQH/AgEAMB8GA1UdIwQYMBaAFNlBKbAPD2Ns72nX9c0pnqRIajDmMHAG
# A1UdHwRpMGcwZaBjoGGGX2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDb2RlJTIwU2lnbmluZyUy
# MFBDQSUyMDIwMjEuY3JsMH0GCCsGAQUFBwEBBHEwbzBtBggrBgEFBQcwAoZhaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJ
# RCUyMFZlcmlmaWVkJTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDIxLmNydDAN
# BgkqhkiG9w0BAQwFAAOCAgEAkHVaGf1NJt/JdoimmRZbMWr6baaDi8mkdWvWStk0
# hdZDpxSYTA7HuipAoLL3qIhI101XOl7fOiCh5++jZOamQdAV79ojEUNoIgCZmL2X
# JrLaGanwdjNynecJyYVCTrRf2+h7KknpWOp4axdOs6K9ZQ5g0IsQWXCwfc0dfkSk
# LKNY3pDcWLlJPh2jd5NUue6pNDv/2G5MFNJhCwltODebyAjGceU+XOzav+7i721Y
# QnQ+39m2aQOFO7zpAdaKAeAGhEd6Y6CdDGneSxcoujWvafWbv4ay3jo1ORSLUuWM
# bKr5X18QE4Sde+gppGLLSkZsrUh2eyYSkX1envWX7ZPzg2/wiuKRlQFarDn+N9+2
# 0BqzhxwkNyLzfYJp1Lg4fCXb24XqFjx8SDdRgebFImOfOLVze8XQ/CwkrEaib0PH
# u2t4GVk4FYroEbNUFqvjdBvTY3uiR5TdQoyXoYHvh+TxpLSY2vo7hhK9D/rpEpHC
# +qmmcRUE4d0gyO9Zb1vvt25fxM3ekjvDfVHcPq3qMr0Rwsk4krKZWUEgU1SXT5qN
# 6gqRrshxbT6OQgZ9/xT04qiXdzPQR6KindBvSpoOnxnALxcJyzVwNpKL+9u8EZYy
# 98qX6i+4gE/2J6cbpekcB0ZXDn/XQxoNUUb6/djT/wllVyG+vIHkdq71PzbH5rYx
# dcAwggeeMIIFhqADAgECAhMzAAAAB4ejNKN7pY4cAAAAAAAHMA0GCSqGSIb3DQEB
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
# MSswKQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDA0AhMz
# AABWh4wSB8KYYL2uAAAAAFaHMA0GCWCGSAFlAwQCAQUAoF4wEAYKKwYBBAGCNwIB
# DDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# INcIXfxMxfhz0JkzfJwRnKucA680oED74YjQxxLnDeT5MA0GCSqGSIb3DQEBAQUA
# BIIBgJhRKKCoIkJgG0wUVyG8sdDWBWpsSpgvEeV5gyw9U+jyUGNKTHSeGY+Z9fza
# AP2I5uKtrAuFtChr+YHvDjFoLLBREhTK35fdRBhkBhibOdEjsUzNmLF05+lub4KJ
# iO8VbbpinPiIPMep7EUkQe1MhJet/mNxbdAeNLQ718e3dQAJPUBsEDix1bXcrIo+
# +8Rpa2HmEh/vhh/TFpXX2Hdcb3FhJFpxki0sncukGD99Qg/pP5WsGr7Q87SUjr/k
# sWaUOpuT41i1rOMfc+83uPV2KsPNfL1yK7OPDJ9/X79fW8PrFoeIJwii1CsaTAVS
# MejdtKFM8fGvETeFfMxIXhS14lO2ZEuR3sthUFqRa0RJK4Q4t6ZGH/KW7+mb06zg
# 64rbmrHG8ZI59n9pHWVyHu52vxBwcVKx9sqe7UPnzqNvXbjbck8hACq9+7r1MLNV
# TwbELqaLvAhvf574lEA6mywbKYZjNB49kgDwLPbqbPoYAdtBHpRmSyZG0dJPwOK5
# jtVW+aGCFLIwghSuBgorBgEEAYI3AwMBMYIUnjCCFJoGCSqGSIb3DQEHAqCCFIsw
# ghSHAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFqBgsqhkiG9w0BCRABBKCCAVkEggFV
# MIIBUQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBDt8i84ZSwQsFV
# TqoJlgOtpPO2DiLaWR4hGpGz/yCLSgIGacZcchqNGBMyMDI2MDQxNTE5NDQzNS44
# NDlaMASAAgH0oIHppIHmMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExp
# bWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0NTFBLTA1RTAtRDk0NzE1
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
# r1nJfiWG2GwYe6ZoAF1bMIIHnzCCBYegAwIBAgITMwAAAFxhTACmp/LpIwAAAAAA
# XDANBgkqhkiG9w0BAQwFADBhMQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVibGljIFJTQSBU
# aW1lc3RhbXBpbmcgQ0EgMjAyMDAeFw0yNjAxMDgxODU5MDZaFw0yNzAxMDcxODU5
# MDZaMIHjMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo0NTFBLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHkwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCuNYzOVXmTR3eDbVZVMTaDh6n+nv04
# Jw4zW6v7OTN1oTSxBIhyq6QKMBanA2eXpOyqQ0VvcXgcC5Sz3aMgldXyKR79bMIe
# LVPQtXSCsjrrLjd9mpdd5VQq4HfKgaisPLFv6ynp1x2g1veINh5V+bLEFp1XCqWW
# CEd1KRMQpkUkLSFRBZaFmb6Nz3MGrRAmU4nxt0wIV/20wSlzhaFKalpP0hSwI+1s
# VCxN8H8rlgh+0jGNZgCJEnXKw3SO/wJEjRhZMPaUSGEX7cwCrzqj/y1hnA+a8Gbw
# fZ0lCQPmMrjbcvx3j1VL6VecFnpdhfyP5ApLH5CSkXtNYhiFi7mG889+Miz+Ccr7
# awPiFP1LvAR9CTDZHz4ua/A5r4jOehH9AU7eEPxulAwy0BBywOl7tpK3gKMexwQy
# gHFpZe5d7TPiuVzKwktbh9ro4CkDwcpdUHCRgysNOuZr8Wd60f9DLkiooQFRh/mi
# cZx82DUTDlM5Ctcl4Ns4HejZNRGr+Gvd7V9kKuZF6XmW2td9qIZGL4eb515I0FUP
# RycH3viftPZVKYDbkh8G/4I84tmfPh4PacHu6JCdkC0BsOU0EZMP8Su2h9NmgwVz
# k86NVH7f1JhFcWwsxZxhRgI3K9EcH5xhWiMsqxebmZkrFighdqO7+yzozZZ3lkkq
# BWikYTg7ikY8PwIDAQABo4IByzCCAccwHQYDVR0OBBYEFK77MhyRGGREOW504FoD
# Eie6JOdpMB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7ZPdshMGwGA1UdHwRl
# MGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAy
# MC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJT
# QSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYDVR0TAQH/BAIwADAW
# BgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwZgYDVR0gBF8w
# XTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMAgGBmeBDAEEAjAN
# BgkqhkiG9w0BAQwFAAOCAgEAhXbQN9yxJIQFnYCFueVeZ09WRv1WkODNsgQQ7iCl
# H9tHz1tD6pbi0LT3KHa1xmQ3gojjdzqd5FE1wGMAaZvu2DzKyW0ZWYDED7BbW0nR
# wvWxE9DSVfKFwxhFgTkHu5cMB9Ofj2te8Qdv5plXp1lra2V9dSPAaBY3D9g8GUie
# V9Ruk03uhmCZffR+fIobO07/0xGT+3PJo+nlXjgrIsihl6UU2CS/cpbbenCinHJn
# K2lUozE7+N25qSyy9Vgqvsv09xxLY14syl0aOZt0xOvVIIqLKmeui3h9HbxQfbtf
# gexLQ40z7wsnOJ/N/lt75vQaswZr39xEoMLeCeShyvgqMionmkQXT961Ti6LpNzG
# hZABR7YVpX+q84f9A6Kbl8amG8txKLdXOd9DKkCd9b+9sSTEnuULPsyuearCoNtr
# 3JOm9psIQ/2TYeumHgbFWNpEvWoZBjLUfjoD89A5w4vjnketG8ImRyYn8MhzE3Br
# k/aVJ6e5wrentLyIYbZidbZRCDLq1uEmLVColC8z+ki3avMrNfgVKIQobf7YIvom
# 1n00p6O73gQu8WiYuibJKgPxPD3RM1Dlh2m8GIkh15WTG6Gzk0dA5NyM2qoFFF/h
# NsbH5lY9qLrYb1meeXNfz3yytaeMs0Xvfq2N1eDYtDkRlEFoXn4JDWLKQdY2Ylw6
# vIMxggPUMIID0AIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRp
# bWVzdGFtcGluZyBDQSAyMDIwAhMzAAAAXGFMAKan8ukjAAAAAABcMA0GCWCGSAFl
# AwQCAQUAoIIBLTAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcN
# AQkEMSIEIIWrKnqpElwTAVSGC+o7TBPic51pX1h092AQP5+gRyB4MIHdBgsqhkiG
# 9w0BCRACLzGBzTCByjCBxzCBoAQg97pqQYd3bjD5LeiLZCbTs0cAUbdUPCOdd6vJ
# a36g7twwfDBlpGMwYTELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0
# YW1waW5nIENBIDIwMjACEzMAAABcYUwApqfy6SMAAAAAAFwwIgQgrcci9b7HOIxK
# IBH7Yg3Er3Da6Q80fPLQHn+iyLjKhfQwDQYJKoZIhvcNAQELBQAEggIARrDOPNHI
# q5ZhNOSuLRlZrYBFgjK6n/FwcbSpG2TfZ3OmoiW33q8yZ59anqzcvAuYG8m43jQQ
# v1gqG6vqESZ3VmiBeBUkIFMNdjDQIM5FoUQ6I+fN9K85iQOIwYPhg3Xo8fmpOEs5
# GdkhhN277uJxV+f/nekEbjbDwxfFs8CN1sOCibsM1XjRa3DCgsAhuAVecgZuRXxO
# Z0iNq4YYFOMAaypx4Py2uW2od4X5xFCPJfYWxKGA/403HI67IxxO9wSKiT9Cg3XD
# SAKNOFmR1mED0mPj0RUAcyW52alTiqgx3Z+edJxTXnqbd0lSqB9omjoAJus8nR+P
# UU4VGJOpZ1rZXzA5iCfpg3ZJyHdUNEyfo8vAfp2JrHaWUKJGJHA4Y06GlzGKF2WY
# G4Jw8kRM9S8UcyGA73YMzKu7DU01Ny193aqxIzCII8URnOMrAmMUeZavh2+mwXmC
# 3OOozKQ3W8GGh7hT5SlyXGHFPhkVc5bn++TtcH6x42bWlqKuGmhZc1J88somXZ4o
# FnwuBBO81enevqUxTHZ5s61etpxDvo+LsdSfYciooBuqlQCsRfyCG7LHBS9gVdDD
# DWhIEM08glcAdInfxqb8PHmpSRR2OR8+dr/hhFioGlr6P0qjEtTTv/FLqNzUrHQe
# DqeHAuSFDA1gtzkiuNHB4YEFveoKK2pyXYE=
# SIG # End signature block
