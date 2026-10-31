<#
.SYNOPSIS
    Spike (feature 001, T1): which unprivileged method can trace the route to an address, on Windows and Linux.
.DESCRIPTION
    Tries, against one target, (a) a TCP trace (connect with growing TTL, plus a check on raw ICMP sockets, the only
    way to read the hop addresses of a TCP trace) and (b) an ICMP trace (Ping with PingOptions(ttl)). Prints for
    each method: works yes/no, hop list, error. Only .NET classes, no external tools. Not part of the module:
    throwaway evidence for plan.md (Risks).
.PARAMETER Target
    IPv4 address to trace to. Default 1.1.1.1.
.PARAMETER Port
    TCP port for the TCP trace. Default 443.
.EXAMPLE
    pwsh -NoProfile -File tests/spikes/Route.Spike.ps1
.EXAMPLE
    pwsh -NoProfile -File tests/spikes/Route.Spike.ps1 -Target 1.1.1.1 -Port 443
#>
[CmdletBinding()]
param(
    [string]$Target = '1.1.1.1',
    [int]$Port = 443
)

$ErrorActionPreference = 'Stop'
$defaultsPath = Join-Path $PSScriptRoot '../../src/Beacon/config/defaults.psd1'
$defaults = Import-PowerShellDataFile -Path $defaultsPath
$maxHops = $defaults.Route.MaxHops
$timeoutMs = $defaults.Route.HopTimeoutSeconds * 1000
$address = [System.Net.IPAddress]::Parse($Target)

function Test-RawIcmpSocket {
    # Can an unprivileged process open a raw ICMP socket (needed to read TTL-exceeded from a TCP trace)?
    try {
        $raw = [System.Net.Sockets.Socket]::new('InterNetwork', 'Raw', 'Icmp')
        try {
            $raw.Bind([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0))
            return [pscustomobject]@{ Works = $true; Error = $null }
        }
        finally { $raw.Dispose() }
    }
    catch {
        return [pscustomobject]@{ Works = $false; Error = $_.Exception.Message }
    }
}

function Get-LocalAddress {
    # Source address the OS would use towards the target (a UDP connect sends nothing).
    $udp = [System.Net.Sockets.Socket]::new('InterNetwork', 'Dgram', 'Udp')
    try {
        $udp.Connect($address, 9)
        return $udp.LocalEndPoint.Address
    }
    finally { $udp.Dispose() }
}

function Receive-IcmpHop {
    # Reads ICMP time-exceeded (type 11) quoting our packet to the target: its sender is the hop. Null if none.
    param([System.Net.Sockets.Socket]$RawSocket)
    $buffer = [byte[]]::new(1500)
    $from = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
    $deadline = [System.Diagnostics.Stopwatch]::StartNew()
    while ($deadline.ElapsedMilliseconds -lt $timeoutMs) {
        if (-not $RawSocket.Poll(100000, 'SelectRead')) { continue }
        $remote = [System.Net.EndPoint]$from
        $length = $RawSocket.ReceiveFrom($buffer, [ref]$remote)
        $ihl = ($buffer[0] -band 0x0F) * 4
        if ($length -lt $ihl + 28 -or $buffer[$ihl] -ne 11) { continue }
        $quotedDest = [System.Net.IPAddress]::new($buffer[($ihl + 8 + 16)..($ihl + 8 + 19)])
        if ($quotedDest.Equals($address)) { return $remote.Address.ToString() }
    }
    return $null
}

function Invoke-TcpTrace {
    # One connect attempt per TTL. Hop addresses are visible only through a raw ICMP socket, when it is allowed.
    $rawSocket = $null
    if ($raw.Works) {
        $rawSocket = [System.Net.Sockets.Socket]::new('InterNetwork', 'Raw', 'Icmp')
        $rawSocket.Bind([System.Net.IPEndPoint]::new((Get-LocalAddress), 0))
    }
    for ($ttl = 1; $ttl -le $maxHops; $ttl++) {
        $socket = [System.Net.Sockets.Socket]::new('InterNetwork', 'Stream', 'Tcp')
        $socket.Ttl = [int16]$ttl
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $outcome = 'timeout'
        $hop = $null
        try {
            $task = $socket.ConnectAsync($address, $Port)
            if ($rawSocket) { $hop = Receive-IcmpHop -RawSocket $rawSocket }
            if ($task.Wait($(if ($rawSocket) { 0 } else { $timeoutMs }))) { $outcome = 'connected' }
        }
        catch {
            $inner = $_.Exception.InnerException ?? $_.Exception
            $outcome = if ($inner -is [System.Net.Sockets.SocketException]) { $inner.SocketErrorCode.ToString() } else { $inner.Message }
        }
        finally { $socket.Dispose() }
        [pscustomobject]@{ Ttl = $ttl; Address = $hop; Outcome = $outcome; Ms = $watch.ElapsedMilliseconds }
        if ($outcome -in 'connected', 'ConnectionRefused') { break }
    }
    if ($rawSocket) { $rawSocket.Dispose() }
}

function Invoke-IcmpTrace {
    $ping = [System.Net.NetworkInformation.Ping]::new()
    $payload = [byte[]]::new(32)
    try {
        for ($ttl = 1; $ttl -le $maxHops; $ttl++) {
            $options = [System.Net.NetworkInformation.PingOptions]::new($ttl, $true)
            $reply = $ping.Send($address, $timeoutMs, $payload, $options)
            [pscustomobject]@{
                Ttl     = $ttl
                Address = if ($reply.Status -in 'TtlExpired', 'Success') { $reply.Address.ToString() } else { $null }
                Outcome = $reply.Status.ToString()
                Ms      = $reply.RoundtripTime
            }
            if ($reply.Status -eq 'Success') { break }
        }
    }
    finally { $ping.Dispose() }
}

function Write-Method {
    param([string]$Name, [object[]]$Hops, [string]$ErrorText, [bool]$HasAddresses)
    '--- {0}' -f $Name
    'works (hop addresses learned): {0}' -f $(if ($HasAddresses) { 'yes' } else { 'no' })
    'error: {0}' -f $(if ($ErrorText) { $ErrorText } else { '-' })
    $Hops | ForEach-Object { '  ttl={0,2} addr={1,-16} outcome={2} ms={3}' -f $_.Ttl, ($_.Address ?? '*'), $_.Outcome, $_.Ms }
}

$os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
'target={0}:{1} maxHops={2} hopTimeoutMs={3} os={4} pwsh={5}' -f $Target, $Port, $maxHops, $timeoutMs, $os, $PSVersionTable.PSVersion

$raw = Test-RawIcmpSocket
'raw ICMP socket unprivileged: {0} ({1})' -f $(if ($raw.Works) { 'yes' } else { 'no' }), ($raw.Error ?? 'opened and bound')

try {
    $tcp = @(Invoke-TcpTrace)
    $reached = [bool]($tcp | Where-Object Outcome -In 'connected', 'ConnectionRefused')
    $tcpError = if (-not $reached) { 'target not reached within max hops' }
    Write-Method -Name 'TCP trace (Socket.Ttl, connect)' -Hops $tcp -ErrorText $tcpError -HasAddresses ([bool]($tcp | Where-Object Address))
}
catch { Write-Method -Name 'TCP trace (Socket.Ttl, connect)' -Hops @() -ErrorText $_.Exception.Message -HasAddresses $false }

try {
    $icmp = @(Invoke-IcmpTrace)
    $expired = [bool]($icmp | Where-Object Outcome -EQ 'TtlExpired')
    $icmpError = if (-not $expired) { 'no TtlExpired reply with a hop address' }
    Write-Method -Name 'ICMP trace (Ping + PingOptions ttl)' -Hops $icmp -ErrorText $icmpError -HasAddresses $expired
}
catch { Write-Method -Name 'ICMP trace (Ping + PingOptions ttl)' -Hops @() -ErrorText $_.Exception.Message -HasAddresses $false }
