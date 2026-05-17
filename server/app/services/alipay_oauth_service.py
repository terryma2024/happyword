"""Alipay website OAuth login."""

from __future__ import annotations

import base64
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol
from urllib.parse import urlencode

import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

from app.config import Settings, get_settings
from app.services.oauth_redirect_urls import (
    callback_url_for_origin,
    canonical_callback_url,
    preview_callback_url,
    registered_callback_urls,
)

_ALIPAY_PROVIDER = "alipay"
_ALIPAY_AUTH_URL = "https://openauth.alipay.com/oauth2/publicAppAuthorize.htm"
_ALIPAY_GATEWAY_URL = "https://openapi.alipay.com/gateway.do"


@dataclass(frozen=True)
class AlipayTokenResponse:
    access_token: str
    user_id: str


@dataclass(frozen=True)
class AlipayIdentity:
    subject: str


class AlipayOAuthClient(Protocol):
    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str: ...

    async def exchange_code(self, code: str) -> AlipayTokenResponse: ...

    async def fetch_identity(self, tokens: AlipayTokenResponse) -> AlipayIdentity: ...


class AlipayOAuthClientImpl:
    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()

    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
        params = {
            "app_id": self._settings.alipay_oauth_app_id,
            "scope": "auth_user",
            "redirect_uri": redirect_uri,
            "state": state,
        }
        return f"{_ALIPAY_AUTH_URL}?{urlencode(params)}"

    async def exchange_code(self, code: str) -> AlipayTokenResponse:
        params = {
            "app_id": self._settings.alipay_oauth_app_id,
            "method": "alipay.system.oauth.token",
            "format": "JSON",
            "charset": "utf-8",
            "sign_type": "RSA2",
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "version": "1.0",
            "grant_type": "authorization_code",
            "code": code,
        }
        params["sign"] = _sign_params(params, self._settings.alipay_oauth_app_private_key)
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(_ALIPAY_GATEWAY_URL, params=params)
        if response.status_code != 200:
            msg = f"Alipay token exchange failed: HTTP {response.status_code}"
            raise ValueError(msg)
        payload = response.json()
        body = payload.get("alipay_system_oauth_token_response")
        if not isinstance(body, dict):
            msg = "Alipay token response malformed"
            raise ValueError(msg)
        if body.get("code") and body.get("code") != "10000":
            msg = f"Alipay token exchange failed: {body.get('sub_code') or body.get('code')}"
            raise ValueError(msg)
        access_token = body.get("access_token")
        user_id = body.get("user_id")
        if not isinstance(access_token, str) or not isinstance(user_id, str):
            msg = "Alipay token response missing access_token/user_id"
            raise ValueError(msg)
        return AlipayTokenResponse(access_token=access_token, user_id=user_id)

    async def fetch_identity(self, tokens: AlipayTokenResponse) -> AlipayIdentity:
        return AlipayIdentity(subject=tokens.user_id)


def _sign_params(params: dict[str, str], private_key_pem: str) -> str:
    unsigned = "&".join(
        f"{key}={value}"
        for key, value in sorted(params.items())
        if key != "sign" and value != ""
    )
    private_key = serialization.load_pem_private_key(
        _normalize_private_key(private_key_pem).encode("utf-8"),
        password=None,
    )
    signature = private_key.sign(
        unsigned.encode("utf-8"),
        padding.PKCS1v15(),
        hashes.SHA256(),
    )
    return base64.b64encode(signature).decode("ascii")


def _normalize_private_key(value: str) -> str:
    stripped = value.replace("\\n", "\n").strip()
    if "BEGIN" in stripped:
        return stripped
    return f"-----BEGIN PRIVATE KEY-----\n{stripped}\n-----END PRIVATE KEY-----"


def alipay_callback_url_for_origin(origin: str, settings: Settings | None = None) -> str:
    return callback_url_for_origin(_ALIPAY_PROVIDER, origin, settings)


def registered_alipay_callback_urls(settings: Settings | None = None) -> frozenset[str]:
    return registered_callback_urls(_ALIPAY_PROVIDER, settings)


def canonical_alipay_callback_url(settings: Settings | None = None) -> str:
    return canonical_callback_url(_ALIPAY_PROVIDER, settings)


def preview_alipay_callback_url(settings: Settings | None = None) -> str | None:
    return preview_callback_url(_ALIPAY_PROVIDER, settings)


def get_alipay_oauth_client() -> AlipayOAuthClient:
    return AlipayOAuthClientImpl()
