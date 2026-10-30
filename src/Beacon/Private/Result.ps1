function Get-BeaconTimestamp {
    <# ISO 8601 with the offset, as the schema's date-time wants. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [datetimeoffset] $Time
    )

    $Time.ToString('yyyy-MM-dd\THH:mm:sszzz')
}

function Write-BeaconResult {
    <# Writes result.json only when it differs, through a temp file in the same folder (a reader never sees half a file). #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Run
    )

    $json = $Run.Result | ConvertTo-Json -Depth 20
    # .NET file calls: the provider cmdlets fail on Windows short (8.3) paths such as the default temp folder.
    if ([System.IO.File]::Exists($Run.Path) -and [System.IO.File]::ReadAllText($Run.Path) -eq $json) { return }

    $temp = Join-Path ([System.IO.Path]::GetDirectoryName($Run.Path)) ".result.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($temp, $Run.Path, $true)
    }
    finally {
        if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) }
    }
}

function New-BeaconRun {
    <# Creates the run folder and writes result.json at once, incomplete: a run that does not end stays recognisable. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [AllowNull()] [string] $Environment,
        [Parameter(Mandatory)] [hashtable] $Config,
        [datetimeoffset] $Now = [datetimeoffset]::Now
    )

    $name = $Now.ToString('yyyyMMdd_HHmmss')
    # Absolute, from the current location: the .NET file calls do not know the PowerShell location.
    $runsFolder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Config.RunsFolder)
    $folder = Join-Path $runsFolder $name
    # A folder that exists is never reused: it belongs to another run.
    for ($suffix = 2; [System.IO.Directory]::Exists($folder); $suffix++) {
        $folder = Join-Path $runsFolder "${name}_$suffix"
    }

    $manifest = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../Beacon.psd1')
    $run = [pscustomobject]@{
        Path   = Join-Path $folder 'result.json'
        Result = [ordered]@{
            schemaVersion = $Config.ResultSchemaVersion
            run           = [ordered]@{
                startedAt     = Get-BeaconTimestamp -Time $Now
                endedAt       = $null
                complete      = $false
                environment   = if ($Environment) { $Environment } else { $null }
                beaconVersion = $manifest.ModuleVersion
                egress        = [ordered]@{ hostName = [Environment]::MachineName }
            }
            checks        = [System.Collections.Generic.List[object]]::new()
        }
    }

    if ($PSCmdlet.ShouldProcess($run.Path, 'Create run')) {
        $null = [System.IO.Directory]::CreateDirectory($folder)
        Write-BeaconResult -Run $run
        $run
    }
}

function Add-BeaconRecords {
    <# Appends check records to the run and rewrites the file. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Name fixed by the plan: it adds many records.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Run,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Records
    )

    if ($PSCmdlet.ShouldProcess($Run.Path, 'Add records')) {
        $Run.Result.checks.AddRange($Records)
        Write-BeaconResult -Run $Run
    }
}

function Complete-BeaconRun {
    <# Marks the run as ended: endedAt set and complete true. #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] $Run,
        [datetimeoffset] $Now = [datetimeoffset]::Now
    )

    if ($PSCmdlet.ShouldProcess($Run.Path, 'Complete run')) {
        $Run.Result.run.endedAt = Get-BeaconTimestamp -Time $Now
        $Run.Result.run.complete = $true
        Write-BeaconResult -Run $Run
    }
}
