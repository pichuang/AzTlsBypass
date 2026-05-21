@{
    # Module manifest for AzTlsBypass
    RootModule           = 'AzTlsBypass.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'b1bc0d8e-9b87-4a8f-9c14-1c4f5d2e9a01'
    Author               = 'AzTlsBypass Contributors'
    CompanyName          = 'AzTlsBypass Contributors'
    Copyright            = '(c) AzTlsBypass Contributors. MIT License.'
    Description          = 'Transparent TLS bypass + proxy wrapper for Azure CLI behind TLS-intercepting enterprise proxies. Supports PowerShell 5.1 and 7+.'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Public functions exported by the module.
    FunctionsToExport    = @(
        'Enable-AzTlsBypass'
        'Disable-AzTlsBypass'
        'Get-AzTlsBypassStatus'
        'Invoke-AzWithBypass'
        'Set-AzTlsBypassConfig'
        'Get-AzTlsBypassConfig'
        'Clear-AzTlsBypassConfig'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureCLI', 'TLS', 'Proxy', 'Enterprise')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/<your-org>/tls-bypass'
            ReleaseNotes = 'Initial release: dual-track (PowerShell module + planned az extension) TLS bypass.'
        }
    }
}
