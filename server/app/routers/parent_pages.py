"""V0.6.1 — server-rendered HTML pages for the parent web shell.

These routes are form-friendly siblings of the JSON endpoints in
`parent_auth`. Browsers POST regular form data; we redirect or re-render
HTML accordingly. Cookies are issued via the shared
`set_parent_session_cookie` helper so cookie shape stays in sync.
"""

from __future__ import annotations

import contextlib
import time
from typing import TYPE_CHECKING

from fastapi import APIRouter, Depends, Form, HTTPException, Path, Request, Response, status
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
from app.models.pair_token import PairToken
from app.models.redemption_request import RedemptionRequest
from app.models.user import User, UserRole
from app.services.auth_service import (
    JwtError,
    create_session_token,
    decode_typed_token,
)
from app.services.family_service import create_family_for_parent
from app.services.notification_service import (
    EmailDeliveryDegraded,
    send_otp_email,
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

router = APIRouter(prefix="/parent", tags=["parent-web"])

templates = Jinja2Templates(directory="app/templates")


def _normalize_email(email: str) -> str:
    return email.strip().lower()


@router.get("/login", response_class=HTMLResponse)
async def get_login(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request, "parent/login.html", {"user": None}
    )


@router.get("/verify", response_class=HTMLResponse)
async def get_verify(request: Request, email: str = "") -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "parent/verify.html",
        {"user": None, "email": _normalize_email(email)},
    )


@router.post("/auth/request-code")
async def post_request_code_form(
    request: Request,
    email: str = Form(...),
    provider: EmailProvider = Depends(get_email_provider),
) -> HTMLResponse:
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


@router.post("/auth/verify-code", response_model=None)
async def post_verify_code_form(
    request: Request,
    email: str = Form(...),
    code: str = Form(...),
) -> HTMLResponse | RedirectResponse:
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

    _, user = await create_family_for_parent(email=email_norm)
    token = create_session_token(role="parent", identifier=user.username)
    redirect = RedirectResponse(url="/parent/", status_code=303)
    set_parent_session_cookie(redirect, token)
    return redirect


@router.post("/auth/logout")
async def post_logout_form() -> RedirectResponse:
    redirect = RedirectResponse(url="/parent/login", status_code=303)
    clear_parent_session_cookie(redirect)
    return redirect


@router.get("/", response_class=HTMLResponse, response_model=None)
@router.get("", response_class=HTMLResponse, response_model=None)
async def get_dashboard(request: Request) -> HTMLResponse | RedirectResponse:
    """Soft-auth: cookie missing or invalid → redirect to login (HTML flow)."""
    cookie_token = request.cookies.get(get_settings().session_cookie_name)
    if not cookie_token:
        return RedirectResponse(url="/parent/login", status_code=303)
    try:
        typed = decode_typed_token(cookie_token)
    except JwtError:
        return RedirectResponse(url="/parent/login", status_code=303)
    if typed.role != "parent":
        return RedirectResponse(url="/parent/login", status_code=303)
    user = await User.find_one(
        User.username == typed.identifier, User.role == UserRole.PARENT
    )
    if user is None:
        return RedirectResponse(url="/parent/login", status_code=303)
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


@router.get("/redemptions", response_class=HTMLResponse, response_model=None)
async def get_redemption_inbox(
    request: Request,
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
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


@router.post("/redemptions/{request_id}/approve", response_model=None)
async def post_approve_redemption(
    request_id: str = Path(min_length=4, max_length=64),
    user: User = Depends(current_parent_user),
) -> RedirectResponse:
    with contextlib.suppress(RequestNotFound, AlreadyDecided):
        await redemption_approve(
            request_id=request_id,
            family_id=user.family_id or "",
            decided_by=user.username,
            note=None,
        )
    return RedirectResponse(url="/parent/redemptions", status_code=303)


@router.post("/redemptions/{request_id}/reject", response_model=None)
async def post_reject_redemption(
    request_id: str = Path(min_length=4, max_length=64),
    user: User = Depends(current_parent_user),
) -> RedirectResponse:
    with contextlib.suppress(RequestNotFound, AlreadyDecided):
        await redemption_reject(
            request_id=request_id,
            family_id=user.family_id or "",
            decided_by=user.username,
            note=None,
        )
    return RedirectResponse(url="/parent/redemptions", status_code=303)


@router.get("/devices/add", response_class=HTMLResponse)
async def get_devices_add(
    request: Request,
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
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


@router.get("/devices/add/status", response_class=HTMLResponse)
async def get_devices_add_status(
    request: Request,
    token: str,
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
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


@router.post("/devices/add/cancel", response_model=None)
async def post_devices_add_cancel(
    token: str = Form(...),
    user: User = Depends(current_parent_user),
) -> RedirectResponse:
    with contextlib.suppress(PairTokenInvalid):
        await pair_cancel(token=token, family_id=user.family_id or "")
    return RedirectResponse(url="/parent/", status_code=303)


@router.get("/devices/{binding_id}", response_class=HTMLResponse)
async def get_device_detail(
    request: Request,
    binding_id: str = Path(min_length=8, max_length=64),
    user: User = Depends(current_parent_user),
) -> HTMLResponse:
    """V0.6.5 — render the per-device detail page with embedded report
    block. Other-family bindings raise 404."""
    binding = await DeviceBinding.find_one(
        DeviceBinding.binding_id == binding_id,
        DeviceBinding.family_id == (user.family_id or ""),
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
        ChildProfile.family_id == (user.family_id or ""),
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
