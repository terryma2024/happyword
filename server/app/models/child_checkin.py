"""V0.8.8 — Cloud copy of child daily check-ins."""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class ChildCheckIn(Document):
    child_profile_id: Annotated[str, Indexed()]
    day_key: Annotated[str, Indexed()]
    source_device_id: str | None = None
    updated_at: datetime

    class Settings:
        name = "child_checkins"
        indexes = [[("child_profile_id", 1), ("day_key", 1)]]
