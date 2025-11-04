function Get-PublisherItemDetails {
    <#
    .SYNOPSIS
        Retrieves and formats publisher, product, and version details from an executable file for AppLocker.

    .DESCRIPTION
        This function robustly parses a file's digital signature and version info. It uses a regular
        expression to correctly parse the certificate subject, handling special characters within values
        (e.g., commas inside quotes). It reads the numeric binary file version from the FileVersionRaw
        property to ensure accuracy and formats all output strings to uppercase.

    .PARAMETER FilePath
        The full path to the executable file you want to inspect.

    .EXAMPLE
        PS C:\> Get-PublisherItemDetails -FilePath "C:\Program Files\Autodesk\AutoCAD 2025\acad.exe"

        type          value
        ----          -----
        PublisherItem @{publisherName=O=AUTODESK, INC., L=SAN FRANCISCO, S=CALIFORNIA, C=US; productName=AUTOCAD; fileName=ACAD.EXE; fileVersion=31.1.122.0}

    .EXAMPLE
        PS C:\> Get-PublisherItemDetails -FilePath C:\Windows\System32\cmd.exe | ConvertTo-Json -Compress | clip.exe

        Generates a JSON representation of the output and copies it to the clipboard, which can be used in Citrix WEM to paste the data into the Publisher field.

    .NOTES
        Function  : Get-PublisherItemDetails
        Author    : John Billekens
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.7
#>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Enter the full path to the file."
        )]
        [ValidateScript({
                if (-not (Test-Path $_ -PathType Leaf)) {
                    throw "File not found at path: $_"
                }
                return $true
            })]
        [string]
        $FilePath
    )

    begin {
        Write-Verbose "Starting file detail retrieval process."
    }

    process {
        try {
            Write-Verbose "Processing file: $($FilePath)"

            # Get the raw version and signature info
            $VersionInfo = (Get-Item $FilePath).VersionInfo
            $Signature = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue

            # --- Start Transformations ---

            # 1. Format the Publisher Name using a robust regex parser
            $FormattedPublisher = "NOT SIGNED"
            if ($Signature -and $Signature.Status -eq 'Valid') {
                # This regex finds all key=value pairs, correctly handling quoted values that contain commas.
                $DnRegex = '\w+=(".*?"|[^,]+)'
                $Matches = [regex]::Matches($Signature.SignerCertificate.Subject, $DnRegex)

                # Filter out the 'CN=' parts and rebuild the string.
                $FilteredParts = $Matches | Where-Object { $_.Value -notlike 'CN=*' } | ForEach-Object { $_.Value }
                $JoinedSubject = $FilteredParts -join ', '

                # Remove any quotes and convert to uppercase for the final format.
                $FormattedPublisher = ($JoinedSubject -replace '"', '').ToUpper()
            }

            # 2. Correctly assemble the File Version from the FileVersionRaw object parts
            $FormattedFileVersion = "{0}.{1}.{2}.{3}" -f $VersionInfo.FileVersionRaw.Major,
            $VersionInfo.FileVersionRaw.Minor,
            $VersionInfo.FileVersionRaw.Build,
            $VersionInfo.FileVersionRaw.Revision

            # --- End Transformations ---

            # Construct the final output object
            $OutputValue = [PSCustomObject]@{
                publisherName = $FormattedPublisher
                productName   = $VersionInfo.ProductName.ToUpper()
                fileName      = $VersionInfo.OriginalFilename.ToUpper()
                fileVersion   = $FormattedFileVersion
            }

            $Result = [PSCustomObject]@{
                type  = "PublisherItem"
                value = $OutputValue
            }

            Write-Output $Result
        } catch {
            Write-Error -Message "An unexpected error occurred while processing '$($FilePath)': $($_.Exception.Message)"
        }
    }

    end {
        Write-Verbose "File detail retrieval process finished."
    }
}