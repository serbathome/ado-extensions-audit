# Azure DevOps Extensions and Pipelines Audit Tools

This repository contains PowerShell scripts for auditing and analyzing Azure DevOps (ADO) extensions, tasks, and pipelines. These tools help you understand what extensions are installed in your organization, what permissions they have, and what tasks are being used in your pipelines.

## Prerequisites

- PowerShell 5.1 or higher
- A way to authenticate to Azure DevOps (choose one, see [Authentication](#authentication) below):
  - A Personal Access Token (PAT) with appropriate permissions, or
  - Sign-in with your Microsoft Entra ID (Azure AD) account (no PAT required)
- Environment variables set up:
  - `ADO_ORGANIZATION`: Your Azure DevOps organization name — just the short name (e.g. `contoso`), **not**
    a full URL. If you accidentally set it to `https://dev.azure.com/contoso` or
    `https://contoso.visualstudio.com`, the scripts detect and correct this automatically.
  - `ADO_PAT`: Your Personal Access Token (only required in PAT mode)

## Authentication

All three scripts share a common authentication helper, [`AdoAuth.ps1`](./AdoAuth.ps1), which builds the
`Authorization` header used for every Azure DevOps REST API call. It supports two modes, selected with the
`$env:ADO_AUTH_MODE` environment variable:

| `ADO_AUTH_MODE` | Description | Extra requirements |
| --- | --- | --- |
| `PAT` (default) | Uses `$env:ADO_PAT` with Basic authentication, same as before. | None. |
| `OAuth` | Uses a Microsoft Entra ID access token, acquired interactively via the `Az.Accounts` PowerShell module. No PAT is created or stored. | The [`Az.Accounts`](https://www.powershellgallery.com/packages/Az.Accounts) module (`Install-Module Az.Accounts -Scope CurrentUser`). |

This addresses [#2](https://github.com/serbathome/ado-extensions-audit/issues/2): organizations that block PAT
creation can now run these scripts by signing in interactively instead.

### Option A: Personal Access Token (PAT)

Set up your environment variables before running the scripts:

```powershell
# Windows PowerShell
$env:ADO_ORGANIZATION = "your-organization-name"
$env:ADO_PAT = "your-personal-access-token"

# Or on macOS/Linux with PowerShell Core
$env:ADO_ORGANIZATION = "your-organization-name"
$env:ADO_PAT = "your-personal-access-token"
```

### Option B: Microsoft Entra ID (OAuth) sign-in — no PAT needed

Instead of a PAT, you can sign in interactively with your Microsoft Entra ID account. This requires the
`Az.Accounts` PowerShell module, which handles the interactive browser/device-code prompt and token
acquisition — no Azure CLI installation is required.

```powershell
# One-time module install
Install-Module Az.Accounts -Scope CurrentUser

# Configure the scripts to use Entra ID sign-in instead of a PAT
$env:ADO_ORGANIZATION = "your-organization-name"
$env:ADO_AUTH_MODE = "OAuth"

# Run any of the scripts as usual; a sign-in prompt appears the first time
# a token is needed (or when the cached Az context has expired).
./auditADOExtensions.ps1
```

Notes and requirements for OAuth mode:

- Your Azure DevOps organization must be connected to (backed by) a Microsoft Entra ID tenant. Organizations
  that are only backed by Microsoft accounts (MSA) cannot use this mode — use a PAT instead.
- **The token is automatically requested for the correct tenant.** The scripts discover the Microsoft Entra
  tenant that backs your organization (from its `X-VSS-ResourceTenant`) and request the access token for that
  specific tenant. This matters because Azure DevOps rejects a token minted for any other tenant (treating the
  request as anonymous and redirecting to sign-in) — which is easy to hit if your account can access multiple
  tenants and `Connect-AzAccount` last selected a subscription in a different one.
- The acquired token reflects your own Azure DevOps permissions (same access as when signing in through the
  browser); there is no separate scope-consent step like with PATs.
- Tokens are short-lived (about one hour). `Az.Accounts` caches your sign-in (`Connect-AzAccount`), so
  subsequent script runs in the same session typically won't prompt again until the cached context expires.
- To sign out / clear the cached context: `Disconnect-AzAccount`.
- For unattended/CI scenarios, `Connect-AzAccount` also supports service principals and managed identities
  (see the [`Az.Accounts` docs](https://learn.microsoft.com/powershell/module/az.accounts/connect-azaccount)),
  which avoids the interactive prompt entirely.
- If your account has access to many Microsoft Entra tenants (e.g. as a guest in several organizations),
  `Connect-AzAccount` may show a long "select a tenant and subscription" list and print warnings for
  unrelated tenants — this is normal and harmless (we only need one token, not a subscription). Automatic
  tenant discovery usually handles this for you; to override it (or if discovery can't determine the tenant),
  set `$env:ADO_ENTRA_TENANT_ID` to your organization's Microsoft Entra tenant ID (found under your
  organization's **Organization settings > Microsoft Entra ID** page) before running a script.

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

## The Authentication Helper (`AdoAuth.ps1`)

The `AdoAuth.ps1` file is dot-sourced by all three scripts and exposes `Get-AdoAuthHeader`, which returns the
`Authorization` header hashtable to use for `Invoke-RestMethod` calls, based on `$env:ADO_AUTH_MODE`
(`PAT` or `OAuth`). See [Authentication](#authentication) for configuration details.

## The Dictionary File (`dict.csv`)

The `dict.csv` file contains a mapping of Azure DevOps permission scopes to their descriptions. This is used by the extensions audit script to provide readable descriptions of the permissions requested by each extension.

## Troubleshooting

If you encounter errors:

1. Verify your environment variables are set correctly (`ADO_ORGANIZATION`, and either `ADO_PAT` or
   `ADO_AUTH_MODE = "OAuth"`).
2. Ensure your account/PAT has sufficient permissions:
   - For extensions audit: `vso.extension` and `vso.extension.data` scopes
   - For pipelines audit: `vso.build` and `vso.project` scopes
   - For tasks audit: `vso.build` scope
   - In OAuth mode, these correspond to your normal Azure DevOps organization/project permissions rather than
     PAT scopes.
3. In OAuth mode, if you see `The 'Az.Accounts' PowerShell module isn't installed`, run
   `Install-Module Az.Accounts -Scope CurrentUser`.
4. In OAuth mode, if you see `Could not load file or assembly 'Microsoft.Azure.PowerShell...'. Assembly with same
   name is already loaded`, an older version of `Az.Accounts` was already loaded in that terminal (for example
   from a previous `Connect-AzAccount` call before an Az module upgrade). Close and reopen your PowerShell
   terminal/window and try again — different Az module versions can't be loaded side by side in the same session.
5. In OAuth mode, if sign-in fails or hangs in a headless/remote session, run `Connect-AzAccount -UseDeviceAuthentication`
   once in an interactive session first so a cached context/device-code flow can be used.
6. If you see `The resource cannot be found` (HTTP 404), double-check `ADO_ORGANIZATION` is just the
   organization name and not a full URL (see [Prerequisites](#prerequisites) — the scripts normalize common
   URL forms automatically, but other typos in the name will still 404).
7. In OAuth mode, if `Connect-AzAccount` shows a long list of tenants/subscriptions to choose from, set
   `$env:ADO_ENTRA_TENANT_ID` to your organization's Microsoft Entra tenant ID beforehand (see
   [Authentication](#authentication)).
8. In OAuth mode, if the response is an HTML sign-in page or the audit reports no data even though you're
   signed in (the API treated the request as anonymous), the access token was likely issued for the wrong
   Microsoft Entra tenant. The scripts auto-discover and request the organization's tenant, but if discovery
   is blocked (e.g. by a network proxy) set `$env:ADO_ENTRA_TENANT_ID` to your organization's tenant ID to
   force it.
9. Check your network connectivity to Azure DevOps
10. Set `$DebugPreference = "Continue"` (already in scripts) to see detailed debug output

## Notes

- The scripts have debug output enabled by default. To disable, set `$DebugPreference = "SilentlyContinue"` in the scripts.
- Results are output to the console. To save to a file, use PowerShell redirection: `./scriptName.ps1 > results.txt`
- With debug output enabled, `Invoke-RestMethod`'s request tracing prints the full `Authorization` header
  (your PAT's Basic auth value, or your OAuth Bearer token) to the console. Avoid sharing that console output
  or redirected log files with anyone else, and prefer `$DebugPreference = "SilentlyContinue"` when redirecting
  output to a file you intend to share.
