BeforeAll {
    . (Join-Path $PSScriptRoot '../src/Beacon/Private/Common.ps1')
}

Describe 'Get-BeaconConfig' {
    AfterEach {
        $env:BEACON_RUNS = $null
    }

    It 'reads the defaults' {
        (Get-BeaconConfig).RunsFolder | Should -Be 'beacon-runs'
    }

    It 'takes the runs folder from BEACON_RUNS when set' {
        $env:BEACON_RUNS = 'elsewhere'
        (Get-BeaconConfig).RunsFolder | Should -Be 'elsewhere'
    }
}

Describe 'New-BeaconCheckRecord' {
    It 'builds a record in the order of the schema, without data when none is given' {
        $record = New-BeaconCheckRecord -Check port -Subject '443' -Status OK -Detail 'Opened.' -DurationMs 3
        @($record.Keys) | Should -Be @('check', 'subject', 'status', 'detail', 'durationMs')
    }

    It 'keeps the data when given' {
        $record = New-BeaconCheckRecord -Check port -Subject '443' -Status FAIL -Detail 'Refused.' -DurationMs 1 -Data @{ reason = 'refused' }
        $record.data.reason | Should -Be 'refused'
    }

    It 'rejects a status outside the schema' {
        { New-BeaconCheckRecord -Check port -Subject '443' -Status MAYBE -Detail 'x' -DurationMs 0 } | Should -Throw
    }
}

Describe 'New-BeaconInputError' {
    It 'carries the BeaconInput id and the message' {
        $err = New-BeaconInputError -Message 'Host is missing'
        $err.FullyQualifiedErrorId | Should -Be 'BeaconInput'
        $err.Exception.Message | Should -Be 'Host is missing'
    }
}
