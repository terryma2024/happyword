"""User feedback submitted from the parent web shell."""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class UserFeedback(Document):
    feedback_id: Annotated[str, Indexed(unique=True)]
    parent_user_id: Annotated[str, Indexed()]
    family_id: Annotated[str, Indexed()]
    parent_email: str | None = None
    subject: str
    body: str
    created_at: datetime
    admin_reply: str | None = None
    replied_by: str | None = None
    replied_at: datetime | None = None

    class Settings:
        name = "user_feedback"
        indexes = [
            [("parent_user_id", 1), ("created_at", -1)],
            [("created_at", -1)],
        ]
