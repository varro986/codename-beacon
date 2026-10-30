BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Chain.ps1')

    # Stubs with the signatures of the check entries (written elsewhere): the tests mock them.
    function Invoke-BeaconDnsCheck { [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')] param([string] $HostName, [string[]] $ExpectedAddresses, [hashtable] $Config) }
    function Invoke-BeaconRouteCheck { [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')] param([string] $Address, [hashtable] $Config) }
    function Invoke-BeaconPortCheck { [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')] param([string] $Address, [int] $Port, [hashtable] $Config) }
    function Invoke-BeaconTlsCheck { [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')] param([string] $HostName, [string] $Address, [int] $Port, [string] $Subject, [hashtable] $Config) }
    function Invoke-BeaconHttpCheck { [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')] param([string] $Url, [string] $MatrixProxy, [int[]] $ExpectedStatus, [hashtable] $Config) }
    function Resolve-BeaconProxy { [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')] param([string] $Url, [string] $MatrixProxy, [System.Collections.IDictionary] $Environment) }

    function Get-TestTarget {
        param($Ports = @(443), $Urls = @(), $ExpectedStatus = $null)
        @{ Group = 'web'; Name = 'portal'; Host = 'portal.example.com'; ExpectedAddresses = @('192.0.2.10')
            Ports = $Ports; Urls = $Urls; ExpectedStatus = $ExpectedStatus; SecretEnv = $null }
    }
    function Get-TestRecord {
        param($Check, $Subject, $Status = 'OK', $Detail = 'x', $Data = $null)
        New-BeaconCheckRecord -Check $Check -Subject $Subject -Status $Status -Detail $Detail -DurationMs 1 -Data $Data
    }
    function Get-Line {
        # One short line per record, to compare the order and the outcome at a glance.
        param($Records)
        @($Records | ForEach-Object { "$($_.check) $($_.subject) $($_.status)" })
    }
}

Describe 'Invoke-BeaconChain' {
    BeforeEach {
        $script:config = @{ }
        Mock Invoke-BeaconDnsCheck { Get-TestRecord dns $HostName OK -Data @{ addresses = @('192.0.2.10', '192.0.2.11') } }
        Mock Invoke-BeaconRouteCheck { Get-TestRecord route $Address INFO -Data @{ hops = @('198.51.100.1'); lastAnswering = '198.51.100.1'; method = 'tcp' } }
        Mock Invoke-BeaconPortCheck { Get-TestRecord port "$Port" }
        Mock Invoke-BeaconTlsCheck { Get-TestRecord tls $Subject }
        Mock Invoke-BeaconHttpCheck { Get-TestRecord http $Url }
        Mock Resolve-BeaconProxy { $null }
    }

    It 'runs everything in order when all is well, with group and target first' {
        $target = Get-TestTarget -Ports @(8443, 443) -Urls @('https://portal.example.com/health')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com OK', 'route 192.0.2.10 INFO', 'port 443 OK', 'port 8443 OK'
            'tls https://portal.example.com/health OK', 'http https://portal.example.com/health OK')
        @($records[0].Keys)[0..2] | Should -Be @('group', 'target', 'check')
        $records[0].group | Should -Be 'web'
        $records[0].target | Should -Be 'portal'
        @($records[0].Keys) | Should -Be @('group', 'target', 'check', 'subject', 'status', 'detail', 'durationMs', 'data')
    }

    It 'asks DNS for the expected addresses and uses the first address for the route and the ports' {
        Invoke-BeaconChain -Target (Get-TestTarget) -Config $script:config | Out-Null

        Should -Invoke Invoke-BeaconDnsCheck -Times 1 -ParameterFilter { $ExpectedAddresses -contains '192.0.2.10' }
        Should -Invoke Invoke-BeaconRouteCheck -Times 1 -ParameterFilter { $Address -eq '192.0.2.10' }
        Should -Invoke Invoke-BeaconPortCheck -Times 1 -ParameterFilter { $Address -eq '192.0.2.10' -and $Port -eq 443 }
    }

    It 'skips everything after a DNS failure, with the reason' {
        Mock Invoke-BeaconDnsCheck { Get-TestRecord dns $HostName FAIL -Data @{ error = 'NXDOMAIN' } }
        $target = Get-TestTarget -Ports @(80) -Urls @('https://portal.example.com/health')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com FAIL', 'route portal.example.com SKIP', 'port 80 SKIP', 'port 443 SKIP'
            'tls https://portal.example.com/health SKIP', 'http https://portal.example.com/health SKIP')
        $records[1..5] | ForEach-Object { $_.detail | Should -Be 'Not run: DNS failed.' }
        Should -Invoke Invoke-BeaconRouteCheck -Times 0
        Should -Invoke Invoke-BeaconPortCheck -Times 0
    }

    It 'goes on when the route is SKIP or INFO without a last hop' {
        Mock Invoke-BeaconRouteCheck { Get-TestRecord route $Address SKIP }
        $target = Get-TestTarget -Urls @('https://portal.example.com/health')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com OK', 'route 192.0.2.10 SKIP', 'port 443 OK'
            'tls https://portal.example.com/health OK', 'http https://portal.example.com/health OK')
    }

    It 'skips the TLS and HTTP of a URL whose port failed, and adds the last hop to the port detail' {
        Mock Invoke-BeaconPortCheck { Get-TestRecord port "$Port" ($Port -eq 8443 ? 'FAIL' : 'OK') -Detail 'Refused.' }
        $target = Get-TestTarget -Ports @(443) -Urls @('https://portal.example.com:8443/a', 'https://portal.example.com/b')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com OK', 'route 192.0.2.10 INFO', 'port 443 OK', 'port 8443 FAIL'
            'tls https://portal.example.com:8443/a SKIP', 'http https://portal.example.com:8443/a SKIP'
            'tls https://portal.example.com/b OK', 'http https://portal.example.com/b OK')
        $records[3].detail | Should -Be 'Refused. Last hop that answered: 198.51.100.1.'
        $records[4].detail | Should -Be 'Not run: port 8443 failed.'
        $records[5].detail | Should -Be 'Not run: port 8443 failed.'
        Should -Invoke Invoke-BeaconTlsCheck -Times 1
        Should -Invoke Invoke-BeaconHttpCheck -Times 1
    }

    It 'leaves the port detail alone when the last hop is not known' {
        Mock Invoke-BeaconRouteCheck { Get-TestRecord route $Address SKIP }
        Mock Invoke-BeaconPortCheck { Get-TestRecord port "$Port" FAIL -Detail 'Refused.' }
        $records = Invoke-BeaconChain -Target (Get-TestTarget) -Config $script:config

        $records[2].detail | Should -Be 'Refused.'
    }

    It 'skips HTTP after a TLS failure' {
        Mock Invoke-BeaconTlsCheck { Get-TestRecord tls $Subject FAIL }
        $target = Get-TestTarget -Urls @('https://portal.example.com/health')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        $records[-2].status | Should -Be 'FAIL'
        $records[-1].check | Should -Be 'http'
        $records[-1].status | Should -Be 'SKIP'
        $records[-1].detail | Should -Be 'Not run: TLS failed.'
        Should -Invoke Invoke-BeaconHttpCheck -Times 0
    }

    It 'passes the URL as TLS subject, the matrix proxy and the expected status to the checks' {
        $target = Get-TestTarget -Urls @('https://portal.example.com/health') -ExpectedStatus @(401)
        Invoke-BeaconChain -Target $target -MatrixProxy 'http://proxy.example.net:8080' -Config $script:config | Out-Null

        Should -Invoke Invoke-BeaconTlsCheck -Times 1 -ParameterFilter {
            $Subject -eq 'https://portal.example.com/health' -and $HostName -eq 'portal.example.com' -and $Port -eq 443 -and $Address -eq '192.0.2.10' }
        Should -Invoke Invoke-BeaconHttpCheck -Times 1 -ParameterFilter {
            $MatrixProxy -eq 'http://proxy.example.net:8080' -and $ExpectedStatus -contains 401 }
    }

    It 'checks the proxy port for a URL through a proxy, with no direct TLS' {
        Mock Resolve-BeaconProxy { [uri] 'http://proxy.example.net:8080' }
        $target = Get-TestTarget -Ports @(443) -Urls @('https://portal.example.com/health')
        $records = Invoke-BeaconChain -Target $target -MatrixProxy 'http://proxy.example.net:8080' -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com OK', 'route 192.0.2.10 INFO', 'port 443 OK', 'port proxy proxy.example.net:8080 OK'
            'http https://portal.example.com/health OK')
        Should -Invoke Invoke-BeaconPortCheck -Times 1 -ParameterFilter { $Address -eq 'proxy.example.net' -and $Port -eq 8080 }
        Should -Invoke Invoke-BeaconPortCheck -Times 1 -ParameterFilter { $Address -eq '192.0.2.10' -and $Port -eq 443 }
        Should -Invoke Invoke-BeaconTlsCheck -Times 0
    }

    It 'skips the HTTP of a URL through a proxy whose port failed' {
        Mock Resolve-BeaconProxy { [uri] 'http://proxy.example.net:8080' }
        Mock Invoke-BeaconPortCheck { Get-TestRecord port "$Port" ($Port -eq 8080 ? 'FAIL' : 'OK') }
        $target = Get-TestTarget -Ports @() -Urls @('https://portal.example.com/health')
        $records = Invoke-BeaconChain -Target $target -MatrixProxy 'http://proxy.example.net:8080' -Config $script:config

        $records[-1].status | Should -Be 'SKIP'
        $records[-1].detail | Should -Be 'Not run: port 8080 failed.'
        Should -Invoke Invoke-BeaconHttpCheck -Times 0
    }

    It 'checks a port once when it is declared and used by URLs' {
        $target = Get-TestTarget -Ports @(443, 443) -Urls @('https://portal.example.com/a', 'https://portal.example.com/b')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        @($records | Where-Object check -EQ 'port').Count | Should -Be 1
        Should -Invoke Invoke-BeaconPortCheck -Times 1
    }

    It 'on a DNS failure skips the direct checks but still runs the URLs through a proxy' {
        Mock Invoke-BeaconDnsCheck { Get-TestRecord dns $HostName FAIL -Data @{ error = 'NXDOMAIN' } }
        Mock Resolve-BeaconProxy { if ($Url -like '*proxied*') { [uri] 'http://proxy.example.net:8080' } }
        $target = Get-TestTarget -Ports @(443) -Urls @('https://portal.example.com/direct', 'https://portal.example.com/proxied')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com FAIL', 'route portal.example.com SKIP', 'port 443 SKIP', 'port proxy proxy.example.net:8080 OK'
            'tls https://portal.example.com/direct SKIP', 'http https://portal.example.com/direct SKIP'
            'http https://portal.example.com/proxied OK')
        Should -Invoke Invoke-BeaconPortCheck -Times 1 -ParameterFilter { $Address -eq 'proxy.example.net' -and $Port -eq 8080 }
        Should -Invoke Invoke-BeaconHttpCheck -Times 1 -ParameterFilter { $Url -like '*proxied' }
    }

    It 'checks a URL on another host against its own DNS, with the port subject host:port' {
        Mock Invoke-BeaconDnsCheck {
            $addresses = if ($HostName -eq 'api.example.org') { @('203.0.113.5') } else { @('192.0.2.10') }
            Get-TestRecord dns $HostName OK -Data @{ addresses = $addresses } }
        $target = Get-TestTarget -Ports @(443) -Urls @('https://API.example.org:8443/x')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com OK', 'route 192.0.2.10 INFO', 'port 443 OK'
            'dns api.example.org OK', 'port api.example.org:8443 OK'
            'tls https://API.example.org:8443/x OK', 'http https://API.example.org:8443/x OK')
        Should -Invoke Invoke-BeaconDnsCheck -Times 1 -ParameterFilter { $HostName -eq 'api.example.org' -and -not $ExpectedAddresses }
        Should -Invoke Invoke-BeaconPortCheck -Times 1 -ParameterFilter { $Address -eq '203.0.113.5' -and $Port -eq 8443 }
        Should -Invoke Invoke-BeaconTlsCheck -Times 1 -ParameterFilter { $Address -eq '203.0.113.5' -and $HostName -eq 'api.example.org' }
    }

    It 'skips the direct checks of a URL whose own host fails DNS, naming the host' {
        Mock Invoke-BeaconDnsCheck {
            if ($HostName -eq 'api.example.org') { Get-TestRecord dns $HostName FAIL -Data @{ error = 'NXDOMAIN' } }
            else { Get-TestRecord dns $HostName OK -Data @{ addresses = @('192.0.2.10') } } }
        $target = Get-TestTarget -Ports @() -Urls @('https://api.example.org/x', 'https://portal.example.com/y')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com OK', 'route 192.0.2.10 INFO', 'port 443 OK'
            'dns api.example.org FAIL', 'port api.example.org:443 SKIP'
            'tls https://api.example.org/x SKIP', 'http https://api.example.org/x SKIP'
            'tls https://portal.example.com/y OK', 'http https://portal.example.com/y OK')
        $records[4].detail | Should -Be 'Not run: DNS failed for api.example.org.'
        $records[6].detail | Should -Be 'Not run: DNS failed for api.example.org.'
    }

    It 'runs one DNS check and one port check for two URLs on the same other host' {
        Mock Invoke-BeaconDnsCheck { Get-TestRecord dns $HostName OK -Data @{ addresses = @('203.0.113.5') } }
        $target = Get-TestTarget -Ports @() -Urls @('https://api.example.org/a', 'https://api.example.org/b')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        @($records | Where-Object { $_.check -eq 'dns' -and $_.subject -eq 'api.example.org' }).Count | Should -Be 1
        @($records | Where-Object { $_.check -eq 'port' -and $_.subject -eq 'api.example.org:443' }).Count | Should -Be 1
        @($records | Where-Object check -EQ 'tls').Count | Should -Be 2
    }

    It 'adds the default port of a plain http URL' {
        $target = Get-TestTarget -Ports @() -Urls @('http://portal.example.com/')
        $records = Invoke-BeaconChain -Target $target -Config $script:config

        Get-Line $records | Should -Be @(
            'dns portal.example.com OK', 'route 192.0.2.10 INFO', 'port 80 OK', 'http http://portal.example.com/ OK')
    }
}
