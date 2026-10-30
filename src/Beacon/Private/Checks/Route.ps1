function Get-BeaconRouteOutcome {
    <# Pure half of the route check: the facts of an ICMP trace become a check record. The route informs: INFO or SKIP, never FAIL. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure: builds an object, changes nothing.')]
    [CmdletBinding()]
    [OutputType([ordered])]
    param(
        [Parameter(Mandatory)] [string] $Address,
        # hops (address or '*', one per TTL), replies (hops that answered, with or without address), unreachable (hop, address, status, or null),
        # reached, error, durationMs, method
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Facts
    )

    $hops = @($Facts.hops)
    $lastIndex = -1
    for ($i = 0; $i -lt $hops.Count; $i++) {
        if ($hops[$i] -ne '*') { $lastIndex = $i }
    }

    $data = [ordered]@{ hops = $hops }
    if ($lastIndex -ge 0) { $data.lastAnswering = [string] $hops[$lastIndex] }
    $data.method = $Facts.method

    if ($Facts.reached) {
        $status = 'INFO'
        $detail = "Reached in $($hops.Count) $(if ($hops.Count -eq 1) { 'hop' } else { 'hops' })."
    }
    elseif ($Facts.unreachable) {
        $status = 'INFO'
        $detail = "Unreachable after hop $($Facts.unreachable.hop) ($($Facts.unreachable.address ?? 'unknown address')): $($Facts.unreachable.status)."
        $data.unreachable = $Facts.unreachable.status
    }
    elseif ($lastIndex -ge 0) {
        $status = 'INFO'
        $detail = "No answer after hop $($lastIndex + 1) ($($hops[$lastIndex])): trace packets dropped or filtered."
    }
    elseif ($Facts.replies -and -not $Facts.error) {
        $status = 'SKIP'
        $detail = 'The hops answered but their addresses are not available on this system.'
    }
    else {
        $status = 'SKIP'
        $detail = if ($Facts.error) { [string] $Facts.error } else { 'No unprivileged way to trace the route on this system.' }
    }

    New-BeaconCheckRecord -Check route -Subject $Address -Status $status -Detail $detail -DurationMs $Facts.durationMs -Data $data
}

function Get-BeaconRouteFact {
    <# Probe half of the route check: an ICMP trace with growing TTL. The TCP trace needs a raw socket, so it is not used. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $Address,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    $maxHops = $Config.Route.MaxHops
    $timeoutMs = $Config.Route.HopTimeoutSeconds * 1000
    $facts = @{ hops = [System.Collections.Generic.List[string]]::new(); replies = 0; unreachable = $null; reached = $false; error = $null; durationMs = 0; method = 'icmp' }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $ip = [System.Net.IPAddress]::Parse($Address)
    $payload = [byte[]]::new($Config.Route.PingBufferBytes)
    $ping = [System.Net.NetworkInformation.Ping]::new()
    try {
        for ($ttl = 1; $ttl -le $maxHops; $ttl++) {
            $options = [System.Net.NetworkInformation.PingOptions]::new($ttl, $true)
            $reply = $ping.Send($ip, $timeoutMs, $payload, $options)
            $isHop = $reply.Status -in 'TtlExpired', 'Success'
            $isDefinitive = $reply.Status.ToString() -like 'Destination*'
            # PingReply.Address can be null on Linux even for an answer: the hop stays, as '*'.
            $address = if ($isHop -or $isDefinitive) { $reply.Address }
            $facts.hops.Add($(if ($address) { $address.ToString() } else { '*' }))
            if ($isHop) { $facts.replies++ }
            if ($reply.Status -eq 'Success') {
                $facts.reached = $true
                break
            }
            if ($isDefinitive) {
                # A router said there is no way on: going on to MaxHops would only wait for silence.
                $facts.unreachable = @{ hop = $ttl; address = $address?.ToString(); status = [string] $reply.Status }
                break
            }
        }
    }
    catch {
        # PlatformNotSupported, missing permission, PingException: the trace cannot run here.
        $inner = $_.Exception.InnerException ?? $_.Exception
        $facts.error = $inner.Message
    }
    finally {
        $stopwatch.Stop()
        $ping.Dispose()
    }
    $facts.durationMs = [int] $stopwatch.ElapsedMilliseconds
    $facts
}

function Invoke-BeaconRouteCheck {
    <# Traces the route to the address and reports the hops and the last one that answered. #>
    [CmdletBinding()]
    [OutputType([ordered])]
    param(
        [Parameter(Mandatory)] [string] $Address,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    $facts = Get-BeaconRouteFact -Address $Address -Config $Config
    Get-BeaconRouteOutcome -Address $Address -Facts $facts
}
