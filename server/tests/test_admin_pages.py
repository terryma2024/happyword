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
async def test_admin_login_page_includes_icp_footer(client: AsyncClient) -> None:
    res = await client.get("/admin/login")

    assert res.status_code == 200
    assert "沪ICP备2026023209号-1" in res.text
    assert 'href="https://beian.miit.gov.cn/"' in res.text


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
async def test_admin_family_packs_page_renders_copy_action_dialogs(
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
    family, user = await create_family_for_parent(email="family-copy-html@example.com")
    await family_pack_service.create_definition(
        family_id=family.family_id,
        name="Family Copy From HTML",
        description=None,
        parent_user_id=user.username,
        pack_id="pck-html-copy-render",
    )

    page = await client.get("/admin/family-packs")

    assert page.status_code == 200
    soup = BeautifulSoup(page.text, "html.parser")
    action_cell = soup.find("td", attrs={"data-pack-actions": "pck-html-copy-render"})
    assert action_cell is not None
    visible_action_bar = action_cell.find("div", attrs={"data-action-buttons": "true"})
    assert visible_action_bar is not None
    assert visible_action_bar.find("textarea") is None
    assert visible_action_bar.find("input") is None
    assert visible_action_bar.find("button", string="复制为全局") is not None
    assert visible_action_bar.find("button", string="复制到家庭") is not None

    global_dialog = action_cell.find(
        "dialog", attrs={"id": "copy-global-pck-html-copy-render"}
    )
    family_dialog = action_cell.find(
        "dialog", attrs={"id": "copy-family-pck-html-copy-render"}
    )
    assert global_dialog is not None
    assert family_dialog is not None
    global_form = global_dialog.find(
        "form",
        attrs={"action": "/admin/family-packs/pck-html-copy-render/copy-to-global"},
    )
    family_form = family_dialog.find(
        "form",
        attrs={"action": "/admin/family-packs/pck-html-copy-render/copy-to-family"},
    )
    assert global_form is not None
    assert global_form.find("textarea", attrs={"name": "reason"}) is not None
    assert global_form.find("input", attrs={"name": "delete_source"}) is not None
    assert family_form is not None
    assert family_form.find("input", attrs={"name": "target_family_id"}) is not None
    assert family_form.find("textarea", attrs={"name": "reason"}) is not None
    assert family_form.find("input", attrs={"name": "delete_source"}) is not None


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_packs_page_links_readonly_detail_without_story_editor(
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
    family, user = await create_family_for_parent(email="family-story-html@example.com")
    await family_pack_service.create_definition(
        family_id=family.family_id,
        name="Family Story From HTML",
        description="family desc",
        parent_user_id=user.username,
        pack_id="pck-html-story-render",
        scene={
            "storyEn": "A family story glows on the server page.",
            "storyZh": "家庭小故事在服务端页面发光。",
        },
    )

    page = await client.get("/admin/family-packs")

    assert page.status_code == 200
    soup = BeautifulSoup(page.text, "html.parser")
    action_cell = soup.find("td", attrs={"data-pack-actions": "pck-html-story-render"})
    assert action_cell is not None
    action_bar = action_cell.find("div", attrs={"data-action-buttons": "true"})
    assert action_bar is not None
    detail_link = action_bar.find(
        "a", attrs={"href": "/admin/family-packs/pck-html-story-render"}
    )
    assert detail_link is not None
    assert detail_link.string == "详情"
    assert action_bar.find("button", string="编辑 story") is None
    assert action_cell.find("dialog", attrs={"id": "story-pck-html-story-render"}) is None
    assert "story/generate" not in page.text
    assert "/metadata" not in page.text


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_pack_detail_renders_story_and_words_readonly(
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
    family, user = await create_family_for_parent(email="family-story-edit@example.com")
    await family_pack_service.create_definition(
        family_id=family.family_id,
        name="Family Story Detail",
        description="family desc",
        parent_user_id=user.username,
        pack_id="pck-html-story-detail",
        scene={
            "bossName": "Keep Me",
            "storyEn": "A family lantern lights every word.",
            "storyZh": "家庭灯笼照亮每一个单词。",
        },
    )
    definition = await family_pack_service.get_definition_for_family(
        pack_id="pck-html-story-detail",
        family_id=family.family_id,
    )
    await family_pack_service.upsert_draft_word(
        definition=definition,
        word_id=f"{family.family_id}-apple",
        payload={
            "source": "custom",
            "word": "apple",
            "meaning_zh": "苹果",
            "category": "fruit",
            "difficulty": 1,
        },
        parent_user_id=user.username,
    )
    await family_pack_service.publish(
        definition=definition,
        parent_user_id=user.username,
        notes="v1",
    )

    page = await client.get("/admin/family-packs/pck-html-story-detail")

    assert page.status_code == 200
    soup = BeautifulSoup(page.text, "html.parser")
    assert soup.find("a", attrs={"href": "/admin/family-packs"}) is not None
    assert "Family Story Detail" in page.text
    assert "family desc" in page.text
    assert "A family lantern lights every word." in page.text
    assert "家庭灯笼照亮每一个单词。" in page.text
    assert "apple" in page.text
    assert "苹果" in page.text
    assert "v1" in page.text
    assert soup.find(
        "form", attrs={"action": "/admin/family-packs/pck-html-story-detail/metadata"}
    ) is None
    assert "story/generate" not in page.text
    assert soup.find("textarea", attrs={"name": "storyEn"}) is None
    assert soup.find("textarea", attrs={"name": "storyZh"}) is None


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_pack_story_edit_endpoints_are_removed(
    client: AsyncClient,
) -> None:
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)

    metadata = await client.post(
        "/admin/family-packs/pck-missing/metadata",
        data={"name": "X", "description": "", "storyEn": "x", "storyZh": "y"},
        follow_redirects=False,
    )
    generate = await client.post(
        "/admin/family-packs/pck-missing/story/generate",
        follow_redirects=False,
    )

    assert metadata.status_code == 404
    assert generate.status_code == 404


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
async def test_admin_family_pack_copy_to_global_copies_definition_and_draft(
    db: object,
) -> None:
    from app.models.family_pack_draft import FamilyPackDraft
    from app.models.family_pack_pointer import FamilyPackPointer
    from app.models.family_word_pack import FamilyWordPack
    from app.services import admin_console_service as acs
    from app.services import family_pack_service
    from app.services.family_pack_service import GLOBAL_PACK_FAMILY_ID
    from app.services.family_service import create_family_for_parent

    family, user = await create_family_for_parent(email="copy-global-src@example.com")
    definition = await family_pack_service.create_definition(
        family_id=family.family_id,
        name="Copy Source",
        description="source description",
        parent_user_id=user.username,
        scene={"bossName": "Dragon"},
        pack_id="pck-copy-global-src",
    )
    await family_pack_service.upsert_draft_word(
        definition=definition,
        word_id="apple",
        payload={"source": "global"},
        parent_user_id=user.username,
    )
    await family_pack_service.publish(
        definition=definition, parent_user_id=user.username, notes="source v1"
    )

    summary = await acs.admin_family_pack_copy(
        admin_username="console-admin",
        source_pack_id="pck-copy-global-src",
        target_kind="global",
        target_family_id=None,
        delete_source=False,
        reason="复制到全局词包",
    )

    assert summary.source_pack_id == "pck-copy-global-src"
    assert summary.source_family_id == family.family_id
    assert summary.target_family_id == GLOBAL_PACK_FAMILY_ID
    assert summary.target_pack_id.startswith("gpk-")
    assert summary.copied_word_count == 1
    assert summary.deleted_source is False

    target_definition = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == summary.target_pack_id
    )
    assert target_definition is not None
    assert target_definition.family_id == GLOBAL_PACK_FAMILY_ID
    assert target_definition.name == "Copy Source"
    assert target_definition.description == "source description"
    assert target_definition.scene == {"bossName": "Dragon"}

    target_draft = await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == summary.target_pack_id
    )
    assert target_draft is not None
    assert target_draft.family_id == GLOBAL_PACK_FAMILY_ID
    assert target_draft.words == [{"id": "apple"}]

    assert (
        await FamilyWordPack.find(
            FamilyWordPack.pack_definition_id == summary.target_pack_id
        ).count()
        == 0
    )
    assert await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == summary.target_pack_id
    ) is None

    audit = await AuditLog.find_one(AuditLog.action == "family_pack.copy_to_global")
    assert audit is not None
    assert audit.target_id == "pck-copy-global-src"
    assert audit.payload_summary["target_pack_id"] == summary.target_pack_id
    assert audit.payload_summary["copied_word_count"] == 1


@pytest.mark.asyncio
async def test_admin_family_pack_copy_to_family_creates_target_draft_and_unique_name(
    db: object,
) -> None:
    from app.models.family_pack_draft import FamilyPackDraft
    from app.models.family_pack_pointer import FamilyPackPointer
    from app.models.family_word_pack import FamilyWordPack
    from app.services import admin_console_service as acs
    from app.services import family_pack_service
    from app.services.family_service import create_family_for_parent

    source_family, source_user = await create_family_for_parent(
        email="copy-family-src@example.com"
    )
    target_family, target_user = await create_family_for_parent(
        email="copy-family-target@example.com"
    )
    source = await family_pack_service.create_definition(
        family_id=source_family.family_id,
        name="Shared Unit",
        description="unit desc",
        parent_user_id=source_user.username,
        pack_id="pck-copy-family-src",
    )
    await family_pack_service.create_definition(
        family_id=target_family.family_id,
        name="Shared Unit",
        description=None,
        parent_user_id=target_user.username,
        pack_id="pck-copy-family-existing",
    )
    await family_pack_service.upsert_draft_word(
        definition=source,
        word_id=f"fam-{source_family.family_id.removeprefix('fam-')[:8]}-cat",
        payload={
            "source": "custom",
            "word": "cat",
            "meaning_zh": "猫",
            "category": "animals",
            "difficulty": 1,
        },
        parent_user_id=source_user.username,
    )
    await family_pack_service.publish(
        definition=source, parent_user_id=source_user.username, notes="source v1"
    )

    summary = await acs.admin_family_pack_copy(
        admin_username="console-admin",
        source_pack_id="pck-copy-family-src",
        target_kind="family",
        target_family_id=target_family.family_id,
        delete_source=False,
        reason="复制给另一个家庭",
    )

    target_definition = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == summary.target_pack_id
    )
    assert target_definition is not None
    assert target_definition.family_id == target_family.family_id
    assert target_definition.name == "Shared Unit (copy)"
    target_draft = await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == summary.target_pack_id
    )
    assert target_draft is not None
    assert target_draft.words[0]["word"] == "cat"
    assert (
        await FamilyWordPack.find(
            FamilyWordPack.pack_definition_id == summary.target_pack_id
        ).count()
        == 0
    )
    assert await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == summary.target_pack_id
    ) is None


@pytest.mark.asyncio
async def test_admin_family_pack_copy_delete_source_removes_original_records(
    db: object,
) -> None:
    from app.models.family_pack_draft import FamilyPackDraft
    from app.models.family_pack_pointer import FamilyPackPointer
    from app.models.family_word_pack import FamilyWordPack
    from app.services import admin_console_service as acs
    from app.services import family_pack_service
    from app.services.family_service import create_family_for_parent

    source_family, source_user = await create_family_for_parent(
        email="copy-delete-src@example.com"
    )
    target_family, _ = await create_family_for_parent(
        email="copy-delete-target@example.com"
    )
    source = await family_pack_service.create_definition(
        family_id=source_family.family_id,
        name="Delete After Copy",
        description=None,
        parent_user_id=source_user.username,
        pack_id="pck-copy-delete-src",
    )
    await family_pack_service.upsert_draft_word(
        definition=source,
        word_id="banana",
        payload={"source": "global"},
        parent_user_id=source_user.username,
    )
    await family_pack_service.publish(
        definition=source, parent_user_id=source_user.username, notes="v1"
    )

    summary = await acs.admin_family_pack_copy(
        admin_username="console-admin",
        source_pack_id="pck-copy-delete-src",
        target_kind="family",
        target_family_id=target_family.family_id,
        delete_source=True,
        reason="复制后删除来源",
    )

    assert summary.deleted_source is True
    assert await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "pck-copy-delete-src"
    ) is None
    assert await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == "pck-copy-delete-src"
    ) is None
    assert await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == "pck-copy-delete-src"
    ) is None
    assert (
        await FamilyWordPack.find(
            FamilyWordPack.pack_definition_id == "pck-copy-delete-src"
        ).count()
        == 0
    )
    assert await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == summary.target_pack_id
    ) is not None


@pytest.mark.asyncio
async def test_admin_family_pack_copy_rejects_global_source_and_bad_target_family(
    db: object,
) -> None:
    from app.services import admin_console_service as acs
    from app.services import family_pack_service, global_pack_service
    from app.services.family_service import create_family_for_parent

    await global_pack_service.create_definition(
        name="Global Source",
        admin_id="console-admin",
        pack_id="gpk-copy-guard",
    )
    with pytest.raises(ValueError, match="全局词库"):
        await acs.admin_family_pack_copy(
            admin_username="console-admin",
            source_pack_id="gpk-copy-guard",
            target_kind="global",
            target_family_id=None,
            delete_source=False,
            reason="错误入口保护",
        )

    source_family, source_user = await create_family_for_parent(
        email="copy-guard-src@example.com"
    )
    await family_pack_service.create_definition(
        family_id=source_family.family_id,
        name="Guard Source",
        description=None,
        parent_user_id=source_user.username,
        pack_id="pck-copy-guard-src",
    )
    with pytest.raises(ValueError, match="未找到目标 family"):
        await acs.admin_family_pack_copy(
            admin_username="console-admin",
            source_pack_id="pck-copy-guard-src",
            target_kind="family",
            target_family_id="fam-missing",
            delete_source=False,
            reason="目标不存在",
        )
    with pytest.raises(ValueError, match="另外一个 family"):
        await acs.admin_family_pack_copy(
            admin_username="console-admin",
            source_pack_id="pck-copy-guard-src",
            target_kind="family",
            target_family_id=source_family.family_id,
            delete_source=False,
            reason="不能复制给自己",
        )


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_pack_copy_to_global_html_copies_and_audits(
    client: AsyncClient,
) -> None:
    from app.models.family_pack_draft import FamilyPackDraft
    from app.services import family_pack_service
    from app.services.family_pack_service import GLOBAL_PACK_FAMILY_ID
    from app.services.family_service import create_family_for_parent

    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    family, user = await create_family_for_parent(email="html-copy-global@example.com")
    definition = await family_pack_service.create_definition(
        family_id=family.family_id,
        name="HTML Copy Global",
        description=None,
        parent_user_id=user.username,
        pack_id="pck-html-copy-global",
    )
    await family_pack_service.upsert_draft_word(
        definition=definition,
        word_id="apple",
        payload={"source": "global"},
        parent_user_id=user.username,
    )

    res = await client.post(
        "/admin/family-packs/pck-html-copy-global/copy-to-global",
        data={"reason": "复制为全局词包"},
        follow_redirects=False,
    )

    assert res.status_code == 303
    assert res.headers["location"] == "/admin/family-packs?flash_ok=copied_global"
    copied = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.family_id == GLOBAL_PACK_FAMILY_ID,
        FamilyPackDefinition.name == "HTML Copy Global",
    )
    assert copied is not None
    copied_draft = await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == copied.pack_id
    )
    assert copied_draft is not None
    assert copied_draft.words == [{"id": "apple"}]
    audit = await AuditLog.find_one(AuditLog.action == "family_pack.copy_to_global")
    assert audit is not None


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_pack_copy_to_family_html_can_delete_source(
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
    source_family, source_user = await create_family_for_parent(
        email="html-copy-family-src@example.com"
    )
    target_family, _ = await create_family_for_parent(
        email="html-copy-family-target@example.com"
    )
    await family_pack_service.create_definition(
        family_id=source_family.family_id,
        name="HTML Copy Family",
        description=None,
        parent_user_id=source_user.username,
        pack_id="pck-html-copy-family",
    )

    res = await client.post(
        "/admin/family-packs/pck-html-copy-family/copy-to-family",
        data={
            "target_family_id": target_family.family_id,
            "reason": "复制给另一个家庭",
            "delete_source": "on",
        },
        follow_redirects=False,
    )

    assert res.status_code == 303
    assert res.headers["location"] == "/admin/family-packs?flash_ok=copied_family"
    assert await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "pck-html-copy-family"
    ) is None
    copied = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.family_id == target_family.family_id,
        FamilyPackDefinition.name == "HTML Copy Family",
    )
    assert copied is not None
    audit = await AuditLog.find_one(AuditLog.action == "family_pack.copy_to_family")
    assert audit is not None
    assert audit.payload_summary["deleted_source"] is True


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
        scene={
            "storyEn": "A global story waits for editing.",
            "storyZh": "一个全局小故事等着编辑。",
        },
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
    metadata_form = soup.find(id="global-pack-metadata-form")
    assert metadata_form is not None
    assert metadata_form.get("action") == "/admin/global-packs/packs/gpk-html-split-ui/metadata"
    assert soup.find("textarea", attrs={"name": "storyEn"}) is not None
    assert soup.find("textarea", attrs={"name": "storyZh"}) is not None
    story_button = soup.find(id="global-pack-story-generate-submit")
    assert story_button is not None
    assert story_button.get_text(strip=True) == "🔄"
    assert story_button.get("form") == "global-pack-story-generate-form"
    assert story_button.get("data-submitting-label") == "..."
    story_form = soup.find(id="global-pack-story-generate-form")
    assert story_form is not None
    assert story_form.get("data-disable-on-submit") == "true"
    cover_form = soup.find(id="global-pack-cover-generate-form")
    assert cover_form is not None
    assert cover_form.get("action") == "/admin/global-packs/packs/gpk-html-split-ui/cover/generate"
    assert cover_form.get("data-disable-on-submit") == "true"
    cover_button = soup.find(id="global-pack-cover-generate-submit")
    assert cover_button is not None
    assert cover_button.get_text(strip=True) == "生成封面"
    assert cover_button.get("data-submitting-label") == "生成中，请稍候..."
    assert 'form.dataset.submitting === "true"' in page.text
    assert "submitButton.disabled = true" in page.text
    assert "A global story waits for editing." in page.text
    assert "一个全局小故事等着编辑。" in page.text


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_global_pack_metadata_form_updates_story_fields(
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
        name="Metadata Story",
        admin_id="console-admin",
        pack_id="gpk-html-story-edit",
        scene={"bossName": "Keep Me"},
    )

    resp = await client.post(
        "/admin/global-packs/packs/gpk-html-story-edit/metadata",
        data={
            "name": "Metadata Story",
            "description": "short desc",
            "storyEn": "A bright key unlocks the global pack.",
            "storyZh": "明亮钥匙打开了全局词包。",
        },
        follow_redirects=False,
    )

    assert resp.status_code == 303
    refreshed = await global_pack_service.get_definition(pack_id="gpk-html-story-edit")
    assert refreshed.description == "short desc"
    assert refreshed.scene["bossName"] == "Keep Me"
    assert refreshed.scene["storyEn"] == "A bright key unlocks the global pack."
    assert refreshed.scene["storyZh"] == "明亮钥匙打开了全局词包。"


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_global_pack_story_generate_form_updates_scene(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import global_pack_service, pack_story_service

    async def fake_generate_pack_story(
        *, pack_name: str, words: list[dict[str, object]]
    ) -> tuple[str, dict[str, str]]:
        assert pack_name == "Global Generate"
        assert words[0]["word"] == "moon"
        return (
            "fake-story-model",
            {
                "storyEn": "Moon words shimmer across a silver classroom.",
                "storyZh": "月亮单词照亮银色教室。",
            },
        )

    monkeypatch.setattr(pack_story_service, "generate_pack_story", fake_generate_pack_story)
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    await global_pack_service.create_definition(
        name="Global Generate",
        admin_id="console-admin",
        pack_id="gpk-html-story-generate",
    )
    await global_pack_service.upsert_draft_word(
        pack_id="gpk-html-story-generate",
        admin_id="console-admin",
        entry={
            "id": "moon",
            "word": "moon",
            "meaningZh": "月亮",
            "category": "sky",
            "difficulty": 1,
        },
    )

    resp = await client.post(
        "/admin/global-packs/packs/gpk-html-story-generate/story/generate",
        follow_redirects=False,
    )

    assert resp.status_code == 303
    refreshed = await global_pack_service.get_definition(pack_id="gpk-html-story-generate")
    assert refreshed.scene["storyEn"] == "Moon words shimmer across a silver classroom."
    assert refreshed.scene["storyZh"] == "月亮单词照亮银色教室。"


@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_global_pack_cover_generate_form_updates_scene(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import global_pack_service, spellbook_cover_service

    async def fake_generate_and_attach_spellbook_cover(
        *,
        definition: FamilyPackDefinition,
        words: list[dict[str, object]],
    ) -> tuple[str, str, FamilyPackDefinition]:
        assert definition.pack_id == "gpk-html-cover-generate"
        assert words == []
        definition.scene = {
            **definition.scene,
            "spellbookCoverUrl": "https://assets.example.test/covers/html-cover.png",
        }
        await definition.save()
        return "fake-image-model", definition.scene["spellbookCoverUrl"], definition

    monkeypatch.setattr(
        spellbook_cover_service,
        "generate_and_attach_spellbook_cover",
        fake_generate_and_attach_spellbook_cover,
    )
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)
    await global_pack_service.create_definition(
        name="HTML Cover Generate",
        admin_id="console-admin",
        pack_id="gpk-html-cover-generate",
        scene={"storyZh": "封面生成测试。"},
    )

    resp = await client.post(
        "/admin/global-packs/packs/gpk-html-cover-generate/cover/generate",
        follow_redirects=False,
    )

    assert resp.status_code == 303
    assert resp.headers["location"].endswith("flash_ok=cover_generated")
    refreshed = await global_pack_service.get_definition(pack_id="gpk-html-cover-generate")
    assert (
        refreshed.scene["spellbookCoverUrl"]
        == "https://assets.example.test/covers/html-cover.png"
    )


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
async def test_admin_system_config_can_change_image_provider(
    client: AsyncClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("DASHSCOPE_API_KEY", "sk-test-dashscope")
    from app.config import get_settings  # noqa: PLC0415
    from app.models.system_config import SystemConfig  # noqa: PLC0415
    from app.routers import admin_pages  # noqa: PLC0415

    get_settings.cache_clear()

    async def _fake_connectivity(**kwargs: object) -> object:
        return {"provider_id": kwargs["provider_id"], "model": "qwen-image"}

    monkeypatch.setattr(admin_pages, "test_image_provider_connectivity", _fake_connectivity)
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)

    page = await client.get("/admin/system-config")
    assert page.status_code == 200
    assert "魔法书封面生成模型" in page.text
    assert "Qwen Image" in page.text
    assert "Doubao Seedream" in page.text
    assert "doubao-seedream-4-5-251128" in page.text

    saved = await client.post(
        "/admin/system-config/image-provider",
        data={"image_provider": "qwen"},
        follow_redirects=False,
    )

    assert saved.status_code == 303
    assert saved.headers["location"] == "/admin/system-config?flash_ok=image_provider_updated"
    row = await SystemConfig.find_one(SystemConfig.key == "image_provider")
    assert row is not None
    assert row.value == "qwen"
    assert row.updated_by == "console-admin"


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
