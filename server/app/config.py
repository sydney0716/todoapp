from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = (
        "postgresql+psycopg://personaltodo:change-me@localhost:5432/personaltodo"
    )
    jwt_secret: str
    access_token_minutes: int = 15
    refresh_token_days: int = 60
    user1_password: str | None = None
    user2_password: str | None = None
    auto_migrate: bool = False

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @field_validator("jwt_secret")
    @classmethod
    def reject_placeholder_secret(cls, value: str) -> str:
        if not value.strip() or value.strip().lower().startswith("change-me"):
            raise ValueError(
                "JWT_SECRET must be configured with a private signing secret"
            )
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
