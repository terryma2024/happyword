"""V0.6.8 — device-side self-edit of `/api/v1/child/profile`.

These cover only the new device-token-authed endpoint. The parent-side
`PUT /api/v1/parent/children/{id}` is exercised in
`test_device_management.py`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.child_profile import ChildProfile

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def parent_with_device(
    db: object,
) -> AsyncIterator[tuple[AsyncClient, str, str, str]]:
    """Yields (httpx_client, binding_id, child_profile_id, device_token).

    Same fixture shape as `test_redemption_flow.parent_with_device` so
    the test file can stay self-contained without importing fixtures
    from sibling tests.
    """
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.auth_service import create_device_token
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", follow_redirects=False
    ) as ac:
        await ac.post(
            "/api/v1/parent/auth/request-code",
            json={"email": "self-edit@example.com"},
        )
        code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]
        await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "self-edit@example.com", "code": code},
        )
        c = await ac.post("/api/v1/parent/pair/create")
        token = c.json()["token"]
        rd = await ac.post(
            "/api/v1/pair/redeem",
            json={"token": token, "device_id": "dev-self-001"},
        )
        body = rd.json()
        device_token = create_device_token(
            binding_id=body["binding_id"],
            child_profile_id=body["child_profile_id"],
        )
        yield ac, body["binding_id"], body["child_profile_id"], device_token

    app.dependency_overrides.pop(get_email_provider, None)
    from app.routers.pair import _rate_buckets

    _rate_buckets.clear()


@pytest.mark.asyncio
async def test_device_can_update_own_nickname(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding_id, child_id, device_token = parent_with_device

    r = await ac.put(
        "/api/v1/child/profile",
        json={"nickname": "  小明  "},
        headers={"Authorization": f"Bearer {device_token}"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["profile_id"] == child_id
    # service.update strips before storing
    assert body["nickname"] == "小明"
    # avatar untouched: stays at the redeem default
    assert body["avatar_emoji"] == "🦄"
    assert "updated_at" in body and "family_id" in body

    # Parent-side list reflects the new value (single source of truth).
    pl = await ac.get("/api/v1/parent/children")
    assert pl.status_code == 200
    rows = pl.json()
    assert len(rows) == 1
    assert rows[0]["nickname"] == "小明"


@pytest.mark.asyncio
async def test_device_blank_nickname_is_400(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding_id, child_id, device_token = parent_with_device

    r = await ac.put(
        "/api/v1/child/profile",
        json={"nickname": "   "},
        headers={"Authorization": f"Bearer {device_token}"},
    )
    assert r.status_code == 400
    assert r.json()["detail"]["error"]["code"] == "INVALID_NICKNAME"

    # Stored value unchanged
    profile = await ChildProfile.find_one(ChildProfile.profile_id == child_id)
    assert profile is not None
    assert profile.nickname == "宝贝"


@pytest.mark.asyncio
async def test_device_long_nickname_is_truncated_to_32(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding_id, _child_id, device_token = parent_with_device

    long_name = "x" * 100
    r = await ac.put(
        "/api/v1/child/profile",
        json={"nickname": long_name},
        headers={"Authorization": f"Bearer {device_token}"},
    )
    assert r.status_code == 200
    body = r.json()
    # Service caps at 32 characters
    assert body["nickname"] == "x" * 32


@pytest.mark.asyncio
async def test_device_revoked_token_yields_404_binding_revoked(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding_id, child_id, device_token = parent_with_device

    # Soft-delete the profile via the parent path; the dep should then
    # reject the device token without our endpoint ever running.
    dr = await ac.delete(f"/api/v1/parent/children/{child_id}")
    assert dr.status_code == 200

    r = await ac.put(
        "/api/v1/child/profile",
        json={"nickname": "x"},
        headers={"Authorization": f"Bearer {device_token}"},
    )
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "BINDING_REVOKED"


@pytest.mark.asyncio
async def test_device_missing_token_is_401(
    parent_with_device: tuple[AsyncClient, str, str, str],
) -> None:
    ac, _binding_id, _child_id, _device_token = parent_with_device

    # Anonymous PUT must not pass auth.
    r = await ac.put(
        "/api/v1/child/profile",
        json={"nickname": "x"},
    )
    assert r.status_code in (401, 403)
