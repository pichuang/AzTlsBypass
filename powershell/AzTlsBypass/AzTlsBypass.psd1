@{
    # Module manifest for AzTlsBypass
    RootModule           = 'AzTlsBypass.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'b1bc0d8e-9b87-4a8f-9c14-1c4f5d2e9a01'
    Author               = 'pichuang'
    CompanyName          = 'pichuang'
    Copyright            = '(c) pichuang. MIT License.'
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

    FileList             = @(
        'AzTlsBypass.psd1'
        'AzTlsBypass.psm1'
        'Public/Clear-AzTlsBypassConfig.ps1'
        'Public/Disable-AzTlsBypass.ps1'
        'Public/Enable-AzTlsBypass.ps1'
        'Public/Get-AzTlsBypassConfig.ps1'
        'Public/Get-AzTlsBypassStatus.ps1'
        'Public/Invoke-AzWithBypass.ps1'
        'Public/Set-AzTlsBypassConfig.ps1'
        'Private/Clear-AzTlsBypassEnvironment.ps1'
        'Private/Get-AzCliPath.ps1'
        'Private/Get-AzTlsBypassConfigPath.ps1'
        'Private/Set-AzTlsBypassEnvironment.ps1'
        'PythonShim/sitecustomize.py'
        'PythonShim/tls_bypass_core.py'
    )

    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureCLI', 'TLS', 'Proxy', 'Enterprise')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/pichuang/AzTlsBypass'
            ReleaseNotes = @'
0.1.0 — Initial public release.

Features:
- Enable/Disable-AzTlsBypass with optional -Persist that writes to $PROFILE.CurrentUserAllHosts
- Transparent global:az function override; `az login` works behind TLS-intercepting proxies with zero user friction
- Get-AzTlsBypassStatus diagnostic cmdlet (Active/EnvActive/FunctionOverride/Persisted/Config/AzPath/PythonPath)
- Invoke-AzWithBypass one-shot worker
- Set/Get/Clear-AzTlsBypassConfig persists ProxyUrl/NoProxy/CaCertPath to ~/.AzTlsBypass/config.json
- PythonShim/sitecustomize.py applied via PYTHONPATH injection; monkey-patches requests.sessions.Session before azure.cli loads
- NO_PROXY auto-merge for IMDS (169.254.169.254), WireServer, and loopback so `az login --identity` works on Azure VMs
- Honors legacy AZ_LOGIN_INSECURE_PATCH env var; mirrors AZURE_CLI_DISABLE_CONNECTION_VERIFICATION / ADAL_PYTHON_SSL_NO_VERIFY / PYTHONHTTPSVERIFY

Compatibility: PowerShell 5.1 (Desktop) and 7+ (Core). Full functionality requires Windows + Azure CLI installation.
'@
        }
    }
}
