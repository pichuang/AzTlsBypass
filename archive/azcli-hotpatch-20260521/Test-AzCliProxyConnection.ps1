<#
.SYNOPSIS
Tests Azure CLI connectivity through an HTTP proxy with a custom CA certificate.

.DESCRIPTION
This script configures proxy and CA bundle environment variables for the current
PowerShell process, then validates:
1. The Azure CLI executable is available.
2. The custom CA certificate file is readable.
3. The HTTP proxy TCP port is reachable.
4. HTTPS can be reached through the proxy using the custom CA certificate.
5. Azure CLI can make a no-login HTTPS request with the same proxy and CA settings.

The script does not permanently change machine or user environment variables.

.EXAMPLE
.\Test-AzCliProxyConnection.ps1

.EXAMPLE
.\Test-AzCliProxyConnection.ps1 -VerboseAzCli

.EXAMPLE
.\Test-AzCliProxyConnection.ps1 -EnableCurlRevocationCheck

.EXAMPLE
.\Test-AzCliProxyConnection.ps1 -AllowAzCliInsecureFallback
#>

[CmdletBinding()]
param(
    [string]$ProxyUrl = "http://proxy.example.com:8080",

    [string]$CertificatePath = ".\corp-ca.crt",

    [string]$TestUrl = "https://management.azure.com/metadata/endpoints?api-version=2020-01-01",

    [switch]$VerboseAzCli,

    [switch]$EnableCurlRevocationCheck,

    [switch]$AllowAzCliInsecureFallback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Pass {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Fail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Write-Warn {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = ($output -join [Environment]::NewLine)
    }
}

function Test-CertificateExtension {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory = $true)]
        [string]$Oid
    )

    $extension = $Certificate.Extensions | Where-Object { $_.Oid.Value -eq $Oid } | Select-Object -First 1
    return $null -ne $extension
}

function Get-ProxyEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $uri = [Uri]$Url
    if (-not $uri.Host) {
        throw "ProxyUrl is invalid: $Url"
    }

    $port = $uri.Port
    if ($port -lt 0) {
        if ($uri.Scheme -eq "https") {
            $port = 443
        }
        else {
            $port = 80
        }
    }

    [pscustomobject]@{
        Host = $uri.Host
        Port = $port
    }
}

try {
    Write-Step "Checking Azure CLI"
    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCommand) {
        throw "Azure CLI was not found in PATH. Install Azure CLI or open a shell where 'az' is available."
    }
    Write-Pass "Azure CLI found: $($azCommand.Source)"

    Write-Step "Checking certificate file"
    $resolvedCertificate = (Resolve-Path -Path $CertificatePath).Path
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($resolvedCertificate)
    Write-Pass "Certificate loaded: Subject='$($certificate.Subject)', NotAfter='$($certificate.NotAfter)'"
    $hasSubjectKeyIdentifier = Test-CertificateExtension -Certificate $certificate -Oid "2.5.29.14"
    $hasAuthorityKeyIdentifier = Test-CertificateExtension -Certificate $certificate -Oid "2.5.29.35"
    if (-not $hasSubjectKeyIdentifier) {
        Write-Warn "Certificate does not contain Subject Key Identifier. Some OpenSSL-based clients may reject it."
    }
    if (-not $hasAuthorityKeyIdentifier) {
        Write-Warn "Certificate does not contain Authority Key Identifier. Azure CLI's Python/urllib3 stack may reject it."
    }

    Write-Step "Configuring proxy and CA environment variables for this process"
    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
    $env:ALL_PROXY = $ProxyUrl
    $env:REQUESTS_CA_BUNDLE = $resolvedCertificate
    $env:CURL_CA_BUNDLE = $resolvedCertificate
    $env:AZURE_CLI_DISABLE_CONNECTION_VERIFICATION = $null
    Write-Pass "HTTP_PROXY, HTTPS_PROXY, ALL_PROXY, REQUESTS_CA_BUNDLE, and CURL_CA_BUNDLE are set"

    Write-Step "Testing proxy TCP connectivity"
    $proxyEndpoint = Get-ProxyEndpoint -Url $ProxyUrl
    $tcpResult = Test-NetConnection -ComputerName $proxyEndpoint.Host -Port $proxyEndpoint.Port -InformationLevel Quiet
    if (-not $tcpResult) {
        throw "Cannot connect to proxy $($proxyEndpoint.Host):$($proxyEndpoint.Port). Check network route, firewall, or proxy service."
    }
    Write-Pass "Proxy TCP port is reachable: $($proxyEndpoint.Host):$($proxyEndpoint.Port)"

    Write-Step "Testing HTTPS through proxy with curl.exe and custom CA"
    $curlCommand = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curlCommand) {
        Write-Host "[WARN] curl.exe was not found; skipping direct HTTPS/proxy/CA test." -ForegroundColor Yellow
    }
    else {
        $curlArgs = @(
            "--fail",
            "--show-error",
            "--silent",
            "--location",
            "--proxy", $ProxyUrl,
            "--cacert", $resolvedCertificate,
            "--connect-timeout", "15",
            "--max-time", "60",
            "--output", "NUL",
            $TestUrl
        )
        if ($IsWindows -and -not $EnableCurlRevocationCheck) {
            $curlArgs = @("--ssl-no-revoke") + $curlArgs
            Write-Host "[INFO] curl.exe Schannel revocation check is disabled for this test. Certificate chain validation remains enabled." -ForegroundColor Yellow
        }

        $curlResult = Invoke-ExternalCommand -FilePath $curlCommand.Source -Arguments $curlArgs
        if ($curlResult.ExitCode -ne 0) {
            throw "curl HTTPS test failed with exit code $($curlResult.ExitCode). Output:$([Environment]::NewLine)$($curlResult.Output)"
        }
        Write-Pass "HTTPS request succeeded through proxy using the custom CA certificate"
    }

    Write-Step "Testing Azure CLI HTTPS request through proxy with custom CA"
    $azArgs = @(
        "extension", "list-available",
        "--query", "[0].name",
        "--output", "tsv"
    )
    if ($VerboseAzCli) {
        $azArgs += "--debug"
    }
    else {
        $azArgs += "--only-show-errors"
    }

    $azResult = Invoke-ExternalCommand -FilePath $azCommand.Source -Arguments $azArgs
    if ($azResult.ExitCode -ne 0) {
        if ($azResult.Output -match "Missing Authority Key Identifier") {
            $akiMessage = @(
                "Azure CLI rejected the CA certificate because it is missing Authority Key Identifier.",
                "This is a certificate compatibility issue in Azure CLI's Python/urllib3/OpenSSL validation path, not a proxy reachability issue.",
                "Ask the proxy/PKI team for a regenerated proxy CA certificate that includes Subject Key Identifier and Authority Key Identifier.",
                "For a connectivity-only Azure CLI test, rerun this script with -AllowAzCliInsecureFallback."
            ) -join [Environment]::NewLine

            if (-not $AllowAzCliInsecureFallback) {
                throw $akiMessage
            }

            Write-Warn "Azure CLI strict certificate validation failed because the CA certificate is missing Authority Key Identifier."
            Write-Warn "Retrying Azure CLI once with AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1 for connectivity-only validation."
            $env:AZURE_CLI_DISABLE_CONNECTION_VERIFICATION = "1"
            $azFallbackResult = Invoke-ExternalCommand -FilePath $azCommand.Source -Arguments $azArgs
            $env:AZURE_CLI_DISABLE_CONNECTION_VERIFICATION = $null

            if ($azFallbackResult.ExitCode -ne 0) {
                throw "Azure CLI insecure fallback connectivity test also failed with exit code $($azFallbackResult.ExitCode). Output:$([Environment]::NewLine)$($azFallbackResult.Output)"
            }

            Write-Pass "Azure CLI connectivity-only request succeeded through proxy. Certificate validation was disabled only for this fallback test."
            Write-Host ""
            Write-Warn "Final result: proxy connectivity works, but the supplied CA certificate is not acceptable to Azure CLI strict validation."
            Write-Host ""
            Write-Host "All connectivity tests completed with Azure CLI insecure fallback." -ForegroundColor Yellow
            exit 0
        }

        throw "Azure CLI connectivity test failed with exit code $($azResult.ExitCode). Output:$([Environment]::NewLine)$($azResult.Output)"
    }
    Write-Pass "Azure CLI no-login network request succeeded through proxy using REQUESTS_CA_BUNDLE"

    Write-Host ""
    Write-Host "All tests passed." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    Write-Host ""
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "- Confirm the proxy is reachable: $ProxyUrl"
    Write-Host "- Confirm the certificate is the CA that signs the proxy-inspected TLS connection."
    Write-Host "- If Azure CLI reports 'Missing Authority Key Identifier', request a regenerated proxy CA with SKI and AKI extensions."
    Write-Host "- For connectivity-only Azure CLI testing, rerun with -AllowAzCliInsecureFallback."
    Write-Host "- On Windows curl.exe, CERT_TRUST_REVOCATION_STATUS_UNKNOWN is usually a revocation lookup issue; rerun without -EnableCurlRevocationCheck."
    Write-Host "- Confirm Azure CLI inherits REQUESTS_CA_BUNDLE in the same PowerShell session."
    Write-Host "- Confirm AZURE_CLI_DISABLE_CONNECTION_VERIFICATION is not set; this script clears it for the current process."
    exit 1
}
