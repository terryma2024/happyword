from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed

from app.models.oauth_identity import OAuthProvider


class OAuthPendingIdentity(Document):
    ticket_id: Annotated[str, Indexed(unique=True)]
    provider: OAuthProvider
    provider_subject: str
    return_origin: str
    created_at: datetime
    expires_at: datetime
    consumed_at: datetime | None = None

    class Settings:
        name = "oauth_pending_identities"
        indexes = [
            [("ticket_id", 1)],
            [("provider", 1), ("provider_subject", 1)],
            [("expires_at", 1)],
        ]
