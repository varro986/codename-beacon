BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Matrix.ps1')

    $script:Config = Get-BeaconConfig
    $script:ExamplePath = Join-Path $PSScriptRoot '../specs/features/001-diagnostic-chain/contracts/matrix.example.psd1'

    # Writes a matrix file in $TestDrive and returns its path.
    function Write-MatrixFile {
        param([string] $Content)
        $path = Join-Path $TestDrive ('matrix-{0}.psd1' -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $path -Value $Content
        $path
    }

    # A matrix with one environment 'test', one group 'web' and the given text as the targets list.
    function Write-TargetsMatrix {
        param([string] $Targets)
        Write-MatrixFile "@{ Environments = @{ test = @{ Groups = @{ web = @{ Targets = @($Targets) } } } } }"
    }

    # The input error raised when reading the matrix, or $null when it reads.
    function Get-ReadError {
        param([string] $Path)
        try { Read-BeaconMatrix -Path $Path -Config $script:Config | Out-Null }
        catch { return $_ }
    }
}

Describe 'Read-BeaconMatrix with the example matrix' {
    BeforeAll {
        $script:Matrix = Read-BeaconMatrix -Path $script:ExamplePath -Config $script:Config
    }

    It 'reads the file' {
        $script:Matrix.Environments.Keys | Sort-Object | Should -Be @('production', 'test')
    }

    It 'yields the targets of test, sorted by group then name, with the proxy' {
        $result = Get-BeaconTargets -Matrix $script:Matrix -Environment 'test'
        $result.Proxy | Should -Be 'http://proxy.example.net:8080'
        @($result.Targets | ForEach-Object { "$($_.Group)/$($_.Name)" }) | Should -Be @('legacy/archive', 'web/api', 'web/portal')
        $api = $result.Targets | Where-Object Name -EQ 'api'
        $api.Host | Should -Be 'api.example.com'
        $api.Ports | Should -Be @(443, 8443, 8444)
        $api.Urls | Should -Be @('https://api.example.com/v1/items')
        $api.ExpectedStatus | Should -Be @(401)
        $api.SecretEnv | Should -Be 'BEACON_API_TOKEN'
        $portal = $result.Targets | Where-Object Name -EQ 'portal'
        $portal.ExpectedAddresses | Should -Be @('192.0.2.10')
        $portal.ExpectedStatus.Count | Should -Be 0
        $portal.SecretEnv | Should -BeNullOrEmpty
    }

    It 'yields only the targets of production, without proxy, when several environments exist' {
        $result = Get-BeaconTargets -Matrix $script:Matrix -Environment 'production'
        $result.Proxy | Should -BeNullOrEmpty
        $result.Targets.Count | Should -Be 1
        $result.Targets[0].Group | Should -Be 'web'
        $result.Targets[0].Name | Should -Be 'portal'
        $result.Targets[0].ExpectedAddresses.Count | Should -Be 0
    }

    It 'rejects an unknown environment and lists the available ones' {
        $err = try { Get-BeaconTargets -Matrix $script:Matrix -Environment 'staging' } catch { $_ }
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        $err.Exception.Message | Should -Match "'staging'"
        $err.Exception.Message | Should -Match 'Available: production, test'
    }
}

Describe 'Read-BeaconMatrix file errors' {
    It 'reports a missing file as an input error' {
        $err = Get-ReadError (Join-Path $TestDrive 'nope.psd1')
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        $err.Exception.Message | Should -Match 'not found'
    }

    It 'reports a parse error as an input error' {
        $err = Get-ReadError (Write-MatrixFile '@{ Environments = ')
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        $err.Exception.Message | Should -Match 'cannot be read'
    }

    It 'does not run code in the file' {
        $marker = Join-Path $TestDrive 'ran.txt'
        $err = Get-ReadError (Write-MatrixFile "@{ Environments = @{ test = @{ Groups = (Set-Content -Path '$marker' -Value x) } } }")
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        Test-Path $marker | Should -BeFalse
    }
}

Describe 'Read-BeaconMatrix structure' {
    It 'requires Environments, and only that top-level key' {
        $err = Get-ReadError (Write-MatrixFile "@{ Envs = @{} }")
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        $err.Exception.Message | Should -Match "Matrix: unknown key 'Envs'. Allowed keys: Environments"
        $err.Exception.Message | Should -Match 'Environments: missing or empty. Add at least one environment'
    }

    It 'requires Groups in an environment' {
        $err = Get-ReadError (Write-MatrixFile "@{ Environments = @{ test = @{ Proxy = 'http://p.example.net:80' } } }")
        $err.Exception.Message | Should -Match 'Environments\.test\.Groups: missing or empty. Add at least one group'
    }

    It 'rejects an unknown key in an environment' {
        $err = Get-ReadError (Write-MatrixFile "@{ Environments = @{ test = @{ Groop = @{}; Groups = @{ web = @{ Targets = @(@{ Name = 'a'; Host = 'h' }) } } } } }")
        $err.Exception.Message | Should -Match "Environments\.test: unknown key 'Groop'. Allowed keys: Groups, Proxy"
    }

    It 'rejects a proxy that is not an absolute http(s) URL' {
        $err = Get-ReadError (Write-MatrixFile "@{ Environments = @{ test = @{ Proxy = 'proxy:8080'; Groups = @{ web = @{ Targets = @(@{ Name = 'a'; Host = 'h' }) } } } } }")
        $err.Exception.Message | Should -Match 'Environments\.test\.Proxy: must be an absolute http or https URL'
    }

    It 'rejects user info in the proxy without echoing it' {
        $err = Get-ReadError (Write-MatrixFile "@{ Environments = @{ test = @{ Proxy = 'http://alice:s3cret@proxy.example.net:8080'; Groups = @{ web = @{ Targets = @(@{ Name = 'a'; Host = 'h' }) } } } } }")
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        $err.Exception.Message | Should -Match 'Environments\.test\.Proxy: must not contain user info'
        $err.Exception.Message | Should -Not -Match 's3cret|alice'
    }

    It 'rejects user info in a target URL without echoing it' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Urls = @('https://alice:s3cret@h.example.net/x') }")
        $err.Exception.Message | Should -Match 'Targets\[0\]\.Urls: a URL contains user info'
        $err.Exception.Message | Should -Not -Match 's3cret|alice'
    }

    It 'requires non-empty Targets in a group' {
        $err = Get-ReadError (Write-MatrixFile "@{ Environments = @{ test = @{ Groups = @{ web = @{ Targets = @() } } } } }")
        $err.Exception.Message | Should -Match 'Environments\.test\.Groups\.web\.Targets: missing or empty. Add a list'
    }

    It 'rejects an unknown key in a group' {
        $err = Get-ReadError (Write-MatrixFile "@{ Environments = @{ test = @{ Groups = @{ web = @{ Hosts = 1; Targets = @(@{ Name = 'a'; Host = 'h' }) } } } } }")
        $err.Exception.Message | Should -Match "Environments\.test\.Groups\.web: unknown key 'Hosts'. Allowed keys: Targets"
    }
}

Describe 'Read-BeaconMatrix target rules' {
    It 'names the entry and the fix when Host is missing' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h' }, @{ Name = 'b' }")
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        $err.Exception.Message | Should -Match ([regex]::Escape("Environments.test.Groups.web.Targets[1]: Host is missing. Add Host = '<name or address>'."))
    }

    It 'names the entry and the fix when Name is missing' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Host = 'h' }")
        $err.Exception.Message | Should -Match ([regex]::Escape("Targets[0]: Name is missing. Add Name = "))
    }

    It 'rejects an empty Host' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = ' ' }")
        $err.Exception.Message | Should -Match 'Targets\[0\]\.Host: must be a non-empty string'
    }

    It 'rejects a duplicate Name in a group but allows it across groups' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h' }, @{ Name = 'A'; Host = 'h2' }")
        $err.Exception.Message | Should -Match "Targets\[1\]\.Name: 'A' is already used by Targets\[0\]"

        $path = Write-MatrixFile "@{ Environments = @{ test = @{ Groups = @{ one = @{ Targets = @(@{ Name = 'a'; Host = 'h' }) }; two = @{ Targets = @(@{ Name = 'a'; Host = 'h' }) } } } } }"
        { Read-BeaconMatrix -Path $path -Config $script:Config } | Should -Not -Throw
    }

    It 'rejects a key outside the allowed ones and names them' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Port = 443 }")
        $err.Exception.Message | Should -Match "Targets\[0\]: unknown key 'Port'. Allowed keys: Name, Host, ExpectedAddresses, Ports, Urls, Expect, SecretEnv"
    }

    It 'rejects a target that is not a table' {
        $err = Get-ReadError (Write-TargetsMatrix "'a'")
        $err.Exception.Message | Should -Match 'Targets\[0\]: a target must be a table'
    }

    It 'rejects an invalid expected address' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; ExpectedAddresses = @('192.0.2.10', '999.1.1.1') }")
        $err.Exception.Message | Should -Match "Targets\[0\]\.ExpectedAddresses: '999\.1\.1\.1' is not an IP address. Use an IPv4 or IPv6"
        $err.Exception.Message | Should -Not -Match "'192\.0\.2\.10' is not"
    }

    It 'accepts IPv6 addresses' {
        $path = Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; ExpectedAddresses = @('2001:db8::1') }"
        { Read-BeaconMatrix -Path $path -Config $script:Config } | Should -Not -Throw
    }

    It 'rejects a URL that is relative or not http(s)' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Urls = @('/health', 'ftp://h/x') }")
        $err.Exception.Message | Should -Match "Targets\[0\]\.Urls: '/health' is not an absolute http or https URL. Write it as"
        $err.Exception.Message | Should -Match "Targets\[0\]\.Urls: 'ftp://h/x' is not"
    }

    It 'rejects Expect with a key other than Http' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Expect = @{ Dns = 1 } }")
        $err.Exception.Message | Should -Match "Targets\[0\]\.Expect: unknown key 'Dns'. Allowed keys: Http"
    }

    It 'rejects an Expect.Http status outside 100-599' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Expect = @{ Http = @(200, 700) } }")
        $err.Exception.Message | Should -Match "Targets\[0\]\.Expect\.Http: '700' is not an HTTP status. Use an integer from 100 to 599"
    }

    It 'accepts several expected statuses' {
        $path = Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Expect = @{ Http = @(200, 401) } }"
        $matrix = Read-BeaconMatrix -Path $path -Config $script:Config
        (Get-BeaconTargets -Matrix $matrix -Environment 'test').Targets[0].ExpectedStatus | Should -Be @(200, 401)
    }

    It 'collects every problem in one error, one per line' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a' }, @{ Host = 'h' }, @{ Name = 'c'; Host = 'h'; Ports = 0 }")
        $lines = $err.Exception.Message -split "`n"
        $lines.Count | Should -Be 4
        $lines[0] | Should -Match '3 problem\(s\)'
        $lines[1] | Should -Match 'Targets\[0\]: Host is missing'
        $lines[2] | Should -Match 'Targets\[1\]: Name is missing'
        $lines[3] | Should -Match 'Targets\[2\]\.Ports'
    }
}

Describe 'Read-BeaconMatrix SecretEnv' {
    It 'accepts a variable name' {
        $path = Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; SecretEnv = 'BEACON_API_TOKEN' }"
        { Read-BeaconMatrix -Path $path -Config $script:Config } | Should -Not -Throw
    }

    It 'rejects a secret-looking value, says to put the name, and never echoes the value' {
        $secret = 'sk-live_9f8e7d6c5b4a/3+2=1'
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; SecretEnv = '$secret' }")
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        $err.Exception.Message | Should -Match 'Targets\[0\]\.SecretEnv: must be the NAME of an environment variable'
        $err.Exception.Message | Should -Match 'never the secret value'
        $err.Exception.Message | Should -Not -Match ([regex]::Escape($secret))
        $err.Exception.Message | Should -Not -Match '9f8e7d6c'
    }

    It 'rejects a value with spaces without echoing it' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; SecretEnv = 'my secret value' }")
        $err.Exception.Message | Should -Match 'SecretEnv: must be the NAME'
        $err.Exception.Message | Should -Not -Match 'my secret value'
    }

    It 'rejects a name starting with a digit' {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; SecretEnv = '1TOKEN' }")
        $err.Exception.Message | Should -Match 'SecretEnv: must be the NAME'
    }
}

Describe 'Ports' {
    It 'expands single ports and ranges, unique and sorted' {
        Expand-BeaconPort -Ports @(8444, '8443-8445', 443, 443) | Should -Be @(443, 8443, 8444, 8445)
    }

    It 'expands a range with spaces around the dash' {
        Expand-BeaconPort -Ports @('80 - 82') | Should -Be @(80, 81, 82)
    }

    It 'returns the expanded ports in the targets of the matrix' {
        $path = Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Ports = @(443, '8443-8444') }"
        $matrix = Read-BeaconMatrix -Path $path -Config $script:Config
        (Get-BeaconTargets -Matrix $matrix -Environment 'test').Targets[0].Ports | Should -Be @(443, 8443, 8444)
    }

    It 'does not add the ports of the URLs' {
        $path = Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Urls = @('https://h/x') }"
        $matrix = Read-BeaconMatrix -Path $path -Config $script:Config
        (Get-BeaconTargets -Matrix $matrix -Environment 'test').Targets[0].Ports.Count | Should -Be 0
    }

    It 'accepts a range of exactly the limit' {
        $limit = $script:Config.MaxPortsPerTarget
        $path = Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Ports = @('1000-$(999 + $limit)') }"
        { Read-BeaconMatrix -Path $path -Config $script:Config } | Should -Not -Throw
    }

    It 'rejects more ports than the limit: it tests declared ports, it does not scan' {
        $limit = $script:Config.MaxPortsPerTarget
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Ports = @('1000-$(1000 + $limit)') }")
        $err.Exception.Message | Should -Match "Targets\[0\]\.Ports: $($limit + 1) ports declared, the limit is $limit"
        $err.Exception.Message | Should -Match 'it does not scan'
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'port 0'; Port = '0'; Expected = 'port 0 is out of range' }
        @{ Case = 'port 65536'; Port = '65536'; Expected = 'port 65536 is out of range' }
        @{ Case = 'a backwards range'; Port = "'90-80'"; Expected = "range '90-80' runs backwards. Write it as 'from-to'" }
        @{ Case = 'a range past 65535'; Port = "'65530-65540'"; Expected = "range '65530-65540' is out of range" }
        @{ Case = 'text'; Port = "'https'"; Expected = "'https' is not a port or a range" }
        @{ Case = 'a number as text'; Port = "'443'"; Expected = "'443' is not a port or a range" }
    ) {
        $err = Get-ReadError (Write-TargetsMatrix "@{ Name = 'a'; Host = 'h'; Ports = @($Port) }")
        $err.FullyQualifiedErrorId | Should -BeLike 'BeaconInput*'
        $err.Exception.Message | Should -Match "Targets\[0\]\.Ports: $([regex]::Escape($Expected))"
    }
}
