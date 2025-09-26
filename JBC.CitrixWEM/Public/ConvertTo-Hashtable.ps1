function ConvertTo-Hashtable {
    <#
        .SYNOPSIS
            Recursively converts a PSObject or an array of PSObjects into a hashtable or an array of hashtables.

        .DESCRIPTION
            This function takes any object as input and recursively converts it into a hashtable.
            If the input is a collection of objects, it returns an array of hashtables. Properties of the
            input object become key-value pairs in the resulting hashtable. Primitive types (like strings
            or integers) are returned as-is.

        .PARAMETER InputObject
            The object to convert. This can be a single object, an array of objects, or a primitive
            type. This parameter accepts input from the pipeline.

        .EXAMPLE
            PS C:\> $Object = [PSCustomObject]@{
                Name = 'Test'
                ID = 123
                Data = [PSCustomObject]@{
                    Value = 'NestedValue'
                    Timestamp = Get-Date
                }
                Tags = @('A', 'B', 'C')
            }
            PS C:\> $Object | ConvertTo-Hashtable

            # This command converts the $Object and its nested objects into a hashtable.
            # The output will be a nested hashtable structure.

        .OUTPUTS
            System.Collections.Hashtable
            System.Array
            System.Object

        .NOTES
            Function  : ConvertTo-Hashtable
            Author    : John Billekens
            Co-Author : Gemini
            Copyright : Copyright (c) John Billekens Consultancy
            Version   : 1.0
    #>
    [CmdletBinding()]
    [OutputType('hashtable')]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object]$InputObject
    )

    process {
        if ($null -eq $InputObject) {
            return $null
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            # If the object is a collection (but not a string), process each item recursively.
            $Collection = @(
                foreach ($Object in $InputObject) {
                    ConvertTo-Hashtable -InputObject $Object
                }
            )
            # Use Write-Output with -NoEnumerate to return the collection as a single array.
            Write-Output -NoEnumerate $Collection
        } elseif ($InputObject -is [PSObject]) {
            # If the object is a PSObject, convert its properties to a hashtable.
            $Hash = @{}
            foreach ($Property in $InputObject.PSObject.Properties) {
                # Recursively convert the property's value.
                $Hash[$Property.Name] = ConvertTo-Hashtable -InputObject $Property.Value
            }
            # Return the populated hashtable.
            $Hash
        } else {
            # For primitive types (string, int, etc.), return the object as-is.
            $InputObject
        }
    }
}