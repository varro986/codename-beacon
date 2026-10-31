BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Result.ps1')

    $script:schema = Get-Content -Raw -Path (Join-Path $PSScriptRoot '../specs/features/001-diagnostic-chain/contracts/result.schema.json')
    $script:now = [datetimeoffset]::new(2026, 10, 30, 9, 0, 0, [timespan]::FromHours(1))

    function Test-RunFile {
        param($Run)
        Test-Json -Json (Get-Content -Raw -LiteralPath $Run.Path) -Schema $script:schema -ErrorAction Stop
    }
}

Describe 'Run result' {
    BeforeEach {
        $script:config = @{ RunsFolder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); ResultSchemaVersion = 1 }
        $script:record = [ordered]@{ group = 'web'; target = 'portal'; check = 'port'; subject = '443'; status = 'OK'
            detail = 'Opened.'; durationMs = 3; data = @{ sourceAddress = '10.0.0.15' } }
    }

    It 'writes at once a file valid against the schema, incomplete and without end' {
        $run = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now

        $run.Path | Should -Be (Join-Path (Join-Path $script:config.RunsFolder '20261030_090000') 'result.json')
        Test-RunFile $run | Should -BeTrue
        $file = Get-Content -Raw -LiteralPath $run.Path | ConvertFrom-Json
        $file.run.complete | Should -BeFalse
        $file.run.endedAt | Should -BeNullOrEmpty
        (Get-Content -Raw -LiteralPath $run.Path) | Should -BeLike '*"startedAt": "2026-10-30T09:00:00+01:00"*'
        $file.run.environment | Should -Be 'test'
        $file.run.egress.hostName | Should -Be ([Environment]::MachineName)
        $file.run.beaconVersion | Should -Match '^\d+\.\d+\.\d+'
        $file.schemaVersion | Should -Be 1
        @($file.checks).Count | Should -Be 0
    }

    It 'accepts no environment for a single target' {
        $run = New-BeaconRun -Environment $null -Config $script:config -Now $script:now

        Test-RunFile $run | Should -BeTrue
        (Get-Content -Raw -LiteralPath $run.Path | ConvertFrom-Json).run.environment | Should -BeNullOrEmpty
    }

    It 'appends records and stays valid, then completes: complete only at the end' {
        $run = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now

        Add-BeaconRecords -Run $run -Records @($script:record)
        Add-BeaconRecords -Run $run -Records @($script:record, $script:record)
        Test-RunFile $run | Should -BeTrue
        $partial = Get-Content -Raw -LiteralPath $run.Path | ConvertFrom-Json
        @($partial.checks).Count | Should -Be 3
        $partial.run.complete | Should -BeFalse

        Complete-BeaconRun -Run $run -Now $script:now.AddSeconds(41)
        Test-RunFile $run | Should -BeTrue
        $done = Get-Content -Raw -LiteralPath $run.Path | ConvertFrom-Json
        $done.run.complete | Should -BeTrue
        (Get-Content -Raw -LiteralPath $run.Path) | Should -BeLike '*"endedAt": "2026-10-30T09:00:41+01:00"*'
        $done.checks[0].data.sourceAddress | Should -Be '10.0.0.15'
    }

    It 'does not rewrite the file when nothing changed' {
        $run = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now
        Add-BeaconRecords -Run $run -Records @()
        $before = (Get-Item -LiteralPath $run.Path).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50

        Add-BeaconRecords -Run $run -Records @()

        (Get-Item -LiteralPath $run.Path).LastWriteTimeUtc | Should -Be $before
    }

    It 'leaves no temp file in the run folder' {
        $run = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now
        Add-BeaconRecords -Run $run -Records @($script:record)
        Complete-BeaconRun -Run $run

        @(Get-ChildItem -LiteralPath (Split-Path $run.Path -Parent) -Force).Name | Should -Be @('result.json', 'run.log')
    }

    It 'gives a suffix to a folder that exists and leaves it untouched' {
        $first = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now
        Add-BeaconRecords -Run $first -Records @($script:record)
        $before = Get-Content -Raw -LiteralPath $first.Path

        $second = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now
        $third = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now

        (Split-Path (Split-Path $second.Path -Parent) -Leaf) | Should -Be '20261030_090000_2'
        (Split-Path (Split-Path $third.Path -Parent) -Leaf) | Should -Be '20261030_090000_3'
        Get-Content -Raw -LiteralPath $first.Path | Should -Be $before
    }

    It 'logs a start line, one line per record and an end line in run.log' {
        $run = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now
        $logPath = Join-Path (Split-Path $run.Path -Parent) 'run.log'
        $other = [ordered]@{ target = 'solo'; check = 'dns'; subject = 'portal'; status = 'FAIL'; detail = "Not found.`nSecond line." }
        Add-BeaconRecords -Run $run -Records @($script:record, $other)
        Complete-BeaconRun -Run $run -Now $script:now.AddSeconds(41)

        $bytes = [System.IO.File]::ReadAllBytes($logPath)
        $bytes[0] | Should -Not -Be 0xEF
        $lines = [System.IO.File]::ReadAllLines($logPath)
        $lines.Count | Should -Be 4
        $lines[0] | Should -BeLike '2026-10-30T09:00:00+01:00 START environment=test beacon=* host=*'
        $lines[1] | Should -Match '^\S+ OK web/portal port 443: Opened\.$'
        $lines[2] | Should -Match '^\S+ FAIL solo dns portal: Not found\. Second line\.$'
        $lines[3] | Should -Be '2026-10-30T09:00:41+01:00 END complete'
    }

    It 'appends to run.log, never rewrites it' {
        $run = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now
        $logPath = Join-Path (Split-Path $run.Path -Parent) 'run.log'
        $first = [System.IO.File]::ReadAllText($logPath)
        Add-BeaconRecords -Run $run -Records @($script:record)
        [System.IO.File]::ReadAllText($logPath) | Should -BeLike "$first*OK web/portal*"
    }

    It 'writes no log line with -WhatIf' {
        $run = New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now
        $logPath = Join-Path (Split-Path $run.Path -Parent) 'run.log'
        Add-BeaconRecords -Run $run -Records @($script:record) -WhatIf
        Complete-BeaconRun -Run $run -WhatIf
        @([System.IO.File]::ReadAllLines($logPath)).Count | Should -Be 1
    }

    It 'writes nothing with -WhatIf' {
        New-BeaconRun -Environment 'test' -Config $script:config -Now $script:now -WhatIf | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:config.RunsFolder | Should -BeFalse
    }
}
