"""Public CloudBase environment manifest endpoint."""

import pytest
from httpx import AsyncClient


async def test_preview_manifest_defaults_to_cloudbase_prod_and_staging(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("PREVIEW_MANIFEST_INLINE_JSON", raising=False)
    monkeypatch.delenv("PREVIEW_MANIFEST_BLOB_URL", raising=False)

    resp = await client.get("/api/v1/public/preview-urls.json")

    assert resp.status_code == 200
    assert resp.json() == {
        "schema_version": 1,
        "updated_at": "cloudbase-static",
        "previews": [
            {
                "pr": 0,
                "title": "HappyWord Production",
                "branch": "main",
                "url": "https://happyword.com.cn",
                "author": "cloudbase",
                "head_sha": "prod",
                "updated_at": "cloudbase-static",
            },
            {
                "pr": 0,
                "title": "CloudBase Staging",
                "branch": "shared-staging",
                "url": "https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com",
                "author": "cloudbase",
                "head_sha": "staging",
                "updated_at": "cloudbase-static",
            },
        ],
    }
    assert resp.headers["cache-control"] == "public, max-age=60"
    assert "etag" not in resp.headers


async def test_preview_manifest_serves_inline_cloudbase_manifest_without_blob(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("PREVIEW_MANIFEST_BLOB_URL", raising=False)
    monkeypatch.setenv(
        "PREVIEW_MANIFEST_INLINE_JSON",
        """
        {
          "updated_at": "2026-05-20T00:00:00Z",
          "items": [
            {
              "name": "CloudBase Staging",
              "url": "https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com",
              "branch": "shared-staging",
              "provider": "cloudbase",
              "source": "inline"
            }
          ]
        }
        """,
    )

    resp = await client.get("/api/v1/public/preview-urls.json")

    assert resp.status_code == 200
    assert resp.json() == {
        "schema_version": 1,
        "updated_at": "2026-05-20T00:00:00Z",
        "previews": [
            {
                "pr": 0,
                "title": "CloudBase Staging",
                "branch": "shared-staging",
                "url": "https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com",
                "author": "cloudbase",
                "head_sha": "inline",
                "updated_at": "2026-05-20T00:00:00Z",
            }
        ],
    }
    assert resp.headers["cache-control"] == "public, max-age=60"


async def test_preview_manifest_ignores_legacy_blob_env_when_inline_is_missing(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("PREVIEW_MANIFEST_INLINE_JSON", raising=False)
    monkeypatch.setenv(
        "PREVIEW_MANIFEST_BLOB_URL",
        "https://happyword.public.blob.vercel-storage.com/preview/preview-urls.json",
    )

    resp = await client.get("/api/v1/public/preview-urls.json")

    assert resp.status_code == 200
    body = resp.json()
    assert [row["title"] for row in body["previews"]] == [
        "HappyWord Production",
        "CloudBase Staging",
    ]
    assert all("blob.vercel-storage.com" not in row["url"] for row in body["previews"])
