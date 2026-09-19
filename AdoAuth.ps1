# AdoAuth.ps1
# Shared helper for building the Authorization header used by the audit scripts.
#
# Supports two authentication modes, selected via the $env:ADO_AUTH_MODE environment variable:
#   - "PAT"   (default): Uses a Personal Access Token from $env:ADO_PAT (Basic auth).
#   - "OAuth": Uses a Microsoft Entra ID access token acquired via the Az.Accounts
#              PowerShell module (Connect-AzAccount / Get-AzAccessToken). This opens an
#              interactive sign-in prompt (browser or device code) instead of requiring a PAT.
#
# The Az.Accounts module is only required when ADO_AUTH_MODE is set to "OAuth". Install it with:
#   Install-Module Az.Accounts -Scope CurrentUser

# Well-known Azure DevOps resource/application ID used to request Microsoft Entra ID access tokens.
# See: https://learn.microsoft.com/azure/devops/cli/entra-tokens
$script:AdoEntraResourceId = "499b84ac-1321-427f-aa17-267ca6975798"

function Get-AdoAuthHeader {
    <#
    .SYNOPSIS
    Builds the Authorization header hashtable for Azure DevOps REST API calls.

    .DESCRIPTION
    Returns @{ Authorization = "Basic <...>" } when using a PAT, or
    @{ Authorization = "Bearer <...>" } when using a Microsoft Entra ID (OAuth) token,
    depending on $env:ADO_AUTH_MODE ("PAT", the default, or "OAuth").
    #>
    param (
        [string]$AuthMode = $(if ($env:ADO_AUTH_MODE) { $env:ADO_AUTH_MODE } else { "PAT" })
    )

    switch ($AuthMode.ToUpperInvariant()) {
        "OAUTH" {
            return @{ Authorization = "Bearer $(Get-AdoEntraAccessToken)" }
        }
        "PAT" {
            return @{ Authorization = "Basic $(Get-AdoPatBase64)" }
        }
        default {
            throw "Unsupported ADO_AUTH_MODE '$AuthMode'. Supported values are 'PAT' and 'OAuth'."
        }
    }
}

function Get-AdoPatBase64 {
    $pat = $env:ADO_PAT
    if ([string]::IsNullOrWhiteSpace($pat)) {
        throw "ADO_PAT environment variable is not set. Set it to a Personal Access Token, or switch to Microsoft Entra ID sign-in with `$env:ADO_AUTH_MODE = 'OAuth'`."
    }
    return [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$pat"))
}

function Get-AdoEntraAccessToken {
    # Only import Az.Accounts if no version of it is already loaded in this session. Explicitly
    # (re-)importing a different version than one already loaded can fail with an "assembly already
    # loaded" error, because Az's native assemblies can't be side-loaded side-by-side in one process.
    # This commonly happens right after upgrading the Az module in a terminal that had already loaded
    # the older version (e.g. via an earlier Connect-AzAccount call) -- restarting the terminal avoids it.
    if (-not (Get-Module -Name Az.Accounts)) {
        if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
            throw "ADO_AUTH_MODE is set to 'OAuth' but the 'Az.Accounts' PowerShell module isn't installed. Install it with: Install-Module Az.Accounts -Scope CurrentUser"
        }
        try {
            Import-Module Az.Accounts -ErrorAction Stop
        }
        catch {
            throw "Failed to load the 'Az.Accounts' module: $($_.Exception.Message). If you recently updated the Az module, close and reopen your PowerShell terminal, then try again."
        }
    }

    if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
        Write-Output "Sign in with your Microsoft Entra ID account (a browser window will open)..."
        Connect-AzAccount -ErrorAction Stop | Out-Null
    }

    $tokenResult = Get-AzAccessToken -ResourceUrl $script:AdoEntraResourceId -ErrorAction Stop

    if ($tokenResult.Token -is [System.Security.SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenResult.Token)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    # Older Az.Accounts versions may return the token as a plain string.
    return $tokenResult.Token
}
