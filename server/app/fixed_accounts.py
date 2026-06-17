from dataclasses import dataclass
from uuid import UUID

from fastapi import HTTPException, status
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import Settings
from .models import User, Workspace, WorkspaceMember

DEFAULT_CURRENT_USER_ID = UUID("00000000-0000-4000-8000-000000000001")
PARTNER_USER_ID = UUID("00000000-0000-4000-8000-000000000002")
DEFAULT_SHARED_WORKSPACE_ID = UUID("00000000-0000-4000-8000-000000000100")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


@dataclass(frozen=True)
class FixedAccount:
    user_id: UUID
    username: str
    display_name: str
    password: str | None


def fixed_accounts(settings: Settings) -> tuple[FixedAccount, FixedAccount]:
    return (
        FixedAccount(
            user_id=DEFAULT_CURRENT_USER_ID,
            username="user",
            display_name="User",
            password=settings.user_password,
        ),
        FixedAccount(
            user_id=PARTNER_USER_ID,
            username="partner",
            display_name="Partner",
            password=settings.partner_password,
        ),
    )


def hash_secret(secret: str) -> str:
    return pwd_context.hash(secret)


def verify_secret(secret: str, hashed_secret: str) -> bool:
    return pwd_context.verify(secret, hashed_secret)


def ensure_fixed_accounts(db: Session, settings: Settings) -> None:
    accounts = fixed_accounts(settings)
    if any(account.password is None or account.password == "" for account in accounts):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Fixed account passwords are not configured",
        )

    workspace = db.get(Workspace, DEFAULT_SHARED_WORKSPACE_ID)
    if workspace is None:
        db.add(Workspace(id=DEFAULT_SHARED_WORKSPACE_ID, name="Shared workspace"))

    for account in accounts:
        user = db.get(User, account.user_id)
        if user is None:
            db.add(
                User(
                    id=account.user_id,
                    username=account.username,
                    password_hash=hash_secret(account.password or ""),
                    display_name=account.display_name,
                    is_active=True,
                )
            )
        else:
            user.username = account.username
            user.display_name = account.display_name
            user.is_active = True
            if not verify_secret(account.password or "", user.password_hash):
                user.password_hash = hash_secret(account.password or "")

        membership = db.scalar(
            select(WorkspaceMember).where(
                WorkspaceMember.workspace_id == DEFAULT_SHARED_WORKSPACE_ID,
                WorkspaceMember.user_id == account.user_id,
            )
        )
        if membership is None:
            db.add(
                WorkspaceMember(
                    workspace_id=DEFAULT_SHARED_WORKSPACE_ID,
                    user_id=account.user_id,
                )
            )

    db.flush()
