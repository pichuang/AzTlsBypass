<#
.SYNOPSIS
Runs any Azure CLI command through the configured HTTP proxy and TLS fallback.

.EXAMPLE
.\Invoke-AzWithProxy.ps1 network application-gateway list

.EXAMPLE
.\Invoke-AzWithProxy.ps1 account show --output table
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AzArguments,

    [string]$ProxyUrl = "http://proxy.example.com:8080",

    [string[]]$NoProxyHosts = @("169.254.169.254", "localhost", "127.0.0.1")
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$previousPythonPath = $env:PYTHONPATH
$previousNoProxy = $env:NO_PROXY
$previousNoProxyLower = $env:no_proxy

function Merge-NoProxyHosts {
    param(
        [string]$Existing,
        [string[]]$Required
    )

    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    if (-not [string]::IsNullOrWhiteSpace($Existing)) {
        foreach ($item in ($Existing -split ',')) {
            $candidate = $item.Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                [void]$set.Add($candidate)
            }
        }
    }

    foreach ($requiredHost in $Required) {
        if (-not [string]::IsNullOrWhiteSpace($requiredHost)) {
            [void]$set.Add($requiredHost.Trim())
        }
    }

    return [string]::Join(',', $set)
}

try {
    $azCommand = Get-Command az.cmd -ErrorAction SilentlyContinue
    if (-not $azCommand) {
        $defaultAzCommand = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
        if (Test-Path -Path $defaultAzCommand) {
            $azCommandPath = $defaultAzCommand
        }
        else {
            throw "Azure CLI az.cmd was not found in PATH."
        }
    }
    else {
        $azCommandPath = $azCommand.Source
    }

    $azWbinPath = Split-Path -Parent $azCommandPath
    $azPythonPath = Join-Path (Split-Path -Parent $azWbinPath) "python.exe"
    if (-not (Test-Path -Path $azPythonPath)) {
        throw "Azure CLI Python executable was not found: $azPythonPath"
    }

    $siteCustomizePath = Join-Path $PSScriptRoot ".azure-cli-insecure-sitecustomize"
    if (-not (Test-Path -Path (Join-Path $siteCustomizePath "sitecustomize.py"))) {
        throw "Missing TLS fallback shim. Run .\Repair-AzCliProxyLogin.ps1 first."
    }

    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
    $env:ALL_PROXY = $ProxyUrl
    $mergedNoProxy = Merge-NoProxyHosts -Existing $env:NO_PROXY -Required $NoProxyHosts
    $env:NO_PROXY = $mergedNoProxy
    $env:no_proxy = $mergedNoProxy
    Remove-Item Env:\REQUESTS_CA_BUNDLE -ErrorAction SilentlyContinue
    Remove-Item Env:\CURL_CA_BUNDLE -ErrorAction SilentlyContinue
    $env:AZURE_CLI_DISABLE_CONNECTION_VERIFICATION = "1"
    $env:ADAL_PYTHON_SSL_NO_VERIFY = "1"
    $env:PYTHONHTTPSVERIFY = "0"
    $env:AZ_LOGIN_INSECURE_PATCH = "1"

    if ($env:PYTHONPATH) {
        $env:PYTHONPATH = "$siteCustomizePath$([IO.Path]::PathSeparator)$env:PYTHONPATH"
    }
    else {
        $env:PYTHONPATH = $siteCustomizePath
    }

    & $azPythonPath -Bm azure.cli @AzArguments
    exit $LASTEXITCODE
}
finally {
    Remove-Item Env:\AZURE_CLI_DISABLE_CONNECTION_VERIFICATION -ErrorAction SilentlyContinue
    Remove-Item Env:\ADAL_PYTHON_SSL_NO_VERIFY -ErrorAction SilentlyContinue
    Remove-Item Env:\PYTHONHTTPSVERIFY -ErrorAction SilentlyContinue
    Remove-Item Env:\AZ_LOGIN_INSECURE_PATCH -ErrorAction SilentlyContinue
    if ($null -eq $previousNoProxy) {
        Remove-Item Env:\NO_PROXY -ErrorAction SilentlyContinue
    }
    else {
        $env:NO_PROXY = $previousNoProxy
    }
    if ($null -eq $previousNoProxyLower) {
        Remove-Item Env:\no_proxy -ErrorAction SilentlyContinue
    }
    else {
        $env:no_proxy = $previousNoProxyLower
    }
    if ($null -eq $previousPythonPath) {
        Remove-Item Env:\PYTHONPATH -ErrorAction SilentlyContinue
    }
    else {
        $env:PYTHONPATH = $previousPythonPath
    }
}
