from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class OAuthHandoffTicket(Document):
    ticket_id: Annotated[str, Indexed(unique=True)]
    user_id: str
    return_origin: str
    expires_at: datetime
    consumed_at: datetime | None = None

    class Settings:
        name = "oauth_handoff_tickets"
