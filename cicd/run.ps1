#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Local checks of Beacon: lint, then tests (contracts included). Run before every push; the remote CI runs this same
    script.
.PARAMETER InstallTools
    Installs the missing tools for the current user, at their minimum version, before the checks.
.EXAMPLE
    pwsh -NoProfile -File cicd/run.ps1
.EXAMPLE
    pwsh -NoProfile -File cicd/run.ps1 -InstallTools
#>
#Requires -Version 7.4
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console runner: coloured output for people.')]
[CmdletBinding()]
param(
    [switch] $InstallTools
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tools = @{ Pester = '5.5.0'; PSScriptAnalyzer = '1.21.0' }

$missing = foreach ($name in $tools.Keys) {
    $found = Get-Module -ListAvailable -Name $name | Where-Object Version -GE ([version] $tools[$name])
    if (-not $found) { $name }
}
if ($missing -and $InstallTools) {
    foreach ($name in $missing) {
        Write-Host "Installing $name >= $($tools[$name]) for the current user"
        Install-PSResource -Name $name -Version "[$($tools[$name]),)" -Scope CurrentUser -TrustRepository
    }
}
elseif ($missing) {
    Write-Host "Missing tools: $($missing -join ', '). Run again with -InstallTools, or install them yourself." -ForegroundColor Red
    exit 1
}

$failed = [System.Collections.Generic.List[string]]::new()

Write-Host '== lint'
Import-Module PSScriptAnalyzer -MinimumVersion $tools.PSScriptAnalyzer
$settings = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'
$issues = foreach ($folder in 'src', 'tests', 'cicd') {
    Invoke-ScriptAnalyzer -Path (Join-Path $root $folder) -Recurse -Settings $settings
}
if ($issues) {
    $issues | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String -Width 200 | Write-Host
    $failed.Add("lint: $(@($issues).Count) issues")
}
else {
    Write-Host 'lint: no issues'
}

Write-Host '== tests'
Import-Module Pester -MinimumVersion $tools.Pester
$config = New-PesterConfiguration
$config.Run.Path = Join-Path $root 'tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
$result = Invoke-Pester -Configuration $config
if ($result.Result -ne 'Passed') {
    $failed.Add("tests: $($result.FailedCount) failed")
}

if ($failed.Count) {
    Write-Host "cicd FAILED: $($failed -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "cicd OK: lint clean, $($result.PassedCount) tests passed" -ForegroundColor Green
# Explicit: the CI shell otherwise ends with the last native exit code (the end-to-end tests leave 1 or 2).
exit 0
