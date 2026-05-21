"""Pytest configuration for the tls-bypass core unit tests.

Adds the ``core/`` directory to ``sys.path`` so tests can ``import
tls_bypass_core`` directly without installing the project.
"""

from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_CORE_DIR = _REPO_ROOT / "core"

if str(_CORE_DIR) not in sys.path:
    sys.path.insert(0, str(_CORE_DIR))
