<#
.SYNOPSIS
    Extracts the results JSON out of the generated ZeroTrustAssessmentReport.html and reduces it
    to a compact per-test status summary used for git history + drift comparison.

.NOTES
    The report embeds its data as `reportData= { ... }` (see upstream Get-HtmlReport.ps1).
    The full JSON contains evidence tables (sensitive) — only the reduced summary is committed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ReportHtmlPath,
    [Parameter(Mandatory)] [string]$OutJsonPath
)
$ErrorActionPreference = 'Stop'

$html  = Get-Content -Path $ReportHtmlPath -Raw
$start = $html.IndexOf('reportData=')
if ($start -lt 0) { throw "reportData marker not found in $ReportHtmlPath — upstream template changed?" }
$start += 'reportData='.Length
$end   = $html.IndexOf('</script>', $start)
$raw   = $html.Substring($start, $end - $start).Trim().TrimEnd(';')

$data = $raw | ConvertFrom-Json

# Reduced, low-sensitivity summary: one line per test. Verify property names against the
# upstream report schema on first real run (TODO: pin to upstream release).
$summary = [ordered]@{
    tenantId   = $data.TenantId
    tenantName = $data.TenantName
    executedAt = $data.ExecutedAt
    module     = $data.CurrentVersion
    tests      = @($data.Tests | ForEach-Object {
        [ordered]@{
            id     = $_.TestId
            title  = $_.TestTitle
            pillar = $_.TestPillar
            risk   = $_.TestRisk
            status = $_.TestStatus     # Passed / Failed / Investigate / Skipped
        }
    })
}

New-Item -ItemType Directory -Force -Path (Split-Path $OutJsonPath) | Out-Null
$summary | ConvertTo-Json -Depth 4 | Set-Content -Path $OutJsonPath -Encoding UTF8
Write-Host "✓ $(($summary.tests).Count) test results → $OutJsonPath"
