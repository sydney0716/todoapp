from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi import HTTPException

from app.login_rate_limit import LoginRateLimiter


def test_ip_limit_applies_across_accounts_and_resets_without_extending(monkeypatch):
    now = [100.0]
    monkeypatch.setattr("app.login_rate_limit.monotonic", lambda: now[0])
    limiter = LoginRateLimiter()
    for attempt in range(10):
        limiter.check("192.0.2.1", "user1" if attempt % 2 else "user2")

    now[0] = 130.0
    with pytest.raises(HTTPException) as blocked:
        limiter.check("192.0.2.1", "user1")
    assert blocked.value.status_code == 429
    assert blocked.value.headers == {"Retry-After": "30"}
    # The other visitor can still use the same account.
    limiter.check("192.0.2.2", "user1")
    now[0] = 160.0
    limiter.check("192.0.2.1", "user1")


def test_account_limit_applies_across_ips_and_normalizes_username():
    limiter = LoginRateLimiter()
    for attempt in range(20):
        limiter.check(f"192.0.2.{attempt}", " User1 ")
    with pytest.raises(HTTPException) as blocked:
        limiter.check("198.51.100.1", "user1")
    assert blocked.value.status_code == 429
    limiter.check("198.51.100.1", "user2")


def test_simultaneous_attempts_cannot_bypass_limit():
    limiter = LoginRateLimiter()

    def attempt(_):
        try:
            limiter.check("192.0.2.1", "user1")
        except HTTPException:
            return False
        return True

    with ThreadPoolExecutor(max_workers=20) as executor:
        assert sum(executor.map(attempt, range(30))) == 10


def test_full_memory_does_not_evict_active_limits_and_recovers(monkeypatch):
    now = [100.0]
    monkeypatch.setattr("app.login_rate_limit.monotonic", lambda: now[0])
    limiter = LoginRateLimiter()
    limiter.MAX_WINDOWS = 3
    limiter.check("192.0.2.1", "unknown-one")
    limiter.check("192.0.2.2", "unknown-two")
    with pytest.raises(HTTPException):
        limiter.check("192.0.2.3", "unknown-three")
    # A known source can continue using its existing bucket.
    limiter.check("192.0.2.1", "unknown-four")
    assert len(limiter._windows) == 3
    now[0] = 160.0
    limiter.check("192.0.2.3", "unknown-three")
