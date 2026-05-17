"""Alipay website OAuth login."""

from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol
from urllib.parse import urlencode

import httpx
from cryptography.exceptions import InvalidSignature
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
    subject: str


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
        _verify_alipay_response_signature(
            response.text,
            response_key="alipay_system_oauth_token_response",
            public_key_pem=self._settings.alipay_oauth_public_key,
        )
        payload = response.json()
        body = payload.get("alipay_system_oauth_token_response")
        if not isinstance(body, dict):
            msg = "Alipay token response malformed"
            raise ValueError(msg)
        if body.get("code") and body.get("code") != "10000":
            msg = f"Alipay token exchange failed: {body.get('sub_code') or body.get('code')}"
            raise ValueError(msg)
        subject = _alipay_subject_from_token_body(body)
        if subject is None:
            keys = ",".join(sorted(str(key) for key in body))
            msg = f"Alipay token response missing user identifier; keys={keys}"
            raise ValueError(msg)
        return AlipayTokenResponse(subject=subject)

    async def fetch_identity(self, tokens: AlipayTokenResponse) -> AlipayIdentity:
        return AlipayIdentity(subject=tokens.subject)


def _alipay_subject_from_token_body(body: dict[str, object]) -> str | None:
    for key in ("user_id", "open_id", "alipay_user_id"):
        value = body.get(key)
        if isinstance(value, str) and value.strip():
            return value
    return None


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


def _normalize_public_key(value: str) -> str:
    stripped = value.replace("\\n", "\n").strip()
    if "BEGIN" in stripped:
        return stripped
    return f"-----BEGIN PUBLIC KEY-----\n{stripped}\n-----END PUBLIC KEY-----"


def _verify_alipay_response_signature(
    response_text: str,
    *,
    response_key: str,
    public_key_pem: str,
) -> None:
    sign = _extract_json_string_field(response_text, "sign")
    signed_body = _extract_json_object_field(response_text, response_key)
    if not sign or not signed_body:
        msg = "Alipay response missing signed payload/signature"
        raise ValueError(msg)
    public_key = serialization.load_pem_public_key(
        _normalize_public_key(public_key_pem).encode("utf-8"),
    )
    try:
        signature = base64.b64decode(sign, validate=True)
        public_key.verify(
            signature,
            signed_body.encode("utf-8"),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
    except (binascii.Error, InvalidSignature) as exc:
        msg = "Alipay response signature invalid"
        raise ValueError(msg) from exc


def _extract_json_string_field(response_text: str, key: str) -> str | None:
    marker = f'"{key}"'
    marker_index = response_text.find(marker)
    if marker_index < 0:
        return None
    colon_index = response_text.find(":", marker_index + len(marker))
    if colon_index < 0:
        return None
    value_start = response_text.find('"', colon_index + 1)
    if value_start < 0:
        return None
    value_end = _find_json_string_end(response_text, value_start)
    if value_end is None:
        return None
    return response_text[value_start + 1 : value_end]


def _extract_json_object_field(response_text: str, key: str) -> str | None:
    marker = f'"{key}"'
    marker_index = response_text.find(marker)
    if marker_index < 0:
        return None
    colon_index = response_text.find(":", marker_index + len(marker))
    if colon_index < 0:
        return None
    object_start = response_text.find("{", colon_index + 1)
    if object_start < 0:
        return None
    object_end = _find_json_object_end(response_text, object_start)
    if object_end is None:
        return None
    return response_text[object_start : object_end + 1]


def _find_json_string_end(text: str, start: int) -> int | None:
    escaped = False
    for index in range(start + 1, len(text)):
        char = text[index]
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            return index
    return None


def _find_json_object_end(text: str, start: int) -> int | None:
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
    return None


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
