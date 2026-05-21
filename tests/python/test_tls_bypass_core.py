"""Unit tests for :mod:`tls_bypass_core`.

These tests exercise the monkey-patch in isolation by snapshotting
``requests.sessions.Session.request`` /
``Session.merge_environment_settings`` and the relevant environment
variables in ``setUp``, then restoring them in ``tearDown``.  No real
network traffic is generated.
"""

from __future__ import annotations

import logging
import os
import unittest

import requests

import tls_bypass_core


_ENV_KEYS = (
    tls_bypass_core.ACTIVE_ENV_VAR,
    tls_bypass_core.LEGACY_ACTIVE_ENV_VAR,
    "AZURE_CLI_DISABLE_CONNECTION_VERIFICATION",
    "ADAL_PYTHON_SSL_NO_VERIFY",
    "PYTHONHTTPSVERIFY",
    "REQUESTS_CA_BUNDLE",
    "CURL_CA_BUNDLE",
)


class TestApplyGlobalInsecureTransport(unittest.TestCase):
    """Behaviour of :func:`tls_bypass_core.apply_global_insecure_transport`."""

    def setUp(self):
        self._orig_request = requests.sessions.Session.request
        self._orig_merge = requests.sessions.Session.merge_environment_settings
        self._env_snapshot = {k: os.environ.get(k) for k in _ENV_KEYS}
        # Reset idempotency flag so each test exercises a fresh patch.
        if hasattr(tls_bypass_core.apply_global_insecure_transport, "_patched"):
            delattr(tls_bypass_core.apply_global_insecure_transport, "_patched")

    def tearDown(self):
        requests.sessions.Session.request = self._orig_request
        requests.sessions.Session.merge_environment_settings = self._orig_merge
        for k, v in self._env_snapshot.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        if hasattr(tls_bypass_core.apply_global_insecure_transport, "_patched"):
            delattr(tls_bypass_core.apply_global_insecure_transport, "_patched")

    def test_not_patched_by_default(self):
        self.assertFalse(tls_bypass_core.is_patched())
        self.assertIs(requests.sessions.Session.request, self._orig_request)

    def test_apply_returns_true_then_false(self):
        self.assertTrue(tls_bypass_core.apply_global_insecure_transport())
        self.assertFalse(tls_bypass_core.apply_global_insecure_transport())
        self.assertTrue(tls_bypass_core.is_patched())

    def test_overrides_request_verify(self):
        captured = {}

        def fake_request(self, method, url, **kwargs):  # pylint: disable=unused-argument
            captured["verify"] = kwargs.get("verify")
            from requests.models import Response

            r = Response()
            r.status_code = 200
            return r

        # Install the fake BEFORE applying so the wrapper snapshots our fake
        # as ``original_request``.
        requests.sessions.Session.request = fake_request

        tls_bypass_core.apply_global_insecure_transport()

        session = requests.Session()
        session.request("GET", "http://example.invalid", verify=True)
        self.assertIs(captured["verify"], False)

    def test_overrides_merge_environment_settings(self):
        def fake_merge(self, *args, **kwargs):  # pylint: disable=unused-argument
            return {"verify": True, "proxies": {}, "stream": False, "cert": None}

        requests.sessions.Session.merge_environment_settings = fake_merge

        tls_bypass_core.apply_global_insecure_transport()

        session = requests.Session()
        settings = session.merge_environment_settings(
            "http://example.invalid", {}, None, True, None
        )
        self.assertIs(settings["verify"], False)

    def test_sets_companion_env_vars(self):
        for key in (
            "AZURE_CLI_DISABLE_CONNECTION_VERIFICATION",
            "ADAL_PYTHON_SSL_NO_VERIFY",
            "PYTHONHTTPSVERIFY",
        ):
            os.environ.pop(key, None)

        tls_bypass_core.apply_global_insecure_transport()

        self.assertEqual(
            os.environ.get("AZURE_CLI_DISABLE_CONNECTION_VERIFICATION"), "1"
        )
        self.assertEqual(os.environ.get("ADAL_PYTHON_SSL_NO_VERIFY"), "1")
        self.assertEqual(os.environ.get("PYTHONHTTPSVERIFY"), "0")

    def test_removes_ca_bundle_env_vars(self):
        os.environ["REQUESTS_CA_BUNDLE"] = "/tmp/bogus-ca.pem"
        os.environ["CURL_CA_BUNDLE"] = "/tmp/bogus-ca.pem"

        tls_bypass_core.apply_global_insecure_transport()

        self.assertNotIn("REQUESTS_CA_BUNDLE", os.environ)
        self.assertNotIn("CURL_CA_BUNDLE", os.environ)

    def test_emits_security_warning(self):
        with self.assertLogs("AzTlsBypass", level=logging.WARNING) as cm:
            tls_bypass_core.apply_global_insecure_transport()

        joined = "\n".join(cm.output)
        self.assertIn("TLS certificate verification disabled", joined)


class TestSitecustomizeMain(unittest.TestCase):
    """Behaviour of :func:`tls_bypass_core.sitecustomize_main`."""

    def setUp(self):
        self._orig_request = requests.sessions.Session.request
        self._orig_merge = requests.sessions.Session.merge_environment_settings
        self._env_snapshot = {k: os.environ.get(k) for k in _ENV_KEYS}
        if hasattr(tls_bypass_core.apply_global_insecure_transport, "_patched"):
            delattr(tls_bypass_core.apply_global_insecure_transport, "_patched")

    def tearDown(self):
        requests.sessions.Session.request = self._orig_request
        requests.sessions.Session.merge_environment_settings = self._orig_merge
        for k, v in self._env_snapshot.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        if hasattr(tls_bypass_core.apply_global_insecure_transport, "_patched"):
            delattr(tls_bypass_core.apply_global_insecure_transport, "_patched")

    def test_no_op_when_inactive(self):
        for key in (
            tls_bypass_core.ACTIVE_ENV_VAR,
            tls_bypass_core.LEGACY_ACTIVE_ENV_VAR,
        ):
            os.environ.pop(key, None)

        self.assertFalse(tls_bypass_core.sitecustomize_main())
        self.assertFalse(tls_bypass_core.is_patched())
        self.assertIs(requests.sessions.Session.request, self._orig_request)

    def test_applies_when_primary_env_set(self):
        os.environ.pop(tls_bypass_core.LEGACY_ACTIVE_ENV_VAR, None)
        os.environ[tls_bypass_core.ACTIVE_ENV_VAR] = "1"

        self.assertTrue(tls_bypass_core.sitecustomize_main())
        self.assertTrue(tls_bypass_core.is_patched())

    def test_applies_when_legacy_env_set(self):
        """Backwards compatibility with the original hotpatch's env var."""
        os.environ.pop(tls_bypass_core.ACTIVE_ENV_VAR, None)
        os.environ[tls_bypass_core.LEGACY_ACTIVE_ENV_VAR] = "1"

        self.assertTrue(tls_bypass_core.sitecustomize_main())
        self.assertTrue(tls_bypass_core.is_patched())

    def test_falsy_values_are_ignored(self):
        os.environ[tls_bypass_core.ACTIVE_ENV_VAR] = "0"

        self.assertFalse(tls_bypass_core.sitecustomize_main())
        self.assertFalse(tls_bypass_core.is_patched())


class TestPublicConstants(unittest.TestCase):
    """Guard against accidental renames; PowerShell shim relies on these."""

    def test_active_env_var_name_stable(self):
        self.assertEqual(tls_bypass_core.ACTIVE_ENV_VAR, "AZ_TLS_BYPASS_ACTIVE")

    def test_legacy_env_var_name_stable(self):
        self.assertEqual(
            tls_bypass_core.LEGACY_ACTIVE_ENV_VAR, "AZ_LOGIN_INSECURE_PATCH"
        )


if __name__ == "__main__":
    unittest.main()
