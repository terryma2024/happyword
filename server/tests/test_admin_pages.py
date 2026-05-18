"""V0.8.2 — system administrator HTML console under /admin/."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

from app.models.user import User, UserRole
from app.services.auth_service import hash_password

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from httpx import AsyncClient

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
        "/admin/system-config",
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


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_system_config_can_change_llm_provider(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "qwen")
    monkeypatch.setenv("DASHSCOPE_API_KEY", "sk-test-dashscope")
    monkeypatch.setenv("KIMI_API_KEY", "moonshot-test")
    from app.config import get_settings  # noqa: PLC0415
    from app.models.system_config import SystemConfig  # noqa: PLC0415
    from app.routers import admin_pages  # noqa: PLC0415

    get_settings.cache_clear()

    async def _fake_connectivity(**kwargs: object) -> object:
        return {"provider_id": kwargs["provider_id"], "model": "kimi-k2.6"}

    monkeypatch.setattr(admin_pages, "test_lesson_provider_connectivity", _fake_connectivity)
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)

    page = await client.get("/admin/system-config")
    assert page.status_code == 200
    assert "系统配置" in page.text
    assert "课程解析模型" in page.text
    assert "Qwen" in page.text
    assert "Kimi" in page.text

    saved = await client.post(
        "/admin/system-config/llm-provider",
        data={"llm_provider": "kimi"},
        follow_redirects=False,
    )

    assert saved.status_code == 303
    assert saved.headers["location"] == "/admin/system-config?flash_ok=llm_provider_updated"
    row = await SystemConfig.find_one(SystemConfig.key == "llm_provider")
    assert row is not None
    assert row.value == "kimi"
    assert row.updated_by == "console-admin"

    refreshed = await client.get("/admin/system-config?flash_ok=llm_provider_updated")
    assert refreshed.status_code == 200
    assert "已更新课程解析模型。" in refreshed.text
    assert "kimi-k2.6" in refreshed.text


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_system_config_can_test_llm_provider_without_saving(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.models.system_config import SystemConfig  # noqa: PLC0415
    from app.routers import admin_pages  # noqa: PLC0415

    async def _fake_connectivity(**kwargs: object) -> object:
        return {"provider_id": kwargs["provider_id"], "model": "kimi-k2.6"}

    monkeypatch.setattr(
        admin_pages,
        "test_lesson_provider_connectivity",
        _fake_connectivity,
        raising=False,
    )
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)

    tested = await client.post(
        "/admin/system-config/llm-provider/test",
        data={"llm_provider": "kimi"},
        follow_redirects=False,
    )

    assert tested.status_code == 303
    assert (
        tested.headers["location"]
        == "/admin/system-config?flash_ok=llm_provider_connected&tested_llm_provider=kimi"
    )
    row = await SystemConfig.find_one(SystemConfig.key == "llm_provider")
    assert row is None


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_system_config_refuses_save_when_connectivity_fails(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.models.system_config import SystemConfig  # noqa: PLC0415
    from app.routers import admin_pages  # noqa: PLC0415
    from app.services.llm_service import LlmCallError  # noqa: PLC0415

    async def _fake_connectivity(**_kwargs: object) -> object:
        raise LlmCallError("simulated connectivity failure")

    monkeypatch.setattr(
        admin_pages,
        "test_lesson_provider_connectivity",
        _fake_connectivity,
        raising=False,
    )
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)

    saved = await client.post(
        "/admin/system-config/llm-provider",
        data={"llm_provider": "kimi"},
        follow_redirects=False,
    )

    assert saved.status_code == 303
    assert saved.headers["location"].startswith(
        "/admin/system-config?flash_err=llm_provider_connectivity_failed"
    )
    row = await SystemConfig.find_one(SystemConfig.key == "llm_provider")
    assert row is None


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_can_restore_revoked_device_binding(client: AsyncClient) -> None:
    from app.models.child_profile import ChildProfile
    from app.models.device_binding import DeviceBinding

    revoked_at = datetime.now(tz=UTC)
    binding = DeviceBinding(
        binding_id="bind-admin-restore",
        family_id="fam-admin",
        device_id="dev-admin-restore",
        child_profile_id="child-admin",
        created_at=datetime.now(tz=UTC),
        last_seen_at=datetime.now(tz=UTC),
        revoked_at=revoked_at,
    )
    await binding.insert()
    child = ChildProfile(
        profile_id="child-admin",
        family_id="fam-admin",
        binding_id="bind-admin-restore",
        created_at=datetime.now(tz=UTC),
        updated_at=revoked_at,
        deleted_at=revoked_at,
    )
    await child.insert()

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)

    listing = await client.get("/admin/devices")
    assert listing.status_code == 200
    assert "恢复绑定" in listing.text

    form = await client.get("/admin/devices/bind-admin-restore/restore")
    assert form.status_code == 200
    assert "恢复设备绑定" in form.text

    restored = await client.post(
        "/admin/devices/bind-admin-restore/restore",
        data={"reason": "manual restore"},
        follow_redirects=False,
    )
    assert restored.status_code == 303
    assert restored.headers["location"] == "/admin/devices?flash_ok=restored"

    refreshed = await DeviceBinding.find_one(
        DeviceBinding.binding_id == "bind-admin-restore"
    )
    assert refreshed is not None
    assert refreshed.revoked_at is None
    restored_child = await ChildProfile.find_one(ChildProfile.profile_id == "child-admin")
    assert restored_child is not None
    assert restored_child.deleted_at is None
