"""End-to-end integration tests.

Simulates what the PowerShell wrapper does at runtime: spawn a fresh
Python interpreter with ``PYTHONPATH`` pointing at the shipped
``PythonShim/`` and ``AZ_TLS_BYPASS_ACTIVE=1`` in the environment, then
assert that :mod:`tls_bypass_core` was imported via ``sitecustomize`` and
that ``requests.sessions.Session.request`` is monkey-patched.

These tests do NOT require Windows or a real ``az.cmd``; they only need a
Python interpreter that ships ``requests``.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest


_REPO_ROOT = Path(__file__).resolve().parents[2]
_SHIM_DIR = _REPO_ROOT / "powershell" / "AzTlsBypass" / "PythonShim"


def _has_requests() -> bool:
    try:
        import requests  # noqa: F401, PLC0415
    except ImportError:
        return False
    return True


pytestmark = pytest.mark.skipif(
    not _has_requests(),
    reason="requests not available in this interpreter",
)


def _run_child(env_extra: dict, script: str) -> dict:
    """Run a Python child process with the given env overlay and return the
    JSON object it prints to stdout.
    """
    env = os.environ.copy()
    env.update(env_extra)

    # Prepend the shim dir so sitecustomize.py is picked up.
    sep = os.pathsep
    existing = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = str(_SHIM_DIR) + (sep + existing if existing else "")

    # IMPORTANT: do not pass ``-I`` (would skip site.py and thus
    # sitecustomize) nor ``-S``.  ``-B`` is fine.
    proc = subprocess.run(
        [sys.executable, "-B", "-c", script],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=30,
    )
    if proc.returncode != 0:
        raise AssertionError(
            f"Child process failed with exit {proc.returncode}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )
    return json.loads(proc.stdout.strip().splitlines()[-1])


_PROBE = textwrap.dedent(
    """
    import json
    import os
    import sys

    import requests

    result = {
        "tls_bypass_core_imported": "tls_bypass_core" in sys.modules,
        "session_request_wrapped": hasattr(
            requests.sessions.Session.request, "__wrapped__"
        ),
        "azure_cli_disable_env": os.environ.get(
            "AZURE_CLI_DISABLE_CONNECTION_VERIFICATION"
        ),
        "active_env": os.environ.get("AZ_TLS_BYPASS_ACTIVE"),
        "legacy_active_env": os.environ.get("AZ_LOGIN_INSECURE_PATCH"),
        "ca_bundle_after": os.environ.get("REQUESTS_CA_BUNDLE"),
    }
    print(json.dumps(result))
    """
).strip()


class TestEndToEnd:
    """Verify the sitecustomize shim wires up correctly in a real child process."""

    def test_inactive_when_env_not_set(self):
        env = {
            # Make sure no leftover from the parent test process leaks.
            "AZ_TLS_BYPASS_ACTIVE": "",
            "AZ_LOGIN_INSECURE_PATCH": "",
        }
        result = _run_child(env, _PROBE)
        # sitecustomize.py is still imported (Python loads it whenever it
        # exists), but apply_global_insecure_transport should NOT have run.
        assert result["tls_bypass_core_imported"] is True
        assert result["session_request_wrapped"] is False

    def test_active_primary_env_patches_requests(self):
        env = {"AZ_TLS_BYPASS_ACTIVE": "1"}
        result = _run_child(env, _PROBE)
        assert result["tls_bypass_core_imported"] is True
        assert result["session_request_wrapped"] is True
        assert result["azure_cli_disable_env"] == "1"

    def test_legacy_env_still_works(self):
        env = {"AZ_LOGIN_INSECURE_PATCH": "1"}
        result = _run_child(env, _PROBE)
        assert result["session_request_wrapped"] is True

    def test_ca_bundle_env_var_is_cleared(self):
        env = {
            "AZ_TLS_BYPASS_ACTIVE": "1",
            "REQUESTS_CA_BUNDLE": "/tmp/should-be-removed.pem",
        }
        result = _run_child(env, _PROBE)
        assert result["session_request_wrapped"] is True
        assert result["ca_bundle_after"] is None or result["ca_bundle_after"] == ""

    def test_falsy_env_value_does_not_activate(self):
        env = {"AZ_TLS_BYPASS_ACTIVE": "0"}
        result = _run_child(env, _PROBE)
        assert result["session_request_wrapped"] is False
