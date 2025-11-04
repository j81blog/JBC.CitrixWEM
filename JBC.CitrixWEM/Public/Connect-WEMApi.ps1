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
    Co-Author:      Gemini
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
        [ValidateSet("eu", "us", "jp")]
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
        [Alias('Quiet, Q')]
        [switch]$Silent,

        [Parameter(Mandatory = $true, ParameterSetName = 'OnPremCredential')]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty
    )

    $LocalConnection = [PSCustomObject]@{
        IsOnPrem     = $false
        BaseUrl      = $null
        CustomerId   = $null
        BearerToken  = $null
        WebSession   = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        CloudProfile = $null
    }
    $LocalConnection.WebSession.UserAgent = "CitrixWEMPoShApi/1.4)"

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
                    $LocalConnection.CustomerId = "$($ApiCredentials.CustomerId))"
                    $LocalConnection.CloudProfile = $ApiCredentials.ProfileName
                } else {
                    $LocalConnection.BearerToken = $ApiCredentials.BearerToken
                    $LocalConnection.CustomerId = "$($ApiCredentials.CustomerId)"
                    $LocalConnection.CloudProfile = $ApiCredentials.ProfileName
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

                $Uri = "https://api-{0}.cloud.com/cctrustoauth2/root/tokens/clients" -f $ApiRegion
                $Body = @{
                    clientId     = $ClientId
                    clientSecret = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)))
                }
                $TokenResponse = Invoke-RestMethod -Uri $Uri -Method Post -Body (ConvertTo-Json -InputObject $Body) -ContentType "application/json"
                if ("$($TokenResponse.token)" -notlike "CWSAuth bearer=*") {
                    $LocalConnection.BearerToken = "CWSAuth bearer=$($TokenResponse.token)"
                } else {
                    $LocalConnection.BearerToken = $($TokenResponse.token)
                }

                $LocalConnection.BearerToken = "CWSAuth bearer=$($TokenResponse.token)"
                Write-Verbose "Successfully connected using API Credentials for Customer ID: $($LocalConnection.CustomerId) in region $($ApiRegion.ToUpper())"
                $IsConnected = $true
            }
        }

        $script:WemApiConnection = $LocalConnection

        try {
            Set-WEMActiveDomain
        } catch {
            Write-Verbose "Could not set active WEM AD Domain: $($_.Exception.Message)"
            Write-Warning "No active WEM AD Domain has been set. Please use Set-WEMActiveDomain to set one."
        }
        Write-Information -MessageData "Connected to WEM. You can use Set-WemActiveConfigurationSite to set the active Configuration Set."
    } catch {
        Write-Error "Failed to connect to WEM API. Details: $($_.Exception.Message)"
        throw
    } finally {
        if (-not $Silent -and -not $IsConnected) {
            Write-Warning "Connection to WEM API was not established."
        } elseif ($Silent.IsPresent -eq $false) {
            Write-Output ([PSCustomObject]@{
                    Message     = "Successfully connected to Citrix WEM Cloud API."
                    CustomerId  = $LocalConnection.CustomerId
                    ApiRegion   = $ApiRegion.ToUpper()
                    IsOnPrem    = $LocalConnection.IsOnPrem
                    IsCloud     = -not $LocalConnection.IsOnPrem
                    IsConnected = $IsConnected
                }
            )
        } else {
            Write-Verbose "Silent mode enabled; suppressing connection success output."
        }
    }
}