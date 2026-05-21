# sitecustomize.py — auto-loaded by Python at startup when this directory
# is on ``sys.path`` (e.g. via PYTHONPATH).  Delegates all work to
# ``tls_bypass_core.sitecustomize_main`` which is gated on the
# ``AZ_TLS_BYPASS_ACTIVE`` environment variable.
#
# Keep this file as thin as possible — the PowerShell wrapper assumes the
# real logic lives in ``tls_bypass_core``.

try:
    import tls_bypass_core
    tls_bypass_core.sitecustomize_main()
except Exception:  # pragma: no cover - never block azure-cli startup
    # Failing here would prevent ``az`` from running at all; swallow.
    pass
