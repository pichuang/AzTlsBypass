"""Core TLS bypass logic shared by the PowerShell module (L1) and the az
extension (L2, planned).

This module provides three entry points:

* :func:`apply_global_insecure_transport` — idempotent monkey-patch that
  disables TLS certificate verification for every ``requests.Session``
  instance created in the current Python process, including the session
  that MSAL builds internally during ``az login``.
* :func:`sitecustomize_main` — opt-in hook for ``sitecustomize.py``.  When
  the environment variable ``AZ_TLS_BYPASS_ACTIVE=1`` is set, this calls
  :func:`apply_global_insecure_transport` automatically as Python starts
  up, *before* any azure-cli or MSAL code is imported.
* :func:`bootstrap_main` — convenience wrapper that applies the patch and
  then dispatches to ``azure.cli.__main__:main``.  This is used by direct
  ``python -m`` style invocations as an alternative to the
  ``sitecustomize`` route.

Security warning
----------------
Calling :func:`apply_global_insecure_transport` disables TLS server
certificate validation for the *entire* Python process.  It must only be
used behind a trusted enterprise TLS-intercepting proxy.  Prefer
``REQUESTS_CA_BUNDLE`` whenever the proxy CA can be installed properly.
"""

from __future__ import annotations

import logging
import os
import sys
from typing import Optional

__all__ = [
    "ACTIVE_ENV_VAR",
    "LEGACY_ACTIVE_ENV_VAR",
    "apply_global_insecure_transport",
    "is_patched",
    "sitecustomize_main",
    "bootstrap_main",
]

#: Primary opt-in env var used by AzTlsBypass.
ACTIVE_ENV_VAR = "AZ_TLS_BYPASS_ACTIVE"

#: Legacy env var honoured for backwards compatibility with the original
#: ``azcli-hotpatch-20260521`` hotpatch.
LEGACY_ACTIVE_ENV_VAR = "AZ_LOGIN_INSECURE_PATCH"

#: azure-cli's own connection-verify env var.  We mirror it so that the
#: existing core paths (extension installer, ``send_raw_request`` etc.)
#: agree with our global override.
_AZURE_CLI_DISABLE_ENV = "AZURE_CLI_DISABLE_CONNECTION_VERIFICATION"
_ADAL_NO_VERIFY_ENV = "ADAL_PYTHON_SSL_NO_VERIFY"
_PYTHON_HTTPS_VERIFY_ENV = "PYTHONHTTPSVERIFY"

#: CA bundle env vars that ``requests`` will pick up and that would
#: otherwise override our ``verify=False`` decision.
_CA_BUNDLE_ENV_VARS = ("REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE")

_logger = logging.getLogger("AzTlsBypass")


def _is_active() -> bool:
    """Return True when either the primary or legacy opt-in env var is set."""
    for name in (ACTIVE_ENV_VAR, LEGACY_ACTIVE_ENV_VAR):
        value = os.environ.get(name)
        if value and value.strip() not in ("", "0", "false", "False"):
            return True
    return False


def is_patched() -> bool:
    """Return True when :func:`apply_global_insecure_transport` has already
    monkey-patched the current process.
    """
    return getattr(apply_global_insecure_transport, "_patched", False)


def apply_global_insecure_transport() -> bool:
    """Monkey-patch ``requests.sessions.Session`` to skip TLS verification.

    The patch is idempotent; repeated calls return ``False`` after the
    first successful application.  Returns ``True`` when the patch is
    newly installed.

    Side effects:

    * Suppress ``urllib3.exceptions.InsecureRequestWarning``.
    * Set companion env vars (``AZURE_CLI_DISABLE_CONNECTION_VERIFICATION``,
      ``ADAL_PYTHON_SSL_NO_VERIFY``, ``PYTHONHTTPSVERIFY``) so the rest of
      azure-cli's HTTP paths agree with the global override.
    * Remove stale CA bundle env vars (``REQUESTS_CA_BUNDLE``,
      ``CURL_CA_BUNDLE``) that would otherwise pin verification back on.
    * Replace ``Session.request`` and ``Session.merge_environment_settings``
      with wrappers that force ``verify=False``.
    """
    if is_patched():
        return False

    # Lazy import so that this module remains importable even when the
    # azure-cli bundled Python does not have requests installed (e.g. unit
    # tests with a stripped-down env).
    try:
        import requests  # noqa: PLC0415
        import urllib3  # noqa: PLC0415
    except ImportError as exc:  # pragma: no cover - smoke-tested only
        _logger.warning(
            "[AzTlsBypass] requests/urllib3 not importable; patch skipped: %s",
            exc,
        )
        return False

    _logger.warning(
        "[AzTlsBypass] TLS certificate verification disabled process-wide. "
        "This is unsafe outside of trusted enterprise TLS-intercepting proxies."
    )

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    # Mirror sister env vars so existing azure-cli paths stay consistent.
    os.environ[_AZURE_CLI_DISABLE_ENV] = "1"
    os.environ[_ADAL_NO_VERIFY_ENV] = "1"
    os.environ[_PYTHON_HTTPS_VERIFY_ENV] = "0"

    # Remove stale CA bundle env vars.
    for ca_env in _CA_BUNDLE_ENV_VARS:
        os.environ.pop(ca_env, None)

    original_request = requests.sessions.Session.request
    original_merge_environment_settings = (
        requests.sessions.Session.merge_environment_settings
    )

    def _request_without_tls_verification(self, method, url, **kwargs):
        kwargs["verify"] = False
        return original_request(self, method, url, **kwargs)

    def _merge_environment_settings_without_tls_verification(
        self, *args, **kwargs
    ):
        settings = original_merge_environment_settings(self, *args, **kwargs)
        settings["verify"] = False
        return settings

    # Preserve __wrapped__ links so ``is_patched`` and tooling that
    # inspects the wrapped chain can find the originals.
    _request_without_tls_verification.__wrapped__ = original_request
    _merge_environment_settings_without_tls_verification.__wrapped__ = (
        original_merge_environment_settings
    )

    requests.sessions.Session.request = _request_without_tls_verification
    requests.sessions.Session.merge_environment_settings = (
        _merge_environment_settings_without_tls_verification
    )

    apply_global_insecure_transport._patched = True  # type: ignore[attr-defined]
    return True


def sitecustomize_main() -> bool:
    """Entry point intended to be called from a ``sitecustomize.py`` shim.

    The patch is only applied when the opt-in env var is set; otherwise
    this is a no-op so that the same Python interpreter remains safe for
    code that does not need the bypass.

    Returns the result of :func:`apply_global_insecure_transport` (``True``
    if newly patched, ``False`` otherwise).
    """
    if not _is_active():
        return False
    return apply_global_insecure_transport()


def bootstrap_main(argv: Optional[list] = None) -> int:
    """Apply the patch then dispatch to ``azure.cli.__main__:main``.

    This is an alternative entry point for environments where the
    ``sitecustomize`` route is unavailable (e.g. ``python -I``).  Returns
    the exit code from azure-cli.
    """
    apply_global_insecure_transport()
    from azure.cli.__main__ import main  # noqa: PLC0415

    if argv is None:
        argv = sys.argv[1:]
    return main(argv)
