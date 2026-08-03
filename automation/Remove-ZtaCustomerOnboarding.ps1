<#
.SYNOPSIS
    Reverts everything New-ZtaCustomerOnboarding.ps1 did in a customer tenant.

.DESCRIPTION
    Run signed in as an admin of the CUSTOMER tenant. Removes, in order:
      1. All directory role assignments of the given app's service principal (e.g. Global Reader).
      2. The app's Sites.Selected permission grant on the 'Zero Trust Assessment' site.
      3. With -DeleteSite: the private M365 group + its team site (soft-deleted, restorable ~30 days).
      4. With -RemoveServicePrincipal: the service principal itself (= revokes the admin consent).

.EXAMPLE
    ./Remove-ZtaCustomerOnboarding.ps1 -CustomerTenantId devcf.onmicrosoft.com -ClientId <appId> -DeleteSite
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CustomerTenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [string]$SiteName = 'Zero Trust Assessment',
    [switch]$DeleteSite,
    [switch]$RemoveServicePrincipal
)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Applications -ErrorAction Stop

Connect-MgGraph -TenantId $CustomerTenantId -NoWelcome -Scopes @(
    'Group.ReadWrite.All','Sites.FullControl.All','RoleManagement.ReadWrite.Directory','Application.ReadWrite.All')

$sp = Get-MgServicePrincipal -Filter "appId eq '$ClientId'"
if (-not $sp) { Write-Host "No service principal for $ClientId — nothing consented here."; return }
Write-Host "App: '$($sp.DisplayName)' · SP $($sp.Id)"

# 1. role assignments
$roles = Invoke-MgGraphRequest -Method GET -Uri "v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($sp.Id)'"
foreach ($r in $roles.value) {
    Invoke-MgGraphRequest -Method DELETE -Uri "v1.0/roleManagement/directory/roleAssignments/$($r.id)" | Out-Null
    Write-Host "✓ removed role assignment $($r.roleDefinitionId)"
}
if (-not $roles.value) { Write-Host '  no role assignments found' }

# 2. site permission grant (+ 3. site itself)
$nick = ($SiteName -replace '[^A-Za-z0-9]', '')
$group = Get-MgGroup -Filter "mailNickname eq '$nick'" | Select-Object -First 1
if ($group) {
    try {
        $site = Invoke-MgGraphRequest -Method GET -Uri "v1.0/groups/$($group.Id)/sites/root"
        $perms = (Invoke-MgGraphRequest -Method GET -Uri "v1.0/sites/$($site.id)/permissions").value |
            Where-Object { $_.grantedToIdentities.application.id -eq $ClientId }
        foreach ($p in $perms) {
            Invoke-MgGraphRequest -Method DELETE -Uri "v1.0/sites/$($site.id)/permissions/$($p.id)" | Out-Null
            Write-Host "✓ removed Sites.Selected grant on $($site.webUrl)"
        }
        if (-not $perms) { Write-Host '  no site grant found for this app' }
    } catch { Write-Warning "site lookup: $_" }
    if ($DeleteSite) {
        Remove-MgGroup -GroupId $group.Id
        Write-Host "✓ deleted group + site '$SiteName' (soft-deleted, restorable ~30 days in Entra → Groups → Deleted groups)"
    } else {
        Write-Host "  site kept (use -DeleteSite to remove group '$SiteName' and its site)"
    }
} else { Write-Host "  no group '$SiteName' found" }

# 4. consent
if ($RemoveServicePrincipal) {
    Remove-MgServicePrincipal -ServicePrincipalId $sp.Id
    Write-Host '✓ service principal removed — admin consent for this app is revoked in this tenant'
} else {
    Write-Host '  service principal kept (use -RemoveServicePrincipal to also revoke consent)'
}
Write-Host 'Done.'
