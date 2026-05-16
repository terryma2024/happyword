"""Unit tests for OAuth preview handoff tickets."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from app.models.user import User, UserRole
from app.services.oauth_handoff_service import (
    OAuthHandoffError,
    consume_handoff_ticket,
    create_handoff_ticket,
)


@pytest.mark.asyncio
async def test_handoff_ticket_single_use(db: object) -> None:
    now = datetime.now(tz=UTC)
    await User(
        username="parent-handoff",
        password_hash=None,
        role=UserRole.PARENT,
        created_at=now,
        family_id="fam-handoff",
        email="handoff@example.com",
    ).insert()

    ticket_id = await create_handoff_ticket(
        user_id="parent-handoff",
        return_origin="https://preview-branch.vercel.app",
    )
    user = await consume_handoff_ticket(
        ticket_id=ticket_id,
        request_origin="https://preview-branch.vercel.app",
    )
    assert user.username == "parent-handoff"

    with pytest.raises(OAuthHandoffError):
        await consume_handoff_ticket(
            ticket_id=ticket_id,
            request_origin="https://preview-branch.vercel.app",
        )


@pytest.mark.asyncio
async def test_handoff_ticket_origin_mismatch(db: object) -> None:
    now = datetime.now(tz=UTC)
    await User(
        username="parent-handoff-2",
        password_hash=None,
        role=UserRole.PARENT,
        created_at=now,
        family_id="fam-handoff-2",
        email="handoff2@example.com",
    ).insert()
    ticket_id = await create_handoff_ticket(
        user_id="parent-handoff-2",
        return_origin="https://preview-a.vercel.app",
    )
    with pytest.raises(OAuthHandoffError):
        await consume_handoff_ticket(
            ticket_id=ticket_id,
            request_origin="https://preview-b.vercel.app",
        )
