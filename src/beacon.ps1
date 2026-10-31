#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Beacon from the command line: runs the diagnostic chain and shows where traffic stops.
.DESCRIPTION
    Exit code: 0 when no check failed (warnings included), 1 when at least one failed, 2 when the matrix or the
    parameters are not valid. Results go to beacon-runs/ under the working directory, or to BEACON_RUNS.
.EXAMPLE
    pwsh -NoProfile -File src/beacon.ps1 -MatrixPath ./matrix.psd1 -Environment test
.EXAMPLE
    pwsh -NoProfile -File src/beacon.ps1 -Target portal.example.com -Port 443 -Url https://portal.example.com/health
#>
#Requires -Version 7.4
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Command line entry: the input error is for people.')]
[CmdletBinding()]
param(
    [string] $MatrixPath,
    [string] $Environment,
    [string] $Target,
    # Text here, converted below: a value that is not a number is an input error (exit 2), not a binding error.
    [string[]] $Port,
    [string[]] $Url,
    [string[]] $ExpectedStatus,
    [string] $Proxy,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'

# Missing or conflicting parameters are input errors: exit 2 here, the only place where exit codes exist.
$usage = if ($Target -and ($MatrixPath -or $Environment)) {
    'Use either -MatrixPath with -Environment, or -Target: not both.'
}
elseif ($Target) { $null }
elseif (-not $MatrixPath -or -not $Environment) {
    'Missing parameters: give -MatrixPath and -Environment, or -Target (with optional -Port, -Url, -ExpectedStatus, -Proxy).'
}
elseif ($Port -or $Url -or $ExpectedStatus -or $Proxy) {
    '-Port, -Url, -ExpectedStatus and -Proxy go with -Target, not with -MatrixPath.'
}
$numbers = @{}
foreach ($name in 'Port', 'ExpectedStatus') {
    $values = foreach ($text in (Get-Variable $name -ValueOnly)) {
        $number = 0
        if ([int]::TryParse($text, [ref] $number)) { $number }
        else { $usage = "-$name '$text' is not a number."; break }
    }
    $numbers[$name] = [int[]] @($values)
}
if ($usage) {
    Write-Host $usage -ForegroundColor Red
    exit 2
}

Import-Module (Join-Path $PSScriptRoot 'Beacon/Beacon.psd1') -Force

$arguments = @{ Quiet = $Quiet }
if ($Target) {
    $arguments.Target = $Target
    if ($Port) { $arguments.Port = $numbers.Port }
    if ($Url) { $arguments.Url = $Url }
    if ($ExpectedStatus) { $arguments.ExpectedStatus = $numbers.ExpectedStatus }
    if ($Proxy) { $arguments.Proxy = $Proxy }
}
else {
    $arguments.MatrixPath = $MatrixPath
    $arguments.Environment = $Environment
}

try {
    $run = Invoke-Beacon @arguments
}
catch {
    if ($_.FullyQualifiedErrorId -notlike 'BeaconInput*') { throw }
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 2
}
Write-Host "Result: $($run.Path)"
exit ($run.Failed ? 1 : 0)
