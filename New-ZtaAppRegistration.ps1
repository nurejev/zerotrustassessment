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
if ($app) { Update-MgApplication -ApplicationId $app.Id @params; Write-Host "Updated: $($app.AppId)" }
else      { $app = New-MgApplication @params;                    Write-Host "Created: $($app.AppId)" }

Write-Host ''
Write-Host "clientId  → paste into CONFIG.clientId in index.html:  $($app.AppId)"
Write-Host 'Grant admin consent in your own tenant: Entra portal → App registrations → API permissions.'
Write-Host 'Customer tenants consent via:'
Write-Host "  https://login.microsoftonline.com/organizations/adminconsent?client_id=$($app.AppId)&redirect_uri=https://zerotrustassessment.limon-it.nl"
Write-Host 'Local test: python3 -m http.server 8080 → http://localhost:8080 (or ?demo=1 without any setup)'
