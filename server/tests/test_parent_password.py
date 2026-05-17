"""Parent password login and account password management."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import TYPE_CHECKING

import pytest
from bs4 import BeautifulSoup
from httpx import ASGITransport, AsyncClient

from app.models.user import User, UserRole
from app.services.auth_service import hash_password, verify_password
from app.services.family_service import create_family_for_parent

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


@pytest.fixture
async def recording_client(db: object) -> AsyncIterator[tuple[AsyncClient, object]]:
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac, provider

    app.dependency_overrides.pop(get_email_provider, None)


@pytest.fixture
async def html_client(db: object) -> AsyncIterator[tuple[AsyncClient, object]]:
    from app.deps_email import get_email_provider
    from app.main import app
    from app.services.email_provider import RecordingEmailProvider

    provider = RecordingEmailProvider()
    app.dependency_overrides[get_email_provider] = lambda: provider

    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport, base_url="http://test", follow_redirects=False
    ) as ac:
        yield ac, provider

    app.dependency_overrides.pop(get_email_provider, None)


def _otp_from_outbox(provider: object) -> str:
    body = provider.outbox[-1]["text"]  # type: ignore[attr-defined]
    return "".join(ch for ch in body if ch.isdigit())[:6]


async def _parent_with_password(
    *, email: str, password: str = "securepass1"
) -> User:
    _, user = await create_family_for_parent(email=email)
    user.password_hash = hash_password(password)
    await user.save()
    return user


@pytest.mark.asyncio
async def test_password_login_success(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    await _parent_with_password(email="pwd@example.com", password="mypassword1")
    r = await ac.post(
        "/api/v1/family/_/auth/password-login",
        json={"email": "pwd@example.com", "password": "mypassword1"},
    )
    assert r.status_code == 200
    assert r.json()["email"] == "pwd@example.com"
    assert "wm_session=" in r.headers.get("set-cookie", "")


@pytest.mark.asyncio
async def test_password_login_email_not_registered(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    r = await ac.post(
        "/api/v1/family/_/auth/password-login",
        json={"email": "nobody@example.com", "password": "anything12"},
    )
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "EMAIL_NOT_REGISTERED"


@pytest.mark.asyncio
async def test_password_login_not_set(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    await create_family_for_parent(email="nopwd@example.com")
    r = await ac.post(
        "/api/v1/family/_/auth/password-login",
        json={"email": "nopwd@example.com", "password": "anything12"},
    )
    assert r.status_code == 409
    assert r.json()["detail"]["error"]["code"] == "PASSWORD_NOT_SET"


@pytest.mark.asyncio
async def test_password_login_wrong_password(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    await _parent_with_password(email="wrong@example.com")
    r = await ac.post(
        "/api/v1/family/_/auth/password-login",
        json={"email": "wrong@example.com", "password": "badpass99"},
    )
    assert r.status_code == 403
    assert r.json()["detail"]["error"]["code"] == "PASSWORD_INVALID"


@pytest.mark.asyncio
async def test_password_login_lockout_after_five_failures(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    await _parent_with_password(email="lockpwd@example.com")
    for _ in range(5):
        r = await ac.post(
            "/api/v1/family/_/auth/password-login",
            json={"email": "lockpwd@example.com", "password": "badpass99"},
        )
        assert r.status_code == 403
    r = await ac.post(
        "/api/v1/family/_/auth/password-login",
        json={"email": "lockpwd@example.com", "password": "badpass99"},
    )
    assert r.status_code == 410
    assert r.json()["detail"]["error"]["code"] == "TOO_MANY_ATTEMPTS"


@pytest.mark.asyncio
async def test_password_set_with_otp(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = recording_client
    await ac.post(
        "/api/v1/family/_/auth/request-code", json={"email": "setpwd@example.com"}
    )
    code = _otp_from_outbox(provider)
    await ac.post(
        "/api/v1/family/_/auth/verify-code",
        json={"email": "setpwd@example.com", "code": code},
    )
    await ac.post("/api/v1/family/_/account/password/request-otp")
    code2 = _otp_from_outbox(provider)
    r = await ac.post(
        "/api/v1/family/_/account/password/set",
        json={
            "code": code2,
            "new_password": "newsecure1",
            "confirm_password": "newsecure1",
        },
    )
    assert r.status_code == 200
    user = await User.find_one(User.email == "setpwd@example.com")
    assert user is not None
    assert user.password_hash is not None
    assert verify_password("newsecure1", user.password_hash)


@pytest.mark.asyncio
async def test_password_change_requires_old_password(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, provider = recording_client
    user = await _parent_with_password(email="chg@example.com", password="oldpass123")
    from app.services.auth_service import create_session_token

    token = create_session_token(role="parent", identifier=user.username)
    ac.cookies.set("wm_session", token)
    r = await ac.post(
        f"/api/v1/family/{user.family_id}/account/password/change",
        json={
            "old_password": "wrongold1",
            "new_password": "newpass123",
            "confirm_password": "newpass123",
        },
    )
    assert r.status_code == 403
    assert r.json()["detail"]["error"]["code"] == "OLD_PASSWORD_INVALID"


@pytest.mark.asyncio
async def test_password_change_success(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    user = await _parent_with_password(email="chgok@example.com", password="oldpass123")
    from app.services.auth_service import create_session_token

    token = create_session_token(role="parent", identifier=user.username)
    ac.cookies.set("wm_session", token)
    r = await ac.post(
        f"/api/v1/family/{user.family_id}/account/password/change",
        json={
            "old_password": "oldpass123",
            "new_password": "newpass456",
            "confirm_password": "newpass456",
        },
    )
    assert r.status_code == 200
    refreshed = await User.find_one(User.username == user.username)
    assert refreshed is not None
    assert verify_password("newpass456", refreshed.password_hash or "")


@pytest.mark.asyncio
async def test_login_page_has_password_form(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    r = await ac.get("/family/login")
    assert r.status_code == 200
    soup = BeautifulSoup(r.text, "html.parser")
    form = soup.find("form", action="/family/_/auth/password-login")
    assert form is not None
    assert form.find("input", attrs={"name": "password"}) is not None


@pytest.mark.asyncio
async def test_password_login_unregistered_renders_confirm_page(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    r = await ac.post(
        "/family/_/auth/password-login",
        data={"email": "newuser@example.com", "password": "temppass12"},
    )
    assert r.status_code == 200
    assert "尚未注册" in r.text
    assert "newuser@example.com" in r.text
    soup = BeautifulSoup(r.text, "html.parser")
    form = soup.find("form", action="/family/_/auth/request-code")
    assert form is not None
    hidden = form.find("input", attrs={"name": "email"})
    assert hidden is not None
    assert hidden.get("value") == "newuser@example.com"


@pytest.mark.asyncio
async def test_password_login_success_redirects_dashboard(
    html_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = html_client
    user = await _parent_with_password(email="htmlpwd@example.com")
    r = await ac.post(
        "/family/_/auth/password-login",
        data={"email": "htmlpwd@example.com", "password": "securepass1"},
    )
    assert r.status_code == 303
    assert r.headers["location"] == f"/family/{user.family_id}/"
    assert "wm_session=" in r.headers.get("set-cookie", "")


@pytest.mark.asyncio
async def test_verify_code_admin_email_still_blocks_password_login(
    recording_client: tuple[AsyncClient, object],
) -> None:
    ac, _ = recording_client
    await User(
        username="admin-pwd",
        password_hash=hash_password("adminpw1"),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
        email="adminpwd@example.com",
    ).insert()
    r = await ac.post(
        "/api/v1/family/_/auth/password-login",
        json={"email": "adminpwd@example.com", "password": "adminpw1"},
    )
    assert r.status_code == 403
    assert r.json()["detail"]["error"]["code"] == "ROLE_MISMATCH"
