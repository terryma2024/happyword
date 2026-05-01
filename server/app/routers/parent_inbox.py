"""V0.6.7 — parent inbox (read/list/mark-read) JSON + HTML routes."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, Path, Query, Request, status
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.deps import current_parent_user
from app.models.parent_inbox_msg import ParentInboxMsg
from app.schemas.inbox import InboxListOut, InboxMsgOut

if TYPE_CHECKING:
    from app.models.user import User


router = APIRouter(prefix="/api/v1/parent/inbox", tags=["parent-inbox"])
html_router = APIRouter(prefix="/parent", tags=["parent-inbox-html"])

templates = Jinja2Templates(directory="app/templates")


def _to_out(m: ParentInboxMsg) -> InboxMsgOut:
    return InboxMsgOut(
        msg_id=m.msg_id,
        family_id=m.family_id,
        parent_user_id=m.parent_user_id,
        kind=str(m.kind),
        title=m.title,
        body_md=m.body_md,
        related_resource=m.related_resource,
        created_at=m.created_at,
        read_at=m.read_at,
    )


@router.get("", response_model=InboxListOut)
async def list_inbox(
    unread_only: bool = Query(default=False),
    user: User = Depends(current_parent_user),
) -> InboxListOut:
    rows = await ParentInboxMsg.find(
        ParentInboxMsg.parent_user_id == user.username
    ).to_list()
    rows.sort(key=lambda m: m.created_at, reverse=True)
    if unread_only:
        rows = [r for r in rows if r.read_at is None]
    unread = sum(1 for r in rows if r.read_at is None)
    return InboxListOut(items=[_to_out(r) for r in rows], unread_count=unread)


@router.post("/{msg_id}/read", status_code=status.HTTP_200_OK)
async def mark_read(
    msg_id: str = Path(min_length=4, max_length=64),
    user: User = Depends(current_parent_user),
) -> dict[str, str]:
    msg = await ParentInboxMsg.find_one(
        ParentInboxMsg.msg_id == msg_id,
        ParentInboxMsg.parent_user_id == user.username,
    )
    if msg is None:
        return {"status": "not_found"}
    if msg.read_at is None:
        msg.read_at = datetime.now(tz=UTC)
        await msg.save()
    return {"status": "ok"}


@router.post("/mark-all-read", status_code=status.HTTP_200_OK)
async def mark_all_read(
    user: User = Depends(current_parent_user),
) -> dict[str, int]:
    rows = await ParentInboxMsg.find(
        ParentInboxMsg.parent_user_id == user.username,
        ParentInboxMsg.read_at == None,  # noqa: E711
    ).to_list()
    now = datetime.now(tz=UTC)
    for r in rows:
        r.read_at = now
        await r.save()
    return {"updated": len(rows)}


@html_router.get("/inbox", response_class=HTMLResponse)
async def get_inbox_html(
    request: Request,
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
    rows = await ParentInboxMsg.find(
        ParentInboxMsg.parent_user_id == user.username
    ).to_list()
    rows.sort(key=lambda m: m.created_at, reverse=True)
    unread = sum(1 for r in rows if r.read_at is None)
    return templates.TemplateResponse(
        request,
        "parent/inbox.html",
        {"user": user, "messages": rows, "unread_count": unread},
    )


__all__ = ["router", "html_router"]
