@{
    RootModule        = 'Beacon.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '2b0209db-a54f-456d-a5ba-3065d4118e4e'
    Author            = 'Beacon contributors'
    Description       = 'Network diagnostics: runs the checks that make sense on a path and shows where traffic stops.'
    PowerShellVersion = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @('Invoke-Beacon')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            LicenseUri = 'https://opensource.org/license/mit'
        }
    }
}
