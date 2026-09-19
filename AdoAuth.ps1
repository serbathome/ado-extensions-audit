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

function Resolve-AdoOrganizationName {
    <#
    .SYNOPSIS
    Normalizes $env:ADO_ORGANIZATION into a bare organization name.

    .DESCRIPTION
    ADO_ORGANIZATION should be just the organization name (e.g. "contoso"), but it's an easy mistake
    to paste a full URL instead (e.g. "https://dev.azure.com/contoso" or "https://contoso.visualstudio.com").
    This strips those known URL forms down to the bare name so the scripts keep working either way.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Organization
    )

    if ([string]::IsNullOrWhiteSpace($Organization)) {
        throw "ADO_ORGANIZATION environment variable is not set. Set it to your Azure DevOps organization name (e.g. 'contoso'), not a full URL."
    }

    $trimmed = $Organization.Trim().TrimEnd('/')

    if ($trimmed -match '^https?://dev\.azure\.com/([^/]+)') {
        return $Matches[1]
    }
    if ($trimmed -match '^https?://([^.]+)\.visualstudio\.com') {
        return $Matches[1]
    }

    return $trimmed
}

function Get-AdoResourceTenantId {
    <#
    .SYNOPSIS
    Discovers the Microsoft Entra tenant ID that backs an Azure DevOps organization.

    .DESCRIPTION
    Azure DevOps returns the organization's backing tenant in the 'X-VSS-ResourceTenant' response
    header. We deliberately send 'X-TFS-FedAuthRedirect: Suppress' so an unauthenticated request
    returns a 401 with that header instead of an HTML sign-in redirect. Returns $null if the tenant
    can't be determined or the organization is backed by a personal Microsoft account (all-zero GUID).
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Organization
    )

    $uri = "https://dev.azure.com/$Organization/_apis/connectionData"
    $reqHeaders = @{ "X-TFS-FedAuthRedirect" = "Suppress"; "Accept" = "application/json" }
    $tenant = $null
    try {
        $iwrParams = @{ Uri = $uri; Headers = $reqHeaders; MaximumRedirection = 0; ErrorAction = "Stop" }
        if ($PSVersionTable.PSVersion.Major -ge 6) { $iwrParams["SkipHttpErrorCheck"] = $true }
        $resp = Invoke-WebRequest @iwrParams
        $tenant = $resp.Headers["X-VSS-ResourceTenant"]
    }
    catch {
        # Windows PowerShell 5.1 throws on a 401; read the header off the thrown response instead.
        if ($_.Exception.Response) {
            $tenant = $_.Exception.Response.Headers["X-VSS-ResourceTenant"]
        }
        else {
            Write-Debug "Unable to discover the organization's Entra tenant: $($_.Exception.Message)"
        }
    }

    if ($tenant) { $tenant = ($tenant -join "").Trim() }
    if ($tenant -and $tenant -ne "00000000-0000-0000-0000-000000000000") {
        return $tenant
    }
    return $null
}

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
        [string]$AuthMode = $(if ($env:ADO_AUTH_MODE) { $env:ADO_AUTH_MODE } else { "PAT" }),
        [string]$Organization = $env:ADO_ORGANIZATION
    )

    switch ($AuthMode.ToUpperInvariant()) {
        "OAUTH" {
            return @{ Authorization = "Bearer $(Get-AdoEntraAccessToken -Organization $Organization)" }
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
    param (
        [string]$Organization = $env:ADO_ORGANIZATION
    )

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

    # Determine the Microsoft Entra tenant that backs the Azure DevOps organization. This matters
    # because Get-AzAccessToken mints a token for a specific tenant, and Azure DevOps rejects tokens
    # issued for any tenant other than the one backing the organization (the request is then treated
    # as anonymous and redirected to sign-in). An explicit $env:ADO_ENTRA_TENANT_ID override wins;
    # otherwise the tenant is auto-discovered from the organization.
    $tenantId = $env:ADO_ENTRA_TENANT_ID
    if ([string]::IsNullOrWhiteSpace($tenantId) -and -not [string]::IsNullOrWhiteSpace($Organization)) {
        $tenantId = Get-AdoResourceTenantId -Organization (Resolve-AdoOrganizationName $Organization)
        if ($tenantId) { Write-Debug "Discovered organization Entra tenant: $tenantId" }
    }

    if (-not (Get-AzContext -ErrorAction SilentlyContinue)) {
        Write-Output "Sign in with your Microsoft Entra ID account (a browser window will open)..."

        # We only need an access token for Azure DevOps, not an Azure Resource Manager subscription
        # context, so skip populating a context per subscription (-SkipContextPopulation). If the
        # account has access to many tenants (e.g. as a guest), Connect-AzAccount otherwise prompts
        # with a long "select a tenant and subscription" list and probes every tenant for a token.
        $connectParams = @{
            SkipContextPopulation = $true
            ErrorAction           = "Stop"
        }
        if ($tenantId) { $connectParams["Tenant"] = $tenantId }
        Connect-AzAccount @connectParams | Out-Null
    }

    # Request the token for the organization's tenant explicitly. Without -TenantId, Get-AzAccessToken
    # uses whatever tenant the current Az context happens to point at, which is often a different
    # tenant (e.g. the one owning the last-selected subscription) and yields a token the organization
    # rejects. If a silent token for that tenant isn't cached yet, reconnect to it and retry.
    $tokenParams = @{ ResourceUrl = $script:AdoEntraResourceId; ErrorAction = "Stop" }
    if ($tenantId) { $tokenParams["TenantId"] = $tenantId }
    try {
        $tokenResult = Get-AzAccessToken @tokenParams
    }
    catch {
        if ($tenantId) {
            Write-Output "Signing in to the organization's Microsoft Entra tenant ($tenantId)..."
            Connect-AzAccount -Tenant $tenantId -SkipContextPopulation -ErrorAction Stop | Out-Null
            $tokenResult = Get-AzAccessToken @tokenParams
        }
        else {
            throw
        }
    }

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
