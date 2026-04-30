from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class UserRole(StrEnum):
    ADMIN = "admin"
    PARENT = "parent"


class User(Document):
    username: Annotated[str, Indexed(unique=True)]
    password_hash: str
    role: UserRole = UserRole.ADMIN
    created_at: datetime
    last_login_at: datetime | None = None

    class Settings:
        name = "users"
