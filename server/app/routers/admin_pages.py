"""V0.8.2 — server-rendered system administrator console under `/admin/`.

JSON admin APIs remain under `/api/v1/admin/*` with bearer tokens; this router
adds form-friendly HTML + a dedicated admin session cookie (`wm_admin_session`).
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.deps import clear_admin_session_cookie, set_admin_session_cookie
from app.models.user import User, UserRole
from app.services.admin_console_overview_service import (
    build_admin_overview,
    format_audit_timestamp,
)
from app.services.auth_service import (
    JwtError,
    create_session_token,
    decode_typed_token,
    verify_password,
)

router = APIRouter(
    prefix="/admin",
    tags=["admin-web"],
    include_in_schema=False,
)

templates = Jinja2Templates(directory="app/templates")


async def _require_admin_html(request: Request) -> User | RedirectResponse:
    settings = get_settings()
    cookie_token = request.cookies.get(settings.admin_session_cookie_name)
    if not cookie_token:
        return RedirectResponse(url="/admin/login", status_code=303)
    try:
        typed = decode_typed_token(cookie_token)
    except JwtError:
        return RedirectResponse(url="/admin/login", status_code=303)
    if typed.role != "admin":
        return RedirectResponse(url="/admin/login", status_code=303)
    user = await User.find_one(
        User.username == typed.identifier,
        User.role == UserRole.ADMIN,
    )
    if user is None or user.password_hash is None:
        return RedirectResponse(url="/admin/login", status_code=303)
    return user


def _redirect_if_authenticated(request: Request) -> RedirectResponse | None:
    settings = get_settings()
    cookie_token = request.cookies.get(settings.admin_session_cookie_name)
    if not cookie_token:
        return None
    try:
        typed = decode_typed_token(cookie_token)
    except JwtError:
        return None
    if typed.role != "admin":
        return None
    return RedirectResponse(url="/admin/", status_code=303)


@router.get("/login", response_class=HTMLResponse, response_model=None)
async def admin_login_page(request: Request) -> HTMLResponse | RedirectResponse:
    early = _redirect_if_authenticated(request)
    if early is not None:
        return early
    return templates.TemplateResponse(request, "admin/login.html", {"error": None})


@router.post("/login", response_class=HTMLResponse, response_model=None)
async def admin_login_post(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
) -> HTMLResponse | RedirectResponse:
    early = _redirect_if_authenticated(request)
    if early is not None:
        return early

    user = await User.find_one(User.username == username.strip())
    if (
        user is None
        or user.role != UserRole.ADMIN
        or user.password_hash is None
        or not verify_password(password, user.password_hash)
    ):
        return templates.TemplateResponse(
            request,
            "admin/login.html",
            {"error": "Invalid username or password."},
            status_code=401,
        )

    settings = get_settings()
    expires_in = settings.admin_session_expire_hours * 3600
    token = create_session_token(
        role="admin",
        identifier=user.username,
        expires_in=expires_in,
    )
    user.last_login_at = datetime.now(tz=UTC)
    await user.save()
    redirect = RedirectResponse(url="/admin/", status_code=303)
    set_admin_session_cookie(redirect, token)
    return redirect


@router.post("/logout", response_model=None)
async def admin_logout() -> RedirectResponse:
    out = RedirectResponse(url="/admin/login", status_code=303)
    clear_admin_session_cookie(out)
    return out


@router.get("/", response_class=HTMLResponse, response_model=None)
async def admin_dashboard(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    overview = await build_admin_overview()
    return templates.TemplateResponse(
        request,
        "admin/dashboard.html",
        {
            "admin_user": gate,
            "overview": overview,
            "audit_ts": format_audit_timestamp,
        },
    )


@router.get("/parents", response_class=HTMLResponse, response_model=None)
async def admin_parents_stub(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    return templates.TemplateResponse(
        request,
        "admin/stub.html",
        {
            "admin_user": gate,
            "page_title": "Parents",
            "description": (
                "Search and inspect parent accounts, linked families, devices, "
                "and family vocabulary."
            ),
        },
    )


@router.get("/devices", response_class=HTMLResponse, response_model=None)
async def admin_devices_stub(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    return templates.TemplateResponse(
        request,
        "admin/stub.html",
        {
            "admin_user": gate,
            "page_title": "Devices",
            "description": "Inspect device bindings, revocation state, and last sync signals.",
        },
    )


@router.get("/global-packs", response_class=HTMLResponse, response_model=None)
async def admin_global_packs_stub(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    return templates.TemplateResponse(
        request,
        "admin/stub.html",
        {
            "admin_user": gate,
            "page_title": "Global packs",
            "description": "Inspect global vocabulary snapshots and publish / rollback operations.",
        },
    )


@router.get("/family-packs", response_class=HTMLResponse, response_model=None)
async def admin_family_packs_stub(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    return templates.TemplateResponse(
        request,
        "admin/stub.html",
        {
            "admin_user": gate,
            "page_title": "Family packs",
            "description": "Read-only family vocabulary diagnostics (no silent draft edits).",
        },
    )


@router.get("/audit-logs", response_class=HTMLResponse, response_model=None)
async def admin_audit_logs_stub(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    return templates.TemplateResponse(
        request,
        "admin/stub.html",
        {
            "admin_user": gate,
            "page_title": "Audit logs",
            "description": "Full audit trail with filters for high-risk administrative actions.",
        },
    )
