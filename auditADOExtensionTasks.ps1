# Constants and configuration
$organization = $env:ADO_ORGANIZATION
$pat = $env:ADO_PAT
$headers = @{
    Authorization = "Bearer $pat"
}
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