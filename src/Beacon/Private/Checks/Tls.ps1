function Invoke-BeaconTlsProbe {
    <# Network half: TCP connect and TLS handshake, returns raw facts. Judging the certificate is Get-BeaconTlsOutcome's job. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $HostName,
        [Parameter(Mandatory)] [string] $Address,
        [Parameter(Mandatory)] [int] $Port,
        [Parameter(Mandatory)] [ValidateRange(1, [int]::MaxValue)] [int] $TimeoutSeconds
    )

    $facts = @{
        handshakeOk  = $false
        error        = $null
        protocol     = $null
        subject      = $null
        issuer       = $null
        notBefore    = $null
        notAfter     = $null
        dnsNames     = @()
        policyErrors = 'None'
        chainStatus  = @()
        durationMs   = 0
    }
    $timeoutMs = $TimeoutSeconds * 1000
    $seen = @{ policyErrors = 'None'; chainStatus = @(); certificate = $null }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $client = [System.Net.Sockets.TcpClient]::new()
    $ssl = $null
    try {
        if (-not $client.ConnectAsync($Address, $Port).Wait($timeoutMs)) {
            throw [System.TimeoutException]::new("TCP connection timed out after $TimeoutSeconds s")
        }
        $network = $client.GetStream()
        $network.ReadTimeout = $timeoutMs
        $network.WriteTimeout = $timeoutMs

        # The callback accepts everything and only records: the certificate is judged afterwards. The synchronous call
        # keeps the callback on this thread, where the runspace is available.
        $callback = [System.Net.Security.RemoteCertificateValidationCallback] {
            # Arguments by position: sender, certificate, chain, policy errors.
            $certificate, $chain, $errors = $args[1], $args[2], $args[3]
            $seen.policyErrors = [string] $errors
            if ($chain) { $seen.chainStatus = @($chain.ChainStatus | ForEach-Object { [string] $_.Status }) }
            if ($certificate) { $seen.certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificate) }
            $true
        }.GetNewClosure()
        $options = [System.Net.Security.SslClientAuthenticationOptions]::new()
        $options.TargetHost = $HostName
        $options.RemoteCertificateValidationCallback = $callback
        $ssl = [System.Net.Security.SslStream]::new($network, $false)
        $ssl.AuthenticateAsClient($options)

        $facts.handshakeOk = $true
        $facts.protocol = [string] $ssl.SslProtocol
    }
    catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        $facts.error = $inner.Message
    }
    finally {
        if ($ssl) { $ssl.Dispose() }
        $client.Dispose()
    }

    $facts.policyErrors = $seen.policyErrors
    $facts.chainStatus = @($seen.chainStatus)
    $certificate = $seen.certificate
    if ($certificate) {
        $facts.subject = $certificate.Subject
        $facts.issuer = $certificate.Issuer
        $facts.notBefore = $certificate.NotBefore.ToUniversalTime()
        $facts.notAfter = $certificate.NotAfter.ToUniversalTime()
        $facts.dnsNames = @(Get-BeaconCertificateDnsName -Certificate $certificate)
        $certificate.Dispose()
    }
    $facts.durationMs = [int] $stopwatch.ElapsedMilliseconds
    $facts
}

function Get-BeaconCertificateDnsName {
    <# DNS names of the subject alternative name extension; its text form differs between Windows ("DNS Name=") and Linux ("DNS:"). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [System.Security.Cryptography.X509Certificates.X509Certificate2] $Certificate
    )

    $extension = $Certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' } | Select-Object -First 1
    if (-not $extension) { return [string[]] @() }
    [string[]] @([regex]::Matches($extension.Format($false), 'DNS(?: Name)?[=:]\s*([^,\s]+)') | ForEach-Object { $_.Groups[1].Value })
}

function Get-BeaconTlsOutcome {
    <# Pure half: facts of the handshake -> check record. Names every problem found, not only the first. #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [hashtable] $Facts,
        [Parameter(Mandatory)] [string] $HostName,
        [Parameter(Mandatory)] [string] $Subject,
        [datetime] $Now = [datetime]::UtcNow
    )

    $now = $Now.ToUniversalTime()
    $day = { param([datetime] $d) $d.ToUniversalTime().ToString('yyyy-MM-dd') }

    if (-not $Facts.handshakeOk) {
        $detail = "TLS handshake failed: $($Facts.error). Check that the port speaks TLS, and that client and server share a protocol version."
        return New-BeaconCheckRecord -Check tls -Subject $Subject -Status FAIL -Detail $detail -DurationMs $Facts.durationMs `
            -Data @{ errors = @('handshake'); error = $Facts.error }
    }

    $chainStatus = @($Facts.chainStatus)
    $policyErrors = [string] $Facts.policyErrors
    $errors = [System.Collections.Generic.List[string]]::new()
    $problems = [System.Collections.Generic.List[string]]::new()

    $timeInvalid = $chainStatus -contains 'NotTimeValid'
    if ($Facts.notAfter -and $now -gt $Facts.notAfter.ToUniversalTime()) {
        $errors.Add('expired')
        $problems.Add("Certificate expired on $(& $day $Facts.notAfter).")
    }
    elseif ($Facts.notBefore -and $now -lt $Facts.notBefore.ToUniversalTime()) {
        $errors.Add('notYetValid')
        $problems.Add("Certificate not valid before $(& $day $Facts.notBefore).")
    }
    elseif ($timeInvalid) {
        $errors.Add('expired')
        $problems.Add('Certificate is outside its validity period.')
    }

    $otherChainErrors = @($chainStatus | Where-Object { $_ -notin 'NoError', 'NotTimeValid' })
    if ($otherChainErrors -or ($policyErrors -match 'RemoteCertificateChainErrors' -and -not $timeInvalid)) {
        $errors.Add('untrusted')
        $issuer = if ($Facts.issuer) { $Facts.issuer } else { 'an unknown issuer' }
        $why = if ($otherChainErrors) { " ($($otherChainErrors -join ', '))" } else { '' }
        $problems.Add("Certificate not trusted: issued by $issuer, which is not in the system trust store$why.")
    }

    if ($policyErrors -match 'RemoteCertificateNameMismatch') {
        $errors.Add('nameMismatch')
        $names = @($Facts.dnsNames)
        $forWhom = if ($names.Count) { $names -join ', ' } else { $Facts.subject }
        $problems.Add("Certificate is for $forWhom, not $HostName.")
    }

    if ($policyErrors -match 'RemoteCertificateNotAvailable') {
        $errors.Add('handshake')
        $problems.Add('The server sent no certificate.')
    }

    $data = [ordered]@{
        subject  = $Facts.subject
        issuer   = $Facts.issuer
        notAfter = if ($Facts.notAfter) { $Facts.notAfter.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") } else { $null }
        protocol = $Facts.protocol
        errors   = @($errors)
    }
    if ($errors.Count) {
        return New-BeaconCheckRecord -Check tls -Subject $Subject -Status FAIL -Detail ($problems -join ' ') -DurationMs $Facts.durationMs -Data $data
    }
    $detail = "Certificate valid for $HostName until $(& $day $Facts.notAfter)."
    New-BeaconCheckRecord -Check tls -Subject $Subject -Status OK -Detail $detail -DurationMs $Facts.durationMs -Data $data
}

function Invoke-BeaconTlsCheck {
    <# The TLS check: probe, then judge. -Subject overrides the default https://host:port (the chain passes the URL). #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [string] $HostName,
        [Parameter(Mandatory)] [string] $Address,
        [Parameter(Mandatory)] [int] $Port,
        [Parameter(Mandatory)] [hashtable] $Config,
        [string] $Subject
    )

    if (-not $Subject) { $Subject = "https://${HostName}:$Port" }
    $facts = Invoke-BeaconTlsProbe -HostName $HostName -Address $Address -Port $Port -TimeoutSeconds $Config.TimeoutSeconds.Tls
    Get-BeaconTlsOutcome -Facts $facts -HostName $HostName -Subject $Subject
}
