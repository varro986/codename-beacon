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
[CmdletBinding(DefaultParameterSetName = 'Matrix')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Matrix')] [string] $MatrixPath,
    [Parameter(Mandatory, ParameterSetName = 'Matrix')] [string] $Environment,
    [Parameter(Mandatory, ParameterSetName = 'Target')] [string] $Target,
    [Parameter(ParameterSetName = 'Target')] [int[]] $Port,
    [Parameter(ParameterSetName = 'Target')] [string[]] $Url,
    [Parameter(ParameterSetName = 'Target')] [int[]] $ExpectedStatus,
    [Parameter(ParameterSetName = 'Target')] [string] $Proxy,
    [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Beacon/Beacon.psd1') -Force

try {
    $run = Invoke-Beacon @PSBoundParameters
}
catch {
    if ($_.FullyQualifiedErrorId -notlike 'BeaconInput*') { throw }
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 2
}
Write-Host "Result: $($run.Path)"
exit ($run.Failed ? 1 : 0)
