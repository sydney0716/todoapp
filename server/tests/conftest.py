from __future__ import annotations

import sys
from pathlib import Path

import pytest

SERVER_ROOT = Path(__file__).resolve().parents[1]
server_root_path = str(SERVER_ROOT)
if server_root_path not in sys.path:
    sys.path.insert(0, server_root_path)


@pytest.fixture(autouse=True)
def isolated_login_rate_limiter():
    from app.login_rate_limit import get_login_rate_limiter

    get_login_rate_limiter.cache_clear()
    yield
    get_login_rate_limiter.cache_clear()
