import pytest
from pydantic import ValidationError

from app.config import Settings


@pytest.mark.parametrize(
    "secret", ["", " ", "change-me", "change-me-to-a-different-long-random-secret"]
)
def test_rejects_missing_or_placeholder_signing_secret(secret):
    with pytest.raises(ValidationError):
        Settings(_env_file=None, jwt_secret=secret)


def test_requires_signing_secret(monkeypatch):
    monkeypatch.delenv("JWT_SECRET", raising=False)
    with pytest.raises(ValidationError):
        Settings(_env_file=None)


def test_accepts_configured_signing_secret():
    assert Settings(_env_file=None, jwt_secret="a-private-test-secret").jwt_secret
