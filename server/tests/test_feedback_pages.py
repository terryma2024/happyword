"""HTML feedback flow for parent users and system administrators."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.feedback import UserFeedback
from app.models.user import User, UserRole
from app.services.auth_service import create_session_token, hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient

_ADMIN_PASSWORD = "feedback-admin-pw-99"


@pytest.fixture
async def feedback_parent(client: AsyncClient) -> AsyncIterator[User]:
    user = User(
        username="feedback-parent",
        role=UserRole.PARENT,
        created_at=datetime.now(tz=UTC),
        family_id="fam-feedback-1",
        email="feedback-parent@example.com",
        display_name="Feedback Parent",
    )
    await user.insert()
    token = create_session_token(role="parent", identifier=user.username)
    client.cookies.set("wm_session", token)
    yield user
    client.cookies.clear()


@pytest.fixture
async def feedback_admin(client: AsyncClient) -> AsyncIterator[User]:
    user = User(
        username="feedback-admin",
        password_hash=hash_password(_ADMIN_PASSWORD),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await user.insert()
    token = create_session_token(role="admin", identifier=user.username)
    client.cookies.set("wm_admin_session", token)
    yield user
    client.cookies.clear()


@pytest.mark.asyncio
async def test_parent_submits_and_sees_only_own_feedback(
    client: AsyncClient,
    feedback_parent: User,
) -> None:
    other = UserFeedback(
        feedback_id="fb-other",
        parent_user_id="other-parent",
        family_id="fam-other",
        parent_email="other@example.com",
        subject="Other parent feedback",
        body="Should not be visible to this parent.",
        created_at=datetime.now(tz=UTC),
    )
    await other.insert()

    page = await client.get("/parent/feedback")
    assert page.status_code == 200
    assert "用户反馈" in page.text
    assert "Other parent feedback" not in page.text

    res = await client.post(
        "/parent/feedback",
        data={
            "subject": "希望支持错题本",
            "body": "孩子想复习最近答错的单词。",
        },
        follow_redirects=False,
    )
    assert res.status_code == 303
    assert res.headers["location"] == "/parent/feedback?flash_ok=created"

    saved = await UserFeedback.find_one(UserFeedback.parent_user_id == feedback_parent.username)
    assert saved is not None
    assert saved.subject == "希望支持错题本"

    updated = await client.get("/parent/feedback")
    assert updated.status_code == 200
    assert "希望支持错题本" in updated.text
    assert "孩子想复习最近答错的单词。" in updated.text
    assert "Other parent feedback" not in updated.text


@pytest.mark.asyncio
async def test_admin_can_view_reply_and_delete_feedback(
    client: AsyncClient,
    feedback_admin: User,
) -> None:
    row = UserFeedback(
        feedback_id="fb-admin-flow",
        parent_user_id="feedback-parent",
        family_id="fam-feedback-1",
        parent_email="feedback-parent@example.com",
        subject="页面太暗",
        body="希望家长后台颜色更亮一点。",
        created_at=datetime.now(tz=UTC),
    )
    await row.insert()

    page = await client.get("/admin/feedback")
    assert page.status_code == 200
    assert "用户反馈" in page.text
    assert "页面太暗" in page.text
    assert "feedback-parent@example.com" in page.text

    reply = await client.post(
        "/admin/feedback/fb-admin-flow/reply",
        data={"reply": "收到，我们会在下个版本优化。"},
        follow_redirects=False,
    )
    assert reply.status_code == 303
    assert reply.headers["location"] == "/admin/feedback?flash_ok=replied"

    refreshed = await UserFeedback.find_one(UserFeedback.feedback_id == "fb-admin-flow")
    assert refreshed is not None
    assert refreshed.admin_reply == "收到，我们会在下个版本优化。"
    assert refreshed.replied_by == feedback_admin.username
    assert refreshed.replied_at is not None

    page_after_reply = await client.get("/admin/feedback")
    assert "收到，我们会在下个版本优化。" in page_after_reply.text

    deleted = await client.post(
        "/admin/feedback/fb-admin-flow/delete",
        follow_redirects=False,
    )
    assert deleted.status_code == 303
    assert deleted.headers["location"] == "/admin/feedback?flash_ok=deleted"
    assert await UserFeedback.find_one(UserFeedback.feedback_id == "fb-admin-flow") is None
