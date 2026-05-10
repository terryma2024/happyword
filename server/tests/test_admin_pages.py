"""V0.8.2 — system administrator HTML console under /admin/."""

from __future__ import annotations

from collections.abc import AsyncIterator
from datetime import UTC, datetime

import pytest
from httpx import AsyncClient

from app.models.user import User, UserRole
from app.services.auth_service import hash_password

_CONSOLE_PW = "console-test-pw-99"


@pytest.fixture
async def admin_console_admin(db: object) -> AsyncIterator[User]:
    u = User(
        username="console-admin",
        password_hash=hash_password(_CONSOLE_PW),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    )
    await u.insert()
    yield u


@pytest.mark.asyncio
async def test_admin_root_redirects_anonymous_to_login(client: AsyncClient) -> None:
    res = await client.get("/admin/", follow_redirects=False)
    assert res.status_code == 303
    assert res.headers["location"] == "/admin/login"


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_login_rejects_bad_password(client: AsyncClient) -> None:
    res = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": "wrong-password"},
        follow_redirects=False,
    )
    assert res.status_code == 401


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_login_sets_cookie_and_overview_renders(client: AsyncClient) -> None:
    res = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    assert res.status_code == 303
    assert res.headers["location"] == "/admin/"
    assert "wm_admin_session" in res.cookies
    client.cookies.update(res.cookies)

    dash = await client.get("/admin/")
    assert dash.status_code == 200
    assert "系统总览" in dash.text
    assert "家长账户数" in dash.text


@pytest.mark.asyncio
async def test_admin_stub_pages_require_auth(client: AsyncClient) -> None:
    for path in (
        "/admin/parents",
        "/admin/devices",
        "/admin/global-packs",
        "/admin/family-packs",
        "/admin/audit-logs",
    ):
        res = await client.get(path, follow_redirects=False)
        assert res.status_code == 303
        assert res.headers["location"] == "/admin/login"


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_logout_clears_cookie(client: AsyncClient) -> None:
    res = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    cookies = res.cookies
    client.cookies.jar.clear()
    client.cookies.update(cookies)
    out = await client.post("/admin/logout", follow_redirects=False)
    assert out.status_code == 303
    assert out.headers["location"] == "/admin/login"
