"""Unit tests for Apple OAuth redirect URI selection."""

from __future__ import annotations

import pytest

from app.config import get_settings
from app.services.apple_oauth_service import (
    apple_callback_url_for_origin,
    canonical_apple_callback_url,
    preview_apple_callback_url,
    registered_apple_callback_urls,
)
from app.services.google_oauth_service import uses_direct_session_on_callback


def test_registered_apple_urls_include_preview_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", "https://happyword-zjumty-2580-terrymas-projects.vercel.app")
    get_settings.cache_clear()
    urls = registered_apple_callback_urls()
    assert canonical_apple_callback_url() in urls
    assert preview_apple_callback_url() in urls


def test_apple_callback_url_for_fixed_preview_origin(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    preview = "https://happyword-zjumty-2580-terrymas-projects.vercel.app"
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", preview)
    get_settings.cache_clear()
    assert apple_callback_url_for_origin(preview) == f"{preview}/v1/oauth/apple/callback"
    assert uses_direct_session_on_callback(preview) is True
