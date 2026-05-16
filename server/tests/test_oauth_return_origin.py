"""Unit tests for OAuth return_origin allowlist."""

from __future__ import annotations

import pytest

from app.config import get_settings
from app.services.oauth_return_origin_service import (
    InvalidOriginError,
    build_google_start_url,
    clear_manifest_cache_for_tests,
    is_allowed_origin,
    normalize_origin,
)


@pytest.mark.asyncio
async def test_allows_canonical_production_origin(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "https://happyword.cool")
    get_settings.cache_clear()
    assert await is_allowed_origin("https://happyword.cool") is True


@pytest.mark.asyncio
async def test_allows_local_origins(monkeypatch: pytest.MonkeyPatch) -> None:
    get_settings.cache_clear()
    assert await is_allowed_origin("http://127.0.0.1:8000") is True


@pytest.mark.asyncio
async def test_allows_vercel_app_suffix() -> None:
    assert await is_allowed_origin("https://happyword-git-abc.vercel.app") is True


@pytest.mark.asyncio
async def test_rejects_unknown_origin() -> None:
    clear_manifest_cache_for_tests()
    assert await is_allowed_origin("https://evil.example") is False


def test_normalize_origin_strips_path() -> None:
    assert normalize_origin("https://foo.vercel.app/some/path") == "https://foo.vercel.app"


def test_normalize_origin_rejects_relative() -> None:
    with pytest.raises(InvalidOriginError):
        normalize_origin("/family/login")


def test_build_google_start_url_relative_on_canonical(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "cid")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "secret")
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "https://happyword.cool")
    get_settings.cache_clear()
    url = build_google_start_url("https://happyword.cool/family/login")
    assert url == "/v1/oauth/google/start"


def test_build_google_start_url_relative_on_preview(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "cid")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_SECRET", "secret")
    monkeypatch.setenv("OAUTH_CANONICAL_BASE_URL", "https://happyword.cool")
    get_settings.cache_clear()
    url = build_google_start_url("https://branch-preview.vercel.app")
    assert url == "/v1/oauth/google/start"
