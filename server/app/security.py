from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from secrets import token_urlsafe
from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from .config import get_settings
from .database import get_db
from .fixed_accounts import hash_secret, verify_secret
from .models import Device, User

bearer_scheme = HTTPBearer(auto_error=False)
_BEARER_DEPENDENCY = Depends(bearer_scheme)
_DB_DEPENDENCY = Depends(get_db)
_ALGORITHM = "HS256"
_ACCESS_TOKEN_TYPE = "access"


@dataclass(frozen=True)
class CurrentUser:
    user_id: UUID
    device_id: UUID | None = None


def create_access_token(*, user_id: UUID, device_id: UUID) -> str:
    settings = get_settings()
    now = datetime.now(UTC)
    expires_at = now + timedelta(minutes=settings.access_token_minutes)
    return jwt.encode(
        {
            "sub": str(user_id),
            "device_id": str(device_id),
            "type": _ACCESS_TOKEN_TYPE,
            "iat": now,
            "exp": expires_at,
        },
        settings.jwt_secret,
        algorithm=_ALGORITHM,
    )


def create_refresh_token() -> str:
    return token_urlsafe(48)


def refresh_token_expires_at() -> datetime:
    return datetime.now(UTC) + timedelta(days=get_settings().refresh_token_days)


def hash_token(token: str) -> str:
    return hash_secret(token)


def verify_token(token: str, token_hash: str) -> bool:
    return verify_secret(token, token_hash)


def require_user(
    credentials: HTTPAuthorizationCredentials | None = _BEARER_DEPENDENCY,
    db: Session = _DB_DEPENDENCY,
) -> CurrentUser:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    settings = get_settings()
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=[_ALGORITHM],
        )
        if payload.get("type") != _ACCESS_TOKEN_TYPE:
            raise ValueError
        user_id = UUID(payload["sub"])
        device_id = UUID(payload["device_id"])
    except (JWTError, KeyError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token",
        ) from None

    user = db.get(User, user_id)
    device = db.get(Device, device_id)
    if (
        user is None
        or not user.is_active
        or device is None
        or device.user_id != user_id
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token",
        )

    return CurrentUser(user_id=user_id, device_id=device_id)
