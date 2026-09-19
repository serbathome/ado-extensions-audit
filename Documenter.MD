# Project Documentation

## Technical Stack

- **Language:** PowerShell
- **Scripts:** auditADOExtensionTasks.ps1, auditADOExtensions.ps1, auditADOPipelinesTasks.ps1
- **Data:** dict.csv (CSV file for dictionary/reference)
- **Platform:** Azure DevOps (ADO)

## Business Logic

This project provides PowerShell scripts to audit Azure DevOps (ADO) extensions and pipeline tasks. The scripts automate the process of extracting, analyzing, and reporting on ADO extensions and pipeline tasks, helping organizations maintain compliance and visibility into their DevOps environment.

- **auditADOExtensionTasks.ps1:** Audits tasks within ADO extensions, generating reports on their usage and configuration.
- **auditADOExtensions.ps1:** Audits installed ADO extensions, summarizing their metadata and deployment status.
- **auditADOPipelinesTasks.ps1:** Audits pipeline tasks across ADO pipelines, identifying task usage and potential issues.
- **dict.csv:** Provides reference data used by the scripts for mapping or lookup purposes.

The scripts are designed to be run in a Windows or Linux environment with PowerShell installed, targeting ADO organizations via API or CLI. Outputs are typically CSV or text reports for further analysis.