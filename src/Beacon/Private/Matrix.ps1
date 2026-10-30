# The target matrix: a data file read with Import-PowerShellDataFile (never run as code), validated as a whole.

function Expand-BeaconPort {
    <# Ports of a target as the sorted, unique integers of a list of ports and 'from-to' ranges (already validated). #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [AllowNull()] [object[]] $Ports
    )

    $expanded = foreach ($port in $Ports) {
        if ($port -is [string]) {
            $from, $to = $port -split '-' | ForEach-Object { [int]$_.Trim() }
            $from..$to
        }
        else { [int]$port }
    }
    [int[]]@($expanded | Sort-Object -Unique)
}

function ConvertTo-BeaconList {
    <# A value as a list: nothing for $null, the items for a list, one item for a single value. #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [AllowNull()] [object] $Value
    )

    if ($null -ne $Value) { @($Value) }
}

function Test-BeaconPortSpec {
    <# The problem of one port entry (an integer 1-65535 or a 'from-to' string), or $null when it is valid. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [object] $Spec
    )

    $fix = "Use a port such as 443 or a range such as '8443-8444' (ports 1-65535)."
    if ($Spec -is [int]) {
        if ($Spec -lt 1 -or $Spec -gt 65535) { return "port $Spec is out of range. $fix" }
        return $null
    }
    if ($Spec -is [string] -and $Spec -match '^\s*(\d{1,9})\s*-\s*(\d{1,9})\s*$') {
        $from = [int]$Matches[1]
        $to = [int]$Matches[2]
        if ($from -lt 1 -or $to -gt 65535) { return "range '$Spec' is out of range. $fix" }
        if ($from -gt $to) { return "range '$Spec' runs backwards. Write it as 'from-to' with from <= to." }
        return $null
    }
    "'$Spec' is not a port or a range. $fix"
}

function Test-BeaconUrl {
    <# True for an absolute http or https URL. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()] [object] $Value
    )

    $uri = $null
    ($Value -is [string]) -and [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in 'http', 'https'
}

function Get-BeaconKeyProblem {
    <# Problems for keys of a table that are not in the allowed list (names only, never values). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Table,
        [Parameter(Mandatory)] [string[]] $Allowed
    )

    foreach ($key in $Table.Keys) {
        if ($key -notin $Allowed) {
            "${Path}: unknown key '$key'. Allowed keys: $($Allowed -join ', '). Remove it or fix the spelling."
        }
    }
}

function Test-BeaconTarget {
    <# Problems of one target (entry path first in each); an empty array when the target is valid. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [AllowNull()] [object] $Target,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    if ($Target -isnot [System.Collections.IDictionary]) {
        return "${Path}: a target must be a table such as @{ Name = '...'; Host = '...' }."
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    $allowed = 'Name', 'Host', 'ExpectedAddresses', 'Ports', 'Urls', 'Expect', 'SecretEnv'
    $problems.AddRange([string[]]@(Get-BeaconKeyProblem -Path $Path -Table $Target -Allowed $allowed))

    $placeholders = @{ Name = 'label of the target'; Host = 'name or address' }
    foreach ($key in 'Name', 'Host') {
        if (-not $Target.Contains($key)) {
            $problems.Add("${Path}: $key is missing. Add $key = '<$($placeholders[$key])>'.")
        }
        elseif ($Target[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($Target[$key])) {
            $problems.Add("${Path}.${key}: must be a non-empty string.")
        }
    }

    if ($Target.Contains('ExpectedAddresses')) {
        foreach ($address in @($Target.ExpectedAddresses)) {
            $ip = $null
            if ($address -isnot [string] -or $address -notmatch '[.:]' -or -not [System.Net.IPAddress]::TryParse($address, [ref]$ip)) {
                $problems.Add("${Path}.ExpectedAddresses: '$address' is not an IP address. Use an IPv4 or IPv6 address such as '192.0.2.10'.")
            }
        }
    }

    if ($Target.Contains('Ports')) {
        $portSpecs = @($Target.Ports)
        $portProblems = @($portSpecs | ForEach-Object { Test-BeaconPortSpec -Spec $_ } | Where-Object { $_ })
        foreach ($problem in $portProblems) { $problems.Add("${Path}.Ports: $problem") }
        if (-not $portProblems) {
            $count = (Expand-BeaconPort -Ports $portSpecs).Count
            if ($count -gt $Config.MaxPortsPerTarget) {
                $problems.Add("${Path}.Ports: $count ports declared, the limit is $($Config.MaxPortsPerTarget). Beacon tests declared ports, it does not scan: list only the ports you need.")
            }
        }
    }

    if ($Target.Contains('Urls')) {
        foreach ($url in @($Target.Urls)) {
            if (-not (Test-BeaconUrl -Value $url)) {
                $problems.Add("${Path}.Urls: '$url' is not an absolute http or https URL. Write it as 'https://host/path'.")
            }
        }
    }

    if ($Target.Contains('Expect')) {
        $expect = $Target.Expect
        if ($expect -isnot [System.Collections.IDictionary]) {
            $problems.Add("${Path}.Expect: must be a table such as @{ Http = 401 }.")
        }
        else {
            $problems.AddRange([string[]]@(Get-BeaconKeyProblem -Path "${Path}.Expect" -Table $expect -Allowed @('Http')))
            if ($expect.Contains('Http')) {
                foreach ($status in @($expect.Http)) {
                    if ($status -isnot [int] -or $status -lt 100 -or $status -gt 599) {
                        $problems.Add("${Path}.Expect.Http: '$status' is not an HTTP status. Use an integer from 100 to 599, or a list of them.")
                    }
                }
            }
        }
    }

    # The value is never echoed: a mistaken secret must not reach the screen or a log.
    if ($Target.Contains('SecretEnv')) {
        if ($Target.SecretEnv -isnot [string] -or $Target.SecretEnv -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            $problems.Add("${Path}.SecretEnv: must be the NAME of an environment variable (letters, digits, underscore). Put the variable name here, never the secret value.")
        }
    }

    $problems.ToArray()
}

function Test-BeaconMatrix {
    <# All problems of a matrix read from the data file, by entry path. An empty array means valid. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()] [object] $Matrix,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    if ($Matrix -isnot [System.Collections.IDictionary]) {
        return 'The matrix must be a table: @{ Environments = @{ ... } }.'
    }
    $problems = [System.Collections.Generic.List[string]]::new()
    $problems.AddRange([string[]]@(Get-BeaconKeyProblem -Path 'Matrix' -Table $Matrix -Allowed @('Environments')))

    $environments = $Matrix['Environments']
    if ($environments -isnot [System.Collections.IDictionary] -or $environments.Count -eq 0) {
        $problems.Add("Environments: missing or empty. Add at least one environment such as Environments = @{ test = @{ Groups = @{ ... } } }.")
        return $problems.ToArray()
    }

    foreach ($envName in $environments.Keys) {
        $envPath = "Environments.$envName"
        $environment = $environments[$envName]
        if ($environment -isnot [System.Collections.IDictionary]) {
            $problems.Add("${envPath}: must be a table with Groups (and optionally Proxy).")
            continue
        }
        $problems.AddRange([string[]]@(Get-BeaconKeyProblem -Path $envPath -Table $environment -Allowed @('Groups', 'Proxy')))

        if ($environment.Contains('Proxy') -and -not (Test-BeaconUrl -Value $environment.Proxy)) {
            $problems.Add("${envPath}.Proxy: must be an absolute http or https URL such as 'http://proxy.example.net:8080'.")
        }

        $groups = $environment['Groups']
        if ($groups -isnot [System.Collections.IDictionary] -or $groups.Count -eq 0) {
            $problems.Add("${envPath}.Groups: missing or empty. Add at least one group such as Groups = @{ web = @{ Targets = @(...) } }.")
            continue
        }

        foreach ($groupName in $groups.Keys) {
            $groupPath = "$envPath.Groups.$groupName"
            $group = $groups[$groupName]
            if ($group -isnot [System.Collections.IDictionary]) {
                $problems.Add("${groupPath}: must be a table with Targets.")
                continue
            }
            $problems.AddRange([string[]]@(Get-BeaconKeyProblem -Path $groupPath -Table $group -Allowed @('Targets')))

            $targets = $group['Targets']
            if ($targets -isnot [array] -or $targets.Count -eq 0) {
                $problems.Add("${groupPath}.Targets: missing or empty. Add a list such as Targets = @( @{ Name = '...'; Host = '...' } ).")
                continue
            }

            $firstIndex = @{}
            for ($i = 0; $i -lt $targets.Count; $i++) {
                $targetPath = "$groupPath.Targets[$i]"
                $problems.AddRange([string[]]@(Test-BeaconTarget -Path $targetPath -Target $targets[$i] -Config $Config))

                $name = if ($targets[$i] -is [System.Collections.IDictionary]) { $targets[$i]['Name'] }
                if ($name -is [string] -and $name.Trim()) {
                    $key = $name.ToLowerInvariant()
                    if ($firstIndex.ContainsKey($key)) {
                        $problems.Add("${targetPath}.Name: '$name' is already used by Targets[$($firstIndex[$key])] in this group. Give each target of a group its own Name.")
                    }
                    else { $firstIndex[$key] = $i }
                }
            }
        }
    }

    $problems.ToArray()
}

function Read-BeaconMatrix {
    <# Reads and validates the matrix file; an input error names every wrong entry and how to fix it. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [hashtable] $Config
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $PSCmdlet.ThrowTerminatingError((New-BeaconInputError -Message "Matrix file not found: $Path. Check the path or create the file from the example in specs/features/001-diagnostic-chain/contracts/matrix.example.psd1."))
    }

    try {
        $matrix = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        $PSCmdlet.ThrowTerminatingError((New-BeaconInputError -Message "Matrix file cannot be read: $Path. It must be a PowerShell data file (.psd1) with literal values only. $($_.Exception.Message)"))
    }

    $problems = @(Test-BeaconMatrix -Matrix $matrix -Config $Config)
    if ($problems.Count -gt 0) {
        $message = "Matrix $Path has $($problems.Count) problem(s):`n" + ($problems -join "`n")
        $PSCmdlet.ThrowTerminatingError((New-BeaconInputError -Message $message))
    }
    $matrix
}

function Get-BeaconTargets {
    <# The proxy and the flat, sorted targets of one environment of a validated matrix. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Name fixed by the plan contract: it returns a list of targets.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [hashtable] $Matrix,
        [Parameter(Mandatory)] [string] $Environment
    )

    $environments = $Matrix.Environments
    if (-not $environments.Contains($Environment)) {
        $available = ($environments.Keys | Sort-Object) -join ', '
        $PSCmdlet.ThrowTerminatingError((New-BeaconInputError -Message "Environment '$Environment' is not in the matrix. Available: $available."))
    }
    $selected = $environments[$Environment]

    $targets = foreach ($groupName in $selected.Groups.Keys) {
        foreach ($target in $selected.Groups[$groupName].Targets) {
            @{
                Group             = [string]$groupName
                Name              = $target.Name
                Host              = $target.Host
                ExpectedAddresses = [string[]]@(ConvertTo-BeaconList $target.ExpectedAddresses)
                Ports             = [int[]]@(Expand-BeaconPort -Ports (ConvertTo-BeaconList $target.Ports))
                Urls              = [string[]]@(ConvertTo-BeaconList $target.Urls)
                ExpectedStatus    = [int[]]@(ConvertTo-BeaconList $target.Expect.Http)
                SecretEnv         = $target.SecretEnv
            }
        }
    }

    @{
        Proxy   = $selected.Proxy
        Targets = @($targets | Sort-Object { $_.Group }, { $_.Name })
    }
}
