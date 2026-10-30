BeforeAll {
    . (Join-Path $PSScriptRoot 'TestServer.ps1')
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:entry = Join-Path $script:root 'src/beacon.ps1'
    $script:schema = Get-Content -Raw -Path (Join-Path $script:root 'specs/features/001-diagnostic-chain/contracts/result.schema.json')
    Import-Module (Join-Path $script:root 'src/Beacon/Beacon.psd1') -Force

    # Loopback only: a proxy of the machine must not take the local requests elsewhere.
    $script:saved = @{}
    foreach ($name in 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'no_proxy', 'BEACON_RUNS') {
        $script:saved[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $null)
    }
    $env:BEACON_RUNS = Join-Path $TestDrive 'runs'

    $script:server = Open-TestServer -Routes @{ '/ok' = (Get-RawResponse -Line '200 OK'); '/auth' = (Get-RawResponse -Line '401 Unauthorized') }
    $script:open = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $script:open.Start()
    $closed = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $closed.Start()
    $script:closedPort = $closed.LocalEndpoint.Port
    $closed.Stop()

    function New-TestMatrix {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper writing into TestDrive.')]
        param([string] $Name, [string] $Targets)
        $path = Join-Path $TestDrive $Name
        Set-Content -Path $path -Encoding utf8NoBOM -Value @"
@{
    Environments = @{
        local = @{ Groups = @{ svc = @{ Targets = @( $Targets ) } } }
        other = @{ Groups = @{ x = @{ Targets = @( @{ Name = 'elsewhere'; Host = 'beacon-other.invalid' } ) } } }
    }
}
"@
        $path
    }

    $openTarget = "@{ Name = 'open'; Host = '127.0.0.1'; Ports = @($($script:open.LocalEndpoint.Port)); Urls = @('$($script:server.Url)/ok') }"
    $script:goodMatrix = New-TestMatrix -Name 'good.psd1' -Targets $openTarget
    $script:mixedMatrix = New-TestMatrix -Name 'mixed.psd1' -Targets @"
$openTarget
@{ Name = 'auth'; Host = '127.0.0.1'; Urls = @('$($script:server.Url)/auth'); Expect = @{ Http = 401 } }
@{ Name = 'closed'; Host = '127.0.0.1'; Ports = @($script:closedPort) }
@{ Name = 'ghost'; Host = 'beacon-test.invalid'; Ports = @(80) }
"@
    $script:badMatrix = New-TestMatrix -Name 'bad.psd1' -Targets "@{ Name = 'nohost'; Ports = @(80) }"

    $script:run = Invoke-Beacon -MatrixPath $script:mixedMatrix -Environment local -Quiet
    $script:checks = @($script:run.Result.checks)
    function Get-Check {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Used inside Where-Object.')]
        param([string] $Target, [string] $Check)
        @($script:checks | Where-Object { $_.target -eq $Target -and $_.check -eq $Check })
    }
}

AfterAll {
    Close-TestServer -Server $script:server
    $script:open.Stop()
    foreach ($name in $script:saved.Keys) { [Environment]::SetEnvironmentVariable($name, $script:saved[$name]) }
}

Describe 'Beacon end to end, against loopback' {
    It 'runs only the targets of the chosen environment' {
        ($script:checks.target | Sort-Object -Unique) | Should -Be @('auth', 'closed', 'ghost', 'open')
    }

    It 'reports a reachable target with every check passed' {
        (Get-Check open dns).status | Should -Be 'OK'
        (Get-Check open port).status | Should -Be @('OK', 'OK')
        (Get-Check open http).status | Should -Be 'OK'
        (Get-Check open route).status | Should -BeIn 'INFO', 'SKIP'
    }

    It 'passes an expected 401 and says it was expected' {
        (Get-Check auth http).status | Should -Be 'OK'
        (Get-Check auth http).detail | Should -BeLike '*as expected*'
    }

    It 'points to the port when it is refused' {
        $port = Get-Check closed port
        $port.status | Should -Be 'FAIL'
        $port.data.reason | Should -Be 'refused'
    }

    It 'points to DNS when the name does not resolve, and does not run the rest' {
        (Get-Check ghost dns).status | Should -Be 'FAIL'
        (Get-Check ghost port).status | Should -Be 'SKIP'
        (Get-Check ghost route).status | Should -Be 'SKIP'
    }

    It 'leaves a complete result, valid against the schema, with the machine and the source addresses' {
        $json = Get-Content -Raw -Path $script:run.Path
        $null = Test-Json -Json $json -Schema $script:schema -ErrorVariable invalid -ErrorAction SilentlyContinue
        @($invalid | ForEach-Object ToString) | Should -BeNullOrEmpty
        $result = $json | ConvertFrom-Json
        $result.run.complete | Should -BeTrue
        $result.run.environment | Should -Be 'local'
        $result.run.egress.hostName | Should -Be ([Environment]::MachineName)
        ($result.checks | Where-Object { $_.check -eq 'port' -and $_.status -ne 'SKIP' }).data.sourceAddress | Should -Not -BeNullOrEmpty
        $script:run.Path | Should -BeLike "$env:BEACON_RUNS*"
    }

    It 'runs a single target from the command line parameters' {
        $single = Invoke-Beacon -Target '127.0.0.1' -Port $script:open.LocalEndpoint.Port -Quiet
        $single.Failed | Should -BeFalse
        $single.Result.run.environment | Should -BeNullOrEmpty
        @($single.Result.checks).check | Should -Be @('dns', 'route', 'port')
    }
}

Describe 'Beacon exit codes' {
    It 'exits 0 when no check failed' {
        $null = & pwsh -NoProfile -File $script:entry -MatrixPath $script:goodMatrix -Environment local -Quiet
        $LASTEXITCODE | Should -Be 0
    }

    It 'exits 1 when a check failed' {
        $null = & pwsh -NoProfile -File $script:entry -MatrixPath $script:mixedMatrix -Environment local -Quiet
        $LASTEXITCODE | Should -Be 1
    }

    It 'exits 2 on a matrix that is not valid, naming the entry, before any check' {
        $before = @(Get-ChildItem -Path $env:BEACON_RUNS -Directory).Count
        $out = & pwsh -NoProfile -File $script:entry -MatrixPath $script:badMatrix -Environment local 6>&1 | Out-String
        $LASTEXITCODE | Should -Be 2
        $out | Should -BeLike '*Targets`[0`]*Host*'
        @(Get-ChildItem -Path $env:BEACON_RUNS -Directory).Count | Should -Be $before
    }

    It 'exits 2 on parameters that are not valid' {
        $null = & pwsh -NoProfile -File $script:entry -Target '127.0.0.1' -Port 70000 -Quiet 6>&1
        $LASTEXITCODE | Should -Be 2
    }
}
