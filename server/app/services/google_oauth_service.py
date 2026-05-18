"""Google OAuth2 authorization code + OpenID id_token verification."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol
from urllib.parse import urlencode

import httpx
from jose import jwt
from jose.exceptions import JWTError

from app.config import Settings, get_settings
from app.services.oauth_login_service import GoogleUserClaims, OAuthUserClaims
from app.services.oauth_redirect_urls import (
    callback_url_for_origin as _callback_url_for_origin,
)
from app.services.oauth_redirect_urls import (
    canonical_callback_url as _canonical_callback_url,
)
from app.services.oauth_redirect_urls import (
    preview_callback_url as _preview_callback_url,
)
from app.services.oauth_redirect_urls import (
    registered_callback_urls as _registered_callback_urls,
)
from app.services.oauth_redirect_urls import (
    uses_direct_session_on_callback as _uses_direct_session_on_callback,
)

_GOOGLE_PROVIDER = "google"

_GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
_GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
_GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
_GOOGLE_ISSUERS = frozenset({"accounts.google.com", "https://accounts.google.com"})


@dataclass(frozen=True)
class GoogleTokenResponse:
    id_token: str
    access_token: str | None = None


class GoogleOAuthClient(Protocol):
    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str: ...

    async def exchange_code(self, code: str, *, redirect_uri: str) -> GoogleTokenResponse: ...

    async def verify_id_token(self, id_token: str) -> GoogleUserClaims: ...


class GoogleOAuthClientImpl:
    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()

    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
        params = {
            "client_id": self._settings.google_oauth_client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": "openid email profile",
            "state": state,
            "prompt": "select_account",
            "access_type": "online",
        }
        return f"{_GOOGLE_AUTH_URL}?{urlencode(params)}"

    async def exchange_code(self, code: str, *, redirect_uri: str) -> GoogleTokenResponse:
        data = {
            "code": code,
            "client_id": self._settings.google_oauth_client_id,
            "client_secret": self._settings.google_oauth_client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(_GOOGLE_TOKEN_URL, data=data)
        if response.status_code != 200:
            msg = f"Google token exchange failed: HTTP {response.status_code}"
            raise ValueError(msg)
        payload = response.json()
        id_token = payload.get("id_token")
        if not isinstance(id_token, str):
            msg = "Google token response missing id_token"
            raise ValueError(msg)
        access_token = payload.get("access_token")
        return GoogleTokenResponse(
            id_token=id_token,
            access_token=access_token if isinstance(access_token, str) else None,
        )

    async def verify_id_token(self, id_token: str) -> GoogleUserClaims:
        jwks = await self._fetch_jwks()
        try:
            claims: dict[str, object] = jwt.decode(
                id_token,
                jwks,
                algorithms=["RS256"],
                audience=self._settings.google_oauth_client_id,
                options={"verify_at_hash": False},
            )
        except JWTError as exc:
            msg = "Google id_token verification failed"
            raise ValueError(msg) from exc

        issuer = claims.get("iss")
        if issuer not in _GOOGLE_ISSUERS:
            msg = "Google id_token issuer mismatch"
            raise ValueError(msg)

        subject = claims.get("sub")
        email = claims.get("email")
        email_verified = claims.get("email_verified")
        if not isinstance(subject, str) or not subject:
            msg = "Google id_token missing sub"
            raise ValueError(msg)
        if not isinstance(email, str) or not email:
            msg = "Google id_token missing email"
            raise ValueError(msg)
        if email_verified is not True:
            msg = "Google account email not verified"
            raise ValueError(msg)

        return OAuthUserClaims(
            subject=subject,
            email=email,
            email_verified=True,
        )

    async def _fetch_jwks(self) -> dict[str, object]:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(_GOOGLE_JWKS_URL)
        if response.status_code != 200:
            msg = f"Google JWKS fetch failed: HTTP {response.status_code}"
            raise ValueError(msg)
        payload = response.json()
        if not isinstance(payload, dict):
            msg = "Google JWKS payload malformed"
            raise ValueError(msg)
        return payload


def canonical_callback_url(settings: Settings | None = None) -> str:
    return _canonical_callback_url(_GOOGLE_PROVIDER, settings)


def preview_callback_url(settings: Settings | None = None) -> str | None:
    return _preview_callback_url(_GOOGLE_PROVIDER, settings)


def google_callback_url_for_origin(origin: str, settings: Settings | None = None) -> str:
    return _callback_url_for_origin(_GOOGLE_PROVIDER, origin, settings)


def registered_google_callback_urls(settings: Settings | None = None) -> frozenset[str]:
    return _registered_callback_urls(_GOOGLE_PROVIDER, settings)


def uses_direct_session_on_callback(
    origin: str,
    settings: Settings | None = None,
) -> bool:
    return _uses_direct_session_on_callback(origin, settings)


def get_google_oauth_client() -> GoogleOAuthClient:
    return GoogleOAuthClientImpl()
