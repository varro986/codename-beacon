BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Checks/Http.ps1')
    $script:Config = Get-BeaconConfig
    . (Join-Path $PSScriptRoot 'TestServer.ps1')

    function Get-TestFact {
        param([hashtable] $With = @{})
        $facts = @{
            Status = $null; Reason = $null; Location = $null; Body = $null; Proxy = $null; Tunneled = $false
            ErrorKind = $null; ErrorMessage = $null; ProxyStatus = $null; DurationMs = 12
        }
        foreach ($key in $With.Keys) { $facts[$key] = $With[$key] }
        $facts
    }
}

Describe 'Resolve-BeaconProxy' {
    It '<Name>' -ForEach @(
        @{ Name = 'the matrix proxy wins over the environment'; Url = 'https://a.example.com/'; Matrix = 'http://m:1'; Env = @{ HTTPS_PROXY = 'http://e:2' }; Expected = 'http://m:1' }
        @{ Name = 'the matrix proxy wins over NO_PROXY'; Url = 'https://a.example.com/'; Matrix = 'http://m:1'; Env = @{ NO_PROXY = '*' }; Expected = 'http://m:1' }
        @{ Name = 'https URL reads HTTPS_PROXY'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; HTTP_PROXY = 'http://p:4' }; Expected = 'http://s:3' }
        @{ Name = 'http URL reads HTTP_PROXY'; Url = 'http://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; HTTP_PROXY = 'http://p:4' }; Expected = 'http://p:4' }
        @{ Name = 'lower case variables are read'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{ https_proxy = 'http://s:3' }; Expected = 'http://s:3' }
        @{ Name = 'http URL ignores HTTPS_PROXY alone'; Url = 'http://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3' }; Expected = $null }
        @{ Name = 'a proxy without scheme is read as http'; Url = 'http://a.example.com/'; Matrix = ''; Env = @{ HTTP_PROXY = 'p:4' }; Expected = 'http://p:4' }
        @{ Name = 'an empty variable is not set'; Url = 'http://a.example.com/'; Matrix = ''; Env = @{ HTTP_PROXY = '' }; Expected = $null }
        @{ Name = 'no variable means direct'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{}; Expected = $null }
        @{ Name = 'NO_PROXY exact host'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; NO_PROXY = 'x.org, a.example.com' }; Expected = $null }
        @{ Name = 'NO_PROXY domain suffix'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; NO_PROXY = 'example.com' }; Expected = $null }
        @{ Name = 'NO_PROXY suffix with leading dot'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; no_proxy = '.example.com' }; Expected = $null }
        @{ Name = 'NO_PROXY does not match a longer name'; Url = 'https://badexample.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; NO_PROXY = 'example.com' }; Expected = 'http://s:3' }
        @{ Name = 'NO_PROXY star means everything'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; NO_PROXY = '*' }; Expected = $null }
        @{ Name = 'NO_PROXY with the port of the URL'; Url = 'https://a.example.com:8443/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; NO_PROXY = 'a.example.com:8443' }; Expected = $null }
        @{ Name = 'NO_PROXY with another port'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; NO_PROXY = 'a.example.com:8443' }; Expected = 'http://s:3' }
        @{ Name = 'NO_PROXY with the default port'; Url = 'https://a.example.com/'; Matrix = ''; Env = @{ HTTPS_PROXY = 'http://s:3'; NO_PROXY = 'a.example.com:443' }; Expected = $null }
    ) {
        Resolve-BeaconProxy -Url $Url -MatrixProxy $Matrix -Environment $Env | Should -Be $Expected
    }

    It 'reads the process environment when none is given' {
        $saved = $env:HTTPS_PROXY, $env:https_proxy
        try {
            $env:https_proxy = $null
            $env:HTTPS_PROXY = 'http://from-process:9'
            Resolve-BeaconProxy -Url 'https://a.example.com/' | Should -Be 'http://from-process:9'
        }
        finally { $env:HTTPS_PROXY = $saved[0]; $env:https_proxy = $saved[1] }
    }
}

Describe 'Hide-BeaconUrlUserInfo' {
    It '<Name>' -ForEach @(
        @{ Name = 'drops user and password'; Url = 'http://alice:s3cret@px:8080'; Expected = 'http://px:8080' }
        @{ Name = 'drops a user alone'; Url = 'http://alice@px:8080/'; Expected = 'http://px:8080/' }
        @{ Name = 'drops a password that contains @'; Url = 'http://alice:p@ss@px:8080'; Expected = 'http://px:8080' }
        @{ Name = 'drops it without scheme'; Url = 'alice:s3cret@px:8080'; Expected = 'px:8080' }
        @{ Name = 'keeps a URL without user info'; Url = 'https://px:8080/a?b=c@d'; Expected = 'https://px:8080/a?b=c@d' }
        @{ Name = 'keeps an @ in the path'; Url = 'http://px/a@b'; Expected = 'http://px/a@b' }
        @{ Name = 'passes an empty value'; Url = ''; Expected = $null }
        @{ Name = 'passes null'; Url = $null; Expected = $null }
    ) {
        Hide-BeaconUrlUserInfo -Url $Url | Should -Be $Expected
    }
}

Describe 'Get-BeaconHttpOutcome' {
    It 'is OK when the expected status is met' {
        $facts = Get-TestFact @{ Status = 401; Reason = 'Unauthorized' }
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -ExpectedStatus 401, 403 -Config $Config
        $r.check | Should -Be 'http'
        $r.subject | Should -Be 'http://h/'
        $r.status | Should -Be 'OK'
        $r.detail | Should -Be '401 Unauthorized, as expected: the route is open.'
        $r.data.expected | Should -Be @(401, 403)
        $r.data.status | Should -Be 401
        $r.data.proxy | Should -Be 'direct'
        $r.durationMs | Should -Be 12
    }

    It 'warns when the expected status is not met, with the body' {
        $facts = Get-TestFact @{ Status = 500; Reason = 'Internal Server Error'; Body = 'boom' }
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -ExpectedStatus 200 -Config $Config
        $r.status | Should -Be 'WARN'
        $r.detail | Should -Be 'Expected 200, got 500 Internal Server Error. boom'
    }

    It '<Status> is <Result> without expectation' -ForEach @(
        @{ Status = 200; Reason = 'OK'; Result = 'OK' }
        @{ Status = 302; Reason = 'Found'; Result = 'OK' }
        @{ Status = 404; Reason = 'Not Found'; Result = 'WARN' }
        @{ Status = 503; Reason = 'Service Unavailable'; Result = 'WARN' }
    ) {
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts (Get-TestFact @{ Status = $Status; Reason = $Reason }) -Config $Config
        $r.status | Should -Be $Result
        $r.detail | Should -BeLike "$Status $Reason*"
        $r.data.Keys | Should -Not -Contain 'expected'
    }

    It 'says where a redirect goes and that it is not followed' {
        $facts = Get-TestFact @{ Status = 302; Reason = 'Found'; Location = 'https://elsewhere/login' }
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -Config $Config
        $r.detail | Should -Be '302 Found. Redirects to https://elsewhere/login (not followed).'
        $r.data.location | Should -Be 'https://elsewhere/login'
    }

    It 'ends a non-OK detail with the body preview, and leaves an OK one without' {
        $bad = Get-BeaconHttpOutcome -Url 'http://h/' -Facts (Get-TestFact @{ Status = 404; Reason = 'Not Found'; Body = 'no such page' }) -Config $Config
        $bad.detail | Should -Be '404 Not Found. no such page'
        $good = Get-BeaconHttpOutcome -Url 'http://h/' -Facts (Get-TestFact @{ Status = 200; Reason = 'OK'; Body = 'hello' }) -Config $Config
        $good.detail | Should -Be '200 OK.'
    }

    It 'says "through the proxy" for an OK answer via a proxy and records the proxy' {
        $facts = Get-TestFact @{ Status = 200; Reason = 'OK'; Proxy = 'http://px:8080'; Tunneled = $true }
        $r = Get-BeaconHttpOutcome -Url 'https://h/' -Facts $facts -Config $Config
        $r.detail | Should -Be '200 OK through the proxy.'
        $r.data.proxy | Should -Be 'http://px:8080'
    }

    It 'fails on a timeout' {
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts (Get-TestFact @{ ErrorKind = 'timeout' }) -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be "No answer from http://h/ within $($Config.TimeoutSeconds.Http) s."
    }

    It 'fails on a connection failure' {
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts (Get-TestFact @{ ErrorKind = 'connectFailed'; ErrorMessage = 'refused' }) -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be 'Connection to http://h/ failed: refused'
    }

    It 'points to the proxy when it is unreachable' {
        $facts = Get-TestFact @{ ErrorKind = 'connectFailed'; ErrorMessage = 'refused'; Proxy = 'http://px:8080' }
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be 'Proxy http://px:8080 unreachable: refused'
    }

    It 'points to the proxy and shows its answer when the tunnel is refused' {
        $facts = Get-TestFact @{ ErrorKind = 'proxyTunnelFailed'; ProxyStatus = 403; Proxy = 'http://px:8080'; Tunneled = $true }
        $r = Get-BeaconHttpOutcome -Url 'https://h/' -Facts $facts -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike '*http://px:8080*403*'
    }

    It 'points to the proxy when it needs authentication' {
        $facts = Get-TestFact @{ ErrorKind = 'proxyAuthRequired'; ProxyStatus = 407; Proxy = 'http://px:8080'; Tunneled = $true }
        $r = Get-BeaconHttpOutcome -Url 'https://h/' -Facts $facts -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike '*http://px:8080*407*'
    }

    It 'reads a 407 answer to a plain http request as the proxy asking for authentication' {
        $facts = Get-TestFact @{ Status = 407; Reason = 'Proxy Authentication Required'; Proxy = 'http://px:8080' }
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike '*http://px:8080*407*'
    }

    It 'warns, neutrally, on a 403 to a plain http request through a proxy, with its body' {
        $facts = Get-TestFact @{ Status = 403; Reason = 'Forbidden'; Body = 'blocked by policy'; Proxy = 'http://px:8080' }
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -Config $Config
        $r.status | Should -Be 'WARN'
        $r.detail | Should -Be '403 Forbidden through proxy http://px:8080: the proxy or the service refused. blocked by policy'
    }

    It 'does not warn about the proxy when the 403 is the expected status' {
        $facts = Get-TestFact @{ Status = 403; Reason = 'Forbidden'; Proxy = 'http://px:8080' }
        (Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -ExpectedStatus 403 -Config $Config).status | Should -Be 'OK'
    }

    It 'shows no user info of the proxy in the detail or the data' {
        $facts = Get-TestFact @{ Status = 403; Reason = 'Forbidden'; Proxy = 'http://alice:s3cret@px:8080' }
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -Config $Config
        $r.detail | Should -BeLike '*http://px:8080*'
        $r.data.proxy | Should -Be 'http://px:8080'
        ($r | ConvertTo-Json -Depth 5) | Should -Not -Match 's3cret|alice'
    }

    It 'leaves a 403 inside a tunnel to the origin' {
        $facts = Get-TestFact @{ Status = 403; Reason = 'Forbidden'; Proxy = 'http://px:8080'; Tunneled = $true }
        (Get-BeaconHttpOutcome -Url 'https://h/' -Facts $facts -Config $Config).status | Should -Be 'WARN'
    }

    It 'fails on a TLS error with its message' {
        $facts = Get-TestFact @{ ErrorKind = 'tls'; ErrorMessage = 'The remote certificate is invalid.'; Proxy = 'http://px:8080'; Tunneled = $true }
        $r = Get-BeaconHttpOutcome -Url 'https://h/' -Facts $facts -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be 'TLS failed: The remote certificate is invalid.'
    }

    It 'fails on any other error' {
        $r = Get-BeaconHttpOutcome -Url 'http://h/' -Facts (Get-TestFact @{ ErrorKind = 'other'; ErrorMessage = 'odd' }) -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -Be 'Request failed: odd'
    }

    It 'does not change the facts it is given' {
        $facts = Get-TestFact @{ Status = 403; Reason = 'Forbidden'; Proxy = 'http://px:8080' }
        $null = Get-BeaconHttpOutcome -Url 'http://h/' -Facts $facts -Config $Config
        $facts.ErrorKind | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-BeaconHttpCheck against local listeners' {
    BeforeAll {
        $script:Origin = Open-TestServer -Routes @{
            '/ok'       = Get-RawResponse '200 OK' 'fine'
            '/denied'   = Get-RawResponse '401 Unauthorized' 'who are you'
            '/moved'    = Get-RawResponse '302 Found' '' @{ Location = 'https://elsewhere.example/login' }
            '/broken'   = Get-RawResponse '500 Internal Server Error' "line one`r`nline two $('x' * 400)"
            '/silent'   = 'HANG'
        }
        $script:Rejecting = Open-TestServer -Default (Get-RawResponse '403 Forbidden' 'blocked by proxy')
    }
    AfterAll {
        Close-TestServer $script:Origin
        Close-TestServer $script:Rejecting
    }

    It 'answers OK for 200' {
        $r = Invoke-BeaconHttpCheck -Url "$($Origin.Url)/ok" -Config $Config
        $r.status | Should -Be 'OK'
        $r.data.status | Should -Be 200
        $r.data.proxy | Should -Be 'direct'
        $r.subject | Should -Be "$($Origin.Url)/ok"
    }

    It 'warns for 401 without expectation, and is OK when 401 is expected' {
        $warned = Invoke-BeaconHttpCheck -Url "$($Origin.Url)/denied" -Config $Config
        $warned.status | Should -Be 'WARN'
        $warned.detail | Should -Be '401 Unauthorized. who are you'
        $r =Invoke-BeaconHttpCheck -Url "$($Origin.Url)/denied" -ExpectedStatus 401 -Config $Config
        $r.status | Should -Be 'OK'
        $r.detail | Should -Be '401 Unauthorized, as expected: the route is open.'
    }

    It 'reports a redirect without following it' {
        $r = Invoke-BeaconHttpCheck -Url "$($Origin.Url)/moved" -Config $Config
        $r.status | Should -Be 'OK'
        $r.data.status | Should -Be 302
        $r.data.location | Should -Be 'https://elsewhere.example/login'
        $r.detail | Should -BeLike '*Redirects to https://elsewhere.example/login (not followed).'
    }

    It 'warns for 500 and cuts the body preview to one line of PreviewChars' {
        $r = Invoke-BeaconHttpCheck -Url "$($Origin.Url)/broken" -Config $Config
        $r.status | Should -Be 'WARN'
        $r.detail | Should -BeLike '500 Internal Server Error. line one line two x*'
        ($r.detail -replace '^500 Internal Server Error\. ', '').Length | Should -Be $Config.Http.PreviewChars
    }

    It 'warns when 500 is not the expected status' {
        $r = Invoke-BeaconHttpCheck -Url "$($Origin.Url)/broken" -ExpectedStatus 200, 401 -Config $Config
        $r.status | Should -Be 'WARN'
        $r.detail | Should -BeLike 'Expected 200 or 401, got 500 Internal Server Error.*'
    }

    It 'fails on a timeout' {
        $short = $Config.Clone()
        $short.TimeoutSeconds = @{ Http = 1 }
        $r = Invoke-BeaconHttpCheck -Url "$($Origin.Url)/silent" -Config $short
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike 'No answer from * within 1 s.'
    }

    It 'fails when nothing listens' {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $port = $probe.LocalEndpoint.Port
        $probe.Stop()
        $r = Invoke-BeaconHttpCheck -Url "http://127.0.0.1:$port/" -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike 'Connection to * failed:*'
    }

    It 'goes through the matrix proxy and warns, neutrally, when it answers 403 to a plain http URL' {
        $r = Invoke-BeaconHttpCheck -Url 'http://beacon-target.invalid/x' -MatrixProxy $Rejecting.Url -Config $Config
        $r.status | Should -Be 'WARN'
        $r.detail | Should -BeLike "403 Forbidden through proxy $($Rejecting.Url): the proxy or the service refused.*blocked by proxy"
        $r.data.proxy | Should -Be $Rejecting.Url
    }

    It 'blames the proxy when it refuses the tunnel of an https URL' {
        $r = Invoke-BeaconHttpCheck -Url 'https://beacon-target.invalid/x' -MatrixProxy $Rejecting.Url -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike "*$($Rejecting.Url)*403*"
        $r.data.proxy | Should -Be $Rejecting.Url
    }

    It 'takes the proxy from the environment variables of the process' {
        $saved = $env:HTTP_PROXY, $env:http_proxy, $env:NO_PROXY, $env:no_proxy
        try {
            $env:http_proxy = $null; $env:no_proxy = $null; $env:NO_PROXY = $null
            $env:HTTP_PROXY = $Rejecting.Url
            $r = Invoke-BeaconHttpCheck -Url 'http://beacon-target.invalid/x' -Config $Config
            $r.data.proxy | Should -Be $Rejecting.Url
            $r.status | Should -Be 'WARN'
        }
        finally { $env:HTTP_PROXY, $env:http_proxy, $env:NO_PROXY, $env:no_proxy = $saved }
    }

    It 'never shows the user info of a proxy taken from the environment' {
        $saved = $env:HTTP_PROXY, $env:http_proxy, $env:NO_PROXY, $env:no_proxy
        try {
            $env:http_proxy = $null; $env:no_proxy = $null; $env:NO_PROXY = $null
            $env:HTTP_PROXY = $Rejecting.Url -replace '//', '//alice:s3cret@'
            $r = Invoke-BeaconHttpCheck -Url 'http://beacon-target.invalid/x' -Config $Config
            $r.data.proxy | Should -Be $Rejecting.Url
            ($r | ConvertTo-Json -Depth 5) | Should -Not -Match 's3cret|alice'
        }
        finally { $env:HTTP_PROXY, $env:http_proxy, $env:NO_PROXY, $env:no_proxy = $saved }
    }

    It 'fails with the proxy named when the proxy is not listening' {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $port = $probe.LocalEndpoint.Port
        $probe.Stop()
        $r = Invoke-BeaconHttpCheck -Url 'https://beacon-target.invalid/' -MatrixProxy "http://127.0.0.1:$port" -Config $Config
        $r.status | Should -Be 'FAIL'
        $r.detail | Should -BeLike "Proxy http://127.0.0.1:$port unreachable:*"
    }
}
