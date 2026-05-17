"""Sign in with Apple for parent web shell: /v1/oauth/apple/*."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Form, Query, Request, status
from fastapi.responses import RedirectResponse

from app.config import Settings, get_settings
from app.models.oauth_identity import OAuthProvider
from app.routers.oauth_common import oauth_login_redirect, oauth_session_redirect
from app.services.apple_oauth_service import (
    AppleOAuthClient,
    apple_callback_url_for_origin,
    get_apple_oauth_client,
    registered_apple_callback_urls,
)
from app.services.family_service import ParentLoginSuspended
from app.services.oauth_handoff_service import (
    OAuthHandoffError,
    consume_handoff_ticket,
    create_handoff_ticket,
)
from app.services.oauth_login_service import (
    OAuthEmailUnavailable,
    OAuthRoleMismatch,
    resolve_apple_login,
)
from app.services.oauth_redirect_urls import uses_direct_session_on_callback
from app.services.oauth_return_origin_service import (
    InvalidOriginError,
    canonical_origin,
    require_allowed_origin,
)
from app.services.oauth_state_service import OAuthStateError, issue_state, verify_state

router = APIRouter(prefix="/v1/oauth/apple", tags=["oauth-apple"])


@router.get("/start")
async def apple_start(
    request: Request,
    return_origin: str | None = None,
    settings: Settings = Depends(get_settings),
    apple: AppleOAuthClient = Depends(get_apple_oauth_client),
) -> RedirectResponse:
    if not settings.apple_oauth_configured():
        return RedirectResponse(url="/family/login", status_code=status.HTTP_302_FOUND)

    origin = return_origin or str(request.base_url).rstrip("/")
    try:
        allowed_origin = await require_allowed_origin(origin, settings)
        redirect_uri = apple_callback_url_for_origin(allowed_origin, settings)
    except InvalidOriginError:
        return oauth_login_redirect("invalid_origin")

    state = issue_state(
        return_origin=allowed_origin,
        provider=OAuthProvider.APPLE.value,
        redirect_uri=redirect_uri,
    )
    location = apple.build_authorize_url(state=state, redirect_uri=redirect_uri)
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


async def _complete_apple_callback(
    *,
    request: Request,
    code: str | None,
    state: str | None,
    settings: Settings,
    apple: AppleOAuthClient,
) -> RedirectResponse:
    if not code or not state:
        return oauth_login_redirect("invalid_request")

    cookie_state = request.cookies.get(settings.oauth_state_cookie_name)
    if cookie_state != state:
        return oauth_login_redirect("invalid_state")

    try:
        payload = verify_state(state)
    except OAuthStateError:
        return oauth_login_redirect("invalid_state")

    return_origin = payload.get("return_origin", canonical_origin(settings))
    redirect_uri = payload.get("redirect_uri", "")
    if redirect_uri not in registered_apple_callback_urls(settings):
        return oauth_login_redirect("invalid_state")

    try:
        allowed_origin = await require_allowed_origin(return_origin, settings)
    except InvalidOriginError:
        return oauth_login_redirect("invalid_origin")

    try:
        tokens = await apple.exchange_code(code, redirect_uri=redirect_uri)
        claims = await apple.verify_id_token(tokens.id_token)
        user, family = await resolve_apple_login(claims)
    except OAuthRoleMismatch:
        return oauth_login_redirect("role_mismatch")
    except ParentLoginSuspended:
        return oauth_login_redirect("suspended")
    except OAuthEmailUnavailable:
        return oauth_login_redirect("email_unavailable")
    except ValueError:
        return oauth_login_redirect("provider_error")

    if uses_direct_session_on_callback(allowed_origin, settings):
        return oauth_session_redirect(
            settings=settings,
            user_id=user.username,
            family_id=family.family_id,
            return_origin=allowed_origin,
            state_cookie_name=settings.oauth_state_cookie_name,
        )

    ticket_id = await create_handoff_ticket(
        user_id=user.username,
        return_origin=allowed_origin,
    )
    finish_url = f"{allowed_origin}/v1/oauth/apple/finish?ticket={ticket_id}"
    redirect = RedirectResponse(url=finish_url, status_code=status.HTTP_302_FOUND)
    redirect.delete_cookie(key=settings.oauth_state_cookie_name, path="/")
    return redirect


@router.post("/callback")
async def apple_callback_post(
    request: Request,
    code: Annotated[str | None, Form()] = None,
    state: Annotated[str | None, Form()] = None,
    error: Annotated[str | None, Form()] = None,
    settings: Settings = Depends(get_settings),
    apple: AppleOAuthClient = Depends(get_apple_oauth_client),
) -> RedirectResponse:
    if error:
        return oauth_login_redirect("cancelled")
    return await _complete_apple_callback(
        request=request,
        code=code,
        state=state,
        settings=settings,
        apple=apple,
    )


@router.get("/callback")
async def apple_callback_get(
    request: Request,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    settings: Settings = Depends(get_settings),
    apple: AppleOAuthClient = Depends(get_apple_oauth_client),
) -> RedirectResponse:
    """Fallback for local tests; Apple production uses form_post on POST."""
    if error:
        return oauth_login_redirect("cancelled")
    return await _complete_apple_callback(
        request=request,
        code=code,
        state=state,
        settings=settings,
        apple=apple,
    )


@router.get("/finish")
async def apple_finish(
    request: Request,
    ticket: Annotated[str | None, Query(alias="ticket")] = None,
    settings: Settings = Depends(get_settings),
) -> RedirectResponse:
    if not ticket:
        return oauth_login_redirect("invalid_request")

    request_origin = f"{request.url.scheme}://{request.url.netloc}"
    try:
        user = await consume_handoff_ticket(
            ticket_id=ticket,
            request_origin=request_origin,
        )
    except OAuthHandoffError:
        return oauth_login_redirect("invalid_ticket")

    if user.family_id is None:
        return oauth_login_redirect("provider_error")

    return oauth_session_redirect(
        settings=settings,
        user_id=user.username,
        family_id=user.family_id,
        return_origin=request_origin,
        state_cookie_name=settings.oauth_state_cookie_name,
    )
