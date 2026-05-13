"""Preview-only client/server debug capture sessions."""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class DebugSession(Document):
    session_id: Annotated[str, Indexed(unique=True)]
    problem: str
    preview_url: str
    branch: str | None = None
    deployment_id: str | None = None
    created_by: str
    created_at: datetime
    expires_at: Annotated[datetime, Indexed()]
    active: bool = True
    stopped_at: datetime | None = None

    class Settings:
        name = "debug_sessions"
        indexes = [[("active", 1), ("expires_at", 1)], [("branch", 1), ("created_at", -1)]]
