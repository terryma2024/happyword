"""V0.6.2 — pair flow API HTTP behaviour contracts (server contracts 1-15)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

import pytest
from bs4 import BeautifulSoup
from httpx import ASGITransport, AsyncClient

from app.models.pair_token import PairTokenStatus

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def parent_client(db: object) -> AsyncIterator[tuple[AsyncClient, str]]:
    """Parent already logged in (cookie present); yields (client, family_id)."""
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
            "/api/v1/parent/auth/request-code", json={"email": "p@example.com"}
        )
        code = "".join(c for c in provider.outbox[-1]["text"] if c.isdigit())[:6]
        r = await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "p@example.com", "code": code},
        )
        family_id = r.json()["family_id"]
        yield ac, family_id

    app.dependency_overrides.pop(get_email_provider, None)
    # Reset rate-limiter state so tests don't interfere.
    from app.routers.pair import _rate_buckets

    _rate_buckets.clear()


@pytest.mark.asyncio
async def test_post_pair_create_returns_201_with_token(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    assert r.status_code == 201
    body = r.json()
    assert len(body["token"]) == 32
    assert len(body["short_code"]) == 6
    assert body["status"] == "pending"
    assert "/p/" in body["qr_payload_url"]


@pytest.mark.asyncio
async def test_post_pair_create_rate_limited_after_5(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    for _ in range(5):
        r = await ac.post("/api/v1/parent/pair/create")
        assert r.status_code == 201
    r = await ac.post("/api/v1/parent/pair/create")
    assert r.status_code == 429
    assert r.json()["detail"]["error"]["code"] == "RATE_LIMITED"


@pytest.mark.asyncio
async def test_status_returns_pending_for_pending_token(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    token = r.json()["token"]
    s = await ac.get(f"/api/v1/parent/pair/status/{token}")
    assert s.status_code == 200
    assert s.json()["status"] == "pending"


@pytest.mark.asyncio
async def test_status_unknown_token_returns_404(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    r = await ac.get("/api/v1/parent/pair/status/" + "0" * 32)
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "TOKEN_INVALID"


@pytest.mark.asyncio
async def test_redeem_token_creates_binding_and_returns_device_token(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, family_id = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    token = r.json()["token"]
    rd = await ac.post(
        "/api/v1/pair/redeem",
        json={"token": token, "device_id": "dev-aaaa-bbbb"},
    )
    assert rd.status_code == 200
    body = rd.json()
    assert body["family_id"] == family_id
    assert body["binding_id"].startswith("bind-")
    assert body["child_profile_id"].startswith("child-")
    assert body["nickname"] == "宝贝"
    assert body["device_token"].count(".") == 2

    s = await ac.get(f"/api/v1/parent/pair/status/{token}")
    assert s.json()["status"] == "redeemed"
    assert s.json()["redeemed_binding_id"] == body["binding_id"]


@pytest.mark.asyncio
async def test_redeem_short_code(parent_client: tuple[AsyncClient, str]) -> None:
    ac, _ = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    short_code = r.json()["short_code"]
    rd = await ac.post(
        "/api/v1/pair/redeem",
        json={"short_code": short_code, "device_id": "dev-short-xyz"},
    )
    assert rd.status_code == 200


@pytest.mark.asyncio
async def test_redeem_expired_returns_410(
    parent_client: tuple[AsyncClient, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    ac, _ = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    token = r.json()["token"]

    from app.services import pair_service

    real_now = datetime.now(tz=UTC)
    monkeypatch.setattr(
        pair_service, "_utcnow", lambda: real_now + timedelta(minutes=10)
    )
    rd = await ac.post(
        "/api/v1/pair/redeem", json={"token": token, "device_id": "dev-ttl-test"}
    )
    assert rd.status_code == 410
    assert rd.json()["detail"]["error"]["code"] == "TOKEN_EXPIRED"


@pytest.mark.asyncio
async def test_redeem_already_used_returns_409(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    token = r.json()["token"]
    await ac.post(
        "/api/v1/pair/redeem", json={"token": token, "device_id": "dev-dup-001"}
    )
    rd = await ac.post(
        "/api/v1/pair/redeem", json={"token": token, "device_id": "dev-dup-002"}
    )
    assert rd.status_code == 409
    assert rd.json()["detail"]["error"]["code"] == "TOKEN_REDEEMED"


@pytest.mark.asyncio
async def test_redeem_unknown_token_returns_404(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    rd = await ac.post(
        "/api/v1/pair/redeem", json={"token": "0" * 32, "device_id": "dev-unknown"}
    )
    assert rd.status_code == 404
    assert rd.json()["detail"]["error"]["code"] == "TOKEN_INVALID"


@pytest.mark.asyncio
async def test_delete_pair_token_cancels_it(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    token = r.json()["token"]
    d = await ac.delete(f"/api/v1/parent/pair/{token}")
    assert d.status_code == 200
    assert d.json()["status"] == "cancelled"
    rd = await ac.post(
        "/api/v1/pair/redeem",
        json={"token": token, "device_id": "dev-cancel-test"},
    )
    assert rd.status_code == 404


@pytest.mark.asyncio
async def test_landing_page_renders(parent_client: tuple[AsyncClient, str]) -> None:
    ac, _ = parent_client
    r = await ac.get("/p/abc123def456")
    assert r.status_code == 200
    soup = BeautifulSoup(r.text, "html.parser")
    assert soup.find(id="pair-landing-instructions") is not None
    assert "WordMagic" in r.text or "快乐背单词" in r.text


@pytest.mark.asyncio
async def test_devices_add_html_renders_qr_data_url(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    r = await ac.get("/parent/devices/add")
    assert r.status_code == 200
    soup = BeautifulSoup(r.text, "html.parser")
    img = soup.find("img", alt="二维码")
    assert img is not None
    assert img.get("src", "").startswith("data:image/png;base64,")
    # Status partial polling endpoint baked into the template.
    status_div = soup.find(id="pair-status")
    assert status_div is not None
    assert "/parent/devices/add/status" in status_div.get("hx-get", "")


@pytest.mark.asyncio
async def test_devices_add_status_partial_returns_pending_then_redeemed(
    parent_client: tuple[AsyncClient, str],
) -> None:
    ac, _ = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    token = r.json()["token"]

    s = await ac.get("/parent/devices/add/status", params={"token": token})
    assert s.status_code == 200
    assert "等待设备扫码" in s.text or "pending" in s.text.lower()

    await ac.post(
        "/api/v1/pair/redeem", json={"token": token, "device_id": "dev-aaaa-1234"}
    )
    s2 = await ac.get("/parent/devices/add/status", params={"token": token})
    assert "已绑定" in s2.text
    assert "1234" in s2.text  # last 4 of device id


@pytest.mark.asyncio
async def test_pending_token_marked_expired_by_expire_old(
    parent_client: tuple[AsyncClient, str], monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services.pair_service import _utcnow as _real
    from app.services.pair_service import expire_old

    ac, _ = parent_client
    r = await ac.post("/api/v1/parent/pair/create")
    token = r.json()["token"]
    from app.services import pair_service

    monkeypatch.setattr(
        pair_service,
        "_utcnow",
        lambda: _real() + timedelta(minutes=10),
    )
    n = await expire_old()
    assert n >= 1
    s = await ac.get(f"/api/v1/parent/pair/status/{token}")
    assert s.json()["status"] == PairTokenStatus.EXPIRED.value
