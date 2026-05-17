"""Pending OAuth identity tickets for providers that do not return email."""

from __future__ import annotations

import secrets
from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

from app.config import Settings, get_settings
from app.models.oauth_pending_identity import OAuthPendingIdentity

if TYPE_CHECKING:
    from app.models.oauth_identity import OAuthProvider


class OAuthPendingIdentityError(Exception):
    """Pending OAuth ticket is missing, expired, consumed, or host-bound elsewhere."""


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


def _to_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


async def create_pending_identity(
    *,
    provider: OAuthProvider,
    provider_subject: str,
    return_origin: str,
    settings: Settings | None = None,
) -> str:
    settings = settings or get_settings()
    now = _utcnow()
    ticket = secrets.token_urlsafe(32)
    row = OAuthPendingIdentity(
        ticket_id=ticket,
        provider=provider,
        provider_subject=provider_subject,
        return_origin=return_origin,
        created_at=now,
        expires_at=now + timedelta(seconds=settings.oauth_pending_bind_ttl_seconds),
    )
    await row.insert()
    return ticket


async def load_pending_identity(
    *,
    ticket_id: str,
    request_origin: str | None = None,
) -> OAuthPendingIdentity:
    row = await OAuthPendingIdentity.find_one(OAuthPendingIdentity.ticket_id == ticket_id)
    if row is None or row.consumed_at is not None:
        raise OAuthPendingIdentityError()
    if _utcnow() >= _to_utc(row.expires_at):
        raise OAuthPendingIdentityError()
    if request_origin is not None and row.return_origin != request_origin:
        raise OAuthPendingIdentityError()
    return row


async def consume_pending_identity(ticket_id: str) -> OAuthPendingIdentity:
    row = await load_pending_identity(ticket_id=ticket_id)
    row.consumed_at = _utcnow()
    await row.save()
    return row
