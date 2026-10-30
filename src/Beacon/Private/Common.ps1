function Get-BeaconConfig {
    <# Defaults from config/defaults.psd1, with the values a machine overrides through environment variables. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $config = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../config/defaults.psd1')
    $runsFolder = [Environment]::GetEnvironmentVariable($config.RunsFolderEnv)
    if ($runsFolder) { $config.RunsFolder = $runsFolder }
    $config
}

function New-BeaconCheckRecord {
    <# A check record of the result schema, without group and target: the chain adds them. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure: builds an object, changes nothing.')]
    [CmdletBinding()]
    [OutputType([ordered])]
    param(
        [Parameter(Mandatory)] [ValidateSet('dns', 'route', 'port', 'tls', 'http')] [string] $Check,
        [Parameter(Mandatory)] [string] $Subject,
        [Parameter(Mandatory)] [ValidateSet('OK', 'WARN', 'FAIL', 'SKIP', 'INFO')] [string] $Status,
        [Parameter(Mandatory)] [string] $Detail,
        [Parameter(Mandatory)] [ValidateRange(0, [int]::MaxValue)] [int] $DurationMs,
        [System.Collections.IDictionary] $Data
    )

    $record = [ordered]@{
        check      = $Check
        subject    = $Subject
        status     = $Status
        detail     = $Detail
        durationMs = $DurationMs
    }
    if ($Data) { $record.data = $Data }
    $record
}

function New-BeaconInputError {
    <# An input error (matrix or parameters): Beacon stops before any check and exits with code 2. #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure: builds an object, changes nothing.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)] [string] $Message
    )

    [System.Management.Automation.ErrorRecord]::new(
        [System.ArgumentException]::new($Message),
        'BeaconInput',
        [System.Management.Automation.ErrorCategory]::InvalidArgument,
        $null)
}
