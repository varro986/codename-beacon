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
    if ((Test-Path -LiteralPath $Run.Path) -and (Get-Content -LiteralPath $Run.Path -Raw) -eq $json) { return }

    $temp = Join-Path (Split-Path $Run.Path -Parent) ".result.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Set-Content -LiteralPath $temp -Value $json -NoNewline -Encoding utf8NoBOM
        Move-Item -LiteralPath $temp -Destination $Run.Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
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
    $folder = Join-Path $Config.RunsFolder $name
    # A folder that exists is never reused: it belongs to another run.
    for ($suffix = 2; Test-Path -LiteralPath $folder; $suffix++) {
        $folder = Join-Path $Config.RunsFolder "${name}_$suffix"
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
        $null = New-Item -ItemType Directory -Path $folder
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
