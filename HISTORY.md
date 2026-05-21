# History

## 0.1.0 — 2026-05-22

Initial public release.

### Features

- **L1 — `AzTlsBypass` PowerShell module** (PS 5.1 + 7+ compatible)
  - `Enable-AzTlsBypass [-Persist]` — opt-in activation; defines `function global:az` for transparent invocation
  - `Disable-AzTlsBypass [-Persist]` — clean removal of function override, env vars, and profile snippet
  - `Get-AzTlsBypassStatus` — diagnostic report (active state, config, resolved paths)
  - `Invoke-AzWithBypass` — one-shot invocation worker
  - `Set/Get/Clear-AzTlsBypassConfig` — persistent JSON config in `~/.AzTlsBypass/config.json`
  - `Install-AzTlsBypass.ps1` / `Uninstall-AzTlsBypass.ps1` — module installation
- **`PythonShim/sitecustomize.py`** — automatically applied via `PYTHONPATH` injection during `az` invocation
- **`tls_bypass_core.py`** — single source of truth for the monkey-patch logic
  - `apply_global_insecure_transport()` — idempotent
  - `sitecustomize_main()` — env-gated entry point
  - `bootstrap_main()` — alternative `python -m` style entry point
- **NO_PROXY auto-merge** — IMDS / WireServer / loopback hosts always included so `az login --identity` works behind proxy

### Tests

- 18 pytest cases (13 unit + 5 integration via subprocess)
- 21 Pester cases (20 module + 1 PSScriptAnalyzer baseline)

### Compatibility

- Honors the legacy `AZ_LOGIN_INSECURE_PATCH=1` env var for backwards compatibility with the original `azcli-hotpatch-20260521` hotpatch
- Mirrors azure-cli's own `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION`, `ADAL_PYTHON_SSL_NO_VERIFY`, `PYTHONHTTPSVERIFY`

### Not yet shipped

- L2 — `az tls-bypass` extension (planned)
- PowerShell Gallery publication (planned)
