"""Live Tencent COS smoke for the M7 storage switch.

This script intentionally stays outside the default pytest suite because it
uses real COS credentials and writes real objects. It validates the same high
level upload helpers the app uses, checks that the returned public URLs are
readable, then deletes the smoke objects unless COS_SMOKE_KEEP_OBJECTS=1.
"""

from __future__ import annotations

import asyncio
import os
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING

import httpx

from app.services import blob_service
from app.services.storage_provider import current_provider

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable

_REQUIRED_ENV = (
    "COS_SECRET_ID",
    "COS_SECRET_KEY",
    "COS_REGION",
    "COS_BUCKET",
    "COS_PUBLIC_BASE_URL",
)


@dataclass(frozen=True)
class _SmokeCase:
    name: str
    upload: Callable[[], Awaitable[str]]


def _require_cos_env() -> None:
    provider = current_provider()
    if provider != "tencent_cos":
        raise SystemExit(
            "ASSET_STORAGE_PROVIDER must be set to 'tencent_cos' for this live smoke "
            f"(got {provider!r})."
        )
    missing = [name for name in _REQUIRED_ENV if not os.environ.get(name, "").strip()]
    if missing:
        raise SystemExit(f"Missing required COS env vars: {', '.join(missing)}")


async def _assert_public_url_readable(url: str) -> None:
    async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
        resp = await client.head(url)
        if resp.status_code == 405:
            resp = await client.get(url)
        resp.raise_for_status()


async def _run() -> None:
    _require_cos_env()

    stamp = str(int(time.time()))
    cases = (
        _SmokeCase(
            "word illustration",
            lambda: blob_service.upload_word_illustration(
                f"m7-smoke-{stamp}",
                b"\x89PNG\r\n\x1a\nm7-smoke",
                "image/png",
            ),
        ),
        _SmokeCase(
            "word audio",
            lambda: blob_service.upload_word_audio(
                f"m7-smoke-{stamp}",
                b"ID3m7-smoke",
                "audio/mpeg",
            ),
        ),
        _SmokeCase(
            "lesson image",
            lambda: blob_service.upload_lesson_image(
                b"\xff\xd8\xff\xe0m7-smoke",
                "image/jpeg",
            ),
        ),
    )

    keep_objects = os.environ.get("COS_SMOKE_KEEP_OBJECTS", "").strip() == "1"
    uploaded: list[tuple[str, str]] = []
    try:
        for case in cases:
            url = await case.upload()
            uploaded.append((case.name, url))
            print(f"{case.name}: {url}")
            await _assert_public_url_readable(url)
            print(f"{case.name}: public URL readable")
    finally:
        if keep_objects:
            print("COS_SMOKE_KEEP_OBJECTS=1; leaving uploaded smoke objects in place.")
        else:
            for name, url in uploaded:
                await blob_service.delete_object(url)
                print(f"{name}: deleted smoke object")


def main() -> None:
    asyncio.run(_run())


if __name__ == "__main__":
    main()
