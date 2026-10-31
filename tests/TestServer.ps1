# Loopback HTTP server for tests, shared by the HTTP and end-to-end tests: dot-source it in BeforeAll.

function Get-RawResponse {
    param([string] $Line, [string] $Body = '', [hashtable] $Headers = @{})
    $extra = ($Headers.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)`r`n" }) -join ''
    "HTTP/1.1 $Line`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n$extra`r`n$Body"
}

# A server on a loopback ephemeral port that answers from raw texts: the route whose key is in the request line,
# else Default. The value 'HANG' keeps the connection open without an answer. It also serves as a fake proxy,
# since any request line (GET http://..., CONNECT host:port) reaches Default.
function Open-TestServer {
    param([hashtable] $Routes = @{}, [string] $Default = '')
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $loop = {
        param($Listener, $Routes, $Default)
        $held = [System.Collections.Generic.List[object]]::new()
        try {
            while ($true) {
                $client = $Listener.AcceptTcpClient()
                $stream = $client.GetStream()
                $buffer = [byte[]]::new(8192)
                $text = ''
                while ($text -notmatch "`r`n`r`n") {
                    $n = $stream.Read($buffer, 0, $buffer.Length)
                    if ($n -le 0) { break }
                    $text += [System.Text.Encoding]::ASCII.GetString($buffer, 0, $n)
                }
                $requestLine = ($text -split "`r`n")[0]
                $raw = $Default
                foreach ($key in $Routes.Keys) { if ($requestLine -like "* $key *") { $raw = $Routes[$key] } }
                if ($raw -eq 'HANG') { $held.Add($client); continue }
                $bytes = [System.Text.Encoding]::ASCII.GetBytes($raw)
                $stream.Write($bytes, 0, $bytes.Length)
                $client.Close()
            }
        }
        catch { $null = $_ }
        finally { foreach ($c in $held) { $c.Close() } }
    }
    $shell = [powershell]::Create().AddScript($loop).AddArgument($listener).AddArgument($Routes).AddArgument($Default)
    [pscustomobject]@{
        Port     = $listener.LocalEndpoint.Port
        Url      = "http://127.0.0.1:$($listener.LocalEndpoint.Port)"
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
