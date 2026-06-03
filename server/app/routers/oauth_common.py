"""Shared helpers for /v1/oauth/{provider} routers."""

from __future__ import annotations

from typing import TYPE_CHECKING
from urllib.parse import urlencode

from fastapi import status
from fastapi.responses import RedirectResponse

from app.models.oauth_identity import OAuthProvider
from app.services.auth_service import create_session_token

if TYPE_CHECKING:
    from app.config import Settings


def oauth_login_redirect(
    oauth_error: str,
    *,
    provider: OAuthProvider | str | None = None,
) -> RedirectResponse:
    params = {"oauth_error": oauth_error}
    if provider:
        params["oauth_provider"] = (
            provider.value if isinstance(provider, OAuthProvider) else provider
        )
    return RedirectResponse(
        url=f"/family/login?{urlencode(params)}",
        status_code=status.HTTP_302_FOUND,
    )


def oauth_dashboard_redirect(family_id: str) -> RedirectResponse:
    return RedirectResponse(
        url=f"/family/{family_id}/",
        status_code=status.HTTP_302_FOUND,
    )


def oauth_session_redirect(
    *,
    settings: Settings,
    user_id: str,
    family_id: str,
    return_origin: str,
    state_cookie_name: str,
) -> RedirectResponse:
    token = create_session_token(role="parent", identifier=user_id)
    redirect = oauth_dashboard_redirect(family_id)
    redirect.delete_cookie(key=state_cookie_name, path="/")
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
