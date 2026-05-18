"""Google OAuth for parent web shell: /v1/oauth/google/*."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import RedirectResponse

from app.config import Settings, get_settings
from app.models.oauth_identity import OAuthProvider
from app.services.auth_service import create_session_token
from app.services.family_service import ParentLoginSuspended
from app.services.google_oauth_service import (
    GoogleOAuthClient,
    get_google_oauth_client,
    google_callback_url_for_origin,
    registered_google_callback_urls,
)
from app.services.oauth_handoff_service import (
    OAuthHandoffError,
    consume_handoff_ticket,
    create_handoff_ticket,
)
from app.services.oauth_login_service import OAuthRoleMismatch, resolve_google_login
from app.services.oauth_redirect_urls import uses_direct_session_on_callback
from app.services.oauth_return_origin_service import (
    InvalidOriginError,
    canonical_origin,
    require_allowed_origin,
)
from app.services.oauth_state_service import OAuthStateError, issue_state, verify_state

router = APIRouter(prefix="/v1/oauth/google", tags=["oauth-google"])


def _login_redirect(oauth_error: str) -> RedirectResponse:
    return RedirectResponse(
        url=f"/family/login?oauth_error={oauth_error}",
        status_code=status.HTTP_302_FOUND,
    )


def _dashboard_redirect(family_id: str) -> RedirectResponse:
    return RedirectResponse(
        url=f"/family/{family_id}/",
        status_code=status.HTTP_302_FOUND,
    )


def _session_redirect(
    *,
    settings: Settings,
    user_id: str,
    family_id: str,
    return_origin: str,
) -> RedirectResponse:
    token = create_session_token(role="parent", identifier=user_id)
    redirect = _dashboard_redirect(family_id)
    redirect.delete_cookie(key=settings.oauth_state_cookie_name, path="/")
    redirect.set_cookie(
        key=settings.session_cookie_name,
        value=token,
        max_age=settings.parent_session_expire_hours * 3600,
        httponly=True,
        secure=return_origin.startswith("https://"),
        samesite="lax",
        domain=settings.session_cookie_domain or None,
        path="/",
    )
    return redirect


@router.get("/start")
async def google_start(
    request: Request,
    return_origin: str | None = None,
    settings: Settings = Depends(get_settings),
    google: GoogleOAuthClient = Depends(get_google_oauth_client),
) -> RedirectResponse:
    if not settings.google_oauth_configured():
        return RedirectResponse(url="/family/login", status_code=status.HTTP_302_FOUND)

    origin = return_origin or str(request.base_url).rstrip("/")
    try:
        allowed_origin = await require_allowed_origin(origin, settings)
        redirect_uri = google_callback_url_for_origin(allowed_origin, settings)
    except InvalidOriginError:
        return _login_redirect("invalid_origin")

    state = issue_state(
        return_origin=allowed_origin,
        provider=OAuthProvider.GOOGLE.value,
        redirect_uri=redirect_uri,
    )
    location = google.build_authorize_url(state=state, redirect_uri=redirect_uri)
    redirect = RedirectResponse(url=location, status_code=status.HTTP_302_FOUND)
    redirect.set_cookie(
        key=settings.oauth_state_cookie_name,
        value=state,
        max_age=settings.oauth_state_ttl_seconds,
        httponly=True,
        secure=allowed_origin.startswith("https://"),
        samesite="lax",
        path="/",
    )
    return redirect


@router.get("/callback")
async def google_callback(
    request: Request,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    settings: Settings = Depends(get_settings),
    google: GoogleOAuthClient = Depends(get_google_oauth_client),
) -> RedirectResponse:
    if error:
        return _login_redirect("cancelled")
    if not code or not state:
        return _login_redirect("invalid_request")

    cookie_state = request.cookies.get(settings.oauth_state_cookie_name)
    if cookie_state != state:
        return _login_redirect("invalid_state")

    try:
        payload = verify_state(state)
    except OAuthStateError:
        return _login_redirect("invalid_state")

    return_origin = payload.get("return_origin", canonical_origin(settings))
    redirect_uri = payload.get("redirect_uri", "")
    if redirect_uri not in registered_google_callback_urls(settings):
        return _login_redirect("invalid_state")

    try:
        allowed_origin = await require_allowed_origin(return_origin, settings)
    except InvalidOriginError:
        return _login_redirect("invalid_origin")

    try:
        tokens = await google.exchange_code(code, redirect_uri=redirect_uri)
        claims = await google.verify_id_token(tokens.id_token)
        user, family = await resolve_google_login(claims)
    except OAuthRoleMismatch:
        return _login_redirect("role_mismatch")
    except ParentLoginSuspended:
        return _login_redirect("suspended")
    except ValueError:
        return _login_redirect("provider_error")

    if uses_direct_session_on_callback(allowed_origin, settings):
        return _session_redirect(
            settings=settings,
            user_id=user.username,
            family_id=family.family_id,
            return_origin=allowed_origin,
        )

    ticket_id = await create_handoff_ticket(
        user_id=user.username,
        return_origin=allowed_origin,
    )
    finish_url = f"{allowed_origin}/v1/oauth/google/finish?ticket={ticket_id}"
    redirect = RedirectResponse(url=finish_url, status_code=status.HTTP_302_FOUND)
    redirect.delete_cookie(key=settings.oauth_state_cookie_name, path="/")
    return redirect


@router.get("/finish")
async def google_finish(
    request: Request,
    ticket: Annotated[str | None, Query(alias="ticket")] = None,
    settings: Settings = Depends(get_settings),
) -> RedirectResponse:
    if not ticket:
        return _login_redirect("invalid_request")

    request_origin = f"{request.url.scheme}://{request.url.netloc}"
    try:
        user = await consume_handoff_ticket(
            ticket_id=ticket,
            request_origin=request_origin,
        )
    except OAuthHandoffError:
        return _login_redirect("invalid_ticket")

    if user.family_id is None:
        return _login_redirect("provider_error")

    return _session_redirect(
        settings=settings,
        user_id=user.username,
        family_id=user.family_id,
        return_origin=request_origin,
    )
