BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Checks/Tls.ps1')

    function Get-TestCertificate {
        # Self-signed, in memory only. The PFX round trip makes the private key usable by SslStream on Windows.
        param([string] $DnsName, [datetime] $NotBefore, [datetime] $NotAfter)
        $key = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            "CN=$DnsName", $key,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $san = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
        $san.AddDnsName($DnsName)
        $request.CertificateExtensions.Add($san.Build())
        $selfSigned = $request.CreateSelfSigned($NotBefore, $NotAfter)
        $pfx = $selfSigned.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
        $selfSigned.Dispose()
        $key.Dispose()
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfx)
    }

    function Open-TestServer {
        # One connection on loopback, served from another runspace. Without a certificate it closes the socket at once.
        param($Certificate)
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $shell = [powershell]::Create()
        $null = $shell.AddScript({
                param($Listener, $Certificate)
                $client = $Listener.AcceptTcpClient()
                try {
                    if ($Certificate) {
                        $ssl = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
                        try {
                            $ssl.AuthenticateAsServer($Certificate)
                            $null = $ssl.Read([byte[]]::new(1), 0, 1)
                        }
                        catch { $null = $_ }
                        finally { $ssl.Dispose() }
                    }
                }
                finally { $client.Dispose() }
            }).AddArgument($listener).AddArgument($Certificate)
        [pscustomobject]@{
            Port     = $listener.LocalEndpoint.Port
            Listener = $listener
            Shell    = $shell
            Handle   = $shell.BeginInvoke()
        }
    }

    function Close-TestServer {
        param($Server)
        $Server.Listener.Stop()
        $null = $Server.Handle.AsyncWaitHandle.WaitOne(5000)
        $Server.Shell.Dispose()
    }

    $script:config = @{ TimeoutSeconds = @{ Tls = 30 } }
}

Describe 'Get-BeaconTlsOutcome' {
    BeforeAll {
        $script:now = [datetime]::new(2026, 10, 30, 12, 0, 0, [DateTimeKind]::Utc)
        function Get-TestFact {
            param([hashtable] $With = @{})
            $facts = @{
                handshakeOk  = $true
                error        = $null
                protocol     = 'Tls13'
                subject      = 'CN=portal.example.com'
                issuer       = 'CN=Example CA'
                notBefore    = [datetime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
                notAfter     = [datetime]::new(2027, 3, 1, 0, 0, 0, [DateTimeKind]::Utc)
                dnsNames     = @('portal.example.com')
                policyErrors = 'None'
                chainStatus  = @()
                durationMs   = 64
            }
            foreach ($key in $With.Keys) { $facts[$key] = $With[$key] }
            $facts
        }
        function Get-Outcome {
            param([hashtable] $Facts)
            Get-BeaconTlsOutcome -Facts $Facts -HostName 'portal.example.com' -Subject 'https://portal.example.com/health' -Now $script:now
        }
    }

    It 'is OK for a valid certificate' {
        $record = Get-Outcome (Get-TestFact)
        $record.check | Should -Be 'tls'
        $record.status | Should -Be 'OK'
        $record.detail | Should -Be 'Certificate valid for portal.example.com until 2027-03-01.'
        $record.data.notAfter | Should -Be '2027-03-01T00:00:00Z'
        $record.data.errors | Should -HaveCount 0
        $record.durationMs | Should -Be 64
    }

    It 'fails for an expired certificate and says the date' {
        $record = Get-Outcome (Get-TestFact @{ notAfter = [datetime]::new(2026, 10, 1, 0, 0, 0, [DateTimeKind]::Utc); chainStatus = @('NotTimeValid'); policyErrors = 'RemoteCertificateChainErrors' })
        $record.status | Should -Be 'FAIL'
        $record.detail | Should -Be 'Certificate expired on 2026-10-01.'
        $record.data.errors | Should -Be @('expired')
    }

    It 'fails for a certificate not yet valid' {
        $record = Get-Outcome (Get-TestFact @{ notBefore = [datetime]::new(2026, 12, 1, 0, 0, 0, [DateTimeKind]::Utc); chainStatus = @('NotTimeValid'); policyErrors = 'RemoteCertificateChainErrors' })
        $record.status | Should -Be 'FAIL'
        $record.detail | Should -Be 'Certificate not valid before 2026-12-01.'
        $record.data.errors | Should -Be @('notYetValid')
    }

    It 'fails for an untrusted issuer and names it' {
        $record = Get-Outcome (Get-TestFact @{ chainStatus = @('UntrustedRoot'); policyErrors = 'RemoteCertificateChainErrors' })
        $record.status | Should -Be 'FAIL'
        $record.detail | Should -BeLike 'Certificate not trusted: issued by CN=Example CA, which is not in the system trust store*'
        $record.data.errors | Should -Be @('untrusted')
    }

    It 'treats a partial chain as untrusted' {
        (Get-Outcome (Get-TestFact @{ chainStatus = @('PartialChain'); policyErrors = 'RemoteCertificateChainErrors' })).data.errors | Should -Be @('untrusted')
    }

    It 'fails for another name and lists the names of the certificate' {
        $record = Get-Outcome (Get-TestFact @{ dnsNames = @('a.example.com', 'b.example.com'); policyErrors = 'RemoteCertificateNameMismatch' })
        $record.status | Should -Be 'FAIL'
        $record.detail | Should -Be 'Certificate is for a.example.com, b.example.com, not portal.example.com.'
        $record.data.errors | Should -Be @('nameMismatch')
    }

    It 'falls back to the subject when the certificate has no names' {
        (Get-Outcome (Get-TestFact @{ dnsNames = @(); subject = 'CN=other'; policyErrors = 'RemoteCertificateNameMismatch' })).detail |
            Should -Be 'Certificate is for CN=other, not portal.example.com.'
    }

    It 'reports every problem together' {
        $record = Get-Outcome (Get-TestFact @{
                notAfter     = [datetime]::new(2026, 10, 1, 0, 0, 0, [DateTimeKind]::Utc)
                chainStatus  = @('NotTimeValid', 'UntrustedRoot')
                policyErrors = 'RemoteCertificateNameMismatch, RemoteCertificateChainErrors'
                dnsNames     = @('other.example.com')
            })
        $record.data.errors | Should -Be @('expired', 'untrusted', 'nameMismatch')
        $record.detail | Should -BeLike '*expired on 2026-10-01.*not trusted*other.example.com, not portal.example.com.'
    }

    It 'fails a handshake that did not complete, with the error and a hint' {
        $record = Get-Outcome @{ handshakeOk = $false; error = 'Connection reset by peer'; durationMs = 7 }
        $record.status | Should -Be 'FAIL'
        $record.detail | Should -BeLike 'TLS handshake failed: Connection reset by peer.*'
        $record.data.errors | Should -Be @('handshake')
        $record.durationMs | Should -Be 7
    }

    It 'uses the subject it is given' {
        (Get-Outcome (Get-TestFact)).subject | Should -Be 'https://portal.example.com/health'
    }
}

Describe 'Invoke-BeaconTlsCheck' {
    AfterEach {
        if ($script:server) { Close-TestServer $script:server; $script:server = $null }
        if ($script:certificate) { $script:certificate.Dispose(); $script:certificate = $null }
    }

    It 'finds a self-signed certificate for another name untrusted and with a wrong name' {
        $script:certificate = Get-TestCertificate -DnsName 'other.invalid' -NotBefore ([datetime]::UtcNow.AddDays(-1)) -NotAfter ([datetime]::UtcNow.AddDays(30))
        $script:server = Open-TestServer $script:certificate
        $record = Invoke-BeaconTlsCheck -HostName 'beacon.test' -Address '127.0.0.1' -Port $script:server.Port -Config $script:config
        $record.check | Should -Be 'tls'
        $record.subject | Should -Be "https://beacon.test:$($script:server.Port)"
        $record.status | Should -Be 'FAIL'
        $record.data.errors | Should -Contain 'untrusted'
        $record.data.errors | Should -Contain 'nameMismatch'
        $record.detail | Should -BeLike '*Certificate is for other.invalid, not beacon.test.*'
        $record.data.subject | Should -Be 'CN=other.invalid'
    }

    It 'finds an expired certificate and takes the subject it is given' {
        $script:certificate = Get-TestCertificate -DnsName 'beacon.test' -NotBefore ([datetime]::UtcNow.AddDays(-10)) -NotAfter ([datetime]::UtcNow.AddDays(-1))
        $script:server = Open-TestServer $script:certificate
        $record = Invoke-BeaconTlsCheck -HostName 'beacon.test' -Address '127.0.0.1' -Port $script:server.Port -Config $script:config -Subject 'https://beacon.test/health'
        $record.subject | Should -Be 'https://beacon.test/health'
        $record.status | Should -Be 'FAIL'
        $record.data.errors | Should -Contain 'expired'
        $record.data.errors | Should -Not -Contain 'nameMismatch'
        $record.detail | Should -BeLike 'Certificate expired on *'
    }

    It 'fails the handshake when the peer closes without speaking TLS' {
        $script:server = Open-TestServer $null
        $record = Invoke-BeaconTlsCheck -HostName 'beacon.test' -Address '127.0.0.1' -Port $script:server.Port -Config $script:config
        $record.status | Should -Be 'FAIL'
        $record.data.errors | Should -Be @('handshake')
    }
}
