"""Storage-provider selection for the CloudBase migration."""

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
