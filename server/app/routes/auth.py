from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db
from ..fixed_accounts import ensure_fixed_accounts, verify_secret
from ..models import Device, User
from ..schemas import AuthLoginRequest, AuthResponse, RefreshRequest
from ..security import (
    CurrentUser,
    create_access_token,
    create_refresh_token,
    hash_token,
    refresh_token_expires_at,
    require_user,
    verify_token,
)

router = APIRouter(prefix="/auth", tags=["auth"])
_CURRENT_USER_DEPENDENCY = Depends(require_user)
_DB_DEPENDENCY = Depends(get_db)


@router.post("/login", response_model=AuthResponse)
def login(
    payload: AuthLoginRequest,
    db: Session = _DB_DEPENDENCY,
) -> AuthResponse:
    settings = get_settings()
    ensure_fixed_accounts(db, settings)

    user = db.scalar(
        select(User).where(User.username == payload.username.strip().lower())
    )
    if (
        user is None
        or not user.is_active
        or not verify_secret(payload.password, user.password_hash)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password",
        )

    refresh_token = create_refresh_token()
    device = db.get(Device, payload.device_id)
    now = datetime.now(UTC)
    if device is None:
        db.add(
            Device(
                id=payload.device_id,
                user_id=user.id,
                device_name=payload.device_name,
                platform=payload.platform,
                refresh_token_hash=hash_token(refresh_token),
                refresh_token_expires_at=refresh_token_expires_at(),
                last_seen_at=now,
            )
        )
    else:
        if device.user_id != user.id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Device is already registered to another account",
            )
        device.user_id = user.id
        device.device_name = payload.device_name
        device.platform = payload.platform
        device.refresh_token_hash = hash_token(refresh_token)
        device.refresh_token_expires_at = refresh_token_expires_at()
        device.last_seen_at = now

    db.commit()
    return AuthResponse(
        access_token=create_access_token(user_id=user.id, device_id=payload.device_id),
        refresh_token=refresh_token,
        user_id=user.id,
        device_id=payload.device_id,
    )


@router.post("/refresh", response_model=AuthResponse)
def refresh(
    payload: RefreshRequest,
    db: Session = _DB_DEPENDENCY,
) -> AuthResponse:
    device = db.get(Device, payload.device_id)
    now = datetime.now(UTC)
    if (
        device is None
        or device.refresh_token_expires_at <= now
        or not verify_token(
            payload.refresh_token,
            device.refresh_token_hash,
        )
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )

    user = db.get(User, device.user_id)
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )

    refresh_token = payload.refresh_token
    device.refresh_token_expires_at = refresh_token_expires_at()
    device.last_seen_at = now
    db.commit()

    return AuthResponse(
        access_token=create_access_token(user_id=user.id, device_id=device.id),
        refresh_token=refresh_token,
        user_id=user.id,
        device_id=device.id,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    current_user: CurrentUser = _CURRENT_USER_DEPENDENCY,
    db: Session = _DB_DEPENDENCY,
) -> None:
    if current_user.device_id is None:
        return
    device = db.get(Device, current_user.device_id)
    if device is not None:
        device.refresh_token_hash = hash_token(create_refresh_token())
        device.refresh_token_expires_at = datetime.now(UTC)
        device.last_seen_at = datetime.now(UTC)
        db.commit()
