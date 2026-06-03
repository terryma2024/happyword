"""Google OAuth client URL builder tests."""

from __future__ import annotations

import pytest
import httpx

from app.config import get_settings
from app.services import google_oauth_service
from app.services.google_oauth_service import GoogleOAuthClientImpl, canonical_callback_url


def test_build_authorize_url_contains_client_id_and_state(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "test-client-id")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "test-secret")
    get_settings.cache_clear()
    client = GoogleOAuthClientImpl()
    url = client.build_authorize_url(
        state="state-token-abc",
        redirect_uri=canonical_callback_url(),
    )
    assert "accounts.google.com" in url
    assert "client_id=test-client-id" in url
    assert "state=state-token-abc" in url
    assert "prompt=select_account" in url


def test_canonical_callback_url() -> None:
    assert canonical_callback_url().endswith("/v1/oauth/google/callback")


@pytest.mark.asyncio
async def test_exchange_code_wraps_network_errors(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class TimeoutClient:
        def __init__(self, *, timeout: float) -> None:
            _ = timeout

        async def __aenter__(self) -> "TimeoutClient":
            return self

        async def __aexit__(self, *args: object) -> None:
            _ = args

        async def post(self, url: str, *, data: dict[str, str]) -> httpx.Response:
            _ = url, data
            raise httpx.ConnectTimeout("connect timed out")

    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "test-client-id")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "test-secret")
    monkeypatch.setattr(google_oauth_service.httpx, "AsyncClient", TimeoutClient)
    get_settings.cache_clear()

    client = GoogleOAuthClientImpl()
    with pytest.raises(ValueError, match="Google token exchange request failed"):
        await client.exchange_code("auth-code", redirect_uri=canonical_callback_url())
