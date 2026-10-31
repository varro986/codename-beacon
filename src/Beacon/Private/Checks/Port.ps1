function Get-BeaconPortOutcome {
    <# Pure half of the port check: the facts of a TCP connection attempt become a check record. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure: builds an object, changes nothing.')]
    [CmdletBinding()]
    [OutputType([ordered])]
    param(
        [Parameter(Mandatory)] [int] $Port,
        # connected, reason (refused, timeout, unreachable, other), error (socket error, for other), durationMs, sourceAddress
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Facts,
        [Parameter(Mandatory)] [int] $TimeoutSeconds
    )

    $data = [ordered]@{}
    if ($Facts.connected) {
        $status = 'OK'
        $detail = "TCP connection opened from $($Facts.sourceAddress)."
    }
    else {
        $status = 'FAIL'
        $data.reason = $Facts.reason
        $detail = switch ($Facts.reason) {
            'refused' { 'Refused: the host answered, nothing listens on this port.' }
            'timeout' { "Timed out after $TimeoutSeconds s: filtered, likely a firewall." }
            'unreachable' { 'No route to the address: check routing and the VPN.' }
            default { "Connection failed ($($Facts.error)): check the address and the network." }
        }
        if ($Facts.reason -eq 'other') { $data.error = [string] $Facts.error }
    }
    $data.sourceAddress = $Facts.sourceAddress

    New-BeaconCheckRecord -Check port -Subject "$Port" -Status $status -Detail $detail -DurationMs $Facts.durationMs -Data $data
}

function Get-BeaconSourceAddress {
    <# The local address the system would use to reach the target. A UDP connect sends no packet, so it works even when TCP fails. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [System.Net.IPAddress] $Address,
        [Parameter(Mandatory)] [int] $Port
    )

    $udp = [System.Net.Sockets.Socket]::new($Address.AddressFamily, [System.Net.Sockets.SocketType]::Dgram, [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $udp.Connect($Address, $Port)
        $udp.LocalEndPoint.Address.ToString()
    }
    catch [System.Net.Sockets.SocketException] {
        $null
    }
    finally {
        $udp.Dispose()
    }
}

function Invoke-BeaconPortCheck {
    <# Opens a TCP connection to the address and port, and reports what happened. #>
    [CmdletBinding()]
    [OutputType([ordered])]
    param(
        [Parameter(Mandatory)] [string] $Address,
        [Parameter(Mandatory)] [int] $Port,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    $timeout = $Config.TimeoutSeconds.Port
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref] $ip)) {
        # A name (the chain passes the proxy's host): the DNS probe, with its timeout; IPv4 first, as the chain does.
        $dns = Get-BeaconDnsFact -HostName $Address -Config $Config
        $resolved = @($dns.Addresses | Where-Object { $_ -notmatch ':' }) + @($dns.Addresses | Where-Object { $_ -match ':' })
        if ($dns.ErrorKind -or -not $resolved.Count) {
            $data = [ordered]@{ reason = 'other'; error = 'NameNotResolved'; sourceAddress = $null }
            return New-BeaconCheckRecord -Check port -Subject "$Port" -Status FAIL -DurationMs $dns.DurationMs -Data $data `
                -Detail "Name $Address does not resolve: check it, or its DNS zone."
        }
        $ip = [System.Net.IPAddress]::Parse($resolved[0])
    }
    $facts = @{ connected = $false; reason = $null; error = $null; sourceAddress = $null }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $socket = [System.Net.Sockets.Socket]::new($ip.AddressFamily, [System.Net.Sockets.SocketType]::Stream, [System.Net.Sockets.ProtocolType]::Tcp)
    $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($timeout))
    try {
        try {
            $socket.ConnectAsync($ip, $Port, $cts.Token).AsTask().GetAwaiter().GetResult()
            $facts.connected = $true
            $facts.sourceAddress = $socket.LocalEndPoint.Address.ToString()
        }
        catch [System.OperationCanceledException] {
            $facts.reason = 'timeout'
        }
        catch [System.Net.Sockets.SocketException] {
            $code = $_.Exception.SocketErrorCode
            $facts.reason = switch ($code) {
                'ConnectionRefused' { 'refused' }
                { $_ -in 'HostUnreachable', 'NetworkUnreachable', 'NetworkDown' } { 'unreachable' }
                default { 'other' }
            }
            $facts.error = [string] $code
        }
    }
    finally {
        $stopwatch.Stop()
        $cts.Dispose()
        $socket.Dispose()
    }
    if (-not $facts.connected) { $facts.sourceAddress = Get-BeaconSourceAddress -Address $ip -Port $Port }
    $facts.durationMs = [int] $stopwatch.ElapsedMilliseconds

    Get-BeaconPortOutcome -Port $Port -Facts $facts -TimeoutSeconds $timeout
}
