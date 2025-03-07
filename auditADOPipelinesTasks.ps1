# Constants and configuration
$organization = $env:ADO_ORGANIZATION
$pat = $env:ADO_PAT
$headers = @{
    Authorization = "Bearer $pat"
}
$DebugPreference = "Continue" # set to "SilentlyContinue" to disable debug output

# Function to get the list of projects
function Get-ADOProjects {
    param (
        [string]$organization,
        [hashtable]$headers
    )

    $uri = "https://dev.azure.com/$organization/_apis/projects?api-version=6.0"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    return $response.value
}

# Function to get the list of pipelines for a project
function Get-ADOPipelines {
    param (
        [string]$organization,
        [hashtable]$headers,
        [string]$projectName
    )

    $uri = "https://dev.azure.com/$organization/$projectName/_apis/pipelines?api-version=6.0"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    return $response.value
}

# Function to get the YAML preview of a pipeline
function Get-ADOPipelinePreview {
    param (
        [string]$organization,
        [hashtable]$headers,
        [string]$projectName,
        [string]$pipelineId
    )

    $uri = "https://dev.azure.com/$organization/$projectName/_apis/pipelines/$pipelineId/preview?api-version=7.2-preview.1"
    $body = @{
        runParameters = ""
        previewRun = "true"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body -ContentType "application/json"
    return $response
}

# Function to extract task names from YAML
function Get-TaskNamesFromYaml {
    param (
        [string]$yamlContent
    )

    # Use regex to find all task names in the format: task: <TaskName>@<Version>
    $tasks = [regex]::Matches($yamlContent, 'task:\s*(\w+@\d+)') | ForEach-Object { $_.Groups[1].Value }

    return $tasks
}

try {
    # Get all the projets in the organization
    $projects = Get-ADOProjects -organization $organization -headers $headers
    foreach ($project in $projects) {
        Write-Output "Project name: $($project.name)"
        $projectName = $project.name
        # Get all the pipelines in the project
        $pipelines = Get-ADOPipelines -organization $organization -headers $headers -projectName $projectName
        if ($pipelines.Count -eq 0) {
            Write-Output "  No pipelines found for project: $projectName"
        } else {
            foreach ($pipeline in $pipelines) {
                Write-Output "  Pipeline: $($pipeline.name), ID: $($pipeline.id)"
                $pipelineId = $pipeline.id
                # Get the YAML preview of the pipeline
                $preview = Get-ADOPipelinePreview -organization $organization -headers $headers -projectName $projectName -pipelineId $pipelineId
                # Check if the preview is null or empty
                if ($null -eq $preview -or $preview.finalYaml -eq "") {
                    Write-Output "    No YAML preview available for this pipeline."
                    continue
                }
                # Extract task names from the YAML content
                $tasks = Get-TaskNamesFromYaml -yamlContent $preview.finalYaml
                if ($tasks.Count -eq 0) {
                    Write-Output "    No tasks found in pipeline YAML."
                } else {
                    Write-Output "    Tasks in pipeline YAML:"
                    foreach ($task in $tasks) {
                        Write-Output "      - $task"
                    }
                }

            }
        }
    }
}
catch {
    Write-Error "An error occurred: $_"
    return
}

