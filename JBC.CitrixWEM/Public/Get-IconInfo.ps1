function Get-IconInfo {
<#
    .SYNOPSIS
        Enumerates all icon resources within a specified executable or DLL file.

    .DESCRIPTION
        This function uses Windows API calls (P/Invoke) to inspect a PE file (like a .exe or .dll)
        and retrieve a list of all embedded icon group resources. It returns a custom object for
        each icon found, containing its index and resource name or ID.

    .PARAMETER FilePath
        The full path to the executable file (.exe) or library (.dll) from which to extract
        icon information. This parameter is mandatory.

    .EXAMPLE
        PS C:\> Get-IconInfo -FilePath "C:\Windows\System32\shell32.dll"

        Index Name
        ----- ----
            0 #236
            1 #235
            2 #1
            3 #2
        ... (and many more)

        This command lists all the icon resources found in the shell32.dll file, showing their
        zero-based index and resource name/ID.

    .EXAMPLE
        PS C:\> Get-ChildItem -Path "C:\Program Files\Microsoft VS Code\" -Filter "Code.exe" | Get-IconInfo

        Index Name
        ----- ----
            0 IDI_APP_ICON

        This command finds the "Code.exe" file and pipes it to Get-IconInfo to list its icon resources.

    .NOTES
        Function  : Get-IconInfo
        Author    : John Billekens
        Co-Author : Gemini
        Copyright : Copyright (c) John Billekens Consultancy
        Version   : 1.0

        This function depends on the Win32 API and will only work on Windows operating systems.
        It requires the ability to compile C# code via Add-Type at runtime.
#>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0
        )]
        [ValidateScript({
            if (-not (Test-Path -Path $_ -PathType Leaf)) {
                throw "File not found at path: $_"
            }
            return $true
        })]
        [string]
        $FilePath
    )

    begin {
        # Define the Win32 P/Invoke methods if they haven't been defined in this session yet.
        if (-not ([System.Management.Automation.PSTypeName]'Win32.NativeMethods').Type) {
            $CSharpSource = @"
using System;
using System.Runtime.InteropServices;

namespace Win32 {
    public static class NativeMethods {
        // Delegate for the resource enumeration callback function
        public delegate bool EnumResNameProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);

        // Constants for LoadLibraryEx
        public const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;

        // Constants for Resource Types
        public const uint RT_GROUP_ICON = 14;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool FreeLibrary(IntPtr hModule);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool EnumResourceNames(IntPtr hModule, uint lpszType, EnumResNameProc lpEnumFunc, IntPtr lParam);
    }
}
"@
            Add-Type -TypeDefinition $CSharpSource
        }
    }

    process {
        $ResolvedPath = Convert-Path -Path $FilePath
        Write-Verbose "Processing file: $($ResolvedPath)"

        $IconResources = New-Object System.Collections.Generic.List[object]

        # This script block acts as the callback for the EnumResourceNames API call.
        # It gets executed for each icon resource found in the file.
        $ResourceNameCallback = {
            param(
                [IntPtr]$HModule,
                [IntPtr]$LpszType,
                [IntPtr]$LpszName,
                [IntPtr]$LParam
            )

            # A resource name can be an integer ID or a string.
            # If the high-order word is zero, it's an integer ID. Otherwise, it's a pointer to a string.
            if (($LpszName.ToInt64() -band 0xFFFF0000) -ne 0) {
                $Name = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($LpszName)
            }
            else {
                # Format integer IDs with a '#' prefix, which is a common convention.
                $Name = "#$($LpszName.ToInt32())"
            }

            $IconResources.Add([PSCustomObject]@{
                    Index = $IconResources.Count
                    Name  = $Name
                }) | Out-Null

            # Return $true to continue the enumeration.
            return $true
        }
        Write-Verbose "Found $($IconResources.Count) icon resources."

        $EnumDelegate = [Win32.NativeMethods+EnumResNameProc]$ResourceNameCallback
        $HModule = [IntPtr]::Zero

        try {
            # Load the file as a data file, which doesn't execute any code from it.
            $HModule = [Win32.NativeMethods]::LoadLibraryEx($ResolvedPath, [IntPtr]::Zero, [Win32.NativeMethods]::LOAD_LIBRARY_AS_DATAFILE)

            if ($HModule -eq [IntPtr]::Zero) {
                $LastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                throw "Failed to load library '$($ResolvedPath)'. Win32 Error Code: $($LastError)"
            }

            # Enumerate the icon group resources.
            $EnumerationSuccess = [Win32.NativeMethods]::EnumResourceNames(
                $HModule,
                [Win32.NativeMethods]::RT_GROUP_ICON,
                $EnumDelegate,
                [IntPtr]::Zero
            )

            if (-not $EnumerationSuccess -and $IconResources.Count -eq 0) {
                $LastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                # A return of false with error 1813 is expected if no resources of the specified type are found.
                # This is not a critical failure.
                if ($LastError -ne 1813) {
                    Write-Warning "EnumResourceNames failed for '$($ResolvedPath)'. Win32 Error Code: $($LastError)"
                }
                else {
                    Write-Verbose "No icon resources found in '$($ResolvedPath)'."
                }
            }
        }
        finally {
            # Always ensure the library handle is freed to prevent resource leaks.
            if ($HModule -ne [IntPtr]::Zero) {
                [Win32.NativeMethods]::FreeLibrary($HModule) | Out-Null
            }
        }

        # Output the collected objects to the pipeline.
        $IconResources
    }
}