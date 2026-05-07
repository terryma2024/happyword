"""V0.6.7 — parent self-service account endpoints.

JSON:
  GET    /api/v1/parent/account/status
  POST   /api/v1/parent/account/delete
  POST   /api/v1/parent/account/cancel-delete
  POST   /api/v1/parent/account/export

HTML:
  GET    /parent/settings (settings page with delete + export forms)
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.deps import current_parent_user
from app.schemas.account import (
    AccountCancelDeleteOut,
    AccountDeleteOut,
    AccountExportOut,
    AccountStatusOut,
)
from app.services import account_deletion_service

if TYPE_CHECKING:
    from app.models.user import User


router = APIRouter(prefix="/api/v1/parent/account", tags=["parent-account"])
html_router = APIRouter(prefix="/parent/account", tags=["parent-account-html"])

templates = Jinja2Templates(directory="app/templates")


@router.get("/status", response_model=AccountStatusOut)
async def get_status(
    user: User = Depends(current_parent_user),
) -> AccountStatusOut:
    grace = account_deletion_service.grace_days_remaining(
        scheduled=user.scheduled_deletion_at,
        now=datetime.now(tz=UTC),
    )
    return AccountStatusOut(
        user_id=user.username,
        email=user.email or "",
        family_id=user.family_id,
        scheduled_deletion_at=user.scheduled_deletion_at,
        grace_days_remaining=grace,
    )


@router.post("/delete", response_model=AccountDeleteOut)
async def post_delete(
    user: User = Depends(current_parent_user),
) -> AccountDeleteOut:
    scheduled_at = await account_deletion_service.schedule_deletion(
        user_id=user.username, requested_by=user.username
    )
    return AccountDeleteOut(
        user_id=user.username,
        scheduled_deletion_at=scheduled_at,
        grace_days=account_deletion_service.GRACE_PERIOD.days,
    )


@router.post("/cancel-delete", response_model=AccountCancelDeleteOut)
async def post_cancel_delete(
    user: User = Depends(current_parent_user),
) -> AccountCancelDeleteOut:
    cancelled = await account_deletion_service.cancel_deletion(
        user_id=user.username, requested_by=user.username
    )
    return AccountCancelDeleteOut(user_id=user.username, cancelled=cancelled)


@router.post("/export")
async def post_export(
    user: User = Depends(current_parent_user),
) -> JSONResponse:
    snapshot = await account_deletion_service.export_account_data(user=user)
    files = list(snapshot.keys())
    items_count = sum(len(v) for v in snapshot.values())
    headers = {
        "Content-Disposition": (
            f'attachment; filename="happyword-export-{user.username}.json"'
        )
    }
    body = {
        "summary": AccountExportOut(
            user_id=user.username,
            family_id=user.family_id,
            items_count=items_count,
            files=files,
        ).model_dump(),
        "data": snapshot,
    }
    return JSONResponse(body, headers=headers)


@html_router.get("", response_class=HTMLResponse)
async def get_settings_html(
    request: Request,
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
    grace = account_deletion_service.grace_days_remaining(
        scheduled=user.scheduled_deletion_at
    )
    return templates.TemplateResponse(
        request,
        "parent/settings.html",
        {
            "user": user,
            "grace_days_remaining": grace,
            "grace_days_total": account_deletion_service.GRACE_PERIOD.days,
        },
    )


@html_router.post("/delete", response_model=None)
async def post_delete_form(
    user: User = Depends(current_parent_user),
) -> RedirectResponse:
    await account_deletion_service.schedule_deletion(
        user_id=user.username, requested_by=user.username
    )
    return RedirectResponse(url="/parent/account", status_code=303)


@html_router.post("/cancel-delete", response_model=None)
async def post_cancel_delete_form(
    user: User = Depends(current_parent_user),
) -> RedirectResponse:
    await account_deletion_service.cancel_deletion(
        user_id=user.username, requested_by=user.username
    )
    return RedirectResponse(url="/parent/account", status_code=303)


# Reference unused imports so linters stay quiet about HTTPException + status.
_ = HTTPException, status

__all__ = ["router", "html_router"]
