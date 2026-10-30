BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Checks/Port.ps1')
}

Describe 'Get-BeaconPortOutcome' {
    It 'reports an opened connection as OK with the source address' {
        $facts = @{ connected = $true; sourceAddress = '10.0.0.15'; durationMs = 18 }
        $r = Get-BeaconPortOutcome -Port 443 -Facts $facts -TimeoutSeconds 5
        $r.check | Should -Be 'port'
        $r.subject | Should -Be '443'
        $r.status | Should -Be 'OK'
        $r.detail | Should -Be 'TCP connection opened from 10.0.0.15.'
        $r.durationMs | Should -Be 18
        $r.data.sourceAddress | Should -Be '10.0.0.15'
        $r.data.Contains('reason') | Should -BeFalse
    }

    It 'reports a refusal as FAIL' {
        $facts = @{ connected = $false; reason = 'refused'; sourceAddress = '10.0.0.15'; durationMs = 3 }
        $r = Get-BeaconPortOutcome -Port 8444 -Facts $facts -TimeoutSeconds 5
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be 'Refused: the host answered, nothing listens on this port.'
        $r.data.reason | Should -Be 'refused'
        $r.data.sourceAddress | Should -Be '10.0.0.15'
    }

    It 'reports a timeout as FAIL with the configured seconds' {
        $facts = @{ connected = $false; reason = 'timeout'; sourceAddress = '10.0.0.15'; durationMs = 5003 }
        $r = Get-BeaconPortOutcome -Port 8443 -Facts $facts -TimeoutSeconds 5
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be 'Timed out after 5 s: filtered, likely a firewall.'
        $r.data.reason | Should -Be 'timeout'
    }

    It 'reports an unreachable address as FAIL pointing at routing and VPN' {
        $facts = @{ connected = $false; reason = 'unreachable'; sourceAddress = $null; durationMs = 1 }
        $r = Get-BeaconPortOutcome -Port 443 -Facts $facts -TimeoutSeconds 5
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Match 'No route'
        $r.detail | Should -Match 'routing'
        $r.detail | Should -Match 'VPN'
        $r.data.reason | Should -Be 'unreachable'
        $r.data.sourceAddress | Should -BeNullOrEmpty
    }

    It 'reports any other socket error as FAIL with the error' {
        $facts = @{ connected = $false; reason = 'other'; error = 'AccessDenied'; sourceAddress = '10.0.0.15'; durationMs = 1 }
        $r = Get-BeaconPortOutcome -Port 443 -Facts $facts -TimeoutSeconds 5
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Match 'AccessDenied'
        $r.data.reason | Should -Be 'other'
    }
}

Describe 'Invoke-BeaconPortCheck' {
    BeforeAll {
        # The timeout stays above the ~2 s a refused loopback connect can take on Windows.
        $script:config = @{ TimeoutSeconds = @{ Port = 10 } }
    }

    It 'opens a connection to a listener on loopback' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $port = $listener.LocalEndpoint.Port
            $r = Invoke-BeaconPortCheck -Address '127.0.0.1' -Port $port -Config $script:config
        }
        finally {
            $listener.Stop()
        }
        $r.check | Should -Be 'port'
        $r.subject | Should -Be "$port"
        $r.status | Should -Be 'OK'
        $r.data.sourceAddress | Should -Be '127.0.0.1'
    }

    It 'reports a refusal on a port that was bound then released' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        $listener.Stop()

        $r = Invoke-BeaconPortCheck -Address '127.0.0.1' -Port $port -Config $script:config
        $r.status | Should -Be 'FAIL'
        $r.data.reason | Should -Be 'refused'
        $r.data.sourceAddress | Should -Be '127.0.0.1'
    }
}
