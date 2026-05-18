"""Per-provider OAuth redirect URI selection (Google, Apple, …)."""

from __future__ import annotations

from app.config import Settings, get_settings
from app.services.oauth_return_origin_service import (
    InvalidOriginError,
    canonical_origin,
    normalize_origin,
)


def callback_path(provider: str) -> str:
    return f"/v1/oauth/{provider}/callback"


def finish_path(provider: str) -> str:
    return f"/v1/oauth/{provider}/finish"


def canonical_callback_url(provider: str, settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    return f"{settings.oauth_canonical_base_url.rstrip('/')}{callback_path(provider)}"


def preview_callback_url(provider: str, settings: Settings | None = None) -> str | None:
    settings = settings or get_settings()
    raw = settings.oauth_preview_base_url.strip()
    if not raw:
        return None
    return f"{normalize_origin(raw)}{callback_path(provider)}"


def callback_url_for_origin(
    provider: str,
    origin: str,
    settings: Settings | None = None,
) -> str:
    settings = settings or get_settings()
    normalized = normalize_origin(origin)
    if normalized == canonical_origin(settings):
        return canonical_callback_url(provider, settings)
    preview = settings.oauth_preview_base_url.strip()
    if preview:
        preview_origin = normalize_origin(preview)
        if normalized == preview_origin:
            url = preview_callback_url(provider, settings)
            if url is None:
                raise InvalidOriginError("preview OAuth base URL is not configured")
            return url
    return canonical_callback_url(provider, settings)


def registered_callback_urls(provider: str, settings: Settings | None = None) -> frozenset[str]:
    settings = settings or get_settings()
    urls = {canonical_callback_url(provider, settings)}
    preview_url = preview_callback_url(provider, settings)
    if preview_url is not None:
        urls.add(preview_url)
    return frozenset(urls)


def uses_direct_session_on_callback(
    origin: str,
    settings: Settings | None = None,
) -> bool:
    settings = settings or get_settings()
    normalized = normalize_origin(origin)
    if normalized == canonical_origin(settings):
        return True
    preview = settings.oauth_preview_base_url.strip()
    if not preview:
        return False
    return normalized == normalize_origin(preview)
