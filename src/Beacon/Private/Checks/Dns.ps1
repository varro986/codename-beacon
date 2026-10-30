function Get-BeaconDnsServer {
    <# DNS servers of the operational interfaces, distinct, as text. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $servers = foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
        foreach ($address in $nic.GetIPProperties().DnsAddresses) { $address.ToString() }
    }
    [string[]] @($servers | Select-Object -Unique)
}

function Get-BeaconDnsFact {
    <# Probe half: asks the system resolver and returns the raw facts, no judgement. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $HostName,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    $facts = @{
        HostName       = $HostName
        IsLiteral      = $false
        Addresses      = [string[]] @()
        Servers        = [string[]] @()
        ErrorKind      = $null
        ErrorMessage   = $null
        TimeoutSeconds = $Config.TimeoutSeconds.Dns
        DurationMs     = 0
    }

    $parsed = $null
    if ([System.Net.IPAddress]::TryParse($HostName, [ref] $parsed)) {
        $facts.IsLiteral = $true
        $facts.Addresses = [string[]] @($parsed.ToString())
        return $facts
    }

    $facts.Servers = Get-BeaconDnsServer
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $task = [System.Net.Dns]::GetHostAddressesAsync($HostName)
        if ($task.Wait([timespan]::FromSeconds($Config.TimeoutSeconds.Dns))) {
            $facts.Addresses = [string[]] @($task.Result | ForEach-Object { $_.ToString() })
        }
        else {
            $facts.ErrorKind = 'timeout'
        }
    }
    catch {
        # PowerShell and Task.Wait wrap the real exception (MethodInvocation, Aggregate)
        $inner = $_.Exception
        while ($inner.InnerException -and $inner -isnot [System.Net.Sockets.SocketException]) { $inner = $inner.InnerException }
        $facts.ErrorMessage = $inner.Message
        $facts.ErrorKind = 'other'
        if ($inner -is [System.Net.Sockets.SocketException]) {
            $facts.ErrorKind = switch ($inner.SocketErrorCode) {
                { $_ -in 'HostNotFound', 'NoData' } { 'notFound' }
                'TryAgain' { 'serverFailure' }
                default { 'other' }
            }
        }
    }
    $watch.Stop()
    $facts.DurationMs = [int] $watch.ElapsedMilliseconds
    # A name that resolves to nothing is a name not found
    if (-not $facts.ErrorKind -and $facts.Addresses.Count -eq 0) { $facts.ErrorKind = 'notFound' }
    $facts
}

function Get-BeaconDnsOutcome {
    <# Pure half: facts and expected addresses become the check record. #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [hashtable] $Facts,
        [string[]] $ExpectedAddresses
    )

    $record = { param($status, $detail, $data) New-BeaconCheckRecord -Check dns -Subject $Facts.HostName -Status $status -Detail $detail -DurationMs $Facts.DurationMs -Data $data }
    $servers = @($Facts.Servers)
    $serverText = if ($servers.Count) { $servers -join ', ' } else { 'none found on this machine' }

    if ($Facts.ErrorKind) {
        $data = [ordered]@{ servers = $servers }
        switch ($Facts.ErrorKind) {
            'notFound' {
                $data.error = 'NXDOMAIN'
                $detail = "Name not found (NXDOMAIN) from the system resolver (configured DNS servers: $serverText): check the name, or the DNS zone it belongs to."
            }
            'serverFailure' {
                $data.error = 'SERVFAIL'
                $detail = "The DNS server failed to answer for this name (system resolver, configured DNS servers: $serverText): check the DNS servers are reachable and working."
            }
            'timeout' {
                $data.error = 'timeout'
                $detail = "No answer within $($Facts.TimeoutSeconds) s from the system resolver (configured DNS servers: $serverText): check the DNS servers are reachable."
            }
            default {
                $data.error = 'other'
                $detail = "Name resolution failed ($($Facts.ErrorMessage)) asking the system resolver (configured DNS servers: $serverText): check the name and that the DNS servers are reachable."
            }
        }
        return & $record 'FAIL' $detail $data
    }

    # IPv4 first: the chain uses the first address
    $all = @($Facts.Addresses)
    $ordered = @($all | Where-Object { $_ -notmatch ':' }) + @($all | Where-Object { $_ -match ':' })
    $data = [ordered]@{ addresses = $ordered }
    if (-not $Facts.IsLiteral) { $data.servers = $servers }

    $expected = @($ExpectedAddresses | Where-Object { $_ })
    $normalize = {
        param($text)
        $ip = $null
        if ([System.Net.IPAddress]::TryParse($text, [ref] $ip)) { $ip.ToString() } else { $text }
    }
    $found = @($ordered | ForEach-Object { & $normalize $_ })
    $missing = @($expected | Where-Object { (& $normalize $_) -notin $found })
    if ($missing.Count) {
        $detail = "Resolved to $($ordered -join ', '), expected $($expected -join ', '): other address than expected (missing $($missing -join ', '))."
        return & $record 'WARN' $detail $data
    }

    if ($Facts.IsLiteral) { return & $record 'OK' 'Address given, no DNS lookup.' $data }
    $detail = "Resolved to $($ordered -join ', ')" + $(if ($expected.Count) { ', as expected.' } else { '.' })
    & $record 'OK' $detail $data
}

function Invoke-BeaconDnsCheck {
    <# The DNS check of a host: system resolver, optionally against the addresses it is expected to have. #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [string] $HostName,
        [string[]] $ExpectedAddresses,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    Get-BeaconDnsOutcome -Facts (Get-BeaconDnsFact -HostName $HostName -Config $Config) -ExpectedAddresses $ExpectedAddresses
}
