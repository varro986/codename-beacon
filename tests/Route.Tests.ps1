BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Checks/Route.ps1')
}

Describe 'Get-BeaconRouteOutcome' {
    It 'reports a reached target as INFO with the hop count' {
        $facts = @{ hops = @('198.51.100.1', '198.51.100.9', '203.0.113.5', '192.0.2.10'); reached = $true; error = $null; durationMs = 3120; method = 'icmp' }
        $r = Get-BeaconRouteOutcome -Address '192.0.2.10' -Facts $facts
        $r.check | Should -Be 'route'
        $r.subject | Should -Be '192.0.2.10'
        $r.status | Should -Be 'INFO'
        $r.detail | Should -Be 'Reached in 4 hops.'
        $r.durationMs | Should -Be 3120
        $r.data.hops | Should -Be @('198.51.100.1', '198.51.100.9', '203.0.113.5', '192.0.2.10')
        $r.data.lastAnswering | Should -Be '192.0.2.10'
        $r.data.method | Should -Be 'icmp'
    }

    It 'reports the last hop that answered when the trace is not reached' {
        $facts = @{ hops = @('198.51.100.1', '203.0.113.5', '*', '*'); reached = $false; error = $null; durationMs = 30050; method = 'icmp' }
        $r = Get-BeaconRouteOutcome -Address '192.0.2.20' -Facts $facts
        $r.status | Should -Be 'INFO'
        $r.detail | Should -Be 'No answer after hop 2 (203.0.113.5): trace packets dropped or filtered.'
        $r.data.hops | Should -Be @('198.51.100.1', '203.0.113.5', '*', '*')
        $r.data.lastAnswering | Should -Be '203.0.113.5'
    }

    It 'keeps a silent hop in the middle of an answered route' {
        $facts = @{ hops = @('198.51.100.1', '*', '203.0.113.5', '192.0.2.10'); reached = $true; error = $null; durationMs = 4000; method = 'icmp' }
        $r = Get-BeaconRouteOutcome -Address '192.0.2.10' -Facts $facts
        $r.detail | Should -Be 'Reached in 4 hops.'
        $r.data.hops[1] | Should -Be '*'
    }

    It 'skips with the default reason when no hop answered' {
        $facts = @{ hops = @('*', '*', '*'); reached = $false; error = $null; durationMs = 15000; method = 'icmp' }
        $r = Get-BeaconRouteOutcome -Address '192.0.2.20' -Facts $facts
        $r.status | Should -Be 'SKIP'
        $r.detail | Should -Be 'No unprivileged way to trace the route on this system.'
        $r.data.Contains('lastAnswering') | Should -BeFalse
        $r.data.method | Should -Be 'icmp'
    }

    It 'skips with the actual error when the trace could not run' {
        $facts = @{ hops = @(); reached = $false; error = 'Operation not permitted'; durationMs = 2; method = 'icmp' }
        $r = Get-BeaconRouteOutcome -Address '192.0.2.20' -Facts $facts
        $r.status | Should -Be 'SKIP'
        $r.detail | Should -Be 'Operation not permitted'
        $r.data.hops.Count | Should -Be 0
        $r.data.Contains('lastAnswering') | Should -BeFalse
    }
}

Describe 'Get-BeaconRouteOutcome on systems without hop addresses' {
    It 'keeps the hops and skips when replies came but no address at all' {
        $facts = @{ hops = @('*', '*'); replies = 2; reached = $false; error = $null; durationMs = 40; method = 'icmp' }
        $r = Get-BeaconRouteOutcome -Address '192.0.2.20' -Facts $facts
        $r.status | Should -Be 'SKIP'
        $r.detail | Should -BeLike '*addresses are not available on this system*'
        $r.data.hops | Should -Be @('*', '*')
    }

    It 'reaches a target even when its own address is missing' {
        $facts = @{ hops = @('198.51.100.1', '*'); replies = 2; reached = $true; error = $null; durationMs = 40; method = 'icmp' }
        (Get-BeaconRouteOutcome -Address '192.0.2.20' -Facts $facts).detail | Should -Be 'Reached in 2 hops.'
    }

    It 'reports an unreachable status as INFO with the hop that said it' {
        $facts = @{ hops = @('198.51.100.1', '203.0.113.5'); replies = 1; unreachable = @{ hop = 2; address = '203.0.113.5'; status = 'DestinationHostUnreachable' }
            reached = $false; error = $null; durationMs = 40; method = 'icmp' }
        $r = Get-BeaconRouteOutcome -Address '192.0.2.20' -Facts $facts
        $r.status | Should -Be 'INFO'
        $r.detail | Should -Be 'Unreachable after hop 2 (203.0.113.5): DestinationHostUnreachable.'
        $r.data.unreachable | Should -Be 'DestinationHostUnreachable'
    }

    It 'says the address is unknown when the unreachable reply has none' {
        $facts = @{ hops = @('*'); replies = 0; unreachable = @{ hop = 1; address = $null; status = 'DestinationNetworkUnreachable' }
            reached = $false; error = $null; durationMs = 4; method = 'icmp' }
        (Get-BeaconRouteOutcome -Address '192.0.2.20' -Facts $facts).detail | Should -Be 'Unreachable after hop 1 (unknown address): DestinationNetworkUnreachable.'
    }
}

Describe 'Invoke-BeaconRouteCheck' {
    BeforeAll {
        $script:config = @{ Route = @{ MaxHops = 5; HopTimeoutSeconds = 2 } }
    }

    It 'reaches loopback in one hop, or skips with a reason where ping is not permitted' {
        $r = Invoke-BeaconRouteCheck -Address '127.0.0.1' -Config $script:config
        $r.check | Should -Be 'route'
        $r.subject | Should -Be '127.0.0.1'
        if ($r.status -eq 'SKIP') {
            $r.detail | Should -Not -BeNullOrEmpty
        }
        else {
            $r.status | Should -Be 'INFO'
            $r.detail | Should -Be 'Reached in 1 hop.'
            $r.data.hops | Should -Be @('127.0.0.1')
            $r.data.lastAnswering | Should -Be '127.0.0.1'
            $r.data.method | Should -Be 'icmp'
        }
    }

}
