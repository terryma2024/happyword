"""Unit tests for Google OAuth redirect URI selection."""

from __future__ import annotations

import pytest

from app.config import get_settings
from app.services.google_oauth_service import (
    canonical_callback_url,
    google_callback_url_for_origin,
    preview_callback_url,
    registered_google_callback_urls,
    uses_direct_session_on_callback,
)


def test_registered_urls_include_preview_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", "https://happyword-zjumty-2580-terrymas-projects.vercel.app")
    get_settings.cache_clear()
    urls = registered_google_callback_urls()
    assert canonical_callback_url() in urls
    assert preview_callback_url() in urls


def test_callback_url_for_fixed_preview_origin(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    preview = "https://happyword-zjumty-2580-terrymas-projects.vercel.app"
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", preview)
    get_settings.cache_clear()
    assert google_callback_url_for_origin(preview) == f"{preview}/v1/oauth/google/callback"
    assert uses_direct_session_on_callback(preview) is True


def test_random_vercel_preview_uses_canonical_callback(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    preview = "https://happyword-zjumty-2580-terrymas-projects.vercel.app"
    monkeypatch.setenv("OAUTH_PREVIEW_BASE_URL", preview)
    get_settings.cache_clear()
    other = "https://happyword-other.vercel.app"
    assert google_callback_url_for_origin(other) == canonical_callback_url()
    assert uses_direct_session_on_callback(other) is False
