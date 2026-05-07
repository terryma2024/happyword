import hashlib
import os
import re
from functools import lru_cache
from typing import Literal

from pydantic import AliasChoices, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# MongoDB Atlas rejects database names longer than 38 bytes (it surfaces this
# at runtime as `AtlasError 8000: Database name … is too long. Max database
# name length is 38 bytes.`, which crashes the FastAPI lifespan hook on the
# very first Beanie call). Stay under the cap; pre-Atlas Mongo's own 64-byte
# limit is looser, so this is the binding constraint in production.
_ATLAS_MAX_DB_NAME_BYTES = 38


def _slug_branch(branch: str) -> str:
    """Lowercase, collapse non-alphanumerics to `_`, trim outer `_`."""
    return re.sub(r"[^a-z0-9]+", "_", branch.lower()).strip("_")


def _resolve_db_name(template: str, *, pr: str, branch: str) -> str:
    """Substitute Vercel-injected `{pr}` / `{branch}` placeholders in a Mongo DB name.

    Behaviour:
    - Literal templates (no placeholder) pass through unchanged.
    - `{pr}` substitutes `pr` when non-empty, else `branch_<slug>`.
    - `{branch}` always substitutes the slugged branch name.
    - When the assembled name would exceed Atlas's 38-byte cap (e.g. a preview
      deploy off a long branch with no open PR yet, like
      `cursor/bump-actions-to-node24` resolving to
      `happyword_pr_branch_cursor_bump_actions_to_node24_e2e` = 53 bytes), we
      degrade to a deterministic `br_<sha1[:8]>` slug instead of crashing on
      startup. Same branch ⇒ same hash ⇒ same DB across redeploys, so no
      per-restart database churn.
    """
    safe_branch = _slug_branch(branch)
    pr_value = pr or f"branch_{safe_branch}"
    full = template.format(pr=pr_value, branch=safe_branch)
    if len(full) <= _ATLAS_MAX_DB_NAME_BYTES:
        return full

    # The readable form would be rejected by Atlas. Hash the *raw* branch (not
    # the slug) so two branches that slug to the same value still get distinct
    # DBs. SHA-1 is fine here — we only need collision resistance, not crypto.
    branch_hash = hashlib.sha1(branch.encode("utf-8")).hexdigest()[:8]
    short_pr = pr or f"br_{branch_hash}"
    return template.format(pr=short_pr, branch=branch_hash)


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

    @field_validator("mongo_db_name", mode="after")
    @classmethod
    def _expand_db_name(cls, raw: str) -> str:
        return _resolve_db_name(
            raw,
            pr=os.environ.get("VERCEL_GIT_PULL_REQUEST_ID", ""),
            branch=os.environ.get("VERCEL_GIT_COMMIT_REF", "local"),
        )

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

    # V0.6.3 — family word packs
    family_pack_max_words: int = 50

    # V0.6.7 — notifications + account deletion
    notification_email_enabled: bool = True
    account_deletion_grace_days: int = 7


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
