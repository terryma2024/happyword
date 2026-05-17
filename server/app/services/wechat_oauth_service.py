"""WeChat website OAuth login."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol
from urllib.parse import urlencode

import httpx

from app.config import Settings, get_settings
from app.services.oauth_redirect_urls import (
    callback_url_for_origin,
    canonical_callback_url,
    preview_callback_url,
    registered_callback_urls,
)

_WECHAT_PROVIDER = "wechat"
_WECHAT_AUTH_URL = "https://open.weixin.qq.com/connect/qrconnect"
_WECHAT_TOKEN_URL = "https://api.weixin.qq.com/sns/oauth2/access_token"


@dataclass(frozen=True)
class WeChatTokenResponse:
    access_token: str
    openid: str
    unionid: str | None = None


@dataclass(frozen=True)
class WeChatIdentity:
    subject: str


class WeChatOAuthClient(Protocol):
    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str: ...

    async def exchange_code(self, code: str) -> WeChatTokenResponse: ...

    async def fetch_identity(self, tokens: WeChatTokenResponse) -> WeChatIdentity: ...


class WeChatOAuthClientImpl:
    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()

    def build_authorize_url(self, *, state: str, redirect_uri: str) -> str:
        params = {
            "appid": self._settings.wechat_oauth_app_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": "snsapi_login",
            "state": state,
        }
        return f"{_WECHAT_AUTH_URL}?{urlencode(params)}#wechat_redirect"

    async def exchange_code(self, code: str) -> WeChatTokenResponse:
        params = {
            "appid": self._settings.wechat_oauth_app_id,
            "secret": self._settings.wechat_oauth_app_secret,
            "code": code,
            "grant_type": "authorization_code",
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(_WECHAT_TOKEN_URL, params=params)
        if response.status_code != 200:
            msg = f"WeChat token exchange failed: HTTP {response.status_code}"
            raise ValueError(msg)
        payload = response.json()
        if "errcode" in payload:
            msg = f"WeChat token exchange failed: {payload.get('errcode')}"
            raise ValueError(msg)
        access_token = payload.get("access_token")
        openid = payload.get("openid")
        unionid = payload.get("unionid")
        if not isinstance(access_token, str) or not isinstance(openid, str):
            msg = "WeChat token response missing access_token/openid"
            raise ValueError(msg)
        return WeChatTokenResponse(
            access_token=access_token,
            openid=openid,
            unionid=unionid if isinstance(unionid, str) and unionid else None,
        )

    async def fetch_identity(self, tokens: WeChatTokenResponse) -> WeChatIdentity:
        return WeChatIdentity(subject=tokens.unionid or tokens.openid)


def wechat_callback_url_for_origin(origin: str, settings: Settings | None = None) -> str:
    return callback_url_for_origin(_WECHAT_PROVIDER, origin, settings)


def registered_wechat_callback_urls(settings: Settings | None = None) -> frozenset[str]:
    return registered_callback_urls(_WECHAT_PROVIDER, settings)


def canonical_wechat_callback_url(settings: Settings | None = None) -> str:
    return canonical_callback_url(_WECHAT_PROVIDER, settings)


def preview_wechat_callback_url(settings: Settings | None = None) -> str | None:
    return preview_callback_url(_WECHAT_PROVIDER, settings)


def get_wechat_oauth_client() -> WeChatOAuthClient:
    return WeChatOAuthClientImpl()
