# The result is read as ConvertFrom-Json gives it (PSCustomObject) or as ordered hashtables: member access works on both.

$script:BeaconStatuses = @('OK', 'WARN', 'FAIL', 'SKIP')
$script:BeaconStatusColors = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; SKIP = 'DarkGray'; INFO = 'Cyan' }

function New-BeaconStatusCount {
    <# Zeroed counters, in the order of the report. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure: builds an object, changes nothing.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $counts = [ordered]@{}
    foreach ($status in $script:BeaconStatuses) { $counts[$status] = 0 }
    $counts
}

function Get-BeaconTotals {
    <# Counts per status (INFO excluded) overall, per group and per target (key "group/target"), and the outcome of each target. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Name fixed by the plan: the function returns several totals.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)] $Result
    )

    $overall = New-BeaconStatusCount
    $groups = [ordered]@{}
    $targets = [ordered]@{}
    $outcomes = [ordered]@{}

    foreach ($check in $Result.checks) {
        $key = '{0}/{1}' -f $check.group, $check.target
        if (-not $groups.Contains($check.group)) { $groups[$check.group] = New-BeaconStatusCount }
        if (-not $targets.Contains($key)) {
            $targets[$key] = New-BeaconStatusCount
            $outcomes[$key] = [ordered]@{ Reachable = $true; Check = $null; Subject = $null; Text = 'reachable' }
        }

        if ($check.status -in $script:BeaconStatuses) {
            $overall[$check.status]++
            $groups[$check.group][$check.status]++
            $targets[$key][$check.status]++
        }

        # The first failure is where the target is blocked; later ones are consequences or other ports.
        if ($check.status -eq 'FAIL' -and $outcomes[$key].Reachable) {
            $where = if ($check.check -in @('dns', 'route')) { $check.check } else { '{0} {1}' -f $check.check, $check.subject }
            $outcomes[$key] = [ordered]@{ Reachable = $false; Check = $check.check; Subject = $check.subject; Text = "blocked at $where" }
        }
    }

    [ordered]@{ Overall = $overall; Groups = $groups; Targets = $targets; Outcomes = $outcomes }
}

function Format-BeaconCount {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Count
    )

    $parts = foreach ($status in $script:BeaconStatuses) { '{0} {1}' -f $status, $Count[$status] }
    '{0}: {1}' -f $Label, ($parts -join ', ')
}

function Limit-BeaconText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [int] $Width
    )

    if ($Text.Length -le $Width) { return $Text }
    $Text.Substring(0, [Math]::Max($Width - 3, 0)) + '...'
}

function Format-BeaconReport {
    <# The report as lines @{ Text; Color }, without writing anything. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] $Result,
        [ValidateRange(40, 1000)] [int] $Width = 120
    )

    $lines = [System.Collections.Generic.List[hashtable]]::new()
    $add = { param($Text, $Color = 'White') $lines.Add(@{ Text = $Text; Color = $Color }) }
    $totals = Get-BeaconTotals -Result $Result

    # ConvertFrom-Json turns ISO dates into DateTime, a hashtable or a string keeps the text: handle both.
    $startedAt = $Result.run.startedAt
    $started = if ($startedAt -is [datetime]) { [datetimeoffset]$startedAt } else { [datetimeoffset]::Parse([string]$startedAt, [cultureinfo]::InvariantCulture) }
    & $add ('Beacon {0}  environment: {1}  machine: {2}  started: {3}' -f $Result.run.beaconVersion, $Result.run.environment, $Result.run.egress.hostName, $started.ToString('yyyy-MM-dd HH:mm:ss zzz'))
    if (-not $Result.run.complete) {
        & $add 'WARNING: partial run, the chain was interrupted: the results below are not complete.' 'Yellow'
    }
    & $add ''

    $longest = ([int[]]@($Result.checks | ForEach-Object { ([string]$_.subject).Length }) + 7 | Measure-Object -Maximum).Maximum
    $subjectWidth = [Math]::Min($longest, 40)
    $indent = 4
    $detailWidth = [Math]::Max($Width - ($indent + 5 + 1 + $subjectWidth + 1 + 4 + 1), 10)

    & $add ('{0}{1} {2} {3} {4}' -f (' ' * $indent), 'check'.PadRight(5), 'subject'.PadRight($subjectWidth), 'stat'.PadRight(4), 'detail')
    foreach ($groupName in $totals.Groups.Keys) {
        & $add $groupName 'White'
        foreach ($key in $totals.Targets.Keys | Where-Object { $_ -like "$groupName/*" }) {
            & $add ('  ' + $key.Substring($groupName.Length + 1)) 'White'
            foreach ($check in $Result.checks | Where-Object { ('{0}/{1}' -f $_.group, $_.target) -eq $key }) {
                $text = '{0}{1} {2} {3} {4}' -f (' ' * $indent), ([string]$check.check).PadRight(5),
                (Limit-BeaconText -Text ([string]$check.subject) -Width $subjectWidth).PadRight($subjectWidth),
                ([string]$check.status).PadRight(4), (Limit-BeaconText -Text ([string]$check.detail) -Width $detailWidth)
                & $add $text $script:BeaconStatusColors[[string]$check.status]
            }
        }
    }
    & $add ''

    & $add 'Totals' 'White'
    foreach ($groupName in $totals.Groups.Keys) { & $add (Format-BeaconCount -Label "  group $groupName" -Count $totals.Groups[$groupName]) }
    foreach ($key in $totals.Targets.Keys) { & $add (Format-BeaconCount -Label "  target $key" -Count $totals.Targets[$key]) }
    & $add (Format-BeaconCount -Label '  overall' -Count $totals.Overall) 'White'
    & $add ''

    foreach ($key in $totals.Outcomes.Keys) {
        $outcome = $totals.Outcomes[$key]
        if ($outcome.Reachable) {
            & $add "$key is reachable" 'Green'
        } else {
            & $add "$key is $($outcome.Text)" 'Red'
        }
    }

    $lines.ToArray()
}

function Write-BeaconReport {
    <# The coloured report on the console. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console report: coloured output for people.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Result,
        [ValidateRange(40, 1000)] [int] $Width = 120
    )

    foreach ($line in Format-BeaconReport -Result $Result -Width $Width) {
        Write-Host $line.Text -ForegroundColor $line.Color
    }
}
