# Constants and configuration
. "$PSScriptRoot\AdoAuth.ps1"
$organization = Resolve-AdoOrganizationName $env:ADO_ORGANIZATION
# Authenticates with a PAT (ADO_PAT) by default, or with Microsoft Entra ID sign-in
# when $env:ADO_AUTH_MODE is set to "OAuth". See README.md for details.
$headers = Get-AdoAuthHeader
$DebugPreference = "Continue" # set to "SilentlyContinue" to disable debug output

try {
    Write-Output "Starting audit of installed tasks..."
    $tasksUrl = "https://dev.azure.com/$organization/_apis/distributedtask/tasks?api-version=7.1-preview.1"
    Write-Debug "Attempting to connect to: $tasksUrl"
    
    try {
        $response = Invoke-RestMethod -Uri $tasksUrl -Headers $headers -Method Get -ErrorVariable restError -Verbose        
        $response = $response.Replace('""', '"_empty"') | ConvertFrom-Json

        foreach ($task in $response.value) {
            $contributionIdentifier = $task.contributionIdentifier
            if ($contributionIdentifier) {
                $taskName = $task.name
                $taskVersion = $task.version
                Write-Output "Task: $taskName, Contributor: $contributionIdentifier, Version: $($taskVersion.Major).$($taskVersion.Minor).$($taskVersion.Patch)"
            }
        }
    }
    catch {
        Write-Error "API request failed: $_"
        if ($restError) {
            Write-Error "Rest error details: $($restError.Message)"
        }
        return
    }
}
catch {
    Write-Error "An error occurred: $_"
    return
}