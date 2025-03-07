# Azure DevOps Extensions and Pipelines Audit Tools

This repository contains PowerShell scripts for auditing and analyzing Azure DevOps (ADO) extensions, tasks, and pipelines. These tools help you understand what extensions are installed in your organization, what permissions they have, and what tasks are being used in your pipelines.

## Prerequisites

- PowerShell 5.1 or higher
- Azure DevOps access token with appropriate permissions
- Environment variables set up:
  - `ADO_ORGANIZATION`: Your Azure DevOps organization name
  - `ADO_PAT`: Your Personal Access Token

## Setting Up Environment Variables

Before running the scripts, set up your environment variables:

```powershell
# Windows PowerShell
$env:ADO_ORGANIZATION = "your-organization-name"
$env:ADO_PAT = "your-personal-access-token"

# Or on macOS/Linux with PowerShell Core
$env:ADO_ORGANIZATION = "your-organization-name"
$env:ADO_PAT = "your-personal-access-token"
```

## Scripts Overview

### 1. Audit ADO Extensions (`auditADOExtensions.ps1`)

This script audits installed extensions in your Azure DevOps organization.

**What it does:**
- Lists all installed extensions
- Shows the scopes (permissions) requested by each extension
- Provides descriptions of the scopes from a dictionary
- Lists contributions made by each extension

**How to run:**
```powershell
./auditADOExtensions.ps1
```

**How it works:**
1. Connects to the Azure DevOps Extensions API
2. Retrieves a list of installed extensions
3. For each extension, fetches detailed information
4. Matches scopes with descriptions from the dictionary (`dict.csv`)
5. Outputs the results to the console

### 2. Audit ADO Extension Tasks (`auditADOExtensionTasks.ps1`)

This script audits tasks provided by extensions in your Azure DevOps organization.

**What it does:**
- Lists all tasks registered in your organization
- Shows task names, versions, and their contributor identifiers

**How to run:**
```powershell
./auditADOExtensionTasks.ps1
```

**How it works:**
1. Connects to the Azure DevOps Distributed Task API
2. Retrieves a list of all registered tasks
3. Outputs task details including name, contributor identifier, and version

### 3. Audit ADO Pipeline Tasks (`auditADOPipelinesTasks.ps1`)

This script analyzes which tasks are actually being used in your Azure DevOps pipelines.

**What it does:**
- Lists all projects in the organization
- Lists all pipelines in each project
- Generates YAML previews of each pipeline
- Extracts and lists tasks used in each pipeline

**How to run:**
```powershell
./auditADOPipelinesTasks.ps1
```

**How it works:**
1. Connects to the Azure DevOps Projects API to get all projects
2. For each project, retrieves all pipelines
3. For each pipeline, generates a YAML preview
4. Parses the YAML to find task references in the format `task: TaskName@Version`
5. Outputs the tasks used in each pipeline

## The Dictionary File (`dict.csv`)

The `dict.csv` file contains a mapping of Azure DevOps permission scopes to their descriptions. This is used by the extensions audit script to provide readable descriptions of the permissions requested by each extension.

## Troubleshooting

If you encounter errors:

1. Verify your environment variables are set correctly
2. Ensure your PAT has sufficient permissions:
   - For extensions audit: `vso.extension` and `vso.extension.data` scopes
   - For pipelines audit: `vso.build` and `vso.project` scopes
   - For tasks audit: `vso.build` scope
3. Check your network connectivity to Azure DevOps
4. Set `$DebugPreference = "Continue"` (already in scripts) to see detailed debug output

## Notes

- The scripts have debug output enabled by default. To disable, set `$DebugPreference = "SilentlyContinue"` in the scripts.
- Results are output to the console. To save to a file, use PowerShell redirection: `./scriptName.ps1 > results.txt`
