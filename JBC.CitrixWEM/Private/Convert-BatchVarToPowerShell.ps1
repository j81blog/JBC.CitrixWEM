<#
    .SYNOPSIS
        Converts a string containing batch-style environment variables to PowerShell syntax, optionally resolving it to a full path.

    .DESCRIPTION
        This function takes a string, typically a file path, and uses a regular expression
        to find all occurrences of batch-style environment variables (e.g., %VAR%). It then
        replaces them with the corresponding PowerShell environment variable syntax (e.g., ${Env:VAR}).

        If the -Resolve switch is used, the function will then attempt to resolve the converted
        string into a fully qualified file system path.

    .PARAMETER Path
        The input string or path that contains the batch-style variables to be converted.
        This parameter accepts pipeline input.

    .PARAMETER Resolve
        A switch parameter that, if present, causes the function to resolve the converted
        path into a full, absolute path on the file system. If the path does not exist,
        a warning will be displayed.

    .EXAMPLE
        PS C:\> Convert-BatchVarToPowerShell -Path '%SystemRoot%\System32\drivers\etc\hosts'

        ${Env:SystemRoot}\System32\drivers\etc\hosts

        Description
        -----------
        This command converts the provided path, replacing '%SystemRoot%' with '${Env:SystemRoot}'.

    .EXAMPLE
        PS C:\> '%TEMP%\MyApplication\log.txt' | Convert-BatchVarToPowerShell

        ${Env:TEMP}\MyApplication\log.txt

        Description
        -----------
        This command demonstrates pipeline usage. The string is piped to the function, and
        '%TEMP%' is converted to its PowerShell equivalent.

    .EXAMPLE
        PS C:\> Convert-BatchVarToPowerShell -Path '%WinDir%\System32\cmd.exe' -Resolve

        C:\Windows\System32\cmd.exe

        Description
        -----------
        This command converts the path and, because -Resolve is specified, expands it to its
        fully qualified path on the file system.

    .NOTES
        Function  : Convert-BatchVarToPowerShell
        Author    : John Billekens
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.2
#>
function Convert-BatchVarToPowerShell {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(
            Mandatory = $false
        )]
        [switch]$Resolve
    )

    begin {
        # This block is for one-time setup, not needed for this simple function.
    }

    process {
        # The -replace operator uses a regular expression to find all instances
        # of a variable name surrounded by percent signs.
        $ConvertedPath = $Path -replace '%(\w+)%', '${Env:$1}'

        if ($Resolve.IsPresent) {

            $ExpandedPath = $ExecutionContext.InvokeCommand.ExpandString($ConvertedPath)

            Write-Output $ExpandedPath
        } else {
            # If -Resolve is not used, output the converted string as before.
            Write-Output $ConvertedPath
        }
    }

    end {
        # This block is for one-time cleanup, not needed for this simple function.
    }
}