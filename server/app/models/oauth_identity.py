from datetime import datetime
from enum import StrEnum
from typing import Annotated

from beanie import Document, Indexed


class OAuthProvider(StrEnum):
    GOOGLE = "google"
    APPLE = "apple"
    WECHAT = "wechat"
    ALIPAY = "alipay"


class OAuthIdentity(Document):
    provider: OAuthProvider
    provider_subject: str
    user_id: Annotated[str, Indexed()]
    email: str | None = None
    email_verified: bool = False
    linked_at: datetime

    class Settings:
        name = "oauth_identities"
        indexes = [
            [("provider", 1), ("provider_subject", 1)],
            [("user_id", 1)],
        ]
