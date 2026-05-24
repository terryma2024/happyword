"""V0.8.2 — system administrator HTML console under /admin/."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import TYPE_CHECKING
from urllib.parse import urlencode

import pytest
from bs4 import BeautifulSoup

from app.models.audit_log import AuditLog
from app.models.family_pack_definition import FamilyPackDefinition
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
async def test_admin_global_packs_page_renders_delete_form(
    client: AsyncClient,
) -> None:
    from app.services import global_pack_service

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    await global_pack_service.create_definition(
        name="Delete From HTML",
        admin_id="console-admin",
        pack_id="gpk-html-delete",
    )

    page = await client.get("/admin/global-packs")

    assert page.status_code == 200
    assert "/admin/global-packs/packs/gpk-html-delete/delete" in page.text
    assert "删除" in page.text


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_global_pack_html_delete_removes_pack_and_audits(
    client: AsyncClient,
) -> None:
    from app.services import global_pack_service

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    await global_pack_service.create_definition(
        name="Delete From HTML",
        admin_id="console-admin",
        pack_id="gpk-html-delete",
    )

    res = await client.post(
        "/admin/global-packs/packs/gpk-html-delete/delete",
        data={"reason": "清理测试词包"},
        follow_redirects=False,
    )

    assert res.status_code == 303
    assert res.headers["location"] == "/admin/global-packs?flash_ok=gpk_deleted"
    assert await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "gpk-html-delete"
    ) is None
    audit = await AuditLog.find_one(AuditLog.action == "global_pack.definition_delete")
    assert audit is not None
    assert audit.target_id == "gpk-html-delete"
    assert audit.payload_summary["reason"] == "清理测试词包"


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_packs_page_renders_delete_form(
    client: AsyncClient,
) -> None:
    from app.services import family_pack_service
    from app.services.family_service import create_family_for_parent

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    family, user = await create_family_for_parent(email="family-delete-html@example.com")
    await family_pack_service.create_definition(
        family_id=family.family_id,
        name="Family Delete From HTML",
        description=None,
        parent_user_id=user.username,
        pack_id="pck-html-delete",
    )

    page = await client.get("/admin/family-packs")

    assert page.status_code == 200
    assert "/admin/family-packs/pck-html-delete/delete" in page.text
    assert "删除" in page.text


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_pack_html_delete_removes_pack_and_audits(
    client: AsyncClient,
) -> None:
    from app.models.family_pack_draft import FamilyPackDraft
    from app.models.family_pack_pointer import FamilyPackPointer
    from app.models.family_word_pack import FamilyWordPack
    from app.services import family_pack_service
    from app.services.family_service import create_family_for_parent

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    family, user = await create_family_for_parent(email="family-delete-post@example.com")
    definition = await family_pack_service.create_definition(
        family_id=family.family_id,
        name="Family Delete From HTML",
        description=None,
        parent_user_id=user.username,
        pack_id="pck-html-delete",
    )
    await family_pack_service.upsert_draft_word(
        definition=definition,
        word_id="apple",
        payload={"source": "global"},
        parent_user_id=user.username,
    )
    await family_pack_service.publish(
        definition=definition, parent_user_id=user.username, notes="v1"
    )
    await family_pack_service.upsert_draft_word(
        definition=definition,
        word_id="banana",
        payload={"source": "global"},
        parent_user_id=user.username,
    )
    await family_pack_service.publish(
        definition=definition, parent_user_id=user.username, notes="v2"
    )

    res = await client.post(
        "/admin/family-packs/pck-html-delete/delete",
        data={"reason": "清理家庭测试词包"},
        follow_redirects=False,
    )

    assert res.status_code == 303
    assert res.headers["location"] == "/admin/family-packs?flash_ok=deleted"
    assert await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "pck-html-delete"
    ) is None
    assert await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == "pck-html-delete"
    ) is None
    assert await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == "pck-html-delete"
    ) is None
    assert (
        await FamilyWordPack.find(
            FamilyWordPack.pack_definition_id == "pck-html-delete"
        ).count()
        == 0
    )
    audit = await AuditLog.find_one(AuditLog.action == "family_pack.definition_delete")
    assert audit is not None
    assert audit.target_id == "pck-html-delete"
    assert audit.payload_summary["reason"] == "清理家庭测试词包"
    assert audit.payload_summary["family_id"] == family.family_id
    assert audit.payload_summary["deleted_version_count"] == 2


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_pack_delete_rejects_global_sentinel(
    client: AsyncClient,
) -> None:
    from app.services import global_pack_service

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    await global_pack_service.create_definition(
        name="Global Guard",
        admin_id="console-admin",
        pack_id="gpk-family-delete-guard",
    )

    res = await client.post(
        "/admin/family-packs/gpk-family-delete-guard/delete",
        data={"reason": "错误入口保护"},
        follow_redirects=False,
    )

    assert res.status_code == 303
    assert res.headers["location"].startswith("/admin/family-packs?flash_err=")
    assert await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "gpk-family-delete-guard"
    ) is not None


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_global_pack_detail_renders_split_form(
    client: AsyncClient,
) -> None:
    from app.services import global_pack_service

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    await global_pack_service.create_definition(
        name="Split UI",
        admin_id="console-admin",
        pack_id="gpk-html-split-ui",
    )

    page = await client.get("/admin/global-packs/packs/gpk-html-split-ui")

    assert page.status_code == 200
    soup = BeautifulSoup(page.text, "html.parser")
    form = soup.find(id="global-draft-split-form")
    dialog = soup.find(id="global-draft-split-dialog")
    move_button = soup.find(id="global-draft-split-move-open")
    copy_button = soup.find(id="global-draft-split-copy-open")
    assert form is not None
    assert dialog is not None
    assert dialog.find("input", attrs={"name": "new_name"}) is not None
    assert dialog.find("input", attrs={"name": "new_description"}) is not None
    mode = dialog.find("input", attrs={"name": "mode"})
    assert mode is not None
    assert mode.get("type") == "hidden"
    assert soup.find("select", attrs={"name": "mode"}) is None
    assert move_button is not None
    assert move_button.get_text(strip=True) == "移动到新包"
    assert copy_button is not None
    assert copy_button.get_text(strip=True) == "复制到新包"


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_global_pack_split_form_moves_words_and_audits(
    client: AsyncClient,
) -> None:
    from app.services import admin_console_service as acs
    from app.services import global_pack_service

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    await global_pack_service.create_definition(
        name="Split HTML Source",
        admin_id="console-admin",
        pack_id="gpk-html-split-src",
    )
    for word_id in ("fruit-apple", "fruit-banana", "fruit-pear"):
        await global_pack_service.upsert_draft_word(
            pack_id="gpk-html-split-src",
            admin_id="console-admin",
            entry={
                "id": word_id,
                "word": word_id,
                "meaningZh": word_id,
                "category": "fruit",
                "difficulty": 1,
            },
        )

    resp = await client.post(
        "/admin/global-packs/packs/gpk-html-split-src/draft/split",
        content=urlencode(
            [
                ("word_ids", "fruit-apple"),
                ("word_ids", "fruit-pear"),
                ("new_name", "Split HTML New"),
                ("new_description", "from html"),
                ("mode", "move"),
            ]
        ),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        follow_redirects=False,
    )

    assert resp.status_code == 303
    assert resp.headers["location"].startswith("/admin/global-packs/packs/gpk-")
    assert "flash_ok=gpk_split_move" in resp.headers["location"]

    source_detail = await acs.load_global_pack_definition_console(
        pack_id="gpk-html-split-src"
    )
    assert [w["id"] for w in source_detail["draft_words"]] == ["fruit-banana"]

    audit = await AuditLog.find_one(AuditLog.action == "global_pack.draft_split")
    assert audit is not None
    assert audit.target_id == "gpk-html-split-src"
    assert audit.payload_summary["mode"] == "move"


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
