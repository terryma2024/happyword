"""V0.6.7 — parent inbox HTTP routes."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.parent_inbox_msg import ParentInboxKind, ParentInboxMsg

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def parent_client(
    db: object,
) -> AsyncIterator[tuple[AsyncClient, str]]:
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", follow_redirects=False
    ) as ac:
        await ac.post(
            "/api/v1/parent/auth/request-code", json={"email": "ix@example.com"}
        )
        code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]
        await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "ix@example.com", "code": code},
        )
        # Look up the parent username from /me-shaped endpoint isn't available,
        # so we fetch from the User collection directly.
        from app.models.user import User, UserRole

        user = await User.find_one(
            User.email == "ix@example.com", User.role == UserRole.PARENT
        )
        assert user is not None
        yield ac, user.username

    app.dependency_overrides.pop(get_email_provider, None)


async def _seed_msg(
    parent_user_id: str, *, read: bool = False, title: str = "标题"
) -> ParentInboxMsg:
    msg = ParentInboxMsg(
        msg_id=f"msg-{title[-4:].rjust(4, '0')}",
        family_id="fam-aaa11111",
        parent_user_id=parent_user_id,
        kind=ParentInboxKind.SYSTEM,
        title=title,
        body_md="**hello**",
        related_resource=None,
        created_at=datetime.now(tz=UTC),
        read_at=datetime.now(tz=UTC) if read else None,
    )
    await msg.insert()
    return msg


@pytest.mark.asyncio
async def test_list_inbox_returns_unread_count(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, username = parent_client
    await _seed_msg(username, title="未读 1")
    await _seed_msg(username, title="未读 2")
    await _seed_msg(username, title="已读 1", read=True)
    r = await ac.get("/api/v1/parent/inbox")
    assert r.status_code == 200
    body = r.json()
    assert body["unread_count"] == 2
    assert len(body["items"]) == 3


@pytest.mark.asyncio
async def test_unread_only_filter(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, username = parent_client
    await _seed_msg(username, title="未读 1")
    await _seed_msg(username, title="已读 1", read=True)
    r = await ac.get("/api/v1/parent/inbox", params={"unread_only": "true"})
    body = r.json()
    assert len(body["items"]) == 1
    assert body["items"][0]["title"] == "未读 1"


@pytest.mark.asyncio
async def test_mark_read_idempotent(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, username = parent_client
    msg = await _seed_msg(username, title="x")
    r1 = await ac.post(f"/api/v1/parent/inbox/{msg.msg_id}/read")
    r2 = await ac.post(f"/api/v1/parent/inbox/{msg.msg_id}/read")
    assert r1.status_code == 200
    assert r2.status_code == 200
    saved = await ParentInboxMsg.find_one(ParentInboxMsg.msg_id == msg.msg_id)
    assert saved is not None
    assert saved.read_at is not None


@pytest.mark.asyncio
async def test_mark_all_read(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, username = parent_client
    await _seed_msg(username, title="未读 1")
    await _seed_msg(username, title="未读 2")
    r = await ac.post("/api/v1/parent/inbox/mark-all-read")
    assert r.json()["updated"] == 2
    rows = await ParentInboxMsg.find(
        ParentInboxMsg.parent_user_id == username
    ).to_list()
    assert all(r.read_at is not None for r in rows)


@pytest.mark.asyncio
async def test_other_parent_inbox_invisible(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _username = parent_client
    await _seed_msg("other-user", title="不该出现")
    r = await ac.get("/api/v1/parent/inbox")
    assert r.status_code == 200
    titles = [it["title"] for it in r.json()["items"]]
    assert "不该出现" not in titles


@pytest.mark.asyncio
async def test_html_inbox_renders_list(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, username = parent_client
    await _seed_msg(username, title="hello world")
    r = await ac.get("/parent/inbox")
    assert r.status_code == 200
    assert 'id="inbox-list"' in r.text
    assert "hello world" in r.text
