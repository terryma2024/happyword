"""Storage-provider selection for the CloudBase migration."""

import httpx
import pytest


def test_storage_provider_defaults_to_vercel_blob(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("ASSET_STORAGE_PROVIDER", raising=False)

    from app.services.storage_provider import current_provider

    assert current_provider() == "vercel_blob"


def test_storage_provider_accepts_tencent_cos(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASSET_STORAGE_PROVIDER", "tencent_cos")

    from app.services.storage_provider import current_provider

    assert current_provider() == "tencent_cos"


def test_storage_provider_rejects_unknown_value(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASSET_STORAGE_PROVIDER", "mystery_drive")

    from app.services.storage_provider import current_provider

    with pytest.raises(RuntimeError, match="Unsupported ASSET_STORAGE_PROVIDER"):
        current_provider()


def test_cos_config_requires_all_env_vars(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import blob_service

    monkeypatch.setenv("ASSET_STORAGE_PROVIDER", "tencent_cos")
    for name in (
        "COS_SECRET_ID",
        "COS_SECRET_KEY",
        "COS_REGION",
        "COS_BUCKET",
        "COS_PUBLIC_BASE_URL",
    ):
        monkeypatch.delenv(name, raising=False)

    assert blob_service.is_blob_configured() is False

    monkeypatch.setenv("COS_SECRET_ID", "sid")
    monkeypatch.setenv("COS_SECRET_KEY", "skey")
    monkeypatch.setenv("COS_REGION", "ap-guangzhou")
    monkeypatch.setenv("COS_BUCKET", "happyword-assets-staging")
    monkeypatch.setenv("COS_PUBLIC_BASE_URL", "https://assets.example.test")

    assert blob_service.is_blob_configured() is True


@pytest.mark.asyncio
async def test_upload_object_routes_to_cos_when_selected(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import blob_service

    monkeypatch.setenv("ASSET_STORAGE_PROVIDER", "tencent_cos")
    calls: list[tuple[str, bytes, str]] = []

    async def _fake_cos(path: str, payload: bytes, mime: str) -> str:
        calls.append((path, payload, mime))
        return f"https://cos.example.test/{path}"

    monkeypatch.setattr(blob_service, "_upload_cos_object", _fake_cos)

    url = await blob_service.upload_object("illustrations/apple.png", b"image", "image/png")

    assert url == "https://cos.example.test/illustrations/apple.png"
    assert calls == [("illustrations/apple.png", b"image", "image/png")]


@pytest.mark.asyncio
async def test_high_level_upload_paths_stay_deterministic(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import blob_service

    calls: list[tuple[str, bytes, str]] = []

    async def _fake_upload(path: str, payload: bytes, mime: str) -> str:
        calls.append((path, payload, mime))
        return f"https://assets.example.test/{path}"

    monkeypatch.setattr(blob_service, "upload_object", _fake_upload)

    illustration = await blob_service.upload_word_illustration(
        "apple",
        b"image-bytes",
        "image/png",
    )
    audio = await blob_service.upload_word_audio(
        "apple",
        b"audio-bytes",
        "audio/mpeg",
    )
    lesson = await blob_service.upload_lesson_image(
        b"lesson-bytes",
        "image/jpeg",
    )

    image_hash = blob_service.short_hash(b"image-bytes")
    audio_hash = blob_service.short_hash(b"audio-bytes")
    lesson_hash = blob_service.short_hash(b"lesson-bytes")

    assert illustration == f"https://assets.example.test/illustrations/apple-{image_hash}.png"
    assert audio == f"https://assets.example.test/audio/apple-{audio_hash}.mp3"
    assert lesson == f"https://assets.example.test/lessons/{lesson_hash}.jpeg"
    assert calls == [
        (f"illustrations/apple-{image_hash}.png", b"image-bytes", "image/png"),
        (f"audio/apple-{audio_hash}.mp3", b"audio-bytes", "audio/mpeg"),
        (f"lessons/{lesson_hash}.jpeg", b"lesson-bytes", "image/jpeg"),
    ]


@pytest.mark.asyncio
async def test_upload_cos_object_puts_signed_request_and_returns_public_url(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import blob_service

    monkeypatch.setenv("COS_SECRET_ID", "cos-secret-id")
    monkeypatch.setenv("COS_SECRET_KEY", "cos-secret-key")
    monkeypatch.setenv("COS_REGION", "ap-guangzhou")
    monkeypatch.setenv("COS_BUCKET", "happyword-assets-staging")
    monkeypatch.setenv("COS_PUBLIC_BASE_URL", "https://assets.example.test/base")

    requests: list[dict[str, object]] = []

    class _Response:
        def raise_for_status(self) -> None:
            return None

    class _Client:
        def __init__(self, *, timeout: float) -> None:
            self.timeout = timeout

        async def __aenter__(self) -> "_Client":
            return self

        async def __aexit__(self, *exc: object) -> None:
            return None

        async def put(
            self,
            url: str,
            *,
            content: bytes,
            headers: dict[str, str],
        ) -> _Response:
            requests.append({"url": url, "content": content, "headers": headers})
            return _Response()

    monkeypatch.setattr(blob_service.httpx, "AsyncClient", _Client)

    url = await blob_service._upload_cos_object("lessons/page 1.jpeg", b"jpg", "image/jpeg")

    assert url == "https://assets.example.test/base/lessons/page 1.jpeg"
    assert requests == [
        {
            "url": (
                "https://happyword-assets-staging.cos.ap-guangzhou.myqcloud.com/"
                "lessons/page%201.jpeg"
            ),
            "content": b"jpg",
            "headers": {
                "Authorization": requests[0]["headers"]["Authorization"],
                "Content-Type": "image/jpeg",
                "Host": "happyword-assets-staging.cos.ap-guangzhou.myqcloud.com",
            },
        }
    ]
    auth = requests[0]["headers"]["Authorization"]
    assert isinstance(auth, str)
    assert "q-sign-algorithm=sha1" in auth
    assert "q-ak=cos-secret-id" in auth
    assert "q-header-list=host" in auth


@pytest.mark.asyncio
async def test_delete_object_routes_by_url_provider(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import blob_service

    monkeypatch.setenv("ASSET_STORAGE_PROVIDER", "tencent_cos")
    monkeypatch.setenv("COS_PUBLIC_BASE_URL", "https://cos.example.test")
    deleted_vercel: list[str] = []
    deleted_cos: list[str] = []

    async def _fake_vercel(url: str) -> None:
        deleted_vercel.append(url)

    async def _fake_cos(url: str) -> None:
        deleted_cos.append(url)

    monkeypatch.setattr(blob_service, "_delete_vercel_object", _fake_vercel)
    monkeypatch.setattr(blob_service, "_delete_cos_object", _fake_cos)

    await blob_service.delete_object("https://happyword.public.blob.vercel-storage.com/a.png")
    await blob_service.delete_object("https://cos.example.test/illustrations/apple.png")
    await blob_service.delete_object("https://example.com/not-owned.png")

    assert deleted_vercel == ["https://happyword.public.blob.vercel-storage.com/a.png"]
    assert deleted_cos == ["https://cos.example.test/illustrations/apple.png"]


@pytest.mark.asyncio
async def test_delete_object_ignores_unknown_url_without_cos_base(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import blob_service

    monkeypatch.delenv("COS_PUBLIC_BASE_URL", raising=False)

    await blob_service.delete_object("https://example.com/not-owned.png")


@pytest.mark.asyncio
async def test_delete_cos_object_tolerates_upstream_http_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import blob_service

    monkeypatch.setenv("COS_SECRET_ID", "cos-secret-id")
    monkeypatch.setenv("COS_SECRET_KEY", "cos-secret-key")
    monkeypatch.setenv("COS_REGION", "ap-guangzhou")
    monkeypatch.setenv("COS_BUCKET", "happyword-assets-staging")
    monkeypatch.setenv("COS_PUBLIC_BASE_URL", "https://assets.example.test")

    class _Response:
        def raise_for_status(self) -> None:
            request = httpx.Request("DELETE", "https://assets.example.test/lessons/a.jpeg")
            raise httpx.HTTPStatusError("nope", request=request, response=httpx.Response(500))

    class _Client:
        def __init__(self, *, timeout: float) -> None:
            self.timeout = timeout

        async def __aenter__(self) -> "_Client":
            return self

        async def __aexit__(self, *exc: object) -> None:
            return None

        async def delete(self, url: str, *, headers: dict[str, str]) -> _Response:
            return _Response()

    monkeypatch.setattr(blob_service.httpx, "AsyncClient", _Client)

    await blob_service.delete_object("https://assets.example.test/lessons/a.jpeg")
