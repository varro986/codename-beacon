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

function Get-BeaconTargetKey {
    <# Key of a target in the totals: "group/target", or just the target when it has no group (single target from the command line). #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()] [AllowEmptyString()] $Group,
        [AllowNull()] [AllowEmptyString()] $Target
    )

    if ([string]::IsNullOrEmpty([string]$Group)) { return [string]$Target }
    '{0}/{1}' -f $Group, $Target
}

function Get-BeaconTotals {
    <# Counts per status (INFO excluded) overall, per group (key '' when there is none) and per target (key "group/target"), and the outcome of each target. #>
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
        $groupName = [string]$check.group
        $key = Get-BeaconTargetKey -Group $check.group -Target $check.target
        if (-not $groups.Contains($groupName)) { $groups[$groupName] = New-BeaconStatusCount }
        if (-not $targets.Contains($key)) {
            $targets[$key] = New-BeaconStatusCount
            $outcomes[$key] = [ordered]@{ Reachable = $true; Check = $null; Subject = $null; Text = 'reachable'; Detail = '' }
        }

        if ($check.status -in $script:BeaconStatuses) {
            $overall[$check.status]++
            $groups[$groupName][$check.status]++
            $targets[$key][$check.status]++
        }

        # The first failure is where the target is blocked; later ones are consequences or other ports.
        if ($check.status -eq 'FAIL' -and $outcomes[$key].Reachable) {
            $where = if ($check.check -in @('dns', 'route')) { $check.check } else { '{0} {1}' -f $check.check, $check.subject }
            $outcomes[$key] = [ordered]@{ Reachable = $false; Check = $check.check; Subject = $check.subject; Text = "blocked at $where"; Detail = [string]$check.detail }
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
    <# Shortens a subject; details are never shortened (see Split-BeaconText). #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [int] $Width
    )

    if ($Text.Length -le $Width) { return $Text }
    $Text.Substring(0, [Math]::Max($Width - 3, 0)) + '...'
}

function Split-BeaconText {
    <# Wraps text at spaces into lines of at most Width characters; a word longer than Width is split. Nothing is ever cut. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [int] $Width
    )

    $current = ''
    foreach ($word in ($Text -split '\s+' | Where-Object { $_ })) {
        while ($word.Length -gt $Width) {
            if ($current) { $current; $current = '' }
            $word.Substring(0, $Width)
            $word = $word.Substring($Width)
        }
        if (-not $current) { $current = $word }
        elseif (($current.Length + 1 + $word.Length) -le $Width) { $current = "$current $word" }
        else { $current; $current = $word }
    }
    $current
}

function Format-BeaconReport {
    <# The report as lines @{ Text; Color }, without writing anything. Width and subject length come from Config.Report. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Config,
        [ValidateRange(0, 1000)] [int] $Width = 0
    )

    if ($Width -eq 0) { $Width = [int]$Config.Report.Width }
    $subjectChars = [int]$Config.Report.SubjectChars
    $lines = [System.Collections.Generic.List[hashtable]]::new()
    $add = { param($Text, $Color = 'White') $lines.Add(@{ Text = $Text; Color = $Color }) }
    $totals = Get-BeaconTotals -Result $Result

    # ConvertFrom-Json turns ISO dates into DateTime, a hashtable or a string keeps the text: handle both.
    $startedAt = $Result.run.startedAt
    $started = if ($startedAt -is [datetime]) { [datetimeoffset]$startedAt } else { [datetimeoffset]::Parse([string]$startedAt, [cultureinfo]::InvariantCulture) }
    & $add ('Beacon {0}  environment: {1}  machine: {2}  started: {3}' -f $Result.run.beaconVersion, ($Result.run.environment ?? '(single target)'), $Result.run.egress.hostName, $started.ToString('yyyy-MM-dd HH:mm:ss zzz'))
    if (-not $Result.run.complete) {
        & $add 'WARNING: partial run, the chain was interrupted: the results below are not complete.' 'Yellow'
    }
    & $add ''

    $longest = ([int[]]@($Result.checks | ForEach-Object { ([string]$_.subject).Length }) + 7 | Measure-Object -Maximum).Maximum
    $subjectWidth = [Math]::Min($longest, $subjectChars)
    $indent = 4
    $detailColumn = $indent + 5 + 1 + $subjectWidth + 1 + 4 + 1
    $detailWidth = [Math]::Max($Width - $detailColumn, 10)

    & $add ('{0}{1} {2} {3} {4}' -f (' ' * $indent), 'check'.PadRight(5), 'subject'.PadRight($subjectWidth), 'stat'.PadRight(4), 'detail')
    foreach ($groupName in $totals.Groups.Keys) {
        if ($groupName) { & $add $groupName 'White' }
        $targetIndent = if ($groupName) { '  ' } else { '' }
        $groupChecks = @($Result.checks | Where-Object { [string]$_.group -eq $groupName })
        foreach ($targetName in @($groupChecks | ForEach-Object { [string]$_.target } | Select-Object -Unique)) {
            & $add ($targetIndent + $targetName) 'White'
            foreach ($check in $groupChecks | Where-Object { [string]$_.target -eq $targetName }) {
                $prefix = '{0}{1} {2} {3} ' -f (' ' * $indent), ([string]$check.check).PadRight(5),
                (Limit-BeaconText -Text ([string]$check.subject) -Width $subjectWidth).PadRight($subjectWidth), ([string]$check.status).PadRight(4)
                $color = $script:BeaconStatusColors[[string]$check.status]
                $parts = @(Split-BeaconText -Text ([string]$check.detail) -Width $detailWidth)
                if ($parts.Count -eq 0) { $parts = @('') }
                for ($i = 0; $i -lt $parts.Count; $i++) {
                    $lead = if ($i -eq 0) { $prefix } else { ' ' * $detailColumn }
                    & $add (($lead + $parts[$i]).TrimEnd()) $color
                }
            }
        }
    }
    & $add ''

    & $add 'Totals' 'White'
    foreach ($groupName in $totals.Groups.Keys) {
        if ($groupName) { & $add (Format-BeaconCount -Label "  group $groupName" -Count $totals.Groups[$groupName]) }
    }
    foreach ($key in $totals.Targets.Keys) { & $add (Format-BeaconCount -Label "  target $key" -Count $totals.Targets[$key]) }
    & $add (Format-BeaconCount -Label '  overall' -Count $totals.Overall) 'White'
    & $add ''

    foreach ($key in $totals.Outcomes.Keys) {
        $outcome = $totals.Outcomes[$key]
        if ($outcome.Reachable) {
            & $add "$key is reachable" 'Green'
        } else {
            $sentence = "$key is $($outcome.Text)"
            if ($outcome.Detail) { $sentence = "${sentence}: $($outcome.Detail)" }
            $parts = @(Split-BeaconText -Text $sentence -Width $Width)
            for ($i = 0; $i -lt $parts.Count; $i++) {
                & $add ($(if ($i -eq 0) { '' } else { '  ' }) + $parts[$i]) 'Red'
            }
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
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Config,
        [ValidateRange(0, 1000)] [int] $Width = 0
    )

    foreach ($line in Format-BeaconReport -Result $Result -Config $Config -Width $Width) {
        Write-Host $line.Text -ForegroundColor $line.Color
    }
}
