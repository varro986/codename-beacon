BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Checks/Dns.ps1')

    function New-DnsFact {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper: builds a hashtable.')]
        param([hashtable] $With = @{})
        $facts = @{
            HostName       = 'portal.example.com'
            IsLiteral      = $false
            Addresses      = [string[]] @('192.0.2.10')
            Servers        = [string[]] @('10.0.0.2')
            ErrorKind      = $null
            ErrorMessage   = $null
            TimeoutSeconds = 5
            DurationMs     = 12
        }
        foreach ($key in $With.Keys) { $facts[$key] = $With[$key] }
        $facts
    }
}

Describe 'Get-BeaconDnsOutcome' {
    It 'is OK with the addresses when the name resolves' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact)
        $r.check | Should -Be 'dns'
        $r.subject | Should -Be 'portal.example.com'
        $r.status | Should -Be 'OK'
        $r.detail | Should -Be 'Resolved to 192.0.2.10.'
        $r.durationMs | Should -Be 12
        $r.data.servers | Should -Be @('10.0.0.2')
    }

    It 'says "as expected" when the expected address is among the resolved ones' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact) -ExpectedAddresses '192.0.2.10'
        $r.status | Should -Be 'OK'
        $r.detail | Should -Be 'Resolved to 192.0.2.10, as expected.'
    }

    It 'orders IPv4 before IPv6' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact @{ Addresses = [string[]] @('2001:db8::1', '192.0.2.10', '192.0.2.11') })
        $r.data.addresses | Should -Be @('192.0.2.10', '192.0.2.11', '2001:db8::1')
    }

    It 'warns with both lists when an expected address is missing' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact) -ExpectedAddresses '192.0.2.99'
        $r.status | Should -Be 'WARN'
        $r.detail | Should -BeLike '*192.0.2.10*192.0.2.99*'
    }

    It 'warns when only one of several expected addresses is missing' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact) -ExpectedAddresses '192.0.2.10', '192.0.2.99'
        $r.status | Should -Be 'WARN'
    }

    It 'compares IPv6 addresses in their normal form' {
        $facts = New-DnsFact @{ Addresses = [string[]] @('2001:db8::1') }
        (Get-BeaconDnsOutcome -Facts $facts -ExpectedAddresses '2001:0db8:0:0:0:0:0:1').status | Should -Be 'OK'
    }

    It 'does no lookup for an address given' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact @{ HostName = '192.0.2.5'; IsLiteral = $true; Addresses = [string[]] @('192.0.2.5'); Servers = [string[]] @() })
        $r.status | Should -Be 'OK'
        $r.detail | Should -Be 'Address given, no DNS lookup.'
        $r.data.addresses | Should -Be @('192.0.2.5')
    }

    It 'fails with NXDOMAIN, the server asked and what to do when the name is not found' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact @{ ErrorKind = 'notFound'; Addresses = [string[]] @() })
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be 'Name not found (NXDOMAIN) from the system resolver (configured DNS servers: 10.0.0.2): check the name, or the DNS zone it belongs to.'
        $r.data.error | Should -Be 'NXDOMAIN'
    }

    It 'fails when the DNS server fails' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact @{ ErrorKind = 'serverFailure'; Addresses = [string[]] @() })
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike '*configured DNS servers: 10.0.0.2*reachable*'
        $r.data.error | Should -Be 'SERVFAIL'
    }

    It 'fails with the time waited when the server does not answer' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact @{ ErrorKind = 'timeout'; Addresses = [string[]] @() })
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike 'No answer within 5 s from the system resolver (configured DNS servers: 10.0.0.2)*reachable*'
        $r.data.error | Should -Be 'timeout'
    }

    It 'fails with the message for any other error, also without known servers' {
        $r = Get-BeaconDnsOutcome -Facts (New-DnsFact @{ ErrorKind = 'other'; ErrorMessage = 'boom'; Addresses = [string[]] @(); Servers = [string[]] @() })
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike '*boom*configured DNS servers: none found on this machine*'
        $r.data.error | Should -Be 'other'
    }
}

Describe 'Get-BeaconDnsFact' {
    BeforeAll {
        $script:config = @{ TimeoutSeconds = @{ Dns = 5 } }
    }

    It 'resolves localhost' {
        $facts = Get-BeaconDnsFact -HostName 'localhost' -Config $script:config
        $facts.ErrorKind | Should -BeNullOrEmpty
        $facts.Addresses.Count | Should -BeGreaterThan 0
    }

    It 'does not look up an address given' {
        $facts = Get-BeaconDnsFact -HostName '192.0.2.5' -Config $script:config
        $facts.IsLiteral | Should -BeTrue
        $facts.Addresses | Should -Be @('192.0.2.5')
    }

    It 'reports a name under .invalid as not found' {
        $facts = Get-BeaconDnsFact -HostName 'beacon-test.invalid' -Config $script:config
        if (-not $facts.ErrorKind) {
            throw "The local resolver answers for every name ($($facts.Addresses -join ', ') for beacon-test.invalid): this test cannot tell a missing name; turn off the resolver's wildcard answers."
        }
        $facts.ErrorKind | Should -Be 'notFound'
    }
}

Describe 'Invoke-BeaconDnsCheck' {
    It 'returns an OK record for localhost' {
        $r = Invoke-BeaconDnsCheck -HostName 'localhost' -Config @{ TimeoutSeconds = @{ Dns = 5 } }
        $r.check | Should -Be 'dns'
        $r.subject | Should -Be 'localhost'
        $r.status | Should -Be 'OK'
    }
}
