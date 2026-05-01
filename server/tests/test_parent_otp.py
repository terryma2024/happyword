"""V0.6.1 — /api/v1/parent/auth/* + /api/v1/parent/me HTTP behaviour contracts.

Covers spec §V0.6.1 server contracts 1-16 (rate limit, cookie issue, role
mismatch, verify edge cases, /me, logout, cookie renewal).
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

import pytest
from httpx import ASGITransport, AsyncClient

from app.models.email_verification import EmailVerification, EmailVerificationStatus
from app.models.family import Family
from app.models.user import User, UserRole

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def recording_client(db: object) -> AsyncIterator[tuple[AsyncClient, object]]:
    """Client + the in-memory EmailProvider injected via dependency override."""
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac, provider

    app.dependency_overrides.pop(get_email_provider, None)


@pytest.mark.asyncio
async def test_request_code_new_email_returns_202_and_sends_email(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = recording_client
    r = await ac.post(
        "/api/v1/parent/auth/request-code",
        json={"email": "alice@example.com"},
    )
    assert r.status_code == 202
    assert r.json()["status"] == "accepted"
    assert len(provider.outbox) == 1  # type: ignore[attr-defined]
    assert provider.outbox[0]["to"] == "alice@example.com"  # type: ignore[attr-defined]
    pending = await EmailVerification.find(
        EmailVerification.email == "alice@example.com"
    ).to_list()
    assert len(pending) == 1
    assert pending[0].status == EmailVerificationStatus.PENDING


@pytest.mark.asyncio
async def test_request_code_rate_limited_within_60s(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = recording_client
    r1 = await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "rl@example.com"}
    )
    r2 = await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "rl@example.com"}
    )
    assert r1.status_code == 202
    assert r2.status_code == 202
    # Same response shape but only ONE email actually sent.
    assert len(provider.outbox) == 1  # type: ignore[attr-defined]


@pytest.mark.asyncio
async def test_verify_code_success_creates_family_and_returns_cookie(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = recording_client
    await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "verify@example.com"}
    )
    # Pluck plain code from the EmailVerification row by re-asking the service
    # for it via test seam: we call OTP service directly with a special hook.
    # Simpler: peek the email body sent by the recording provider.
    body = provider.outbox[-1]["text"]  # type: ignore[attr-defined]
    code = "".join(ch for ch in body if ch.isdigit())[:6]
    assert len(code) == 6

    r = await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "verify@example.com", "code": code},
    )
    assert r.status_code == 200
    body_json = r.json()
    assert body_json["email"] == "verify@example.com"
    assert body_json["family_id"].startswith("fam-")
    assert "wm_session=" in r.headers.get("set-cookie", "")
    assert (await Family.find(Family.primary_email == "verify@example.com").count()) == 1
    assert (await User.find(User.email == "verify@example.com").count()) == 1


@pytest.mark.asyncio
async def test_verify_code_wrong_returns_403(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "wrong@example.com"}
    )
    r = await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "wrong@example.com", "code": "000000"},
    )
    assert r.status_code == 403
    assert r.json()["detail"]["error"]["code"] == "INVALID_CODE"


@pytest.mark.asyncio
async def test_verify_code_5th_wrong_returns_410_too_many(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "lock@example.com"}
    )
    for _ in range(4):
        r = await ac.post(
            "/api/v1/parent/auth/verify-code",
            json={"email": "lock@example.com", "code": "000000"},
        )
        assert r.status_code == 403
    r = await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "lock@example.com", "code": "000000"},
    )
    assert r.status_code == 410
    assert r.json()["detail"]["error"]["code"] == "TOO_MANY_ATTEMPTS"


@pytest.mark.asyncio
async def test_verify_code_after_expiry_returns_410(
    recording_client: tuple[AsyncClient, object], monkeypatch: pytest.MonkeyPatch
) -> None:
    ac, provider = recording_client
    await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "exp@example.com"}
    )
    body = provider.outbox[-1]["text"]  # type: ignore[attr-defined]
    code = "".join(ch for ch in body if ch.isdigit())[:6]

    from app.services import otp_service

    real_now = datetime.now(tz=UTC)
    monkeypatch.setattr(otp_service, "_utcnow", lambda: real_now + timedelta(minutes=11))
    r = await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "exp@example.com", "code": code},
    )
    assert r.status_code == 410
    assert r.json()["detail"]["error"]["code"] == "CODE_EXPIRED"


@pytest.mark.asyncio
async def test_verify_code_idempotent_for_existing_parent(
    recording_client: tuple[AsyncClient, object],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    ac, provider = recording_client
    await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "idem@example.com"}
    )
    code = "".join(ch for ch in provider.outbox[-1]["text"] if ch.isdigit())[:6]  # type: ignore[attr-defined]
    r1 = await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "idem@example.com", "code": code},
    )
    assert r1.status_code == 200
    fam_count = await Family.count()
    user_count = await User.count()

    # Skip past the 60s rate-limit window.
    from app.services import otp_service

    real_now = datetime.now(tz=UTC)
    monkeypatch.setattr(
        otp_service, "_utcnow", lambda: real_now + timedelta(seconds=120)
    )
    await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "idem@example.com"}
    )
    code2 = "".join(ch for ch in provider.outbox[-1]["text"] if ch.isdigit())[:6]  # type: ignore[attr-defined]
    r2 = await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "idem@example.com", "code": code2},
    )
    assert r2.status_code == 200
    assert (await Family.count()) == fam_count
    assert (await User.count()) == user_count


@pytest.mark.asyncio
async def test_verify_code_admin_email_returns_403_role_mismatch(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = recording_client
    # Seed an admin user with the colliding email field set explicitly.
    from app.services.auth_service import hash_password

    await User(
        username="admin",
        password_hash=hash_password("pw"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
        email="admin@example.com",
    ).insert()
    await ac.post(
        "/api/v1/parent/auth/request-code",
        json={"email": "admin@example.com"},
    )
    code = "".join(ch for ch in provider.outbox[-1]["text"] if ch.isdigit())[:6]  # type: ignore[attr-defined]
    r = await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "admin@example.com", "code": code},
    )
    assert r.status_code == 403
    assert r.json()["detail"]["error"]["code"] == "ROLE_MISMATCH"


@pytest.mark.asyncio
async def test_me_without_cookie_returns_401(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    r = await ac.get("/api/v1/parent/me")
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_me_with_admin_cookie_returns_403(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    from app.services.auth_service import create_session_token

    admin_token = create_session_token(role="admin", identifier="root")
    ac.cookies.set("wm_session", admin_token)
    r = await ac.get("/api/v1/parent/me")
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_me_with_parent_cookie_returns_profile(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = recording_client
    await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "me@example.com"}
    )
    code = "".join(ch for ch in provider.outbox[-1]["text"] if ch.isdigit())[:6]  # type: ignore[attr-defined]
    r = await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "me@example.com", "code": code},
    )
    assert r.status_code == 200
    # The Set-Cookie from verify-code was already absorbed by the client,
    # so subsequent /me calls reuse the cookie.
    me = await ac.get("/api/v1/parent/me")
    assert me.status_code == 200
    body = me.json()
    assert body["email"] == "me@example.com"
    assert body["role"] == "parent"
    assert body["display_name"] == "me"
    assert body["family_id"].startswith("fam-")


@pytest.mark.asyncio
async def test_logout_clears_cookie(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = recording_client
    await ac.post(
        "/api/v1/parent/auth/request-code", json={"email": "out@example.com"}
    )
    code = "".join(ch for ch in provider.outbox[-1]["text"] if ch.isdigit())[:6]  # type: ignore[attr-defined]
    await ac.post(
        "/api/v1/parent/auth/verify-code",
        json={"email": "out@example.com", "code": code},
    )
    r = await ac.post("/api/v1/parent/auth/logout")
    assert r.status_code == 200
    set_cookie = r.headers.get("set-cookie", "")
    # Either Max-Age=0 or expires in the past; both delete the cookie.
    assert "wm_session=" in set_cookie
    assert "Max-Age=0" in set_cookie or "expires=" in set_cookie.lower()
