"""Google OAuth client URL builder tests."""

from __future__ import annotations

import pytest

from app.config import get_settings
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
