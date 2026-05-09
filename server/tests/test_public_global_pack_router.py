"""V0.6.5 — public /api/v1/public/global-packs/latest.json router tests."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from app.services import global_pack_service as svc

if TYPE_CHECKING:
    from httpx import AsyncClient


async def _seed_one_pack(pack_id: str = "gpk-fruit-forest") -> None:
    await svc.create_definition(
        name="Fruit Forest",
        admin_id="seed",
        pack_id=pack_id,
        scene={"bossName": "Orchard Sentinel"},
        description="apples and pears",
    )
    await svc.upsert_draft_word(
        pack_id=pack_id,
        admin_id="seed",
        entry={
            "id": "fruit-apple",
            "word": "apple",
            "meaningZh": "苹果",
            "category": "fruit",
            "difficulty": 1,
        },
    )
    await svc.publish(pack_id=pack_id, admin_id="seed")


@pytest.mark.asyncio
async def test_get_global_packs_latest_returns_204_when_no_packs(
    client: AsyncClient,
) -> None:
    r = await client.get("/api/v1/public/global-packs/latest.json")
    assert r.status_code == 204
    assert r.text == ""


@pytest.mark.asyncio
async def test_get_global_packs_latest_serves_published_packs_anonymous(
    client: AsyncClient,
) -> None:
    await _seed_one_pack()
    r = await client.get("/api/v1/public/global-packs/latest.json")
    assert r.status_code == 200, r.text
    assert "etag" in {k.lower() for k in r.headers}
    body = r.json()
    assert len(body["packs"]) == 1
    pack = body["packs"][0]
    assert pack["pack_id"] == "gpk-fruit-forest"
    assert pack["scene"]["bossName"] == "Orchard Sentinel"
    assert pack["description"] == "apples and pears"
    assert pack["words"][0]["word"] == "apple"


@pytest.mark.asyncio
async def test_get_global_packs_latest_returns_304_on_etag_match(
    client: AsyncClient,
) -> None:
    await _seed_one_pack()
    r1 = await client.get("/api/v1/public/global-packs/latest.json")
    etag = r1.headers["etag"]
    r2 = await client.get(
        "/api/v1/public/global-packs/latest.json",
        headers={"If-None-Match": etag},
    )
    assert r2.status_code == 304


@pytest.mark.asyncio
async def test_head_global_packs_latest_returns_etag(
    client: AsyncClient,
) -> None:
    await _seed_one_pack()
    r = await client.head("/api/v1/public/global-packs/latest.json")
    assert r.status_code == 200
    assert "etag" in {k.lower() for k in r.headers}


@pytest.mark.asyncio
async def test_get_global_packs_latest_excludes_test_category_words(
    client: AsyncClient,
) -> None:
    """Spec §11 — global packs must not contain `category=='test'` words."""
    await svc.create_definition(
        name="Mixed",
        admin_id="seed",
        pack_id="gpk-mixed",
    )
    await svc.upsert_draft_word(
        pack_id="gpk-mixed",
        admin_id="seed",
        entry={
            "id": "real-1",
            "word": "real",
            "meaningZh": "真",
            "category": "fruit",
            "difficulty": 1,
        },
    )
    await svc.upsert_draft_word(
        pack_id="gpk-mixed",
        admin_id="seed",
        entry={
            "id": "e2e-1",
            "word": "test",
            "meaningZh": "测试",
            "category": "test",
            "difficulty": 1,
        },
    )
    await svc.publish(pack_id="gpk-mixed", admin_id="seed")
    r = await client.get("/api/v1/public/global-packs/latest.json")
    assert r.status_code == 200
    [pack] = r.json()["packs"]
    assert [w["id"] for w in pack["words"]] == ["real-1"]
