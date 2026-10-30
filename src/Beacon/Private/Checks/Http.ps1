function Get-BeaconEnvironmentValue {
    <# A variable by its name in lower or upper case (lower first, as curl does); an empty one counts as not set. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Environment,
        [Parameter(Mandatory)] [string] $Name
    )

    foreach ($key in $Name.ToLowerInvariant(), $Name.ToUpperInvariant()) {
        if ($Environment[$key]) { return [string] $Environment[$key] }
    }
}

function Resolve-BeaconProxy {
    <# The proxy for a URL: the matrix one, else HTTPS_PROXY / HTTP_PROXY filtered by NO_PROXY as curl reads them,
       else $null (direct). The system proxy settings are not read: they differ by OS. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [string] $MatrixProxy,
        [System.Collections.IDictionary] $Environment = [Environment]::GetEnvironmentVariables()
    )

    if ($MatrixProxy) { return $MatrixProxy }

    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref] $uri)) { return $null }

    $proxy = Get-BeaconEnvironmentValue -Environment $Environment -Name ($uri.Scheme -eq 'https' ? 'HTTPS_PROXY' : 'HTTP_PROXY')
    if (-not $proxy) { return $null }

    foreach ($entry in (Get-BeaconEnvironmentValue -Environment $Environment -Name 'NO_PROXY') -split ',') {
        $entry = $entry.Trim().ToLowerInvariant()
        if (-not $entry) { continue }
        if ($entry -eq '*') { return $null }
        if ($entry -notmatch '^(?<host>\[[^\]]+\]|[^:]+)(:(?<port>\d+))?$') { continue }
        if ($Matches.port -and [int] $Matches.port -ne $uri.Port) { continue }
        $domain = $Matches.host.TrimStart('.')
        if ($uri.Host -eq $domain -or $uri.Host.EndsWith(".$domain", [StringComparison]::OrdinalIgnoreCase)) { return $null }
    }

    # curl reads a proxy without scheme as http.
    if ($proxy -notmatch '^[a-z][a-z0-9+.-]*://') { $proxy = "http://$proxy" }
    $proxy
}

function Invoke-BeaconHttpProbe {
    <# The network half: one GET, redirects not followed, raw facts. Never throws on a network failure. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [string] $Proxy,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    $facts = @{
        Status = $null; Reason = $null; Location = $null; Body = $null
        Proxy = $Proxy; Tunneled = $Proxy -and $Url -match '^https:'
        ErrorKind = $null; ErrorMessage = $null; ProxyStatus = $null; DurationMs = 0
    }
    $handler = [System.Net.Http.SocketsHttpHandler]::new()
    $handler.AllowAutoRedirect = $false
    if ($Proxy) {
        $handler.UseProxy = $true
        $handler.Proxy = [System.Net.WebProxy]::new($Proxy)
    }
    else {
        $handler.UseProxy = $false
    }
    $client = [System.Net.Http.HttpClient]::new($handler)
    # One deadline for headers and body: HttpClient.Timeout stops at the headers when the body streams.
    $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    $cts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($Config.TimeoutSeconds.Http))
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $response = $null
    try {
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult()
        $facts.Status = [int] $response.StatusCode
        $facts.Reason = $response.ReasonPhrase
        if ($response.Headers.Location) { $facts.Location = $response.Headers.Location.OriginalString }

        # Up to 4 bytes per character in UTF-8; a read cut by the deadline leaves the preview as it is.
        $limit = [int] $Config.Http.PreviewChars
        $buffer = [byte[]]::new($limit * 4)
        $count = 0
        try {
            $stream = $response.Content.ReadAsStreamAsync($cts.Token).GetAwaiter().GetResult()
            do {
                $read = $stream.ReadAsync($buffer, $count, $buffer.Length - $count, $cts.Token).GetAwaiter().GetResult()
                $count += $read
            } while ($read -gt 0 -and $count -lt $buffer.Length)
        }
        catch { Write-Verbose "Body read stopped: $($_.Exception.Message)" }
        $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $count) -replace '\s+', ' '
        $text = $text.Trim()
        $facts.Body = $text.Substring(0, [Math]::Min($text.Length, $limit))
    }
    catch [System.Net.Http.HttpRequestException] {
        $ex = $_.Exception
        $facts.ErrorMessage = $ex.Message
        switch ($ex.HttpRequestError) {
            'SecureConnectionError' {
                $facts.ErrorKind = 'tls'
                if ($ex.InnerException) { $facts.ErrorMessage = $ex.InnerException.Message }
            }
            'ProxyTunnelError' {
                $facts.ErrorKind = 'proxyTunnelFailed'
                $facts.ProxyStatus = $ex.StatusCode ? [int] $ex.StatusCode : $null
                if ($facts.ProxyStatus -eq 407) { $facts.ErrorKind = 'proxyAuthRequired' }
            }
            { $_ -in 'ConnectionError', 'NameResolutionError' } { $facts.ErrorKind = 'connectFailed' }
            default { $facts.ErrorKind = 'other' }
        }
    }
    catch [System.OperationCanceledException] {
        $facts.ErrorKind = 'timeout'
        $facts.ErrorMessage = $_.Exception.Message
    }
    catch {
        $facts.ErrorKind = 'other'
        $facts.ErrorMessage = $_.Exception.Message
    }
    finally {
        $clock.Stop()
        $facts.DurationMs = [int] $clock.ElapsedMilliseconds
        if ($response) { $response.Dispose() }
        $cts.Dispose()
        $client.Dispose()
        $handler.Dispose()
    }
    $facts
}

function Get-BeaconHttpOutcome {
    <# The pure half: facts of the probe + expected statuses + config -> the check record. #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [hashtable] $Facts,
        [int[]] $ExpectedStatus,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    $proxy = $Facts.Proxy
    $data = [ordered]@{}
    if ($null -ne $Facts.Status) { $data.status = $Facts.Status }
    $data.proxy = $proxy ? $proxy : 'direct'
    if ($Facts.Location) { $data.location = $Facts.Location }
    if ($ExpectedStatus) { $data.expected = $ExpectedStatus }
    $record = {
        param([string] $Status, [string] $Detail)
        New-BeaconCheckRecord -Check http -Subject $Url -Status $Status -Detail $Detail -DurationMs $Facts.DurationMs -Data $data
    }
    $withPreview = { param([string] $Text) $Facts.Body ? "$Text $($Facts.Body)" : $Text }
    $answer = if ($null -ne $Facts.Status) { "$($Facts.Status) $($Facts.Reason)".Trim() }

    # The proxy answered 407, or refused a plain http request with a status listed as a rejection: not the origin's word.
    $rejectStatuses = $Config.Http.ProxyRejectStatuses ?? @(403)
    $viaProxyOnly = $proxy -and -not $Facts.Tunneled -and $null -ne $Facts.Status
    $kind = $Facts.ErrorKind
    $proxyStatus = $Facts.ProxyStatus
    if ($viaProxyOnly -and $Facts.Status -eq 407) { $kind = 'proxyAuthRequired'; $proxyStatus = 407 }
    elseif ($viaProxyOnly -and $Facts.Status -in $rejectStatuses) { $kind = 'proxyTunnelFailed'; $proxyStatus = $Facts.Status }

    if ($kind) {
        $proxyAnswer = if ($proxyStatus) { "answered $($answer ?? $proxyStatus)" }
        switch ($kind) {
            'timeout' {
                $where = $proxy ? " through proxy $proxy" : ''
                return & $record FAIL "No answer from $Url$where within $($Config.TimeoutSeconds.Http) s."
            }
            'connectFailed' {
                $text = $proxy ? "Proxy $proxy unreachable: $($Facts.ErrorMessage)" : "Connection to $Url failed: $($Facts.ErrorMessage)"
                return & $record FAIL $text
            }
            'proxyAuthRequired' {
                return & $record FAIL (& $withPreview "Proxy $proxy requires authentication (answered 407): check the proxy credentials.")
            }
            'proxyTunnelFailed' {
                $text = $proxyAnswer ? "Proxy $proxy refused the request, it $proxyAnswer." : "Proxy $proxy refused the tunnel: $($Facts.ErrorMessage)"
                return & $record FAIL (& $withPreview $text)
            }
            'tls' { return & $record FAIL "TLS failed: $($Facts.ErrorMessage)" }
            default { return & $record FAIL "Request failed: $($Facts.ErrorMessage)" }
        }
    }

    $redirect = $Facts.Location ? " Redirects to $($Facts.Location) (not followed)." : ''

    if ($ExpectedStatus) {
        if ($Facts.Status -in $ExpectedStatus) {
            return & $record OK "$answer, as expected: the route is open."
        }
        return & $record WARN (& $withPreview "Expected $($ExpectedStatus -join ' or '), got $answer.$redirect")
    }

    $class = [int][Math]::Floor($Facts.Status / 100)
    if ($class -in $Config.Http.OkClasses) {
        $through = $proxy ? ' through the proxy' : ''
        return & $record OK "$answer$through.$redirect"
    }
    if ($class -in $Config.Http.WarnClasses) {
        return & $record WARN (& $withPreview "$answer.$redirect")
    }
    & $record FAIL (& $withPreview "${answer}: status class $class is neither OK nor WARN in the configuration.")
}

function Invoke-BeaconHttpCheck {
    <# HTTP check of one URL: GET, redirects reported and not followed, through the proxy that applies. #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [string] $MatrixProxy,
        [int[]] $ExpectedStatus,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    $proxy = Resolve-BeaconProxy -Url $Url -MatrixProxy $MatrixProxy
    $facts = Invoke-BeaconHttpProbe -Url $Url -Proxy $proxy -Config $Config
    Get-BeaconHttpOutcome -Url $Url -Facts $facts -ExpectedStatus $ExpectedStatus -Config $Config
}
