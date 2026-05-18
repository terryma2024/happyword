from __future__ import annotations

from datetime import UTC, datetime

from beanie import Document
from pydantic import Field


class SystemConfig(Document):
    key: str
    value: str
    updated_at: datetime = Field(default_factory=lambda: datetime.now(tz=UTC))
    updated_by: str | None = None

    class Settings:
        name = "system_config"
