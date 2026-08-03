<#
.SYNOPSIS
    Creates the multi-tenant SPA app registration for the ZTA web app (delegated, read-only).
    Same pattern as ENCA's New-EncaAppRegistration.ps1.

.EXAMPLE
    ./New-ZtaAppRegistration.ps1
    Then paste the printed application (client) id into CONFIG.clientId in index.html.
#>
[CmdletBinding()]
param(
    [string]$DisplayName = 'ZTA (Limon-IT)',
    [string]$AppObjectId,
    [string[]]$RedirectUris = @('https://zerotrustassessment.limon-it.nl','http://localhost:8080')
)
$ErrorActionPreference = 'Stop'

# Delegated scopes the v1 web app uses (base + on-demand)
$delegatedScopes = @(
    'User.Read'
    'Policy.Read.All'
    'Directory.Read.All'
    'DeviceManagementConfiguration.Read.All'   # Devices pillar, on demand
    'Sites.ReadWrite.All'                      # Save to SharePoint, on demand
    'RoleManagement.Read.Directory'            # PIM eligibility check (ZTA-024)
    'AuditLog.Read.All'                        # MFA registration report (ZTA-025)
)

Import-Module Microsoft.Graph.Applications -ErrorAction Stop
if (-not (Get-MgContext)) { Connect-MgGraph -Scopes 'Application.ReadWrite.All','Directory.Read.All' -NoWelcome }

$ctx = Get-MgContext
$org = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/organization').value[0]
Write-Host ''
Write-Host "Tenant:  $($org.displayName) ($($ctx.TenantId))" -ForegroundColor Cyan
Write-Host "Ran as:  $($ctx.Account)" -ForegroundColor Cyan
Write-Host ''

$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$access = foreach ($s in $delegatedScopes) {
    $perm = $graphSp.Oauth2PermissionScopes | Where-Object Value -eq $s
    if (-not $perm) { Write-Warning "Scope not found: $s"; continue }
    @{ Id = $perm.Id; Type = 'Scope' }
}

$params = @{
    DisplayName            = $DisplayName
    SignInAudience         = 'AzureADMultipleOrgs'
    Spa                    = @{ RedirectUris = $RedirectUris }
    RequiredResourceAccess = @(@{ ResourceAppId = '00000003-0000-0000-c000-000000000000'; ResourceAccess = @($access) })
}
$app = if ($AppObjectId) { Get-MgApplication -ApplicationId $AppObjectId }
       else { Get-MgApplication -Filter "displayName eq '$DisplayName'" | Select-Object -First 1 }

if ($app) {
    # ---- capture state BEFORE the update, so we can report exactly what changed ----
    $scopeName = @{}; $graphSp.Oauth2PermissionScopes | ForEach-Object { $scopeName[$_.Id] = $_.Value }
    $beforeScopes = @(($app.RequiredResourceAccess |
        Where-Object ResourceAppId -eq '00000003-0000-0000-c000-000000000000').ResourceAccess |
        Where-Object Type -eq 'Scope' | ForEach-Object { $scopeName[$_.Id] })
    $beforeUris   = @($app.Spa.RedirectUris)

    Update-MgApplication -ApplicationId $app.Id @params
    Write-Host "Updated: $($app.AppId)"

    # ---- change report ----
    $addedScopes   = @($delegatedScopes | Where-Object { $_ -notin $beforeScopes })
    $removedScopes = @($beforeScopes    | Where-Object { $_ -notin $delegatedScopes })
    $addedUris     = @($RedirectUris    | Where-Object { $_ -notin $beforeUris })
    $removedUris   = @($beforeUris      | Where-Object { $_ -notin $RedirectUris })

    Write-Host ''
    Write-Host '========== CHANGE REPORT ==========' -ForegroundColor Green
    if ($addedScopes)   { Write-Host "  + scopes added:    $($addedScopes -join ', ')" -ForegroundColor Yellow }
    if ($removedScopes) { Write-Host "  - scopes removed:  $($removedScopes -join ', ')" }
    if ($addedUris)     { Write-Host "  + redirect URIs:   $($addedUris -join ', ')" }
    if ($removedUris)   { Write-Host "  - redirect URIs:   $($removedUris -join ', ')" }
    if (-not ($addedScopes -or $removedScopes -or $addedUris -or $removedUris)) {
        Write-Host '  no changes — registration already matched.'
    }
    if ($addedScopes) {
        Write-Host ''
        Write-Host '  ⚠ New scopes need FRESH ADMIN CONSENT:' -ForegroundColor Yellow
        Write-Host '    - your own tenant: Entra portal → App registrations → API permissions → Grant admin consent'
        Write-Host '    - customer tenants: resend the consent URL below. Until then, the checks needing these'
        Write-Host '      scopes show as Skipped in the app.'
    }
} else {
    $app = New-MgApplication @params
    Write-Host "Created: $($app.AppId)  (new registration — all $($delegatedScopes.Count) scopes are new)"
}

Write-Host ''
Write-Host "clientId  → paste into CONFIG.clientId in index.html:  $($app.AppId)"
Write-Host 'Grant admin consent in your own tenant: Entra portal → App registrations → API permissions.'
Write-Host 'Customer tenants consent via:'
Write-Host "  https://login.microsoftonline.com/organizations/adminconsent?client_id=$($app.AppId)&redirect_uri=https://zerotrustassessment.limon-it.nl"
Write-Host 'Local test: python3 -m http.server 8080 → http://localhost:8080 (or ?demo=1 without any setup)'
