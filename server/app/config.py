from functools import lru_cache
from typing import Literal

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env.local",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Vercel Marketplace MongoDB integrations auto-inject `MONGODB_URI`.
    # `MONGO_URI` is kept as an alias so existing .env.local files keep working.
    mongo_uri: str = Field(validation_alias=AliasChoices("MONGODB_URI", "MONGO_URI"))
    mongo_db_name: str
    jwt_secret: str
    jwt_expire_hours: int = 24
    admin_bootstrap_user: str
    admin_bootstrap_pass: str
    openai_api_key: str = ""
    openai_model_text: str = "gpt-4o-mini"
    openai_model_vision: str = "gpt-4o"
    cors_allow_origins: str = "*"
    log_level: Literal["debug", "info", "warning", "error"] = "info"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
