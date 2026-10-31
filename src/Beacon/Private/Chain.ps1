function New-BeaconSkipRecord {
    <# A SKIP record: the check was not run, the detail says why. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure: builds an object, changes nothing.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Check,
        [Parameter(Mandatory)] [string] $Subject,
        [Parameter(Mandatory)] [string] $Reason
    )

    New-BeaconCheckRecord -Check $Check -Subject $Subject -Status SKIP -Detail "Not run: $Reason." -DurationMs 0
}

function Get-BeaconChainPlan {
    <# Ports to check on the target (and proxies), each once, and per URL the port check it depends on. Pure: no network. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Target,
        [string] $MatrixProxy
    )

    $ports = [ordered]@{}
    foreach ($port in @($Target.Ports)) {
        $ports["$port"] = @{ Subject = "$port"; Port = [int] $port; Address = $null }
    }

    $urls = foreach ($url in @($Target.Urls)) {
        if (-not $url) { continue }
        $uri = [uri] $url
        $proxyParams = @{ Url = $url }
        if ($MatrixProxy) { $proxyParams.MatrixProxy = $MatrixProxy }
        $proxy = Resolve-BeaconProxy @proxyParams
        # A URL through a proxy never needs its own DNS: the proxy resolves the name.
        $otherHost = -not $proxy -and $uri.Host -ne $Target.Host

        if ($proxy) {
            # The proxy name goes to the port check as it is: that check accepts a name too.
            $key = "proxy $($proxy.Host):$($proxy.Port)"
            $ports[$key] = @{ Subject = $key; Port = [int] $proxy.Port; Address = $proxy.Host }
            $checkedPort = [int] $proxy.Port
        }
        elseif ($otherHost) {
            # Ports of another host are checked when the URL comes up, not in the target's list.
            $key = "$($uri.Host):$($uri.Port)"
            $checkedPort = [int] $uri.Port
        }
        else {
            $key = "$($uri.Port)"
            if (-not $ports.Contains($key)) {
                $ports[$key] = @{ Subject = $key; Port = [int] $uri.Port; Address = $null }
            }
            $checkedPort = [int] $uri.Port
        }
        @{ Url = $url; Uri = $uri; PortKey = $key; CheckedPort = $checkedPort; Proxied = [bool] $proxy; OtherHost = $otherHost }
    }

    @{
        Ports = @($ports.Values | Sort-Object { $_.Port }, { $_.Subject })
        Urls  = @($urls)
    }
}

function Invoke-BeaconChain {
    <# The chain of one target: DNS, route, ports, then per URL its own DNS (other host), port, TLS and HTTP. A failure turns what depends on it into SKIP. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Target,
        [string] $MatrixProxy,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    $records = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($record)
        # Schema order: group and target first, then the fields of the check.
        $row = [ordered]@{ group = $Target.Group; target = $Target.Name }
        foreach ($key in 'check', 'subject', 'status', 'detail', 'durationMs', 'data') {
            if ($record.Contains($key)) { $row[$key] = $record[$key] }
        }
        $records.Add($row)
    }

    $plan = Get-BeaconChainPlan -Target $Target -MatrixProxy $MatrixProxy

    $dnsParams = @{ HostName = $Target.Host; Config = $Config }
    if ($Target.ExpectedAddresses) { $dnsParams.ExpectedAddresses = @($Target.ExpectedAddresses) }
    $dns = Invoke-BeaconDnsCheck @dnsParams
    & $add $dns

    $address = @($dns.data.addresses)[0]
    # Without the target's address only the direct checks on it are skipped: a proxy resolves names by itself.
    $targetUp = $dns.status -ne 'FAIL' -and [bool] $address

    $lastHop = $null
    if ($targetUp) {
        # The route informs, it never stops the chain.
        $route = Invoke-BeaconRouteCheck -Address $address -Config $Config
        & $add $route
        $lastHop = if ($route.data) { $route.data.lastAnswering } else { $null }
    }
    else {
        & $add (New-BeaconSkipRecord -Check route -Subject $Target.Host -Reason 'DNS failed')
    }

    $portStatus = @{}
    foreach ($port in $plan.Ports) {
        if (-not $port.Address -and -not $targetUp) {
            & $add (New-BeaconSkipRecord -Check port -Subject $port.Subject -Reason 'DNS failed')
            $portStatus[$port.Subject] = 'SKIP'
            continue
        }
        $portAddress = if ($port.Address) { $port.Address } else { $address }
        $record = Invoke-BeaconPortCheck -Address $portAddress -Port $port.Port -Config $Config
        # The port check knows only a number: the chain names the proxy hop.
        if ($port.Address) { $record.subject = $port.Subject }
        if ($record.status -eq 'FAIL' -and $lastHop) {
            $record.detail = "$($record.detail) Last hop that answered: $lastHop."
        }
        $portStatus[$port.Subject] = $record.status
        & $add $record
    }

    $otherDns = @{}
    foreach ($url in $plan.Urls) {
        $direct = -not $url.Proxied
        $tlsApplies = $url.Uri.Scheme -eq 'https' -and $direct
        $urlAddress = $address
        $skipReason = $null

        if ($direct -and $url.OtherHost) {
            # Another host than the target: its own DNS (once per host; an IP literal goes through the same call, which does not look up) and its own port check.
            $urlHost = $url.Uri.Host
            if (-not $otherDns.ContainsKey($urlHost)) {
                $otherDns[$urlHost] = Invoke-BeaconDnsCheck -HostName $urlHost -Config $Config
                & $add $otherDns[$urlHost]
            }
            $hostDns = $otherDns[$urlHost]
            $urlAddress = @($hostDns.data.addresses)[0]
            if ($hostDns.status -eq 'FAIL' -or -not $urlAddress) {
                $skipReason = "DNS failed for $urlHost"
                if (-not $portStatus.ContainsKey($url.PortKey)) {
                    & $add (New-BeaconSkipRecord -Check port -Subject $url.PortKey -Reason $skipReason)
                    $portStatus[$url.PortKey] = 'SKIP'
                }
            }
            elseif (-not $portStatus.ContainsKey($url.PortKey)) {
                $record = Invoke-BeaconPortCheck -Address $urlAddress -Port $url.CheckedPort -Config $Config
                $record.subject = $url.PortKey
                $portStatus[$url.PortKey] = $record.status
                & $add $record
            }
        }
        elseif ($direct -and -not $targetUp) {
            $skipReason = 'DNS failed'
        }

        if (-not $skipReason -and $portStatus[$url.PortKey] -eq 'FAIL') { $skipReason = "port $($url.CheckedPort) failed" }
        $tlsFailed = $false

        if ($tlsApplies) {
            if ($skipReason) {
                & $add (New-BeaconSkipRecord -Check tls -Subject $url.Url -Reason $skipReason)
            }
            else {
                $tls = Invoke-BeaconTlsCheck -HostName $url.Uri.Host -Address $urlAddress -Port $url.Uri.Port -Subject $url.Url -Config $Config
                & $add $tls
                $tlsFailed = $tls.status -eq 'FAIL'
            }
        }

        if ($skipReason) {
            & $add (New-BeaconSkipRecord -Check http -Subject $url.Url -Reason $skipReason)
        }
        elseif ($tlsFailed) {
            & $add (New-BeaconSkipRecord -Check http -Subject $url.Url -Reason 'TLS failed')
        }
        else {
            $httpParams = @{ Url = $url.Url; Config = $Config }
            if ($MatrixProxy) { $httpParams.MatrixProxy = $MatrixProxy }
            if ($Target.ExpectedStatus) { $httpParams.ExpectedStatus = @($Target.ExpectedStatus) }
            & $add (Invoke-BeaconHttpCheck @httpParams)
        }
    }

    $records.ToArray()
}
