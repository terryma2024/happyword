"""Service helpers for parent-submitted feedback."""

from __future__ import annotations

import secrets
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from app.models.feedback import UserFeedback

if TYPE_CHECKING:
    from app.models.user import User

SUBJECT_MAX_LEN = 120
BODY_MAX_LEN = 4000


def _feedback_id() -> str:
    return f"fb-{secrets.token_hex(8)}"


def _clean_required(value: str, *, field: str, max_len: int) -> str:
    cleaned = value.strip()
    if not cleaned:
        raise ValueError(f"{field} is required.")
    if len(cleaned) > max_len:
        raise ValueError(f"{field} is too long.")
    return cleaned


async def create_feedback(*, user: User, subject: str, body: str) -> UserFeedback:
    row = UserFeedback(
        feedback_id=_feedback_id(),
        parent_user_id=user.username,
        family_id=user.family_id or "",
        parent_email=user.email,
        subject=_clean_required(subject, field="subject", max_len=SUBJECT_MAX_LEN),
        body=_clean_required(body, field="body", max_len=BODY_MAX_LEN),
        created_at=datetime.now(tz=UTC),
    )
    await row.insert()
    return row


async def list_feedback_for_parent(*, parent_user_id: str) -> list[UserFeedback]:
    rows = await UserFeedback.find(UserFeedback.parent_user_id == parent_user_id).to_list()
    rows.sort(key=lambda r: r.created_at, reverse=True)
    return rows


async def list_feedback_for_admin() -> list[UserFeedback]:
    rows = await UserFeedback.find_all().to_list()
    rows.sort(key=lambda r: r.created_at, reverse=True)
    return rows


async def reply_to_feedback(
    *, feedback_id: str, admin_username: str, reply: str
) -> UserFeedback | None:
    row = await UserFeedback.find_one(UserFeedback.feedback_id == feedback_id)
    if row is None:
        return None
    row.admin_reply = _clean_required(reply, field="reply", max_len=BODY_MAX_LEN)
    row.replied_by = admin_username
    row.replied_at = datetime.now(tz=UTC)
    await row.save()
    return row


async def delete_feedback(*, feedback_id: str) -> bool:
    row = await UserFeedback.find_one(UserFeedback.feedback_id == feedback_id)
    if row is None:
        return False
    await row.delete()
    return True
