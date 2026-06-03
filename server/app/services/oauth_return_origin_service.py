"""Allowlist for OAuth `return_origin` (production hop + preview handoff)."""

from __future__ import annotations

import json
import time
from urllib.parse import quote
from urllib.parse import urlparse

import httpx

from app.config import Settings, get_settings

_MANIFEST_CACHE: tuple[float, set[str]] | None = None
_MANIFEST_CACHE_TTL_SECONDS = 60


class InvalidOriginError(ValueError):
    """Raised when return_origin fails allowlist checks."""


def normalize_origin(value: str) -> str:
    """Return scheme://host[:port] only; reject paths, queries, or missing host."""
    parsed = urlparse(value.strip())
    if not parsed.scheme or not parsed.netloc:
        msg = "return_origin must be an absolute origin (scheme + host)"
        raise InvalidOriginError(msg)
    return f"{parsed.scheme}://{parsed.netloc}"


def canonical_origin(settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    return normalize_origin(settings.oauth_canonical_base_url)


def google_oauth_enabled(settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    return settings.google_oauth_configured()


def apple_oauth_enabled(settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    return settings.apple_oauth_configured()


def wechat_oauth_enabled(settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    return settings.wechat_oauth_configured()


def alipay_oauth_enabled(settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    return settings.alipay_oauth_configured()


def _local_origins(settings: Settings) -> set[str]:
    return {
        normalize_origin(part)
        for part in settings.oauth_local_origins.split(",")
        if part.strip()
    }


def _host_allowed_by_suffix(host: str) -> bool:
    return host == "vercel.app" or host.endswith(".vercel.app")


async def _manifest_origins(settings: Settings) -> set[str]:
    global _MANIFEST_CACHE  # noqa: PLW0603
    now = time.monotonic()
    if _MANIFEST_CACHE is not None:
        cached_at, cached = _MANIFEST_CACHE
        if now - cached_at < _MANIFEST_CACHE_TTL_SECONDS:
            return cached

    url = f"{settings.oauth_canonical_base_url.rstrip('/')}/api/v1/public/preview-urls.json"
    origins: set[str] = set()
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url)
        if response.status_code == 200:
            payload = response.json()
            origins |= _origins_from_manifest_payload(payload)
    except (httpx.HTTPError, json.JSONDecodeError, TypeError, InvalidOriginError):
        origins = set()

    _MANIFEST_CACHE = (now, origins)
    return origins


def _origins_from_manifest_payload(payload: object) -> set[str]:
    origins: set[str] = set()
    if isinstance(payload, dict):
        deployments = payload.get("deployments")
        if isinstance(deployments, list):
            for item in deployments:
                if isinstance(item, dict):
                    url = item.get("url") or item.get("deployment_url")
                    if isinstance(url, str):
                        origins.add(normalize_origin(url))
                elif isinstance(item, str):
                    origins.add(normalize_origin(item))
        for key in ("urls", "previews"):
            values = payload.get(key)
            if isinstance(values, list):
                for value in values:
                    if isinstance(value, str):
                        origins.add(normalize_origin(value))
    return origins


async def is_allowed_origin(origin: str, settings: Settings | None = None) -> bool:
    settings = settings or get_settings()
    try:
        normalized = normalize_origin(origin)
    except InvalidOriginError:
        return False

    if normalized == canonical_origin(settings):
        return True
    if normalized in _local_origins(settings):
        return True
    host = urlparse(normalized).hostname or ""
    if _host_allowed_by_suffix(host):
        return True
    return normalized in await _manifest_origins(settings)


async def require_allowed_origin(origin: str, settings: Settings | None = None) -> str:
    normalized = normalize_origin(origin)
    if not await is_allowed_origin(normalized, settings):
        raise InvalidOriginError(f"return_origin not allowed: {normalized}")
    return normalized


def build_oauth_start_url(
    provider: str,
    *,
    request_base_url: str,  # noqa: ARG001 — kept for call-site stability
    settings: Settings | None = None,
) -> str:
    """Same-origin OAuth start on the host serving /family/login."""
    settings = settings or get_settings()
    if provider == "google" and not settings.google_oauth_configured():
        return ""
    if provider == "apple" and not settings.apple_oauth_configured():
        return ""
    if provider == "wechat" and not settings.wechat_oauth_configured():
        return ""
    if provider == "alipay" and not settings.alipay_oauth_configured():
        return ""
    return_origin = quote(canonical_origin(settings), safe="")
    return f"/v1/oauth/{provider}/start?return_origin={return_origin}"


def build_google_start_url(
    request_base_url: str,  # noqa: ARG001
    settings: Settings | None = None,
) -> str:
    return build_oauth_start_url("google", request_base_url=request_base_url, settings=settings)


def build_apple_start_url(
    request_base_url: str,  # noqa: ARG001
    settings: Settings | None = None,
) -> str:
    return build_oauth_start_url("apple", request_base_url=request_base_url, settings=settings)


def build_wechat_start_url(
    request_base_url: str,  # noqa: ARG001
    settings: Settings | None = None,
) -> str:
    return build_oauth_start_url("wechat", request_base_url=request_base_url, settings=settings)


def build_alipay_start_url(
    request_base_url: str,  # noqa: ARG001
    settings: Settings | None = None,
) -> str:
    return build_oauth_start_url("alipay", request_base_url=request_base_url, settings=settings)


def clear_manifest_cache_for_tests() -> None:
    global _MANIFEST_CACHE  # noqa: PLW0603
    _MANIFEST_CACHE = None
