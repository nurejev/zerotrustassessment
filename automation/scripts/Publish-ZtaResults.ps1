<#
.SYNOPSIS
    Uploads assessment output to the customer's own SharePoint site (app-only, Sites.Selected).
    Requires the ZTA-Automation certificate to be in the CurrentUser\My store (workflow does this).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$DriveId,
    [Parameter(Mandatory)] [string[]]$FilePath,      # files to upload
    [string]$Folder = ''                             # e.g. '2026' — created if missing
)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateSubjectName 'CN=ZeroTrustAssessment' -NoWelcome

foreach ($f in $FilePath) {
    if (-not (Test-Path $f)) { Write-Warning "skip missing: $f"; continue }
    $name = Split-Path $f -Leaf
    $dest = if ($Folder) { "$Folder/$name" } else { $name }
    $uri  = "v1.0/drives/$DriveId/root:/$([Uri]::EscapeDataString($dest).Replace('%2F','/')):/content"

    $size = (Get-Item $f).Length
    if ($size -lt 4MB) {
        Invoke-MgGraphRequest -Method PUT -Uri $uri -Body ([IO.File]::ReadAllBytes($f)) -ContentType 'application/octet-stream' | Out-Null
    } else {
        # large file (HTML reports can be big) → upload session in 8 MiB chunks
        $session = Invoke-MgGraphRequest -Method POST -Uri "v1.0/drives/$DriveId/root:/$dest:/createUploadSession" -Body '{}'
        $stream = [IO.File]::OpenRead($f); $chunk = 8MB; $pos = 0
        try {
            while ($pos -lt $size) {
                $len = [Math]::Min($chunk, $size - $pos)
                $buf = New-Object byte[] $len
                [void]$stream.Read($buf, 0, $len)
                Invoke-RestMethod -Method PUT -Uri $session.uploadUrl -Body $buf -Headers @{
                    'Content-Range' = "bytes $pos-$($pos+$len-1)/$size"
                } | Out-Null
                $pos += $len
            }
        } finally { $stream.Dispose() }
    }
    Write-Host "✓ uploaded $dest ($([Math]::Round($size/1KB)) KB)"
}
Disconnect-MgGraph | Out-Null
