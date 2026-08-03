<#
.SYNOPSIS
    Onboards ONE customer tenant for scheduled Zero Trust Assessment runs.

.DESCRIPTION
    Admin consent alone only creates the service principal + grants API permissions — it can NOT
    create a SharePoint site. This script is the missing half. Run it right after consent, signed
    in as an admin OF THE CUSTOMER TENANT (their Global Admin, or you via GDAP). It:

      1. Verifies admin consent was granted (prints the consent URL and waits if not).
      2. Creates the delivery site — a private M365 group 'Zero Trust Assessment' whose team site
         becomes the report library — or reuses an existing site via -ExistingSiteUrl.
      3. Grants ZTA-Automation WRITE on ONLY that site (Sites.Selected grant).
      4. Assigns the service principal the Global Reader directory role (read access for
         app-only Exchange Online / Security & Compliance cmdlets).
      5. Uploads ONBOARDING-TEST.txt to prove the delivery path works.
      6. Prints the customers.json entry.

    Delegated scopes requested for THIS SESSION ONLY (nothing standing is added):
      Group.ReadWrite.All, Sites.FullControl.All, RoleManagement.ReadWrite.Directory,
      Application.Read.All

.EXAMPLE
    ./New-ZtaCustomerOnboarding.ps1 -CustomerTenantId contoso.onmicrosoft.com -ClientId <ZTA-Automation appId>
    ./New-ZtaCustomerOnboarding.ps1 -CustomerTenantId contoso.nl -ClientId <appId> -ExistingSiteUrl https://contoso.sharepoint.com/sites/security
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CustomerTenantId,
    [Parameter(Mandatory)] [string]$ClientId,          # ZTA-Automation (Limon-IT) application id
    [string]$CustomerName,
    [string]$SiteName = 'Zero Trust Assessment',
    [string]$ExistingSiteUrl,                          # reuse a site instead of creating one
    [switch]$SkipRoleAssignment
)

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Applications -ErrorAction Stop

# ---------- 0. consent ----------
$consentUrl = "https://login.microsoftonline.com/$CustomerTenantId/adminconsent?client_id=$ClientId"
Write-Host "If admin consent is not yet granted, open (as customer Global Admin):`n  $consentUrl`n"

Connect-MgGraph -TenantId $CustomerTenantId -NoWelcome -Scopes @(
    'Group.ReadWrite.All','Sites.FullControl.All','RoleManagement.ReadWrite.Directory','Application.Read.All')

$sp = Get-MgServicePrincipal -Filter "appId eq '$ClientId'"
while (-not $sp) {
    Read-Host 'Service principal not found — grant consent via the URL above, then press Enter to re-check'
    $sp = Get-MgServicePrincipal -Filter "appId eq '$ClientId'"
}
Write-Host "✓ Consent OK — app '$($sp.DisplayName)', service principal $($sp.Id)"
if ($sp.DisplayName -notlike '*Automation*') {
    Write-Warning "'$($sp.DisplayName)' does not look like the ZTA-Automation app. If this is the delegated"
    Write-Warning 'web app (ZTA (Limon-IT)), abort and re-run with the ZTA-Automation appId — the scheduled'
    Write-Warning 'runs authenticate as ZTA-Automation and need the grant/role on THAT service principal.'
    if ((Read-Host 'Continue anyway? (y/N)') -ne 'y') { return }
}

# ---------- 1. site ----------
if ($ExistingSiteUrl) {
    $u = [Uri]$ExistingSiteUrl
    $site = Invoke-MgGraphRequest -Method GET -Uri "v1.0/sites/$($u.Host):$($u.AbsolutePath)"
    Write-Host "✓ Reusing site: $($site.webUrl)"
} else {
    $nick = ($SiteName -replace '[^A-Za-z0-9]', '')
    $group = Get-MgGroup -Filter "mailNickname eq '$nick'" | Select-Object -First 1
    if (-not $group) {
        $group = New-MgGroup -DisplayName $SiteName -MailNickname $nick -MailEnabled:$true `
            -SecurityEnabled:$false -GroupTypes @('Unified') -Visibility 'Private' `
            -Description 'Zero Trust Assessment reports — delivered by Limon-IT. Contains sensitive tenant security information.'
        Write-Host "✓ Created private M365 group '$SiteName' — waiting for site provisioning…"
    } else { Write-Host "✓ Group '$SiteName' already exists" }

    $site = $null
    foreach ($i in 1..12) {   # site provisioning can take a minute
        try { $site = Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$($group.Id)/sites/root"; break }
        catch { Start-Sleep -Seconds 10 }
    }
    if (-not $site) { throw 'Site was not provisioned in time — re-run the script in a few minutes.' }
    Write-Host "✓ Site ready: $($site.webUrl)"
    Write-Host '  ➜ Add the customer contacts who may read reports as MEMBERS of this private group.'
}

$drive = Invoke-MgGraphRequest -Method GET -Uri "v1.0/sites/$($site.id)/drive"

# ---------- 2. Sites.Selected grant (write on ONLY this site) ----------
$existing = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/sites/$($site.id)/permissions").value |
    Where-Object { $_.grantedToIdentities.application.id -eq $ClientId }
if (-not $existing) {
    Invoke-MgGraphRequest -Method POST -Uri "v1.0/sites/$($site.id)/permissions" -Body (@{
        roles = @('write')
        grantedToIdentities = @(@{ application = @{ id = $ClientId; displayName = 'ZTA-Automation (Limon-IT)' } })
    } | ConvertTo-Json -Depth 5) | Out-Null
    Write-Host '✓ Sites.Selected grant: ZTA-Automation → write on this site only'
} else { Write-Host '✓ Sites.Selected grant already present' }

# ---------- 3. directory role for app-only EXO / Security & Compliance ----------
if (-not $SkipRoleAssignment) {
    $roleTemplateId = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'   # Global Reader
    $body = @{ '@odata.type' = '#microsoft.graph.unifiedRoleAssignment'
               principalId = $sp.Id; roleDefinitionId = $roleTemplateId; directoryScopeId = '/' }
    try {
        Invoke-MgGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignments' -Body ($body | ConvertTo-Json) | Out-Null
        Write-Host '✓ Global Reader assigned to the service principal'
    } catch {
        if ($_ -match 'exists') { Write-Host '✓ Global Reader already assigned' } else { throw }
    }
    Write-Host '  Note: if SharePoint-specific checks fail app-only, upstream requires the SharePoint'
    Write-Host '  Administrator role as well — add it only if needed (see automation/README.md).'
}

# ---------- 4. test upload ----------
$bytes = [Text.Encoding]::UTF8.GetBytes("Zero Trust Assessment delivery test — $(Get-Date -Format s). Safe to delete.")
Invoke-MgGraphRequest -Method PUT -Uri "v1.0/drives/$($drive.id)/root:/ONBOARDING-TEST.txt:/content" `
    -Body $bytes -ContentType 'text/plain' | Out-Null
Write-Host '✓ Test upload OK (ONBOARDING-TEST.txt — delivered with your delegated session;'
Write-Host '  the first scheduled run validates the app-only path end-to-end)'

# ---------- 5. customers.json entry ----------
$org = (Invoke-MgGraphRequest -Method GET -Uri 'v1.0/organization').value[0]
$entry = [ordered]@{
    name     = if ($CustomerName) { $CustomerName } else { $org.displayName }
    tenantId = $org.id
    siteId   = $site.id
    driveId  = $drive.id
    siteUrl  = $site.webUrl
    schedule = 'monthly'    # or 'weekly' — the workflow filters on this
}
Write-Host "`n=== Add this to automation/customers.json ===" -ForegroundColor Green
$entry | ConvertTo-Json

Write-Host "`nOptional (Azure log-export checks): give the service principal 'Reader' on the customer subscription(s):"
Write-Host "  az role assignment create --assignee $($sp.Id) --role Reader --scope /subscriptions/<subscription-id>"
