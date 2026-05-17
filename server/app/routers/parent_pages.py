"""V0.6.1 — server-rendered HTML pages for the parent web shell.

These routes are form-friendly siblings of the JSON endpoints in
`parent_auth`. Browsers POST regular form data; we redirect or re-render
HTML accordingly. Cookies are issued via the shared
`set_parent_session_cookie` helper so cookie shape stays in sync.
"""

from __future__ import annotations

import contextlib
import time
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, Form, HTTPException, Path, Query, Request, Response, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.deps import (
    clear_parent_session_cookie,
    current_parent_user,
    set_parent_session_cookie,
)
from app.deps_email import get_email_provider
from app.models.child_profile import ChildProfile
from app.models.cloud_wishlist_item import CloudWishlistItem
from app.models.device_binding import DeviceBinding
from app.models.oauth_identity import OAuthProvider
from app.models.pair_token import PairToken
from app.models.redemption_request import RedemptionRequest
from app.models.user import User, UserRole
from app.services import feedback_service
from app.services.auth_service import (
    JwtError,
    create_session_token,
    decode_typed_token,
)
from app.services.family_service import ParentLoginSuspended, create_family_for_parent
from app.services.parent_password_service import (
    EmailNotRegistered,
    ParentPasswordError,
    PasswordInvalid,
    PasswordLocked,
    PasswordNotSet,
    RoleMismatch,
    authenticate_parent_password,
)
from app.services.notification_service import (
    EmailDeliveryDegraded,
    send_device_unbind_otp_email,
    send_otp_email,
)
from app.services.oauth_login_service import OAuthRoleMismatch, OAuthUserClaims, resolve_oauth_login
from app.services.oauth_pending_identity_service import (
    OAuthPendingIdentityError,
    consume_pending_identity,
    load_pending_identity,
)
from app.services.otp_service import (
    OtpExpired,
    OtpInvalid,
    OtpTooManyAttempts,
    request_code,
    verify_code,
)
from app.services.pair_service import (
    PairTokenInvalid,
    create_pair,
)
from app.services.pair_service import (
    cancel as pair_cancel,
)
from app.services.parent_report_service import (
    ChildProfileNotFoundForReport,
    build_report,
)
from app.services.qr_service import render_qr_data_url
from app.services.redemption_service import (
    AlreadyDecided,
    RequestNotFound,
    list_pending_for_family,
    list_recent_for_family,
)
from app.services.redemption_service import (
    approve as redemption_approve,
)
from app.services.redemption_service import (
    reject as redemption_reject,
)

if TYPE_CHECKING:
    from app.services.email_provider import EmailProvider

router = APIRouter(prefix="/family", tags=["parent-web"])

templates = Jinja2Templates(directory="app/templates")


def _normalize_email(email: str) -> str:
    return email.strip().lower()


async def _load_active_device_for_parent(
    *, binding_id: str, family_id: str
) -> tuple[DeviceBinding, ChildProfile]:
    binding = await DeviceBinding.find_one(
        DeviceBinding.binding_id == binding_id,
        DeviceBinding.family_id == family_id,
        DeviceBinding.revoked_at == None,  # noqa: E711
    )
    if binding is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "BINDING_NOT_FOUND",
                    "message": "Device binding not in your family",
                }
            },
        )
    child = await ChildProfile.find_one(
        ChildProfile.profile_id == binding.child_profile_id,
        ChildProfile.family_id == family_id,
    )
    if child is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "CHILD_NOT_FOUND",
                    "message": "Child profile missing for this binding",
                }
            },
        )
    return binding, child


def _oauth_error_message(code: str) -> str:
    messages = {
        "invalid_origin": "无法从当前站点发起 Google 登录，请使用官方家长后台地址。",
        "cancelled": "已取消 Google 登录。",
        "invalid_state": "登录状态已失效，请重试。",
        "invalid_request": "登录请求无效，请重试。",
        "role_mismatch": "该邮箱归属于管理员账号；请使用管理员登录入口。",
        "suspended": "家长账号已被管理员暂停登录。",
        "provider_error": "第三方登录失败，请稍后重试或使用邮箱验证码登录。",
        "invalid_ticket": "登录凭证已失效，请重新登录。",
        "email_unavailable": (
            "无法获取邮箱信息，请使用邮箱验证码登录，或先在 Apple 账号设置中共享邮箱。"
        ),
    }
    return messages.get(code, "登录失败，请重试或使用邮箱验证码登录。")


@router.get("/login", response_class=HTMLResponse)
async def get_login(
    request: Request,
    oauth_error: str = "",
) -> HTMLResponse:
    """Canonical pre-login parent shell entry (no decorative `{family_id}` segment)."""
    from app.services.oauth_return_origin_service import (
        alipay_oauth_enabled,
        apple_oauth_enabled,
        build_alipay_start_url,
        build_apple_start_url,
        build_google_start_url,
        build_wechat_start_url,
        google_oauth_enabled,
        wechat_oauth_enabled,
    )

    base = str(request.base_url)
    return templates.TemplateResponse(
        request,
        "parent/login.html",
        {
            "user": None,
            "google_oauth_enabled": google_oauth_enabled(),
            "google_start_url": build_google_start_url(base),
            "apple_oauth_enabled": apple_oauth_enabled(),
            "apple_start_url": build_apple_start_url(base),
            "wechat_oauth_enabled": wechat_oauth_enabled(),
            "wechat_start_url": build_wechat_start_url(base),
            "alipay_oauth_enabled": alipay_oauth_enabled(),
            "alipay_start_url": build_alipay_start_url(base),
            "oauth_error": oauth_error,
            "oauth_error_message": _oauth_error_message(oauth_error) if oauth_error else "",
        },
    )


@router.get("/login/password", response_class=HTMLResponse)
async def get_login_password(
    request: Request,
    email: str = "",
) -> HTMLResponse:
    """Dedicated email + password login page (linked from /family/login)."""
    return templates.TemplateResponse(
        request,
        "parent/login_password.html",
        {
            "user": None,
            "password_error": "",
            "password_email": _normalize_email(email) if email else "",
        },
    )


@router.get("/oauth/bind-email", response_class=HTMLResponse, response_model=None)
async def get_oauth_bind_email(
    request: Request,
    ticket: str = Query(min_length=1),
) -> HTMLResponse | RedirectResponse:
    try:
        pending = await load_pending_identity(
            ticket_id=ticket,
            request_origin=f"{request.url.scheme}://{request.url.netloc}",
        )
    except OAuthPendingIdentityError:
        return RedirectResponse(url="/family/login?oauth_error=invalid_ticket", status_code=303)
    return templates.TemplateResponse(
        request,
        "parent/oauth_bind_email.html",
        {
            "user": None,
            "ticket": ticket,
            "provider": pending.provider.value,
            "email": "",
            "sent": False,
        },
    )


@router.post(
    "/oauth/bind-email/request-code",
    response_class=HTMLResponse,
    response_model=None,
)
async def post_oauth_bind_email_request_code(
    request: Request,
    ticket: str = Form(...),
    email: str = Form(...),
    provider: EmailProvider = Depends(get_email_provider),
) -> HTMLResponse | RedirectResponse:
    try:
        pending = await load_pending_identity(
            ticket_id=ticket,
            request_origin=f"{request.url.scheme}://{request.url.netloc}",
        )
    except OAuthPendingIdentityError:
        return RedirectResponse(url="/family/login?oauth_error=invalid_ticket", status_code=303)

    settings = get_settings()
    email_norm = _normalize_email(email)
    _, plain_code = await request_code(email_norm)
    if plain_code is not None:
        with contextlib.suppress(EmailDeliveryDegraded):
            await send_otp_email(
                provider,
                to=email_norm,
                code=plain_code,
                expires_in_minutes=settings.otp_expiry_minutes,
            )
    return templates.TemplateResponse(
        request,
        "parent/oauth_bind_email.html",
        {
            "user": None,
            "ticket": ticket,
            "provider": pending.provider.value,
            "email": email_norm,
            "sent": True,
        },
    )


@router.post(
    "/oauth/bind-email/verify-code",
    response_class=HTMLResponse,
    response_model=None,
)
async def post_oauth_bind_email_verify_code(
    request: Request,
    ticket: str = Form(...),
    email: str = Form(...),
    code: str = Form(...),
) -> HTMLResponse | RedirectResponse:
    try:
        pending = await load_pending_identity(
            ticket_id=ticket,
            request_origin=f"{request.url.scheme}://{request.url.netloc}",
        )
    except OAuthPendingIdentityError:
        return RedirectResponse(url="/family/login?oauth_error=invalid_ticket", status_code=303)

    email_norm = _normalize_email(email)
    base_context = {
        "user": None,
        "ticket": ticket,
        "provider": pending.provider.value,
        "email": email_norm,
        "sent": True,
    }

    existing = await User.find_one(User.email == email_norm)
    if existing is not None and existing.role == UserRole.ADMIN:
        return templates.TemplateResponse(
            request,
            "parent/oauth_bind_email.html",
            {**base_context, "error": "该邮箱归属于管理员账号；请使用管理员登录入口。"},
            status_code=400,
        )

    try:
        await verify_code(email=email_norm, code=code)
    except OtpInvalid:
        return templates.TemplateResponse(
            request,
            "parent/oauth_bind_email.html",
            {**base_context, "error": "验证码错误，请重新输入。"},
            status_code=400,
        )
    except OtpTooManyAttempts:
        return templates.TemplateResponse(
            request,
            "parent/oauth_bind_email.html",
            {**base_context, "error": "尝试次数过多，请重新发送验证码。"},
            status_code=400,
        )
    except OtpExpired:
        return templates.TemplateResponse(
            request,
            "parent/oauth_bind_email.html",
            {**base_context, "error": "验证码已过期，请重新发送。"},
            status_code=400,
        )

    try:
        user, family = await resolve_oauth_login(
            OAuthProvider(pending.provider),
            OAuthUserClaims(
                subject=pending.provider_subject,
                email=email_norm,
                email_verified=True,
            ),
        )
    except OAuthRoleMismatch:
        return templates.TemplateResponse(
            request,
            "parent/oauth_bind_email.html",
            {**base_context, "error": "该邮箱归属于管理员账号；请使用管理员登录入口。"},
            status_code=400,
        )
    except ParentLoginSuspended:
        return templates.TemplateResponse(
            request,
            "parent/oauth_bind_email.html",
            {**base_context, "error": "该家长账号已被管理员暂停登录，请联系支持。"},
            status_code=403,
        )
    except ValueError:
        return templates.TemplateResponse(
            request,
            "parent/oauth_bind_email.html",
            {**base_context, "error": "第三方登录绑定失败，请重新登录。"},
            status_code=400,
        )

    await consume_pending_identity(ticket)
    token = create_session_token(role="parent", identifier=user.username)
    redirect = RedirectResponse(url=f"/family/{family.family_id}/", status_code=303)
    set_parent_session_cookie(redirect, token)
    return redirect


@router.get("/{family_id}/login", include_in_schema=False)
async def get_login_scoped_redirect(
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse:
    """Backward-compatible alias: `/family/_/login` (and any `{family_id}`) → `/family/login`."""
    _ = family_id
    return RedirectResponse(url="/family/login", status_code=308)


@router.get("/{family_id}/verify", response_class=HTMLResponse)
async def get_verify(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    email: str = "",
) -> HTMLResponse:
    _ = family_id
    return templates.TemplateResponse(
        request,
        "parent/verify.html",
        {"user": None, "email": _normalize_email(email)},
    )


@router.post("/{family_id}/auth/request-code")
async def post_request_code_form(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    email: str = Form(...),
    provider: EmailProvider = Depends(get_email_provider),
) -> HTMLResponse:
    _ = family_id
    settings = get_settings()
    email_norm = _normalize_email(email)
    _, plain_code = await request_code(email_norm)
    if plain_code is not None:
        # Persist row regardless; user can retry on the verify page.
        with contextlib.suppress(EmailDeliveryDegraded):
            await send_otp_email(
                provider,
                to=email_norm,
                code=plain_code,
                expires_in_minutes=settings.otp_expiry_minutes,
            )
    return templates.TemplateResponse(
        request,
        "parent/verify.html",
        {"user": None, "email": email_norm},
    )


@router.post("/{family_id}/auth/verify-code", response_model=None)
async def post_verify_code_form(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    email: str = Form(...),
    code: str = Form(...),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    email_norm = _normalize_email(email)

    existing = await User.find_one(User.email == email_norm)
    if existing is not None and existing.role == UserRole.ADMIN:
        return templates.TemplateResponse(
            request,
            "parent/verify.html",
            {
                "user": None,
                "email": email_norm,
                "error": "该邮箱归属于管理员账号；请使用管理员登录入口。",
            },
            status_code=400,
        )

    try:
        await verify_code(email=email_norm, code=code)
    except OtpInvalid:
        return templates.TemplateResponse(
            request,
            "parent/verify.html",
            {
                "user": None,
                "email": email_norm,
                "error": "验证码错误，请重新输入。",
            },
            status_code=400,
        )
    except OtpTooManyAttempts:
        return templates.TemplateResponse(
            request,
            "parent/verify.html",
            {
                "user": None,
                "email": email_norm,
                "error": "尝试次数过多，请重新发送验证码。",
            },
            status_code=400,
        )
    except OtpExpired:
        return templates.TemplateResponse(
            request,
            "parent/verify.html",
            {
                "user": None,
                "email": email_norm,
                "error": "验证码已过期，请重新发送。",
            },
            status_code=400,
        )

    try:
        _, user = await create_family_for_parent(email=email_norm)
    except ParentLoginSuspended:
        return templates.TemplateResponse(
            request,
            "parent/verify.html",
            {
                "user": None,
                "email": email_norm,
                "error": "该家长账号已被管理员暂停登录，请联系支持。",
            },
            status_code=403,
        )
    token = create_session_token(role="parent", identifier=user.username)
    fid = user.family_id or "_"
    redirect = RedirectResponse(url=f"/family/{fid}/", status_code=303)
    set_parent_session_cookie(redirect, token)
    return redirect


@router.post("/{family_id}/auth/password-login", response_model=None)
async def post_password_login_form(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    email: str = Form(...),
    password: str = Form(...),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    email_norm = _normalize_email(email)

    def _password_page(
        *, error: str, status_code: int
    ) -> HTMLResponse:
        return templates.TemplateResponse(
            request,
            "parent/login_password.html",
            {
                "user": None,
                "password_error": error,
                "password_email": email_norm,
            },
            status_code=status_code,
        )

    try:
        user = await authenticate_parent_password(email=email_norm, password=password)
    except EmailNotRegistered:
        return templates.TemplateResponse(
            request,
            "parent/password_register_confirm.html",
            {"user": None, "email": email_norm},
        )
    except RoleMismatch:
        return _password_page(
            error="该邮箱归属于管理员账号；请使用管理员登录入口。",
            status_code=400,
        )
    except ParentLoginSuspended:
        return _password_page(
            error="该家长账号已被管理员暂停登录，请联系支持。",
            status_code=403,
        )
    except PasswordNotSet as e:
        return _password_page(error=e.message, status_code=409)
    except (PasswordInvalid, PasswordLocked) as e:
        return _password_page(
            error=(
                "密码错误，请重试。"
                if isinstance(e, PasswordInvalid)
                else "尝试次数过多，请稍后再试或使用邮箱验证码登录。"
            ),
            status_code=403 if isinstance(e, PasswordInvalid) else 410,
        )
    except ParentPasswordError as e:
        return _password_page(error=e.message, status_code=400)

    token = create_session_token(role="parent", identifier=user.username)
    fid = user.family_id or "_"
    redirect = RedirectResponse(url=f"/family/{fid}/", status_code=303)
    set_parent_session_cookie(redirect, token)
    return redirect


@router.post("/{family_id}/auth/logout")
async def post_logout_form(
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse:
    _ = family_id
    redirect = RedirectResponse(url="/family/login", status_code=303)
    clear_parent_session_cookie(redirect)
    return redirect


@router.get("/{family_id}/", response_class=HTMLResponse, response_model=None)
@router.get("/{family_id}", response_class=HTMLResponse, response_model=None)
async def get_dashboard(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    """Soft-auth: cookie missing or invalid → redirect to login (HTML flow)."""
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
    if user is None:
        return RedirectResponse(url="/family/login", status_code=303)
    bindings = await DeviceBinding.find(
        DeviceBinding.family_id == (user.family_id or ""),
        DeviceBinding.revoked_at == None,  # noqa: E711
    ).to_list()
    children = await ChildProfile.find(
        ChildProfile.family_id == (user.family_id or ""),
        ChildProfile.deleted_at == None,  # noqa: E711
    ).to_list()
    children_by_id = {c.profile_id: c for c in children}
    pending_rows = await _decorated_redemptions(
        family_id=user.family_id or "", pending=True, limit=5
    )
    return templates.TemplateResponse(
        request,
        "parent/dashboard.html",
        {
            "user": user,
            "bindings": bindings,
            "children_by_id": children_by_id,
            "pending_redemptions": pending_rows,
            "flash_ok": (
                "设备已解除绑定。"
                if request.query_params.get("flash_ok") == "device_unbound"
                else None
            ),
        },
    )


async def _decorated_redemptions(
    *, family_id: str, pending: bool, limit: int = 50
) -> list[dict[str, str | int]]:
    """Decorate redemption rows with the joined item display name +
    child nickname so the partial template doesn't have to fetch.
    """
    if pending:
        rows = await list_pending_for_family(family_id=family_id)
    else:
        rows = await list_recent_for_family(family_id=family_id, limit=limit)
    if not rows:
        return []
    item_ids = {r.wishlist_item_id for r in rows}
    profile_ids = {r.child_profile_id for r in rows}
    items = await CloudWishlistItem.find(
        {"item_id": {"$in": list(item_ids)}}
    ).to_list()
    items_by_id = {i.item_id: i for i in items}
    profiles = await ChildProfile.find(
        {"profile_id": {"$in": list(profile_ids)}}
    ).to_list()
    profiles_by_id = {p.profile_id: p for p in profiles}

    def _fmt(dt: object) -> str:
        if dt is None or not hasattr(dt, "strftime"):
            return ""
        return str(dt.strftime("%Y-%m-%d %H:%M"))

    out: list[dict[str, str | int]] = []
    for r in rows:
        item = items_by_id.get(r.wishlist_item_id)
        profile = profiles_by_id.get(r.child_profile_id)
        out.append(
            {
                "request_id": r.request_id,
                "child_nickname": profile.nickname if profile else "（已删除）",
                "item_display_name": item.display_name if item else "（已删除）",
                "cost_coins_at_request": r.cost_coins_at_request,
                "requested_at_label": _fmt(r.requested_at),
                "decided_at_label": _fmt(r.decided_at),
                "status": str(r.status),
                "decision_note": r.decision_note or "",
            }
        )
    return out


@router.get("/{family_id}/redemptions", response_class=HTMLResponse, response_model=None)
async def get_redemption_inbox(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
    _ = family_id
    pending = await _decorated_redemptions(
        family_id=user.family_id or "", pending=True
    )
    recent = await _decorated_redemptions(
        family_id=user.family_id or "", pending=False, limit=20
    )
    # Filter "recent" to decided rows only so the section is clearly distinct.
    recent = [r for r in recent if r["status"] != "pending"]
    return templates.TemplateResponse(
        request,
        "parent/redemptions.html",
        {"user": user, "pending": pending, "recent": recent},
    )


@router.post("/{family_id}/redemptions/{request_id}/approve", response_model=None)
async def post_approve_redemption(
    request_id: str = Path(min_length=4, max_length=64),
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> RedirectResponse:
    _ = family_id
    with contextlib.suppress(RequestNotFound, AlreadyDecided):
        await redemption_approve(
            request_id=request_id,
            family_id=user.family_id or "",
            decided_by=user.username,
            note=None,
        )
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/redemptions", status_code=303)


@router.post("/{family_id}/redemptions/{request_id}/reject", response_model=None)
async def post_reject_redemption(
    request_id: str = Path(min_length=4, max_length=64),
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> RedirectResponse:
    _ = family_id
    with contextlib.suppress(RequestNotFound, AlreadyDecided):
        await redemption_reject(
            request_id=request_id,
            family_id=user.family_id or "",
            decided_by=user.username,
            note=None,
        )
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/redemptions", status_code=303)


@router.get("/{family_id}/feedback", response_class=HTMLResponse, response_model=None)
async def get_feedback(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
    _ = family_id
    rows = await feedback_service.list_feedback_for_parent(parent_user_id=user.username)
    ok_map = {"created": "反馈已提交，感谢你的建议。"}
    return templates.TemplateResponse(
        request,
        "parent/feedback.html",
        {
            "user": user,
            "feedback_items": rows,
            "flash_ok": ok_map.get(request.query_params.get("flash_ok", "")),
            "error": None,
            "draft_subject": "",
            "draft_body": "",
        },
    )


@router.post("/{family_id}/feedback", response_class=HTMLResponse, response_model=None)
async def post_feedback(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    subject: str = Form(...),
    body: str = Form(...),
    user: User = Depends(current_parent_user),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    try:
        await feedback_service.create_feedback(user=user, subject=subject, body=body)
    except ValueError:
        rows = await feedback_service.list_feedback_for_parent(parent_user_id=user.username)
        return templates.TemplateResponse(
            request,
            "parent/feedback.html",
            {
                "user": user,
                "feedback_items": rows,
                "flash_ok": None,
                "error": "请填写反馈标题和内容，标题不超过 120 字，内容不超过 4000 字。",
                "draft_subject": subject,
                "draft_body": body,
            },
            status_code=400,
        )
    return RedirectResponse(
        url=f"/family/{user.family_id or '_'}/feedback?flash_ok=created",
        status_code=303,
    )


@router.get("/{family_id}/devices/add", response_class=HTMLResponse)
async def get_devices_add(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
    _ = family_id
    """V0.6.2 — render a fresh QR + 6-digit short code for the parent to share."""
    pt = await create_pair(family_id=user.family_id or "", parent_id=user.username)
    settings = get_settings()
    qr_payload = f"{settings.parent_web_base_url.rstrip('/')}/p/{pt.token[:12]}"
    qr_data_url = render_qr_data_url(qr_payload)
    return templates.TemplateResponse(
        request,
        "parent/devices_add.html",
        {
            "user": user,
            "token": pt.token,
            "short_code": pt.short_code,
            "qr_data_url": qr_data_url,
            "qr_payload_url": qr_payload,
        },
    )


@router.get("/{family_id}/devices/add/status", response_class=HTMLResponse)
async def get_devices_add_status(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    token: str = Query(min_length=8),
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
    _ = family_id
    """HTMX poll endpoint returning the small status partial."""
    pt = await PairToken.find_one(
        PairToken.token == token, PairToken.family_id == (user.family_id or "")
    )
    if pt is None:
        return templates.TemplateResponse(
            request,
            "partials/pair_status_row.html",
            {"user": user, "status": "expired", "device_id_tail": ""},
        )
    device_id_tail = ""
    if pt.redeemed_by_device_id:
        device_id_tail = pt.redeemed_by_device_id[-4:]
    return templates.TemplateResponse(
        request,
        "partials/pair_status_row.html",
        {
            "user": user,
            "status": pt.status.value,
            "device_id_tail": device_id_tail,
        },
    )


@router.post("/{family_id}/devices/add/cancel", response_model=None)
async def post_devices_add_cancel(
    token: str = Form(...),
    family_id: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> RedirectResponse:
    _ = family_id
    with contextlib.suppress(PairTokenInvalid):
        await pair_cancel(token=token, family_id=user.family_id or "")
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/", status_code=303)


@router.get(
    "/{family_id}/devices/{binding_id}/unbind",
    response_class=HTMLResponse,
    response_model=None,
)
async def get_device_unbind_confirm(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    binding_id: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
    provider: EmailProvider = Depends(get_email_provider),
) -> HTMLResponse:
    _ = family_id
    binding, child = await _load_active_device_for_parent(
        binding_id=binding_id,
        family_id=user.family_id or "",
    )
    email = _normalize_email(user.email or "")
    delivery_degraded = False
    if email:
        settings = get_settings()
        _, plain_code = await request_code(email)
        if plain_code is not None:
            device_tail = binding.device_id[-4:] if binding.device_id else "----"
            try:
                await send_device_unbind_otp_email(
                    provider,
                    to=email,
                    code=plain_code,
                    expires_in_minutes=settings.otp_expiry_minutes,
                    child_nickname=child.nickname,
                    device_tail=device_tail,
                )
            except EmailDeliveryDegraded:
                delivery_degraded = True
    return templates.TemplateResponse(
        request,
        "parent/device_unbind_confirm.html",
        {
            "user": user,
            "binding": binding,
            "child": child,
            "email": email,
            "error": None if email else "当前家长账号缺少邮箱，无法发送验证码。",
            "delivery_degraded": delivery_degraded,
        },
    )


@router.post(
    "/{family_id}/devices/{binding_id}/unbind",
    response_class=HTMLResponse,
    response_model=None,
)
async def post_device_unbind_confirm(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    binding_id: str = Path(min_length=8, max_length=64),
    code: str = Form(...),
    user: User = Depends(current_parent_user),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    binding, child = await _load_active_device_for_parent(
        binding_id=binding_id,
        family_id=user.family_id or "",
    )
    email = _normalize_email(user.email or "")
    if not email:
        return templates.TemplateResponse(
            request,
            "parent/device_unbind_confirm.html",
            {
                "user": user,
                "binding": binding,
                "child": child,
                "email": email,
                "error": "当前家长账号缺少邮箱，无法校验验证码。",
                "delivery_degraded": False,
            },
            status_code=400,
        )

    try:
        await verify_code(email=email, code=code.strip())
    except OtpInvalid:
        error = "验证码错误，请重新输入。"
    except OtpTooManyAttempts:
        error = "尝试次数过多，请重新发送验证码。"
    except OtpExpired:
        error = "验证码已过期，请重新打开解绑确认页。"
    else:
        now = datetime.now(tz=UTC)
        binding.revoked_at = now
        child.deleted_at = now
        child.updated_at = now
        await binding.save()
        await child.save()
        return RedirectResponse(
            url=f"/family/{user.family_id or '_'}/?flash_ok=device_unbound",
            status_code=303,
        )

    return templates.TemplateResponse(
        request,
        "parent/device_unbind_confirm.html",
        {
            "user": user,
            "binding": binding,
            "child": child,
            "email": email,
            "error": error,
            "delivery_degraded": False,
        },
        status_code=400,
    )


@router.get("/{family_id}/devices/{binding_id}", response_class=HTMLResponse)
async def get_device_detail(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    binding_id: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
    _ = family_id
    """V0.6.5 — render the per-device detail page with embedded report
    block. Other-family bindings raise 404."""
    binding, child = await _load_active_device_for_parent(
        binding_id=binding_id,
        family_id=user.family_id or "",
    )
    try:
        report = await build_report(
            family_id=user.family_id or "",
            child_profile_id=child.profile_id,
            lookback_days=7,
            now_ms=int(time.time() * 1000),
        )
    except ChildProfileNotFoundForReport as e:
        # Should be unreachable since we just looked the profile up, but
        # be explicit about the contract.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "CHILD_NOT_FOUND",
                    "message": "Child profile not in your family",
                }
            },
        ) from e
    wishlist_items = await CloudWishlistItem.find(
        CloudWishlistItem.child_profile_id == child.profile_id,
    ).to_list()
    return templates.TemplateResponse(
        request,
        "parent/device_detail.html",
        {
            "user": user,
            "binding": binding,
            "child": child,
            "report": report,
            "wishlist_items": wishlist_items,
        },
    )


# Keep a referenced symbol so unused-import linting stays calm if Response
# gets repurposed by future helpers.
_ = (
    Response,
    HTTPException,
    ChildProfile,
    DeviceBinding,
    RedemptionRequest,
    CloudWishlistItem,
)
