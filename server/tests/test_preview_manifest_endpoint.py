"""Public preview manifest proxy endpoint."""

from collections.abc import Iterator
from types import TracebackType

import httpx
import pytest
from httpx import AsyncClient


class _FakeBlobClient:
    status_code = 200
    text = '{"schema_version":1,"updated_at":"2026-05-08T00:00:00Z","previews":[]}'
    headers = {"ETag": '"manifest-v1"'}
    requests: list[tuple[str, dict[str, str]]] = []

    def __init__(self, *args: object, **kwargs: object) -> None:
        pass

    async def __aenter__(self) -> "_FakeBlobClient":
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        return None

    async def get(self, url: str, headers: dict[str, str] | None = None) -> httpx.Response:
        self.requests.append((url, headers or {}))
        return httpx.Response(
            self.status_code,
            content=self.text.encode(),
            headers=self.headers,
            request=httpx.Request("GET", url),
        )


@pytest.fixture(autouse=True)
def _reset_fake_client() -> Iterator[None]:
    _FakeBlobClient.status_code = 200
    _FakeBlobClient.text = '{"schema_version":1,"updated_at":"2026-05-08T00:00:00Z","previews":[]}'
    _FakeBlobClient.headers = {"ETag": '"manifest-v1"'}
    _FakeBlobClient.requests = []
    yield


async def test_preview_manifest_returns_503_when_blob_url_is_missing(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("PREVIEW_MANIFEST_BLOB_URL", raising=False)

    resp = await client.get("/api/v1/public/preview-urls.json")

    assert resp.status_code == 503
    assert resp.json()["detail"] == "PREVIEW_MANIFEST_BLOB_URL is not configured"


async def test_preview_manifest_proxies_blob_json_with_cache_and_etag(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import preview_manifest_service

    monkeypatch.setenv(
        "PREVIEW_MANIFEST_BLOB_URL",
        "https://happyword.public.blob.vercel-storage.com/preview/preview-urls.json",
    )
    monkeypatch.setattr(preview_manifest_service.httpx, "AsyncClient", _FakeBlobClient)

    resp = await client.get(
        "/api/v1/public/preview-urls.json",
        headers={"If-None-Match": '"manifest-v1"'},
    )

    assert resp.status_code == 200
    assert resp.json() == {
        "schema_version": 1,
        "updated_at": "2026-05-08T00:00:00Z",
        "previews": [],
    }
    assert resp.headers["etag"] == '"manifest-v1"'
    assert resp.headers["cache-control"] == "public, max-age=60"
    assert resp.headers["vercel-cdn-cache-control"] == "max-age=60"
    assert _FakeBlobClient.requests == [
        (
            "https://happyword.public.blob.vercel-storage.com/preview/preview-urls.json",
            {"If-None-Match": '"manifest-v1"'},
        ),
    ]


async def test_preview_manifest_returns_502_when_blob_fetch_fails(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.services import preview_manifest_service

    _FakeBlobClient.status_code = 500
    _FakeBlobClient.text = "upstream down"
    _FakeBlobClient.headers = {}
    monkeypatch.setenv(
        "PREVIEW_MANIFEST_BLOB_URL",
        "https://happyword.public.blob.vercel-storage.com/preview/preview-urls.json",
    )
    monkeypatch.setattr(preview_manifest_service.httpx, "AsyncClient", _FakeBlobClient)

    resp = await client.get("/api/v1/public/preview-urls.json")

    assert resp.status_code == 502
    assert resp.json()["detail"] == "Preview manifest Blob returned 500"
