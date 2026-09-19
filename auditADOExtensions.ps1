
# Helper functions
# Get-DescriptionByScope function to retrieve description by scope from the dictionary
function Get-DescriptionByScope {
    param (
        [Parameter(Mandatory = $true)]
        [string]$scope,
        
        [Parameter(Mandatory = $true)]
        [array]$dict
    )
    foreach ($item in $dict) {
        if ($item.Scope -eq $scope) {
            return $item.Description
        }
    }
    return $null
}
# Function to read dict from a csv file into a list of objects
function Get-DictFromCsv {
    param (
        [Parameter(Mandatory = $true)]
        [string]$csvPath
    )
    return Import-Csv -Path $csvPath | ForEach-Object {
        [PSCustomObject]@{
            Scope        = $_.scope
            Name         = $_.name
            Description  = $_.description
            InheritedFrom = $_.inheritedfrom
        }
    }
}

# Constants and configuration
. "$PSScriptRoot\AdoAuth.ps1"
$organization = Resolve-AdoOrganizationName $env:ADO_ORGANIZATION
# Authenticates with a PAT (ADO_PAT) by default, or with Microsoft Entra ID sign-in
# when $env:ADO_AUTH_MODE is set to "OAuth". See README.md for details.
$headers = Get-AdoAuthHeader
$csvPath = "dict.csv"
$DebugPreference = "Continue" # set to "SilentlyContinue" to disable debug output

# Main script execution
try {
    Write-Output "Starting audit of installed extensions..."

    Write-Debug "Using permissions dictionary from: $csvPath"
    
    $dict = Get-DictFromCsv -csvPath $csvPath

    $extensionsUrl = "https://extmgmt.dev.azure.com/$organization/_apis/extensionmanagement/installedextensions?api-version=7.1-preview.1"
    Write-Debug "Attempting to connect to: $extensionsUrl"
    $response = Invoke-RestMethod -Uri $extensionsUrl -Headers $headers -Method Get -ErrorVariable restError

    if ($null -eq $response -or $response.value.Count -eq 0) {
        Write-Error "No installed extensions found or unable to retrieve data."
        return
    }
    else {
        Write-Output "Total installed extensions: $($response.value.Count)"
    }
    
    foreach ($extension in $response.value) {
        $publisherId = $extension.publisherId
        $extensionId = $extension.extensionId
        $publisherName = $extension.publisherName
        $extensionName = $extension.extensionName
        $detailsUrl = "https://extmgmt.dev.azure.com/$organization/_apis/extensionmanagement/installedextensionsbyname/$publisherId/$extensionId\?api-version=7.1-preview.1"

        Write-Output "Extension: $extensionName ($publisherName)"

        $extensionResponse = Invoke-RestMethod -Uri $detailsUrl -Headers $headers -Method Get -ErrorVariable restError
    
        if ($extensionResponse.scopes) {
            foreach ($scope in $extensionResponse.scopes) {
                $description = Get-DescriptionByScope -scope $scope -dict $dict
                if ($description) {
                    Write-Output "Scope: $scope, Description: $description"
                }
                else {
                    Write-Output "Scope: $scope, Description: Not found in dict."
                }
            }
        }
        else {
            Write-Output "No scopes found for this extension."
        }
        if ($extensionResponse.contributions) {
            foreach ($contribution in $extensionResponse.contributions) {
                Write-Output "Contribution ID: $($contribution.id)"
                Write-Output "- Type: $($contribution.type)"
                if ($contribution.description) {
                    Write-Output "- Description: $($contribution.description)"
                }
                else {
                    Write-Output "- Description: No description available."
                }
            }
        }
        else {
            Write-Output "No contributions found for this extension."
        }
        Write-Output "----------------------------------------"
        Write-Output ""
    }
    
    Write-Output "Audit completed successfully."
}
catch {
    Write-Error "Error accessing Azure DevOps Extensions API: $_"
}
