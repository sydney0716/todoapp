from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = (
        "postgresql+psycopg://personaltodo:change-me@localhost:5432/personaltodo"
    )
    jwt_secret: str = "change-me"
    access_token_minutes: int = 15
    refresh_token_days: int = 60
    user_password: str | None = None
    partner_password: str | None = None
    auto_migrate: bool = False

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
