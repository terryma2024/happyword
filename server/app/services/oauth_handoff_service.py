"""One-time tickets to set parent session on preview/local origins."""

from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta

from app.config import get_settings
from app.models.oauth_handoff_ticket import OAuthHandoffTicket
from app.models.user import User
from app.services.oauth_return_origin_service import normalize_origin


class OAuthHandoffError(Exception):
    """Ticket missing, expired, consumed, or origin mismatch."""


async def create_handoff_ticket(*, user_id: str, return_origin: str) -> str:
    settings = get_settings()
    ticket_id = secrets.token_urlsafe(32)
    row = OAuthHandoffTicket(
        ticket_id=ticket_id,
        user_id=user_id,
        return_origin=normalize_origin(return_origin),
        expires_at=datetime.now(tz=UTC)
        + timedelta(seconds=settings.oauth_handoff_ttl_seconds),
        consumed_at=None,
    )
    await row.insert()
    return ticket_id


def _as_utc_aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


async def consume_handoff_ticket(*, ticket_id: str, request_origin: str) -> User:
    normalized_request = normalize_origin(request_origin)
    row = await OAuthHandoffTicket.find_one(OAuthHandoffTicket.ticket_id == ticket_id)
    if row is None:
        raise OAuthHandoffError("ticket not found")
    if row.consumed_at is not None:
        raise OAuthHandoffError("ticket already used")
    if _as_utc_aware(row.expires_at) < datetime.now(tz=UTC):
        raise OAuthHandoffError("ticket expired")
    if row.return_origin != normalized_request:
        raise OAuthHandoffError("ticket origin mismatch")

    user = await User.find_one(User.username == row.user_id)
    if user is None:
        raise OAuthHandoffError("user not found")

    row.consumed_at = datetime.now(tz=UTC)
    await row.save()
    return user
