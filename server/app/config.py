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

    # V0.6.1 — parent web shell
    parent_web_base_url: str = "http://localhost:3000"
    session_cookie_domain: str = ""
    session_cookie_name: str = "wm_session"
    parent_session_expire_hours: int = 24 * 30  # 30 days hard cap
    parent_session_renew_after_days: int = 7  # renew when iat older than this

    # V0.6.1 — OTP
    otp_expiry_minutes: int = 10
    otp_max_attempts: int = 5
    otp_request_min_interval_seconds: int = 60

    # V0.6.1 — email backend (Gmail SMTP default; EmailProvider abstraction)
    email_provider: Literal["gmail_smtp", "resend", "ses"] = "gmail_smtp"
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from_email: str = ""
    smtp_from_name: str = "快乐背单词"
    smtp_starttls: bool = True
    smtp_timeout_seconds: float = 10.0


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
