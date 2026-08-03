<#
.SYNOPSIS
    Drift comparison between two reduced results JSONs (see Export-ZtaResultsJson.ps1).
    Writes a Markdown drift report and sets GitHub Actions outputs (regressions count).
#>
[CmdletBinding()]
param(
    [string]$PreviousJsonPath,                       # may not exist on the first run
    [Parameter(Mandatory)] [string]$CurrentJsonPath,
    [Parameter(Mandatory)] [string]$OutMarkdownPath
)
$ErrorActionPreference = 'Stop'

$cur = Get-Content $CurrentJsonPath -Raw | ConvertFrom-Json
$md  = "# Zero Trust Assessment — drift report`n`n**Tenant:** $($cur.tenantName) · **Run:** $($cur.executedAt)`n`n"
$regressions = 0

if (-not $PreviousJsonPath -or -not (Test-Path $PreviousJsonPath)) {
    $md += "_First run — no previous results to compare. This run is the baseline._`n"
} else {
    $prev    = Get-Content $PreviousJsonPath -Raw | ConvertFrom-Json
    $prevMap = @{}; $prev.tests | ForEach-Object { $prevMap[[string]$_.id] = $_ }
    $curIds  = @{};  $cur.tests | ForEach-Object { $curIds[[string]$_.id] = $true }

    $regressed = @(); $fixed = @(); $new = @(); $removed = @()
    foreach ($t in $cur.tests) {
        $p = $prevMap[[string]$t.id]
        if (-not $p) { $new += $t; continue }
        if ($p.status -ne $t.status) {
            if ($t.status -eq 'Failed') { $regressed += $t }
            elseif ($p.status -eq 'Failed' -and $t.status -eq 'Passed') { $fixed += $t }
        }
    }
    $removed = @($prev.tests | Where-Object { -not $curIds[[string]$_.id] })
    $regressions = $regressed.Count

    $md += "| | Count |`n|---|---|`n"
    $md += "| ❌ Regressed (was OK, now **Failed**) | $($regressed.Count) |`n"
    $md += "| ✅ Fixed (was Failed, now Passed) | $($fixed.Count) |`n"
    $md += "| 🆕 New checks | $($new.Count) |`n"
    $md += "| ➖ Removed checks | $($removed.Count) |`n`n"

    foreach ($section in @(
        @{ t = '## ❌ Regressed';  items = $regressed },
        @{ t = '## ✅ Fixed';      items = $fixed },
        @{ t = '## 🆕 New checks'; items = $new }
    )) {
        if ($section.items.Count) {
            $md += "$($section.t)`n`n| Test | Pillar | Risk | Status |`n|---|---|---|---|`n"
            foreach ($t in $section.items) { $md += "| ZT-$($t.id) $($t.title) | $($t.pillar) | $($t.risk) | $($t.status) |`n" }
            $md += "`n"
        }
    }
}

$passed = @($cur.tests | Where-Object status -eq 'Passed').Count
$failed = @($cur.tests | Where-Object status -eq 'Failed').Count
$md += "`n**Totals:** $passed passed · $failed failed · $($cur.tests.Count) checks`n"

New-Item -ItemType Directory -Force -Path (Split-Path $OutMarkdownPath) | Out-Null
$md | Set-Content -Path $OutMarkdownPath -Encoding UTF8
Write-Host "✓ Drift report → $OutMarkdownPath ($regressions regressions)"

if ($env:GITHUB_OUTPUT) {
    "regressions=$regressions" | Add-Content $env:GITHUB_OUTPUT
    "passed=$passed"           | Add-Content $env:GITHUB_OUTPUT
    "failed=$failed"           | Add-Content $env:GITHUB_OUTPUT
}
