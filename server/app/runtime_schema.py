from pathlib import Path

from sqlalchemy import text

from .config import get_settings
from .database import get_sessionmaker


def apply_migrations(db) -> None:
    """Run the same versioned SQL used by manual deployments, transactionally."""
    db.execute(text("SELECT pg_advisory_xact_lock(741802342)"))
    db.execute(
        text(
            "CREATE TABLE IF NOT EXISTS schema_migrations "
            "(name TEXT PRIMARY KEY, "
            "applied_at TIMESTAMPTZ NOT NULL DEFAULT now())"
        )
    )
    migrations = Path(__file__).resolve().parents[1] / "migrations"
    for migration in sorted(migrations.glob("*.sql")):
        if db.scalar(
            text("SELECT name FROM schema_migrations WHERE name = :name"),
            {"name": migration.name},
        ):
            continue
        db.execute(text(migration.read_text()))
        db.execute(
            text("INSERT INTO schema_migrations (name) VALUES (:name)"),
            {"name": migration.name},
        )
    db.commit()


def apply_runtime_migrations() -> None:
    if get_settings().auto_migrate:
        with get_sessionmaker()() as db:
            apply_migrations(db)


if __name__ == "__main__":
    with get_sessionmaker()() as db:
        apply_migrations(db)
