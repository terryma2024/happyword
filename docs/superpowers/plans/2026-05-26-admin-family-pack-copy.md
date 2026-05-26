# Admin Family Pack Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build admin-console controls that copy a family word pack into a new global pack or into another family, optionally deleting the source afterward.

**Architecture:** Keep the behavior in `admin_console_service` because this is a privileged HTML-console operation with audit requirements. Reuse the existing family/global pack persistence stack: target packs are new `FamilyPackDefinition` + `FamilyPackDraft` records, with no copied `FamilyWordPack` versions or `FamilyPackPointer`. Add two HTML POST routes and compact row forms on `/admin/family-packs`.

**Tech Stack:** Python 3.12, FastAPI, Beanie ODM, Jinja2 templates, pytest/pytest-asyncio, mongomock-backed tests.

---

## File Structure

- Modify `server/app/services/admin_console_service.py`
  - Add a copy summary dataclass.
  - Add name allocation helper.
  - Add `admin_family_pack_copy(...)`.
  - Reuse `validate_reason_text`, `record_admin_action`, `fps.delete_definition`, `fps.create_definition`, `gpk_svc.create_definition`, and `FamilyPackDraft`.
- Modify `server/app/routers/admin_pages.py`
  - Add flash messages.
  - Add `POST /admin/family-packs/{pack_id}/copy-to-global`.
  - Add `POST /admin/family-packs/{pack_id}/copy-to-family`.
- Modify `server/app/templates/admin/family_packs_list.html`
  - Render two copy forms per family-pack row.
- Modify `server/tests/test_admin_pages.py`
  - Add service and HTML tests near existing family-pack admin tests.
- Run targeted tests first, then the full server suite.

---

### Task 1: Service Copy To Global

**Files:**
- Modify: `server/tests/test_admin_pages.py`
- Modify: `server/app/services/admin_console_service.py`

- [ ] **Step 1: Write the failing service test**

Add imports inside the test function as existing tests do. Append this test after `test_admin_family_pack_delete_rejects_global_sentinel`:

```python
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

    assert await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == summary.target_pack_id
    ).count() == 0
    assert await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == summary.target_pack_id
    ) is None

    audit = await AuditLog.find_one(AuditLog.action == "family_pack.copy_to_global")
    assert audit is not None
    assert audit.target_id == "pck-copy-global-src"
    assert audit.payload_summary["target_pack_id"] == summary.target_pack_id
    assert audit.payload_summary["copied_word_count"] == 1
```

- [ ] **Step 2: Run the failing test**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_pack_copy_to_global_copies_definition_and_draft -q
```

Expected: fail because `admin_family_pack_copy` does not exist.

- [ ] **Step 3: Implement the minimal service behavior**

In `server/app/services/admin_console_service.py`, add near imports:

```python
from dataclasses import dataclass
from typing import Literal
```

If `typing.Any` already exists, combine imports as needed. Add near constants:

```python
@dataclass(frozen=True)
class AdminFamilyPackCopySummary:
    source_pack_id: str
    source_family_id: str
    target_pack_id: str
    target_family_id: str
    copied_word_count: int
    deleted_source: bool
```

Add helpers near mutation helpers:

```python
async def _next_copy_name(*, base_name: str, target_family_id: str) -> str:
    root = base_name.strip() or "Copied pack"
    candidates = [root, f"{root} (copy)"]
    for n in range(2, 101):
        candidates.append(f"{root} (copy {n})")
    for candidate in candidates:
        existing = await FamilyPackDefinition.find(
            FamilyPackDefinition.family_id == target_family_id,
            FamilyPackDefinition.name == candidate,
        ).first_or_none()
        if existing is None:
            return candidate
    raise ValueError("目标范围内同名词包过多，请先重命名后再复制。")
```

Add the service:

```python
async def admin_family_pack_copy(
    *,
    admin_username: str,
    source_pack_id: str,
    target_kind: Literal["global", "family"],
    target_family_id: str | None,
    delete_source: bool,
    reason: str,
) -> AdminFamilyPackCopySummary:
    r = validate_reason_text(reason)
    source = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == source_pack_id
    )
    if source is None:
        raise LookupError("pack_not_found")
    if source.family_id == fps.GLOBAL_PACK_FAMILY_ID:
        raise ValueError("请通过「全局词库」页面管理官方全局词包。")

    if target_kind == "global":
        resolved_target_family_id = fps.GLOBAL_PACK_FAMILY_ID
    elif target_kind == "family":
        fid = (target_family_id or "").strip()
        if not fid:
            raise ValueError("目标 family_id 不能为空。")
        if fid == source.family_id:
            raise ValueError("请选择另外一个 family 作为复制目标。")
        target_family = await Family.find_one(Family.family_id == fid)
        if target_family is None:
            raise ValueError("未找到目标 family。")
        resolved_target_family_id = fid
    else:
        raise ValueError("未知复制目标。")

    target_name = await _next_copy_name(
        base_name=source.name,
        target_family_id=resolved_target_family_id,
    )
    source_draft = await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == source.pack_id,
        FamilyPackDraft.family_id == source.family_id,
    )
    copied_words = [dict(word) for word in source_draft.words] if source_draft else []

    if target_kind == "global":
        target = await gpk_svc.create_definition(
            name=target_name,
            admin_id=admin_username,
            description=source.description,
            scene=dict(source.scene),
        )
    else:
        target = await fps.create_definition(
            family_id=resolved_target_family_id,
            name=target_name,
            description=source.description,
            scene=dict(source.scene),
            parent_user_id=f"admin:{admin_username}",
        )

    now = datetime.now(tz=UTC)
    target_draft = FamilyPackDraft(
        pack_definition_id=target.pack_id,
        family_id=target.family_id,
        words=copied_words,
        updated_at=now,
        updated_by_parent_id=f"admin:{admin_username}",
    )
    await target_draft.insert()
    target.updated_at = now
    await target.save()

    if delete_source:
        await fps.delete_definition(pack_id=source.pack_id, family_id=source.family_id)

    summary = AdminFamilyPackCopySummary(
        source_pack_id=source.pack_id,
        source_family_id=source.family_id,
        target_pack_id=target.pack_id,
        target_family_id=target.family_id,
        copied_word_count=len(copied_words),
        deleted_source=delete_source,
    )
    await record_admin_action(
        admin_username=admin_username,
        action=(
            "family_pack.copy_to_global"
            if target_kind == "global"
            else "family_pack.copy_to_family"
        ),
        target_collection="family_pack_definitions",
        target_id=source.pack_id,
        payload_summary={"reason": r, **summary.__dict__},
    )
    return summary
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_pack_copy_to_global_copies_definition_and_draft -q
```

Expected: pass with 0 warnings.

---

### Task 2: Service Family Target, Delete Source, and Guards

**Files:**
- Modify: `server/tests/test_admin_pages.py`
- Modify: `server/app/services/admin_console_service.py`

- [ ] **Step 1: Write failing tests for family target, delete source, and guard behavior**

Add these tests after the Task 1 test:

```python
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
    assert await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == summary.target_pack_id
    ).count() == 0
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
    assert await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == "pck-copy-delete-src"
    ).count() == 0
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
```

- [ ] **Step 2: Run the new tests**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_pack_copy_to_family_creates_target_draft_and_unique_name tests/test_admin_pages.py::test_admin_family_pack_copy_delete_source_removes_original_records tests/test_admin_pages.py::test_admin_family_pack_copy_rejects_global_source_and_bad_target_family -q
```

Expected: pass if Task 1 implementation already satisfies these, otherwise fail on missing guard/name behavior.

- [ ] **Step 3: Adjust implementation if needed**

If the tests fail, update only `admin_console_service.py` to satisfy them:

- ensure `_next_copy_name` checks all definitions in the target family, not just active rows;
- ensure source and target same family raises `ValueError("请选择另外一个 family 作为复制目标。")`;
- ensure missing target family raises `ValueError("未找到目标 family。")`;
- ensure `delete_source=True` calls `fps.delete_definition(...)` after target draft insertion.

- [ ] **Step 4: Run service tests together**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_pack_copy_to_global_copies_definition_and_draft tests/test_admin_pages.py::test_admin_family_pack_copy_to_family_creates_target_draft_and_unique_name tests/test_admin_pages.py::test_admin_family_pack_copy_delete_source_removes_original_records tests/test_admin_pages.py::test_admin_family_pack_copy_rejects_global_source_and_bad_target_family -q
```

Expected: all pass with 0 warnings.

---

### Task 3: HTML Routes

**Files:**
- Modify: `server/tests/test_admin_pages.py`
- Modify: `server/app/routers/admin_pages.py`

- [ ] **Step 1: Write failing HTML route tests**

Append these tests near existing family-pack admin HTML tests:

```python
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
```

- [ ] **Step 2: Run route tests to verify failure**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_pack_copy_to_global_html_copies_and_audits tests/test_admin_pages.py::test_admin_family_pack_copy_to_family_html_can_delete_source -q
```

Expected: fail with 404 because routes do not exist.

- [ ] **Step 3: Implement routes and flash messages**

In `_flash_map_family`, add:

```python
"copied_global": "已复制家庭词包为新的全局词包草稿。",
"copied_family": "已复制家庭词包给目标家庭。",
```

After `admin_family_delete_post`, add:

```python
@router.post("/family-packs/{pack_id}/copy-to-global", response_model=None)
async def admin_family_copy_to_global_post(
    request: Request,
    pack_id: str,
    reason: str = Form(...),
    delete_source: str | None = Form(None),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_family_pack_copy(
            admin_username=gate.username,
            source_pack_id=pack_id,
            target_kind="global",
            target_family_id=None,
            delete_source=delete_source is not None,
            reason=reason,
        )
    except LookupError:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    return RedirectResponse(url="/admin/family-packs?flash_ok=copied_global", status_code=303)


@router.post("/family-packs/{pack_id}/copy-to-family", response_model=None)
async def admin_family_copy_to_family_post(
    request: Request,
    pack_id: str,
    target_family_id: str = Form(...),
    reason: str = Form(...),
    delete_source: str | None = Form(None),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_family_pack_copy(
            admin_username=gate.username,
            source_pack_id=pack_id,
            target_kind="family",
            target_family_id=target_family_id,
            delete_source=delete_source is not None,
            reason=reason,
        )
    except LookupError:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    return RedirectResponse(url="/admin/family-packs?flash_ok=copied_family", status_code=303)
```

- [ ] **Step 4: Run route tests**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_pack_copy_to_global_html_copies_and_audits tests/test_admin_pages.py::test_admin_family_pack_copy_to_family_html_can_delete_source -q
```

Expected: pass with 0 warnings.

---

### Task 4: HTML Forms

**Files:**
- Modify: `server/tests/test_admin_pages.py`
- Modify: `server/app/templates/admin/family_packs_list.html`

- [ ] **Step 1: Write failing render test**

Add this test near `test_admin_family_packs_page_renders_delete_form`:

```python
@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_family_packs_page_renders_copy_forms(
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
    global_form = soup.find(
        "form",
        attrs={"action": "/admin/family-packs/pck-html-copy-render/copy-to-global"},
    )
    family_form = soup.find(
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
```

- [ ] **Step 2: Run render test to verify failure**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_packs_page_renders_copy_forms -q
```

Expected: fail because the copy forms are not rendered.

- [ ] **Step 3: Add forms to family pack row**

In `server/app/templates/admin/family_packs_list.html`, inside the operation cell before rollback/delete forms, add:

```html
            <form method="post" action="/admin/family-packs/{{ d.pack_id }}/copy-to-global" class="space-y-1"
                  onsubmit="return confirm('确认复制为新的全局词包草稿？发布历史和指针不会复制。');">
              <textarea name="reason" placeholder="复制原因（≥4 字）" rows="2" required class="w-full text-xs rounded border border-slate-300 px-2 py-1"></textarea>
              <label class="flex items-center gap-1 text-xs text-slate-600">
                <input type="checkbox" name="delete_source" class="rounded border-slate-300" />
                同时删除原 family 词包
              </label>
              <button type="submit" class="text-xs bg-sky-700 text-white px-2 py-1 rounded">复制为全局</button>
            </form>
            <form method="post" action="/admin/family-packs/{{ d.pack_id }}/copy-to-family" class="space-y-1"
                  onsubmit="return confirm('确认复制给另一个 family？发布历史和指针不会复制。');">
              <input name="target_family_id" placeholder="目标 family_id" required class="w-full text-xs rounded border border-slate-300 px-2 py-1" />
              <textarea name="reason" placeholder="复制原因（≥4 字）" rows="2" required class="w-full text-xs rounded border border-slate-300 px-2 py-1"></textarea>
              <label class="flex items-center gap-1 text-xs text-slate-600">
                <input type="checkbox" name="delete_source" class="rounded border-slate-300" />
                同时删除原 family 词包
              </label>
              <button type="submit" class="text-xs bg-indigo-700 text-white px-2 py-1 rounded">复制到家庭</button>
            </form>
```

- [ ] **Step 4: Run render test**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_packs_page_renders_copy_forms -q
```

Expected: pass with 0 warnings.

---

### Task 5: Verification and Cleanup

**Files:**
- Review: `server/app/services/admin_console_service.py`
- Review: `server/app/routers/admin_pages.py`
- Review: `server/app/templates/admin/family_packs_list.html`
- Review: `server/tests/test_admin_pages.py`

- [ ] **Step 1: Run targeted admin page tests**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py -q
```

Expected: all pass with 0 warnings.

- [ ] **Step 2: Run full server suite**

Run:

```sh
cd server && uv run pytest
```

Expected: all pass with 0 errors and 0 warnings.

- [ ] **Step 3: Inspect changed files**

Run:

```sh
git diff -- server/app/services/admin_console_service.py server/app/routers/admin_pages.py server/app/templates/admin/family_packs_list.html server/tests/test_admin_pages.py docs/superpowers/plans/2026-05-26-admin-family-pack-copy.md
```

Expected: changes are limited to the planned service, route, template, tests, and plan.

- [ ] **Step 4: Commit implementation**

Run:

```sh
git add docs/superpowers/plans/2026-05-26-admin-family-pack-copy.md server/app/services/admin_console_service.py server/app/routers/admin_pages.py server/app/templates/admin/family_packs_list.html server/tests/test_admin_pages.py
git commit -m "feat(server): copy family packs from admin console"
```

Expected: commit succeeds after tests are green.
