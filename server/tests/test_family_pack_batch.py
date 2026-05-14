from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient


async def _make_parent_client(*, email: str = "batch@example.com") -> tuple[AsyncClient, str, str]:
    from app.main import app
    from app.services.auth_service import create_session_token
    from app.services.family_service import create_family_for_parent

    family, user = await create_family_for_parent(email=email)
    token = create_session_token(role="parent", identifier=user.username)
    ac = AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        cookies={"wm_session": token},
    )
    return ac, family.family_id, user.username


@pytest.mark.asyncio
async def test_batch_upsert_accepts_valid_rows_and_reports_invalid_rows(db: object) -> None:
    ac, family_id, _ = await _make_parent_client()
    prefix = f"fam-{family_id.removeprefix('fam-')[:8]}-"
    async with ac:
        created = await ac.post("/api/v1/family/_/family-packs", json={"name": "Unit 1"})
        assert created.status_code == 201
        pack_id = created.json()["pack_id"]

        resp = await ac.post(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/words:batch-upsert",
            json={
                "rows": [
                    {
                        "word_id": f"{prefix}apple",
                        "source": "custom",
                        "word": "apple",
                        "meaning_zh": "苹果",
                        "category": "fruit",
                        "difficulty": 1,
                    },
                    {
                        "word_id": "bad-custom-id",
                        "source": "custom",
                        "word": "pear",
                        "meaning_zh": "梨",
                        "category": "fruit",
                        "difficulty": 1,
                    },
                    {
                        "word_id": "global-school",
                        "source": "global",
                    },
                ]
            },
        )

    assert resp.status_code == 207, resp.text
    body = resp.json()
    assert body["accepted_count"] == 2
    assert body["error_count"] == 1
    assert body["draft"]["word_count"] == 2
    assert body["errors"][0]["row_index"] == 1
    assert body["errors"][0]["code"] == "INVALID_PAYLOAD"


@pytest.mark.asyncio
async def test_batch_upsert_other_family_pack_404(db: object) -> None:
    ac_a, family_a, _ = await _make_parent_client(email="a-batch@example.com")
    ac_b, family_b, _ = await _make_parent_client(email="b-batch@example.com")
    assert family_a != family_b
    async with ac_a, ac_b:
        created = await ac_a.post("/api/v1/family/_/family-packs", json={"name": "Private"})
        pack_id = created.json()["pack_id"]
        resp = await ac_b.post(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/words:batch-upsert",
            json={"rows": [{"word_id": "global-apple", "source": "global"}]},
        )

    assert resp.status_code == 404
    assert resp.json()["detail"]["error"]["code"] == "PACK_NOT_FOUND"


@pytest.mark.asyncio
async def test_batch_upsert_rejects_empty_rows(db: object) -> None:
    ac, _, _ = await _make_parent_client(email="empty-batch@example.com")
    async with ac:
        created = await ac.post("/api/v1/family/_/family-packs", json={"name": "Empty"})
        pack_id = created.json()["pack_id"]
        resp = await ac.post(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/words:batch-upsert",
            json={"rows": []},
        )

    assert resp.status_code == 422
