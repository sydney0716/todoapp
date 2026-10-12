from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from ..database import get_db
from ..schemas import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok")


_DB = Depends(get_db)


@router.get("/ready", response_model=HealthResponse)
def ready(db: Session = _DB) -> HealthResponse:
    try:
        initialized = db.scalar(
            text(
                "SELECT to_regclass('tasks') IS NOT NULL "
                "AND to_regclass('devices') IS NOT NULL "
                "AND to_regclass('sync_events') IS NOT NULL "
                "AND to_regclass('purged_tasks') IS NOT NULL"
            )
        )
    except SQLAlchemyError as error:
        raise HTTPException(503, "Database unavailable") from error
    if not initialized:
        raise HTTPException(503, "Database migrations required")
    return HealthResponse(status="ok")
