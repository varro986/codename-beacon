BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Report.ps1')
    $script:examplePath = Join-Path $PSScriptRoot '../specs/features/001-diagnostic-chain/contracts/result.example.json'
    $script:fromJson = Get-Content -Raw -Path $examplePath | ConvertFrom-Json
    $script:fromHashtable = Get-Content -Raw -Path $examplePath | ConvertFrom-Json -AsHashtable
}

Describe 'Get-BeaconTotals' {
    It 'counts per status overall, leaving INFO out and counting SKIP' {
        $totals = Get-BeaconTotals -Result $fromJson
        $totals.Overall.OK | Should -Be 8
        $totals.Overall.FAIL | Should -Be 3
        $totals.Overall.SKIP | Should -Be 2
        $totals.Overall.WARN | Should -Be 0
        $totals.Overall.Contains('INFO') | Should -BeFalse
    }

    It 'counts per group and per target' {
        $totals = Get-BeaconTotals -Result $fromJson
        $totals.Groups['web'].FAIL | Should -Be 2
        $totals.Groups['legacy'].SKIP | Should -Be 2
        $totals.Targets['web/portal'].OK | Should -Be 4
        $totals.Targets['web/api'].FAIL | Should -Be 2
        $totals.Targets['legacy/archive'].FAIL | Should -Be 1
    }

    It 'says portal is reachable, api blocked at port 8443 and archive blocked at dns' {
        $outcomes = (Get-BeaconTotals -Result $fromJson).Outcomes
        $outcomes['web/portal'].Reachable | Should -BeTrue
        $outcomes['web/api'].Reachable | Should -BeFalse
        $outcomes['web/api'].Text | Should -Be 'blocked at port 8443'
        $outcomes['legacy/archive'].Text | Should -Be 'blocked at dns'
    }

    It 'gives the same totals for both input shapes' {
        $a = Get-BeaconTotals -Result $fromJson
        $b = Get-BeaconTotals -Result $fromHashtable
        ($b.Overall | ConvertTo-Json -Compress) | Should -Be ($a.Overall | ConvertTo-Json -Compress)
        $b.Outcomes['web/api'].Text | Should -Be $a.Outcomes['web/api'].Text
    }
}

Describe 'Format-BeaconReport' {
    It 'starts with environment, machine and start time' {
        $lines = Format-BeaconReport -Result $fromJson
        $lines[0].Text | Should -Match 'environment: test'
        $lines[0].Text | Should -Match 'machine: probe-01'
        $lines[0].Text | Should -Match '\d{4}-\d\d-\d\d \d\d:\d\d:\d\d'
    }

    It 'has no partial-run warning when complete' {
        (Format-BeaconReport -Result $fromJson).Text | Should -Not -Match 'partial run'
    }

    It 'warns of a partial run when complete is false' {
        $partial = Get-Content -Raw -Path $examplePath | ConvertFrom-Json -AsHashtable
        $partial.run.complete = $false
        $warning = Format-BeaconReport -Result $partial | Where-Object { $_.Text -match 'partial run' }
        $warning | Should -Not -BeNullOrEmpty
        $warning.Color | Should -Be 'Yellow'
    }

    It 'colours each check line by its status' {
        $lines = Format-BeaconReport -Result $fromJson
        ($lines | Where-Object { $_.Text -match '^\s+port\s+8443\s' }).Color | Should -Be 'Red'
        ($lines | Where-Object { $_.Text -match '^\s+dns\s+portal' }).Color | Should -Be 'Green'
        ($lines | Where-Object { $_.Text -match '^\s+route\s+archive' }).Color | Should -Be 'DarkGray'
        ($lines | Where-Object { $_.Text -match '^\s+route\s+192\.0\.2\.10' }).Color | Should -Be 'Cyan'
    }

    It 'colours a WARN line yellow' {
        $warn = Get-Content -Raw -Path $examplePath | ConvertFrom-Json -AsHashtable
        $warn.checks[0].status = 'WARN'
        $line = Format-BeaconReport -Result $warn | Where-Object { $_.Text -match '^\s+dns\s+portal' }
        $line.Color | Should -Be 'Yellow'
    }

    It 'groups by group then target and gives totals and one outcome line per target' {
        $texts = (Format-BeaconReport -Result $fromJson).Text
        $texts | Should -Contain 'web/portal is reachable'
        $texts | Should -Contain 'web/api is blocked at port 8443'
        $texts | Should -Contain 'legacy/archive is blocked at dns'
        $texts | Should -Contain '  overall: OK 8, WARN 0, FAIL 3, SKIP 2'
        $texts | Should -Contain '  group web: OK 8, WARN 0, FAIL 2, SKIP 0'
        $texts | Should -Contain '  target web/api: OK 4, WARN 0, FAIL 2, SKIP 0'
        [array]::IndexOf($texts, 'web') | Should -BeLessThan ([array]::IndexOf($texts, 'legacy'))
    }

    It 'truncates the detail to the width' {
        $lines = Format-BeaconReport -Result $fromJson -Width 60
        $line = $lines | Where-Object { $_.Text -match '^\s+port\s+8443\s' }
        $line.Text.Length | Should -BeLessOrEqual 60
        $line.Text | Should -Match '\.\.\.$'
    }

    It 'gives the same lines for both input shapes' {
        $a = (Format-BeaconReport -Result $fromJson).Text
        $b = (Format-BeaconReport -Result $fromHashtable).Text
        $b | Should -Be $a
    }
}

Describe 'Write-BeaconReport' {
    It 'writes every line to the host' {
        Mock Write-Host {}
        $expected = @(Format-BeaconReport -Result $fromJson).Count
        Write-BeaconReport -Result $fromJson
        Should -Invoke Write-Host -Times $expected -Exactly
    }
}
