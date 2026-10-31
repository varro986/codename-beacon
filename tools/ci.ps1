# ci.ps1 - the product's local CI: runs the steps of cicd/steps.json, on this machine, before every push. The remote
# CI calls the same runner. Each step runs in its own pwsh process, in its own folder; the end result is a summary.
#
# Usage (from anywhere):
#   pwsh -NoProfile -File tools/ci.ps1          run every step
#   pwsh -NoProfile -File tools/ci.ps1 -List    list the steps without running them (dry run)
# cicd/steps.json: { "steps": [ { "name": "...", "dir": "relative to the repo root, default .", "run": "pwsh command" } ] }
# Exit codes: 0 all steps ok; 1 at least one step failed. PowerShell 7 (pwsh), ASCII file.
param([switch]$List)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$file = Join-Path $repo (Join-Path "cicd" "steps.json")
if (-not (Test-Path -LiteralPath $file)) { Write-Host "missing $file"; exit 1 }
$steps = @((Get-Content -LiteralPath $file -Raw | ConvertFrom-Json).steps)

if ($List) { foreach ($s in $steps) { "- $($s.name)" }; exit 0 }

$pwsh = (Get-Process -Id $PID).Path
$failed = 0
foreach ($s in $steps) {
  Write-Host "`n=== $($s.name)" -ForegroundColor Cyan
  Push-Location -LiteralPath (Join-Path $repo $(if ($s.dir) { $s.dir } else { "." }))
  try { & $pwsh -NoProfile -Command $s.run; $rc = $LASTEXITCODE } finally { Pop-Location }
  if ($rc -ne 0) { $failed++; Write-Host "FAILED ($rc): $($s.name)" -ForegroundColor Red }
}
"steps: $($steps.Count); failed $failed"
if ($failed) { exit 1 }
exit 0
