from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class UserRole(StrEnum):
    ADMIN = "admin"
    PARENT = "parent"


class User(Document):
    username: Annotated[str, Indexed(unique=True)]
    # V0.6.1: parent users are created from email OTP and have no password.
    password_hash: str | None = None
    role: UserRole = UserRole.ADMIN
    created_at: datetime
    last_login_at: datetime | None = None

    # V0.6.1 parent fields. Admin rows leave these unset.
    family_id: Annotated[str | None, Indexed()] = None
    email: Annotated[str | None, Indexed()] = None
    display_name: str | None = None
    timezone: str = "Asia/Shanghai"
    # V0.6.7 — set by /api/v1/parent/account/delete; cleared on cancel.
    scheduled_deletion_at: datetime | None = None

    class Settings:
        name = "users"
