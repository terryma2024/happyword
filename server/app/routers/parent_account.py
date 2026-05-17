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

import contextlib
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, Form, HTTPException, Path, Request, status
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.deps import current_parent_user
from app.deps_email import get_email_provider
from app.models.user import User, UserRole
from app.schemas.account import (
    AccountCancelDeleteOut,
    AccountDeleteOut,
    AccountExportOut,
    AccountStatusOut,
)
from app.schemas.parent_password import (
    PasswordChangeIn,
    PasswordOkOut,
    PasswordSetIn,
)
from app.services import account_deletion_service
from app.services.auth_service import JwtError, decode_typed_token
from app.services.notification_service import EmailDeliveryDegraded, send_otp_email
from app.services.otp_service import (
    OtpExpired,
    OtpInvalid,
    OtpTooManyAttempts,
    request_code,
)
from app.services.parent_password_service import (
    ParentPasswordError,
    WeakPassword,
    change_parent_password,
    set_parent_password,
)

if TYPE_CHECKING:
    from app.services.email_provider import EmailProvider


router = APIRouter(prefix="/api/v1/family", tags=["parent-account"])
html_router = APIRouter(prefix="/family", tags=["parent-account-html"])

templates = Jinja2Templates(directory="app/templates")


def _account_home(user: User) -> str:
    fid = user.family_id or "_"
    return f"/family/{fid}/account"


def _password_error_http(exc: ParentPasswordError) -> HTTPException:
    return HTTPException(
        status_code=exc.http_status,
        detail={"error": {"code": exc.code, "message": exc.message}},
    )


def _otp_error_http(exc: Exception) -> HTTPException:
    if isinstance(exc, OtpInvalid):
        return HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"error": {"code": "INVALID_CODE", "message": "Invalid verification code."}},
        )
    if isinstance(exc, OtpTooManyAttempts):
        return HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "error": {
                    "code": "TOO_MANY_ATTEMPTS",
                    "message": "Too many wrong attempts; request a new code.",
                }
            },
        )
    if isinstance(exc, OtpExpired):
        return HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "error": {
                    "code": "CODE_EXPIRED",
                    "message": "Verification code expired; request a new one.",
                }
            },
        )
    raise exc


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


@router.post(
    "/{family_id}/account/password/request-otp",
    status_code=status.HTTP_202_ACCEPTED,
)
async def post_password_request_otp(
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
    provider: EmailProvider = Depends(get_email_provider),
) -> dict[str, str | int]:
    _ = family_id
    settings = get_settings()
    email = (user.email or "").strip().lower()
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": {"code": "NO_EMAIL", "message": "Account has no email."}},
        )
    _, plain_code = await request_code(email)
    if plain_code is not None:
        with contextlib.suppress(EmailDeliveryDegraded):
            await send_otp_email(
                provider,
                to=email,
                code=plain_code,
                expires_in_minutes=settings.otp_expiry_minutes,
            )
    return {"status": "accepted", "expires_in_minutes": settings.otp_expiry_minutes}


@router.post("/{family_id}/account/password/set", response_model=PasswordOkOut)
async def post_password_set(
    payload: PasswordSetIn,
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> PasswordOkOut:
    _ = family_id
    if payload.new_password != payload.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "error": {
                    "code": "PASSWORD_MISMATCH",
                    "message": "New password and confirmation do not match.",
                }
            },
        )
    try:
        await set_parent_password(
            user=user, code=payload.code, new_password=payload.new_password
        )
    except WeakPassword as e:
        raise _password_error_http(e) from e
    except (OtpInvalid, OtpTooManyAttempts, OtpExpired) as e:
        raise _otp_error_http(e) from e
    return PasswordOkOut()


@router.post("/{family_id}/account/password/change", response_model=PasswordOkOut)
async def post_password_change(
    payload: PasswordChangeIn,
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> PasswordOkOut:
    _ = family_id
    if payload.new_password != payload.confirm_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "error": {
                    "code": "PASSWORD_MISMATCH",
                    "message": "New password and confirmation do not match.",
                }
            },
        )
    try:
        await change_parent_password(
            user=user,
            old_password=payload.old_password,
            new_password=payload.new_password,
        )
    except ParentPasswordError as e:
        raise _password_error_http(e) from e
    return PasswordOkOut()


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
            "has_password": user.password_hash is not None,
            "password_error": None,
            "password_ok": request.query_params.get("password_ok") == "1",
            "password_otp_sent": False,
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


@html_router.post("/{family_id}/account/password/request-otp", response_model=None)
async def post_password_request_otp_form(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    provider: EmailProvider = Depends(get_email_provider),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    settings = get_settings()
    email = (user.email or "").strip().lower()
    if not email:
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
                "has_password": user.password_hash is not None,
                "password_error": "当前账号缺少邮箱，无法发送验证码。",
                "password_ok": False,
                "password_otp_sent": False,
            },
            status_code=400,
        )
    _, plain_code = await request_code(email)
    if plain_code is not None:
        with contextlib.suppress(EmailDeliveryDegraded):
            await send_otp_email(
                provider,
                to=email,
                code=plain_code,
                expires_in_minutes=settings.otp_expiry_minutes,
            )
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
            "has_password": user.password_hash is not None,
            "password_error": None,
            "password_ok": False,
            "password_otp_sent": True,
        },
    )


@html_router.post("/{family_id}/account/password/set", response_model=None)
async def post_password_set_form(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    code: str = Form(...),
    new_password: str = Form(...),
    confirm_password: str = Form(...),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    grace = account_deletion_service.grace_days_remaining(
        scheduled=user.scheduled_deletion_at
    )
    base = {
        "user": user,
        "grace_days_remaining": grace,
        "grace_days_total": account_deletion_service.GRACE_PERIOD.days,
        "has_password": user.password_hash is not None,
        "password_ok": False,
        "password_otp_sent": True,
    }
    if new_password != confirm_password:
        return templates.TemplateResponse(
            request,
            "parent/settings.html",
            {**base, "password_error": "两次输入的新密码不一致。"},
            status_code=400,
        )
    try:
        await set_parent_password(user=user, code=code.strip(), new_password=new_password)
    except WeakPassword:
        return templates.TemplateResponse(
            request,
            "parent/settings.html",
            {**base, "password_error": "密码至少需要 8 个字符。"},
            status_code=400,
        )
    except OtpInvalid:
        return templates.TemplateResponse(
            request,
            "parent/settings.html",
            {**base, "password_error": "验证码错误，请重新输入。"},
            status_code=400,
        )
    except OtpTooManyAttempts:
        return templates.TemplateResponse(
            request,
            "parent/settings.html",
            {**base, "password_error": "尝试次数过多，请重新发送验证码。"},
            status_code=400,
        )
    except OtpExpired:
        return templates.TemplateResponse(
            request,
            "parent/settings.html",
            {**base, "password_error": "验证码已过期，请重新发送。"},
            status_code=400,
        )
    return RedirectResponse(url=f"{_account_home(user)}?password_ok=1", status_code=303)


@html_router.post("/{family_id}/account/password/change", response_model=None)
async def post_password_change_form(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    old_password: str = Form(...),
    new_password: str = Form(...),
    confirm_password: str = Form(...),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    grace = account_deletion_service.grace_days_remaining(
        scheduled=user.scheduled_deletion_at
    )
    base = {
        "user": user,
        "grace_days_remaining": grace,
        "grace_days_total": account_deletion_service.GRACE_PERIOD.days,
        "has_password": True,
        "password_ok": False,
        "password_otp_sent": False,
    }
    if new_password != confirm_password:
        return templates.TemplateResponse(
            request,
            "parent/settings.html",
            {**base, "password_error": "两次输入的新密码不一致。"},
            status_code=400,
        )
    try:
        await change_parent_password(
            user=user, old_password=old_password, new_password=new_password
        )
    except ParentPasswordError as e:
        msg = (
            "当前密码错误。"
            if e.code == "OLD_PASSWORD_INVALID"
            else e.message
        )
        return templates.TemplateResponse(
            request,
            "parent/settings.html",
            {**base, "password_error": msg},
            status_code=400,
        )
    return RedirectResponse(url=f"{_account_home(user)}?password_ok=1", status_code=303)


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
