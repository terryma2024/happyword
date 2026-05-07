"""V0.6.3 — HTTP behaviour contracts for /api/v1/parent/family-packs/* and
/api/v1/child/family-packs/latest.json.

Covers the cross-cutting (28-30) and child-fetch (21-27) contracts from
the V0.6 plan §V0.6.3.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding


async def _make_parent_client(
    *, email: str = "p@example.com"
) -> tuple[AsyncClient, str]:
    """Create a family + parent + cookie-authed AsyncClient."""
    from app.main import app
    from app.services.auth_service import create_session_token
    from app.services.family_service import create_family_for_parent

    family, user = await create_family_for_parent(email=email)
    token = create_session_token(role="parent", identifier=user.username)
    transport = ASGITransport(app=app)
    ac = AsyncClient(
        transport=transport,
        base_url="http://test",
        cookies={"wm_session": token},
    )
    return ac, family.family_id


async def _make_device_client(
    *, family_id: str, email: str = "d@example.com"
) -> tuple[AsyncClient, str]:
    """Create a binding + device-token-authed AsyncClient under the same family."""
    from app.main import app
    from app.services.auth_service import create_device_token

    now = datetime.now(tz=UTC)
    child = ChildProfile(
        profile_id="child-aaaa1111",
        family_id=family_id,
        binding_id="bind-aaaa1111",
        nickname="kid",
        avatar_emoji="🦄",
        created_at=now,
        updated_at=now,
    )
    await child.insert()
    binding = DeviceBinding(
        binding_id="bind-aaaa1111",
        family_id=family_id,
        device_id="dev-aaaa",
        child_profile_id=child.profile_id,
        user_agent="ut",
        created_at=now,
        last_seen_at=now,
    )
    await binding.insert()
    token = create_device_token(
        binding_id=binding.binding_id, child_profile_id=child.profile_id
    )
    transport = ASGITransport(app=app)
    ac = AsyncClient(transport=transport, base_url="http://test")
    ac.headers["Authorization"] = f"Bearer {token}"
    return ac, binding.binding_id


# ---------------------------------------------------------------------------
# Parent CRUD smoke
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_pack_returns_201_with_pack_id(db: object) -> None:
    ac, _ = await _make_parent_client()
    async with ac:
        r = await ac.post(
            "/api/v1/parent/family-packs",
            json={"name": "三年级第三单元"},
        )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["pack_id"].startswith("pck-")
    assert body["state"] == "active"


@pytest.mark.asyncio
async def test_create_duplicate_active_name_409(db: object) -> None:
    ac, _ = await _make_parent_client()
    async with ac:
        r = await ac.post(
            "/api/v1/parent/family-packs", json={"name": "Fruit"}
        )
        assert r.status_code == 201
        r = await ac.post(
            "/api/v1/parent/family-packs", json={"name": "Fruit"}
        )
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "NAME_TAKEN"


@pytest.mark.asyncio
async def test_list_default_excludes_archived(db: object) -> None:
    ac, _ = await _make_parent_client()
    async with ac:
        await ac.post("/api/v1/parent/family-packs", json={"name": "Keep"})
        rdrop = await ac.post(
            "/api/v1/parent/family-packs", json={"name": "Drop"}
        )
        pack_to_drop = rdrop.json()["pack_id"]
        await ac.post(
            f"/api/v1/parent/family-packs/{pack_to_drop}/archive"
        )

        r = await ac.get("/api/v1/parent/family-packs")
        assert r.status_code == 200
        names = sorted(item["definition"]["name"] for item in r.json()["items"])
        assert names == ["Keep"]

        rall = await ac.get(
            "/api/v1/parent/family-packs?include_archived=true"
        )
        names_all = sorted(
            item["definition"]["name"] for item in rall.json()["items"]
        )
        assert names_all == ["Drop", "Keep"]


@pytest.mark.asyncio
async def test_get_pack_other_family_404(db: object) -> None:
    ac_a, _ = await _make_parent_client(email="a@example.com")
    ac_b, _ = await _make_parent_client(email="b@example.com")
    async with ac_a, ac_b:
        r = await ac_a.post(
            "/api/v1/parent/family-packs", json={"name": "PrivateA"}
        )
        pack_id = r.json()["pack_id"]
        r = await ac_b.get(f"/api/v1/parent/family-packs/{pack_id}")
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "PACK_NOT_FOUND"


@pytest.mark.asyncio
async def test_admin_token_blocked_on_parent_endpoint(db: object) -> None:
    from app.main import app
    from app.services.auth_service import create_session_token

    admin_cookie = create_session_token(role="admin", identifier="root")
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://test",
        cookies={"wm_session": admin_cookie},
    ) as ac:
        r = await ac.post(
            "/api/v1/parent/family-packs", json={"name": "X"}
        )
    assert r.status_code in (401, 403), r.text


# ---------------------------------------------------------------------------
# Draft + publish via HTTP
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_full_publish_flow_via_http(db: object) -> None:
    ac, _ = await _make_parent_client()
    async with ac:
        r = await ac.post(
            "/api/v1/parent/family-packs", json={"name": "Pack1"}
        )
        pack_id = r.json()["pack_id"]

        r = await ac.put(
            f"/api/v1/parent/family-packs/{pack_id}/draft/words/apple",
            json={"source": "global"},
        )
        assert r.status_code == 200
        assert r.json()["word_count"] == 1
        assert r.json()["max_words"] == 50

        r = await ac.post(
            f"/api/v1/parent/family-packs/{pack_id}/publish", json={}
        )
        assert r.status_code == 201
        assert r.json()["version"] == 1

        r = await ac.get(
            f"/api/v1/parent/family-packs/{pack_id}/versions"
        )
        assert r.status_code == 200
        assert [v["version"] for v in r.json()["items"]] == [1]


@pytest.mark.asyncio
async def test_draft_pack_full_409(db: object) -> None:
    ac, _ = await _make_parent_client()
    async with ac:
        r = await ac.post(
            "/api/v1/parent/family-packs", json={"name": "Big"}
        )
        pack_id = r.json()["pack_id"]
        for i in range(50):
            r = await ac.put(
                f"/api/v1/parent/family-packs/{pack_id}/draft/words/g-{i}",
                json={"source": "global"},
            )
            assert r.status_code == 200
        r = await ac.put(
            f"/api/v1/parent/family-packs/{pack_id}/draft/words/g-50",
            json={"source": "global"},
        )
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "PACK_FULL"


@pytest.mark.asyncio
async def test_publish_empty_409(db: object) -> None:
    ac, _ = await _make_parent_client()
    async with ac:
        r = await ac.post(
            "/api/v1/parent/family-packs", json={"name": "Empty"}
        )
        pack_id = r.json()["pack_id"]
        r = await ac.post(
            f"/api/v1/parent/family-packs/{pack_id}/publish", json={}
        )
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "EMPTY_PACK"


@pytest.mark.asyncio
async def test_custom_word_id_must_have_family_prefix(db: object) -> None:
    ac, _ = await _make_parent_client()
    async with ac:
        r = await ac.post(
            "/api/v1/parent/family-packs", json={"name": "P"}
        )
        pack_id = r.json()["pack_id"]
        r = await ac.put(
            f"/api/v1/parent/family-packs/{pack_id}/draft/words/wrong-id",
            json={
                "source": "custom",
                "word": "x",
                "meaning_zh": "y",
                "category": "z",
                "difficulty": 1,
            },
        )
    assert r.status_code == 422
    assert r.json()["detail"]["error"]["code"] == "INVALID_PAYLOAD"


# ---------------------------------------------------------------------------
# Child merged JSON
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_child_merged_json_204_when_no_packs(db: object) -> None:
    ac_p, family_id = await _make_parent_client()
    async with ac_p:
        pass
    ac_d, _ = await _make_device_client(family_id=family_id)
    async with ac_d:
        r = await ac_d.get("/api/v1/child/family-packs/latest.json")
    assert r.status_code == 204


@pytest.mark.asyncio
async def test_child_merged_json_200_with_published(db: object) -> None:
    ac_p, family_id = await _make_parent_client()
    async with ac_p:
        r = await ac_p.post(
            "/api/v1/parent/family-packs", json={"name": "Pack"}
        )
        pack_id = r.json()["pack_id"]
        await ac_p.put(
            f"/api/v1/parent/family-packs/{pack_id}/draft/words/apple",
            json={"source": "global"},
        )
        await ac_p.post(
            f"/api/v1/parent/family-packs/{pack_id}/publish", json={}
        )

    ac_d, _ = await _make_device_client(family_id=family_id)
    async with ac_d:
        r = await ac_d.get("/api/v1/child/family-packs/latest.json")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["family_id"] == family_id
    assert len(body["packs"]) == 1
    etag = r.headers.get("etag")
    assert etag is not None and etag.startswith('"')


@pytest.mark.asyncio
async def test_child_merged_json_304_on_matching_etag(db: object) -> None:
    ac_p, family_id = await _make_parent_client()
    async with ac_p:
        r = await ac_p.post(
            "/api/v1/parent/family-packs", json={"name": "P"}
        )
        pack_id = r.json()["pack_id"]
        await ac_p.put(
            f"/api/v1/parent/family-packs/{pack_id}/draft/words/apple",
            json={"source": "global"},
        )
        await ac_p.post(
            f"/api/v1/parent/family-packs/{pack_id}/publish", json={}
        )

    ac_d, _ = await _make_device_client(family_id=family_id)
    async with ac_d:
        r = await ac_d.get("/api/v1/child/family-packs/latest.json")
        etag = r.headers["etag"]
        r2 = await ac_d.get(
            "/api/v1/child/family-packs/latest.json",
            headers={"If-None-Match": etag},
        )
    assert r2.status_code == 304


@pytest.mark.asyncio
async def test_child_merged_json_head_returns_etag_only(db: object) -> None:
    ac_p, family_id = await _make_parent_client()
    async with ac_p:
        r = await ac_p.post(
            "/api/v1/parent/family-packs", json={"name": "P"}
        )
        pack_id = r.json()["pack_id"]
        await ac_p.put(
            f"/api/v1/parent/family-packs/{pack_id}/draft/words/apple",
            json={"source": "global"},
        )
        await ac_p.post(
            f"/api/v1/parent/family-packs/{pack_id}/publish", json={}
        )

    ac_d, _ = await _make_device_client(family_id=family_id)
    async with ac_d:
        r = await ac_d.head("/api/v1/child/family-packs/latest.json")
    assert r.status_code == 200
    assert r.headers.get("etag") is not None
    assert r.content == b""
