function Invoke-Beacon {
    <#
    .SYNOPSIS
        Runs the diagnostic chain on the targets of a matrix environment, or on one target, and reports where traffic
        stops.
    .DESCRIPTION
        Writes the run result (ADR 0003) to its own folder under the runs folder, shows the console report and returns
        the run: Path, Result and Failed (true when at least one check failed). An input error (matrix or parameters)
        stops before any check with the error id BeaconInput.
    .EXAMPLE
        Invoke-Beacon -MatrixPath ./matrix.psd1 -Environment test
    .EXAMPLE
        Invoke-Beacon -Target portal.example.com -Port 443 -Url https://portal.example.com/health
    #>
    [CmdletBinding(DefaultParameterSetName = 'Matrix')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Matrix')] [string] $MatrixPath,
        [Parameter(Mandatory, ParameterSetName = 'Matrix')] [string] $Environment,
        [Parameter(Mandatory, ParameterSetName = 'Target')] [string] $Target,
        [Parameter(ParameterSetName = 'Target')] [int[]] $Port = @(),
        [Parameter(ParameterSetName = 'Target')] [string[]] $Url = @(),
        [Parameter(ParameterSetName = 'Target')] [int[]] $ExpectedStatus = @(),
        [Parameter(ParameterSetName = 'Target')] [string] $Proxy,
        [switch] $Quiet
    )

    $config = Get-BeaconConfig
    if ($PSCmdlet.ParameterSetName -eq 'Matrix') {
        $matrix = Read-BeaconMatrix -Path $MatrixPath -Config $config
        $selection = Get-BeaconTargets -Matrix $matrix -Environment $Environment
        $runEnvironment = $Environment
    }
    else {
        $problems = Test-BeaconSingleTarget -Port $Port -Url $Url -ExpectedStatus $ExpectedStatus -Proxy $Proxy -Config $config
        if ($problems) { $PSCmdlet.ThrowTerminatingError((New-BeaconInputError -Message ($problems -join "`n"))) }
        $selection = @{
            Proxy   = if ($Proxy) { $Proxy } else { $null }
            Targets = @(@{
                    Group             = $null
                    Name              = $Target
                    Host              = $Target
                    ExpectedAddresses = @()
                    Ports             = [int[]] @($Port | Sort-Object -Unique)
                    Urls              = $Url
                    ExpectedStatus    = $ExpectedStatus
                    SecretEnv         = $null
                })
        }
        $runEnvironment = $null
    }

    $run = New-BeaconRun -Environment $runEnvironment -Config $config
    foreach ($item in $selection.Targets) {
        $chain = @{ Target = $item; Config = $config }
        if ($selection.Proxy) { $chain.MatrixProxy = $selection.Proxy }
        Add-BeaconRecords -Run $run -Records @(Invoke-BeaconChain @chain)
    }
    Complete-BeaconRun -Run $run

    if (-not $Quiet) { Write-BeaconReport -Result $run.Result -Config $config }
    [pscustomobject]@{
        Path   = $run.Path
        Result = $run.Result
        Failed = [bool] ($run.Result.checks | Where-Object { $_.status -eq 'FAIL' })
    }
}

function Test-BeaconSingleTarget {
    <# The problems of a single target given on the command line, the same rules as the matrix. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [int[]] $Port,
        [string[]] $Url,
        [int[]] $ExpectedStatus,
        [string] $Proxy,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    # The rules live in Matrix.ps1: the command line target is checked as a matrix target.
    $target = @{ Name = 'target'; Host = 'target' }
    if ($Port) { $target.Ports = @($Port) }
    if ($Url) { $target.Urls = @($Url) }
    if ($ExpectedStatus) { $target.Expect = @{ Http = @($ExpectedStatus) } }
    Test-BeaconTarget -Path 'Parameters' -Target $target -Config $Config

    if ($Proxy) {
        $proxyProblem = Test-BeaconProxy -Value $Proxy
        if ($proxyProblem) { "Parameters.Proxy: $proxyProblem" }
    }
}
