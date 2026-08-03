<#
.SYNOPSIS
    Creates the ZTA-Automation (Limon-IT) app registration for unattended, multi-customer
    Zero Trust Assessment runs (app-only Certificate-Based Authentication).

.DESCRIPTION
    Run ONCE in the Limon-IT tenant. Creates (or updates) a multi-tenant app registration with:
      - APPLICATION permissions: the app-only twins of the delegated scopes the ZeroTrustAssessment
        module requests, plus Sites.Selected (report delivery) and Exchange.ManageAsApp
        (app-only Exchange Online / Security & Compliance).
      - A self-signed certificate (CN=ZeroTrustAssessment, 1 year), private key exported to PFX.
    The PFX (base64) goes into a GitHub Actions environment secret; the public key stays on the app.

    Style/flow mirrors New-EncaAppRegistration.ps1 from the ENCA repo.

.EXAMPLE
    ./New-ZtaAutomationApp.ps1
    ./New-ZtaAutomationApp.ps1 -AppObjectId <object-id>   # re-run against the exact registration
#>
[CmdletBinding()]
param(
    [string]$DisplayName = 'ZTA-Automation (Limon-IT)',
    [string]$AppObjectId,
    [string]$CertSubject = 'CN=ZeroTrustAssessment',
    [string]$PfxOutPath = './zta-automation.pfx',
    [int]$CertValidityMonths = 12
)

$ErrorActionPreference = 'Stop'

# --- Graph application permissions (app-only twins of the module's delegated scopes) ---
# NOTE: verify against upstream on each release: Connect-ZtAssessment scope list.
$graphAppPermissions = @(
    'AuditLog.Read.All'
    'CrossTenantInformation.ReadBasic.All'
    'DeviceManagementApps.Read.All'
    'DeviceManagementConfiguration.Read.All'
    'DeviceManagementManagedDevices.Read.All'
    'DeviceManagementRBAC.Read.All'
    'DeviceManagementServiceConfig.Read.All'
    'Directory.Read.All'
    'DirectoryRecommendations.Read.All'
    'EntitlementManagement.Read.All'
    'IdentityRiskEvent.Read.All'
    'IdentityRiskyUser.Read.All'
    'IdentityRiskyServicePrincipal.Read.All'
    'NetworkAccess.Read.All'
    'Policy.Read.All'
    'Policy.Read.ConditionalAccess'
    'Policy.Read.PermissionGrant'
    'PrivilegedAccess.Read.AzureAD'
    'Reports.Read.All'
    'RoleManagement.Read.All'
    'UserAuthenticationMethod.Read.All'
    'Sites.Selected'                       # report delivery into the customer's SharePoint site
)
# Office 365 Exchange Online resource API — required for app-only EXO + Security & Compliance
$exoApiAppId      = '00000002-0000-0ff1-ce00-000000000000'
$exoAppPermission = 'Exchange.ManageAsApp'

Import-Module Microsoft.Graph.Applications -ErrorAction Stop
if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes 'Application.ReadWrite.All','Directory.Read.All' -NoWelcome
}

# --- resolve permission ids ---
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$exoSp   = Get-MgServicePrincipal -Filter "appId eq '$exoApiAppId'"

$graphRoleIds = foreach ($p in $graphAppPermissions) {
    $role = $graphSp.AppRoles | Where-Object Value -eq $p
    if (-not $role) { Write-Warning "Graph application permission not found: $p (upstream drift? fix manually)"; continue }
    @{ Id = $role.Id; Type = 'Role' }
}
$exoRole = $exoSp.AppRoles | Where-Object Value -eq $exoAppPermission

$requiredResourceAccess = @(
    @{ ResourceAppId = '00000003-0000-0000-c000-000000000000'; ResourceAccess = @($graphRoleIds) }
    @{ ResourceAppId = $exoApiAppId; ResourceAccess = @(@{ Id = $exoRole.Id; Type = 'Role' }) }
)

# --- create or update the app ---
$app = if ($AppObjectId) { Get-MgApplication -ApplicationId $AppObjectId }
       else { Get-MgApplication -Filter "displayName eq '$DisplayName'" | Select-Object -First 1 }

$params = @{
    DisplayName            = $DisplayName
    SignInAudience         = 'AzureADMultipleOrgs'     # multi-tenant
    RequiredResourceAccess = $requiredResourceAccess
    Web                    = @{ RedirectUris = @() }   # no interactive flows on this app
}
if ($app) {
    Update-MgApplication -ApplicationId $app.Id @params
    Write-Host "Updated existing app: $($app.AppId)"
} else {
    $app = New-MgApplication @params
    Write-Host "Created app: $($app.AppId)"
}

# --- certificate (self-signed, exportable) ---
$cert = New-SelfSignedCertificate -Subject $CertSubject `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 `
    -NotAfter (Get-Date).AddMonths($CertValidityMonths)

Update-MgApplication -ApplicationId $app.Id -KeyCredentials @(@{
    Type  = 'AsymmetricX509Cert'; Usage = 'Verify'
    Key   = $cert.RawData
    DisplayName = "$CertSubject $(Get-Date -Format yyyy-MM)"
})

$pfxPassword = Read-Host -AsSecureString -Prompt 'PFX password (stored nowhere — remember it for the GitHub secret step)'
Export-PfxCertificate -Cert $cert -FilePath $PfxOutPath -Password $pfxPassword | Out-Null

Write-Host ''
Write-Host '================ NEXT STEPS ================'
Write-Host "1. GitHub repo (PRIVATE) → Settings → Environments → 'assessment' → secrets:"
Write-Host "     ZTA_CLIENT_ID   = $($app.AppId)"
Write-Host "     ZTA_PFX_BASE64  = [System.Convert]::ToBase64String([IO.File]::ReadAllBytes('$PfxOutPath'))"
Write-Host '     ZTA_PFX_PASSWORD = <the password you just chose>'
Write-Host "2. Delete $PfxOutPath after uploading the secret."
Write-Host "3. Cert expires $($cert.NotAfter.ToString('yyyy-MM-dd')) — calendar reminder for rotation."
Write-Host '4. Onboard each customer with New-ZtaCustomerOnboarding.ps1.'
