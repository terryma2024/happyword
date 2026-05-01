"""V0.6.2 — parent JSON device & child profile management."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def parent_with_device(
    db: object,
) -> AsyncIterator[tuple[AsyncClient, str, str]]:
    """Logs in a parent + redeems one binding; yields (client, binding_id, child_id)."""
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", follow_redirects=False
    ) as ac:
        await ac.post(
            "/api/v1/parent/auth/request-code", json={"email": "p2@example.com"}
        )
        code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]
        await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "p2@example.com", "code": code},
        )
        c = await ac.post("/api/v1/parent/pair/create")
        token = c.json()["token"]
        rd = await ac.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": "dev-mgmt-001"},
        )
        body = rd.json()
        yield ac, body["binding_id"], body["child_profile_id"]

    app.dependency_overrides.pop(get_email_provider, None)
    from app.routers.pair import _rate_buckets

    _rate_buckets.clear()


@pytest.mark.asyncio
async def test_list_devices_returns_active_bindings(
    parent_with_device: tuple[AsyncClient, str, str],
) -> None:
    ac, binding_id, _ = parent_with_device
    r = await ac.get("/api/v1/parent/devices")
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 1
    assert body["devices"][0]["binding_id"] == binding_id
    assert body["devices"][0]["device_id"] == "dev-mgmt-001"


@pytest.mark.asyncio
async def test_list_children_returns_active_profiles(
    parent_with_device: tuple[AsyncClient, str, str],
) -> None:
    ac, _binding_id, child_id = parent_with_device
    r = await ac.get("/api/v1/parent/children")
    assert r.status_code == 200
    body = r.json()
    assert len(body) == 1
    assert body[0]["profile_id"] == child_id


@pytest.mark.asyncio
async def test_put_child_updates_nickname(
    parent_with_device: tuple[AsyncClient, str, str],
) -> None:
    ac, _binding_id, child_id = parent_with_device
    r = await ac.put(
        f"/api/v1/parent/children/{child_id}",
        json={"nickname": "小明", "avatar_emoji": "🦊"},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["nickname"] == "小明"
    assert body["avatar_emoji"] == "🦊"


@pytest.mark.asyncio
async def test_put_child_other_family_returns_404(
    parent_with_device: tuple[AsyncClient, str, str],
) -> None:
    ac, _binding_id, _child_id = parent_with_device
    r = await ac.put(
        "/api/v1/parent/children/child-deadbeef",
        json={"nickname": "x"},
    )
    assert r.status_code == 404


@pytest.mark.asyncio
async def test_delete_child_revokes_binding(
    parent_with_device: tuple[AsyncClient, str, str],
) -> None:
    ac, binding_id, child_id = parent_with_device
    r = await ac.delete(f"/api/v1/parent/children/{child_id}")
    assert r.status_code == 200
    binding = await DeviceBinding.find_one(DeviceBinding.binding_id == binding_id)
    assert binding is not None
    assert binding.revoked_at is not None
    profile = await ChildProfile.find_one(ChildProfile.profile_id == child_id)
    assert profile is not None
    assert profile.deleted_at is not None


@pytest.mark.asyncio
async def test_device_binding_dep_rejects_revoked_token(
    parent_with_device: tuple[AsyncClient, str, str],
) -> None:
    """Once a child profile is deleted, the previously-issued device JWT must
    yield 404 BINDING_REVOKED on /api/v1/child/* (V0.6.2 ships only the dep;
    sample endpoint /api/v1/child/me is wired here to exercise it)."""
    from fastapi import Depends, FastAPI

    from app.deps import current_device_binding
    from app.services.auth_service import create_device_token

    ac, binding_id, child_id = parent_with_device
    device_token = create_device_token(
        binding_id=binding_id, child_profile_id=child_id
    )

    app = FastAPI()

    @app.get("/__test/me")
    async def _me(
        b=Depends(current_device_binding),  # type: ignore[no-untyped-def]
    ) -> dict:
        return {"binding_id": b.binding_id}

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as tc:
        r = await tc.get(
            "/__test/me", headers={"Authorization": f"Bearer {device_token}"}
        )
    assert r.status_code == 200

    # Now delete the child; binding gets revoked; same token must 404.
    await ac.delete(f"/api/v1/parent/children/{child_id}")
    async with AsyncClient(transport=transport, base_url="http://test") as tc:
        r = await tc.get(
            "/__test/me", headers={"Authorization": f"Bearer {device_token}"}
        )
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "BINDING_REVOKED"


@pytest.mark.asyncio
async def test_devices_add_cancel_form_redirects_home(
    parent_with_device: tuple[AsyncClient, str, str],
) -> None:
    ac, _binding_id, _child_id = parent_with_device
    r = await ac.post("/api/v1/parent/pair/create")
    token = r.json()["token"]
    cr = await ac.post("/parent/devices/add/cancel", data={"token": token})
    assert cr.status_code == 303
    assert cr.headers["location"] == "/parent/"
