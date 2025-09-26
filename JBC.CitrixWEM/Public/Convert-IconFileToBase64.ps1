function Convert-IconFileToBase64 {
    <#
    .SYNOPSIS
        A private helper to convert an icon file to a base64 string.
    .DESCRIPTION
        This function reads an icon file from the specified path, converts its content
        to a byte array, and then returns the base64-encoded string representation.
    .PARAMETER Path
        The file system path to the icon file (.ico, .exe, .dll, etc.).
    .NOTES
        This is a private function and not intended for direct use by the end-user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            throw "The specified icon file was not found at path: $Path"
        }

        $FileBytes = Get-Content -Path $Path -Encoding Byte -ReadCount 0
        $Base64String = [Convert]::ToBase64String($FileBytes)

        return $Base64String
    } catch {
        # Re-throw the exception to be caught by the calling function
        throw "Failed to convert icon file to base64. Details: $($_.Exception.Message)"
    }
}