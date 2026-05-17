"""Sign in with Apple — authorization code + id_token verification."""

from __future__ import annotations

import time
from dataclasses import dataclass
from functools import lru_cache
from typing import Protocol
from urllib.parse import urlencode

import httpx
from cryptography.hazmat.primitives import serialization
from jose import jwt
from jose.exceptions import JWTError

from app.config import Settings, get_settings
from app.services.oauth_login_service import OAuthUserClaims
from app.services.oauth_redirect_urls import (
    callback_url_for_origin,
    canonical_callback_url,
    preview_callback_url,
    registered_callback_urls,
)

_APPLE_PROVIDER = "apple"
_APPLE_AUTH_URL = "https://appleid.apple.com/auth/authorize"
_APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"
_APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
_APPLE_ISSUER = "https://appleid.apple.com"


@dataclass(frozen=True)
class AppleTokenResponse:
    id_token: str
    access_token: str | None = None


class AppleOAuthClient(Protocol):
    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str: ...

    async def exchange_code(self, code: str, *, redirect_uri: str) -> AppleTokenResponse: ...

    async def verify_id_token(self, id_token: str) -> OAuthUserClaims: ...


class AppleOAuthClientImpl:
    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()

    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
        params = {
            "client_id": self._settings.apple_oauth_client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "response_mode": "form_post",
            "scope": "name email",
            "state": state,
        }
        return f"{_APPLE_AUTH_URL}?{urlencode(params)}"

    async def exchange_code(self, code: str, *, redirect_uri: str) -> AppleTokenResponse:
        client_secret = generate_apple_client_secret(self._settings)
        data = {
            "client_id": self._settings.apple_oauth_client_id,
            "client_secret": client_secret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirect_uri,
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(_APPLE_TOKEN_URL, data=data)
        if response.status_code != 200:
            msg = f"Apple token exchange failed: HTTP {response.status_code}"
            raise ValueError(msg)
        payload = response.json()
        id_token = payload.get("id_token")
        if not isinstance(id_token, str):
            msg = "Apple token response missing id_token"
            raise ValueError(msg)
        access_token = payload.get("access_token")
        return AppleTokenResponse(
            id_token=id_token,
            access_token=access_token if isinstance(access_token, str) else None,
        )

    async def verify_id_token(self, id_token: str) -> OAuthUserClaims:
        jwks = await _fetch_jwks()
        try:
            claims: dict[str, object] = jwt.decode(
                id_token,
                jwks,
                algorithms=["RS256"],
                audience=self._settings.apple_oauth_client_id,
                issuer=_APPLE_ISSUER,
                options={"verify_at_hash": False},
            )
        except JWTError as exc:
            msg = "Apple id_token verification failed"
            raise ValueError(msg) from exc

        subject = claims.get("sub")
        if not isinstance(subject, str) or not subject:
            msg = "Apple id_token missing sub"
            raise ValueError(msg)

        email: str | None = None
        email_verified = False
        raw_email = claims.get("email")
        if isinstance(raw_email, str) and raw_email.strip():
            email = raw_email.strip().lower()
            email_verified = claims.get("email_verified") in (True, "true")

        return OAuthUserClaims(
            subject=subject,
            email=email,
            email_verified=email_verified,
        )


@lru_cache(maxsize=4)
def _load_private_key(pem: str) -> object:
    return serialization.load_pem_private_key(pem.encode("utf-8"), password=None)


def generate_apple_client_secret(settings: Settings | None = None) -> str:
    """Apple client_secret is a short-lived ES256 JWT signed with the .p8 key."""
    settings = settings or get_settings()
    private_key = _load_private_key(settings.apple_oauth_private_key)
    now = int(time.time())
    headers = {"kid": settings.apple_oauth_key_id, "alg": "ES256"}
    payload = {
        "iss": settings.apple_oauth_team_id,
        "iat": now,
        "exp": now + 3600,
        "aud": _APPLE_ISSUER,
        "sub": settings.apple_oauth_client_id,
    }
    encoded: str = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    return encoded


async def _fetch_jwks() -> dict[str, object]:
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(_APPLE_JWKS_URL)
    if response.status_code != 200:
        msg = f"Apple JWKS fetch failed: HTTP {response.status_code}"
        raise ValueError(msg)
    payload = response.json()
    if not isinstance(payload, dict):
        msg = "Apple JWKS payload malformed"
        raise ValueError(msg)
    return payload


def apple_callback_url_for_origin(origin: str, settings: Settings | None = None) -> str:
    return callback_url_for_origin(_APPLE_PROVIDER, origin, settings)


def registered_apple_callback_urls(settings: Settings | None = None) -> frozenset[str]:
    return registered_callback_urls(_APPLE_PROVIDER, settings)


def canonical_apple_callback_url(settings: Settings | None = None) -> str:
    return canonical_callback_url(_APPLE_PROVIDER, settings)


def preview_apple_callback_url(settings: Settings | None = None) -> str | None:
    return preview_callback_url(_APPLE_PROVIDER, settings)


def get_apple_oauth_client() -> AppleOAuthClient:
    return AppleOAuthClientImpl()
