"""V0.6.7 — parent self-service account endpoints.

JSON:
  GET    /api/v1/family/{family_id}/account/status
  POST   /api/v1/family/{family_id}/account/delete
  POST   /api/v1/family/{family_id}/account/cancel-delete
  POST   /api/v1/family/{family_id}/account/export

HTML:
  GET    /family/{family_id}/account (settings page with delete + export forms)
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, Path, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.deps import current_parent_user
from app.models.user import User, UserRole
from app.schemas.account import (
    AccountCancelDeleteOut,
    AccountDeleteOut,
    AccountExportOut,
    AccountStatusOut,
)
from app.services import account_deletion_service
from app.services.auth_service import JwtError, decode_typed_token


router = APIRouter(prefix="/api/v1/family", tags=["parent-account"])
html_router = APIRouter(prefix="/family", tags=["parent-account-html"])

templates = Jinja2Templates(directory="app/templates")


def _account_home(user: User) -> str:
    fid = user.family_id or "_"
    return f"/family/{fid}/account"


async def _require_parent_html(request: Request) -> User | RedirectResponse:
    """Soft-auth for browser routes: missing/invalid parent cookie goes to login."""
    cookie_token = request.cookies.get(get_settings().session_cookie_name)
    if not cookie_token:
        return RedirectResponse(url="/family/login", status_code=303)
    try:
        typed = decode_typed_token(cookie_token)
    except JwtError:
        return RedirectResponse(url="/family/login", status_code=303)
    if typed.role != "parent":
        return RedirectResponse(url="/family/login", status_code=303)
    user = await User.find_one(
        User.username == typed.identifier, User.role == UserRole.PARENT
    )
    if user is None or user.parent_login_suspended_at is not None:
        return RedirectResponse(url="/family/login", status_code=303)
    return user


@router.get("/{family_id}/account/status", response_model=AccountStatusOut)
async def get_status(
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> AccountStatusOut:
    _ = family_id
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


@router.post("/{family_id}/account/delete", response_model=AccountDeleteOut)
async def post_delete(
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> AccountDeleteOut:
    _ = family_id
    scheduled_at = await account_deletion_service.schedule_deletion(
        user_id=user.username, requested_by=user.username
    )
    return AccountDeleteOut(
        user_id=user.username,
        scheduled_deletion_at=scheduled_at,
        grace_days=account_deletion_service.GRACE_PERIOD.days,
    )


@router.post("/{family_id}/account/cancel-delete", response_model=AccountCancelDeleteOut)
async def post_cancel_delete(
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> AccountCancelDeleteOut:
    _ = family_id
    cancelled = await account_deletion_service.cancel_deletion(
        user_id=user.username, requested_by=user.username
    )
    return AccountCancelDeleteOut(user_id=user.username, cancelled=cancelled)


@router.post("/{family_id}/account/export")
async def post_export(
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> JSONResponse:
    _ = family_id
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


@html_router.get(
    "/{family_id}/account", response_class=HTMLResponse, response_model=None
)
async def get_settings_html(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
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


@html_router.post("/{family_id}/account/delete", response_model=None)
async def post_delete_form(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    await account_deletion_service.schedule_deletion(
        user_id=user.username, requested_by=user.username
    )
    return RedirectResponse(url=_account_home(user), status_code=303)


@html_router.post("/{family_id}/account/cancel-delete", response_model=None)
async def post_cancel_delete_form(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    await account_deletion_service.cancel_deletion(
        user_id=user.username, requested_by=user.username
    )
    return RedirectResponse(url=_account_home(user), status_code=303)

__all__ = ["router", "html_router"]
