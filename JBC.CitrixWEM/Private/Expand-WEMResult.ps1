function Expand-WEMResult {
    <#
    .SYNOPSIS
        A private helper to consistently handle WEM API return objects.
    .DESCRIPTION
        This function checks if the input object from an API call has an 'Items' property.
        If it exists, it returns the value of 'Items'. Otherwise, it returns the
        original object. This standardizes the output from various API endpoints.
    .PARAMETER Result
        The result object from an Invoke-WemApiRequest call.
    .NOTES
        Version:        1.2
        Author:         John Billekens Consultancy
        Co-Author:      Gemini (Documentation and Review)
        Creation Date:  2025-08-05
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [object]$Result
    )

    process {
        # Return early if the result is null
        if ($null -eq $Result) {
            return
        }

        # Check if the object has a property named 'Items'
        if ($Result.PSObject.Properties['Items']) {
            # If the result has an 'Items' property, return its content.
            return $Result.Items
        } else {
            # Otherwise, return the result as is.
            return $Result
        }
    }
}