"""WeChat OAuth for parent web shell: /v1/oauth/wechat/*."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import RedirectResponse

from app.config import Settings, get_settings
from app.models.oauth_identity import OAuthProvider
from app.routers.oauth_common import (
    oauth_login_redirect as _oauth_login_redirect,
)
from app.routers.oauth_common import (
    oauth_session_redirect,
)
from app.services.family_service import ParentLoginSuspended
from app.services.oauth_handoff_service import create_handoff_ticket
from app.services.oauth_login_service import resolve_existing_oauth_login
from app.services.oauth_pending_identity_service import create_pending_identity
from app.services.oauth_redirect_urls import uses_direct_session_on_callback
from app.services.oauth_return_origin_service import (
    InvalidOriginError,
    canonical_origin,
    require_allowed_origin,
)
from app.services.oauth_state_service import OAuthStateError, issue_state, verify_state
from app.services.wechat_oauth_service import (
    WeChatOAuthClient,
    get_wechat_oauth_client,
    registered_wechat_callback_urls,
    wechat_callback_url_for_origin,
)

router = APIRouter(prefix="/v1/oauth/wechat", tags=["oauth-wechat"])


def oauth_login_redirect(oauth_error: str) -> RedirectResponse:
    return _oauth_login_redirect(oauth_error, provider=OAuthProvider.WECHAT)


@router.get("/start")
async def wechat_start(
    request: Request,
    return_origin: str | None = None,
    settings: Settings = Depends(get_settings),
    wechat: WeChatOAuthClient = Depends(get_wechat_oauth_client),
) -> RedirectResponse:
    if not settings.wechat_oauth_configured():
        return RedirectResponse(url="/family/login", status_code=status.HTTP_302_FOUND)

    origin = return_origin or str(request.base_url).rstrip("/")
    try:
        allowed_origin = await require_allowed_origin(origin, settings)
        redirect_uri = wechat_callback_url_for_origin(allowed_origin, settings)
    except InvalidOriginError:
        return oauth_login_redirect("invalid_origin")

    state = issue_state(
        return_origin=allowed_origin,
        provider=OAuthProvider.WECHAT.value,
        redirect_uri=redirect_uri,
    )
    location = wechat.build_authorize_url(state=state, redirect_uri=redirect_uri)
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
async def wechat_callback(
    request: Request,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    settings: Settings = Depends(get_settings),
    wechat: WeChatOAuthClient = Depends(get_wechat_oauth_client),
) -> RedirectResponse:
    if error:
        return oauth_login_redirect("cancelled")
    if not code or not state:
        return oauth_login_redirect("invalid_request")
    if request.cookies.get(settings.oauth_state_cookie_name) != state:
        return oauth_login_redirect("invalid_state")

    try:
        payload = verify_state(state)
    except OAuthStateError:
        return oauth_login_redirect("invalid_state")

    return_origin = payload.get("return_origin", canonical_origin(settings))
    redirect_uri = payload.get("redirect_uri", "")
    if redirect_uri not in registered_wechat_callback_urls(settings):
        return oauth_login_redirect("invalid_state")

    try:
        allowed_origin = await require_allowed_origin(return_origin, settings)
        tokens = await wechat.exchange_code(code)
        identity = await wechat.fetch_identity(tokens)
        existing = await resolve_existing_oauth_login(OAuthProvider.WECHAT, identity.subject)
    except InvalidOriginError:
        return oauth_login_redirect("invalid_origin")
    except ParentLoginSuspended:
        return oauth_login_redirect("suspended")
    except ValueError:
        return oauth_login_redirect("provider_error")

    if existing is not None:
        user, family = existing
        if uses_direct_session_on_callback(allowed_origin, settings):
            return oauth_session_redirect(
                settings=settings,
                user_id=user.username,
                family_id=family.family_id,
                return_origin=allowed_origin,
                state_cookie_name=settings.oauth_state_cookie_name,
            )
        ticket_id = await create_handoff_ticket(user_id=user.username, return_origin=allowed_origin)
        redirect = RedirectResponse(
            url=f"{allowed_origin}/v1/oauth/wechat/finish?ticket={ticket_id}",
            status_code=status.HTTP_302_FOUND,
        )
        redirect.delete_cookie(key=settings.oauth_state_cookie_name, path="/")
        return redirect

    ticket = await create_pending_identity(
        provider=OAuthProvider.WECHAT,
        provider_subject=identity.subject,
        return_origin=allowed_origin,
        settings=settings,
    )
    redirect = RedirectResponse(
        url=f"{allowed_origin}/family/oauth/bind-email?ticket={ticket}"
        if allowed_origin != str(request.base_url).rstrip("/")
        else f"/family/oauth/bind-email?ticket={ticket}",
        status_code=status.HTTP_302_FOUND,
    )
    redirect.delete_cookie(key=settings.oauth_state_cookie_name, path="/")
    return redirect


@router.get("/finish")
async def wechat_finish(
    request: Request,
    ticket: Annotated[str | None, Query(alias="ticket")] = None,
    settings: Settings = Depends(get_settings),
) -> RedirectResponse:
    from app.services.oauth_handoff_service import OAuthHandoffError, consume_handoff_ticket

    if not ticket:
        return oauth_login_redirect("invalid_request")
    request_origin = f"{request.url.scheme}://{request.url.netloc}"
    try:
        user = await consume_handoff_ticket(ticket_id=ticket, request_origin=request_origin)
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
