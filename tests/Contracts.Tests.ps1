BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:contracts = Join-Path $script:root 'specs/features/001-diagnostic-chain/contracts'
    $script:module = Join-Path $script:root 'src/Beacon'
}

Describe 'Contracts of feature 001' {
    It 'the result example is valid against the result schema' {
        $schema = Get-Content -Raw -Path (Join-Path $script:contracts 'result.schema.json')
        $example = Get-Content -Raw -Path (Join-Path $script:contracts 'result.example.json')
        Test-Json -Json $example -Schema $schema -ErrorAction Stop | Should -BeTrue
    }

    It 'the matrix example is a data file with environments' {
        $matrix = Import-PowerShellDataFile -Path (Join-Path $script:contracts 'matrix.example.psd1')
        $matrix.Environments.Keys | Should -Contain 'test'
    }
}

Describe 'Module Beacon' {
    It 'has a valid manifest' {
        { Test-ModuleManifest -Path (Join-Path $script:module 'Beacon.psd1') -ErrorAction Stop } | Should -Not -Throw
    }

    It 'imports' {
        { Import-Module (Join-Path $script:module 'Beacon.psd1') -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'loads its defaults, with the schema version of the result contract' {
        $defaults = Import-PowerShellDataFile -Path (Join-Path $script:module 'config/defaults.psd1')
        $schema = Get-Content -Raw -Path (Join-Path $script:contracts 'result.schema.json') | ConvertFrom-Json
        $defaults.ResultSchemaVersion | Should -Be $schema.properties.schemaVersion.const
    }
}
