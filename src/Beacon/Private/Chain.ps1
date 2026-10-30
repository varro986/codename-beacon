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
    <# Ports to check, each once, and per URL the port check it depends on. Pure: no network. #>
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

        if ($proxy) {
            # The proxy name goes to the port check as it is: that check accepts a name too.
            $key = "proxy $($proxy.Host):$($proxy.Port)"
            $ports[$key] = @{ Subject = $key; Port = [int] $proxy.Port; Address = $proxy.Host }
            $checkedPort = [int] $proxy.Port
        }
        else {
            $key = "$($uri.Port)"
            if (-not $ports.Contains($key)) {
                $ports[$key] = @{ Subject = $key; Port = [int] $uri.Port; Address = $null }
            }
            $checkedPort = [int] $uri.Port
        }
        @{ Url = $url; Uri = $uri; PortKey = $key; CheckedPort = $checkedPort; Proxied = [bool] $proxy }
    }

    @{
        Ports = @($ports.Values | Sort-Object { $_.Port }, { $_.Subject })
        Urls  = @($urls)
    }
}

function Invoke-BeaconChain {
    <# The chain of one target: DNS, route, ports, then TLS and HTTP per URL. A failure turns what depends on it into SKIP. #>
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
    if ($dns.status -eq 'FAIL' -or -not $address) {
        & $add (New-BeaconSkipRecord -Check route -Subject $Target.Host -Reason 'DNS failed')
        foreach ($port in $plan.Ports) {
            & $add (New-BeaconSkipRecord -Check port -Subject $port.Subject -Reason 'DNS failed')
        }
        foreach ($url in $plan.Urls) {
            if ($url.Uri.Scheme -eq 'https' -and -not $url.Proxied) {
                & $add (New-BeaconSkipRecord -Check tls -Subject $url.Url -Reason 'DNS failed')
            }
            & $add (New-BeaconSkipRecord -Check http -Subject $url.Url -Reason 'DNS failed')
        }
        return $records.ToArray()
    }

    # The route informs, it never stops the chain.
    $route = Invoke-BeaconRouteCheck -Address $address -Config $Config
    & $add $route
    $lastHop = if ($route.data) { $route.data.lastAnswering } else { $null }

    $portStatus = @{}
    foreach ($port in $plan.Ports) {
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

    foreach ($url in $plan.Urls) {
        $skipReason = if ($portStatus[$url.PortKey] -eq 'FAIL') { "port $($url.CheckedPort) failed" }
        $direct = $url.Uri.Scheme -eq 'https' -and -not $url.Proxied
        $tlsFailed = $false

        if ($direct) {
            if ($skipReason) {
                & $add (New-BeaconSkipRecord -Check tls -Subject $url.Url -Reason $skipReason)
            }
            else {
                $tls = Invoke-BeaconTlsCheck -HostName $url.Uri.Host -Address $address -Port $url.Uri.Port -Subject $url.Url -Config $Config
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
