from dataclasses import dataclass
from functools import lru_cache
from math import ceil
from threading import Lock
from time import monotonic

from fastapi import HTTPException, status


@dataclass
class AttemptWindow:
    expires_at: float
    count: int = 0


class LoginRateLimiter:
    """Short, bounded windows for the single-process personal server."""

    WINDOW_SECONDS = 60
    IP_LIMIT = 10
    ACCOUNT_LIMIT = 20
    MAX_WINDOWS = 4096

    def __init__(self) -> None:
        self._windows: dict[tuple[str, str], AttemptWindow] = {}
        self._lock = Lock()

    def check(self, client_ip: str, username: str) -> None:
        # Unknown usernames share a bucket, so arbitrary names cannot grow memory.
        account = username.strip().lower()
        if account not in ("user1", "user2"):
            account = "unknown"
        limits = (
            (("ip", client_ip), self.IP_LIMIT),
            (("account", account), self.ACCOUNT_LIMIT),
        )
        with self._lock:
            now = monotonic()
            self._windows = {
                key: window
                for key, window in self._windows.items()
                if window.expires_at > now
            }
            blocked = [
                window.expires_at - now
                for key, limit in limits
                if (window := self._windows.get(key)) is not None
                and window.count >= limit
            ]
            if blocked:
                self._reject(ceil(max(blocked)))
            missing = sum(key not in self._windows for key, _ in limits)
            if len(self._windows) + missing > self.MAX_WINDOWS:
                self._reject(
                    ceil(
                        min(
                            window.expires_at - now for window in self._windows.values()
                        )
                    )
                )
            # Reserve before bcrypt/database work so concurrent attempts count too.
            for key, _ in limits:
                window = self._windows.setdefault(
                    key, AttemptWindow(now + self.WINDOW_SECONDS)
                )
                window.count += 1

    @staticmethod
    def _reject(retry_after: int) -> None:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many login attempts. Try again in a minute.",
            headers={"Retry-After": str(max(1, retry_after))},
        )


@lru_cache
def get_login_rate_limiter() -> LoginRateLimiter:
    return LoginRateLimiter()
