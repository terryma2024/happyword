# Admin Global Pack Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add audited hard deletion for admin-managed global pack definitions, including drafts, published versions, and pointers.

**Architecture:** Put the deletion primitive in `global_pack_service` so JSON API and HTML console use the same cleanup behavior. Keep admin reason validation and audit logging in `admin_console_service`, matching existing high-risk admin actions. Add a destructive HTML form to the global packs list and a `DELETE` JSON route for scripted cleanup.

**Tech Stack:** FastAPI, Beanie documents, Jinja templates, pytest + httpx async tests.

---

## File Structure

- Modify `server/app/services/global_pack_service.py`: add a deletion summary dataclass and `delete_definition`.
- Modify `server/app/schemas/global_pack.py`: add `GlobalPackDeleteOut` API response schema.
- Modify `server/app/routers/admin_global_pack.py`: add `DELETE /api/v1/admin/global-packs/{pack_id}`.
- Modify `server/app/services/admin_console_service.py`: add audited `admin_delete_global_pack_definition`.
- Modify `server/app/routers/admin_pages.py`: add HTML POST route and flash mapping.
- Modify `server/app/templates/admin/global_packs.html`: add per-row destructive delete form.
- Modify `server/tests/test_admin_global_pack_router.py`: add JSON deletion tests.
- Modify `server/tests/test_admin_pages.py`: add HTML render/delete/audit tests.

### Task 1: JSON API Hard Delete

**Files:**
- Modify: `server/tests/test_admin_global_pack_router.py`
- Modify: `server/app/services/global_pack_service.py`
- Modify: `server/app/schemas/global_pack.py`
- Modify: `server/app/routers/admin_global_pack.py`

- [ ] **Step 1: Write failing JSON deletion test**

Add imports:

```python
from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
```

Add test:

```python
@pytest.mark.asyncio
async def test_admin_delete_global_pack_removes_all_pack_records(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "Delete Me", "pack_id": "gpk-delete-me"},
        headers=headers,
    )
    word_payload = {
        "id": "fruit-apple",
        "word": "apple",
        "meaningZh": "苹果",
        "category": "fruit",
        "difficulty": 1,
    }
    await client.put(
        "/api/v1/admin/global-packs/gpk-delete-me/draft/words/fruit-apple",
        json=word_payload,
        headers=headers,
    )
    await client.post(
        "/api/v1/admin/global-packs/gpk-delete-me/publish",
        json={"notes": "v1"},
        headers=headers,
    )
    await client.put(
        "/api/v1/admin/global-packs/gpk-delete-me/draft/words/fruit-banana",
        json={**word_payload, "id": "fruit-banana", "word": "banana"},
        headers=headers,
    )
    await client.post(
        "/api/v1/admin/global-packs/gpk-delete-me/publish",
        json={"notes": "v2"},
        headers=headers,
    )

    res = await client.delete(
        "/api/v1/admin/global-packs/gpk-delete-me",
        headers=headers,
    )

    assert res.status_code == 200, res.text
    body = res.json()
    assert body == {
        "pack_id": "gpk-delete-me",
        "deleted_definition_count": 1,
        "deleted_draft_count": 1,
        "deleted_version_count": 2,
        "deleted_pointer_count": 1,
    }
    assert await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == "gpk-delete-me"
    ) is None
    assert await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == "gpk-delete-me"
    ) is None
    assert await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == "gpk-delete-me"
    ) is None
    assert await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == "gpk-delete-me"
    ).count() == 0

    listed = await client.get("/api/v1/admin/global-packs", headers=headers)
    assert all(row["pack_id"] != "gpk-delete-me" for row in listed.json())
```

- [ ] **Step 2: Write failing unknown-pack test**

```python
@pytest.mark.asyncio
async def test_admin_delete_unknown_global_pack_returns_404(
    client: AsyncClient, admin: User
) -> None:
    res = await client.delete(
        "/api/v1/admin/global-packs/gpk-missing",
        headers=_bearer(admin.username),
    )

    assert res.status_code == 404
    assert res.json()["detail"]["error"]["code"] == "PACK_NOT_FOUND"
```

- [ ] **Step 3: Verify RED**

Run:

```sh
cd server && uv run pytest tests/test_admin_global_pack_router.py::test_admin_delete_global_pack_removes_all_pack_records tests/test_admin_global_pack_router.py::test_admin_delete_unknown_global_pack_returns_404 -q
```

Expected: fail with 405 or missing route.

- [ ] **Step 4: Add minimal implementation**

In `global_pack_service.py`, add:

```python
from dataclasses import dataclass
```

```python
@dataclass(frozen=True)
class GlobalPackDeleteSummary:
    pack_id: str
    deleted_definition_count: int
    deleted_draft_count: int
    deleted_version_count: int
    deleted_pointer_count: int
```

```python
async def delete_definition(*, pack_id: str) -> GlobalPackDeleteSummary:
    definition = await get_definition(pack_id=pack_id)
    draft_count = await FamilyPackDraft.find(
        FamilyPackDraft.pack_definition_id == pack_id,
        FamilyPackDraft.family_id == GLOBAL_PACK_FAMILY_ID,
    ).count()
    version_count = await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == pack_id,
        FamilyWordPack.family_id == GLOBAL_PACK_FAMILY_ID,
    ).count()
    pointer_count = await FamilyPackPointer.find(
        FamilyPackPointer.pack_definition_id == pack_id,
        FamilyPackPointer.family_id == GLOBAL_PACK_FAMILY_ID,
    ).count()

    await FamilyPackDraft.find(
        FamilyPackDraft.pack_definition_id == pack_id,
        FamilyPackDraft.family_id == GLOBAL_PACK_FAMILY_ID,
    ).delete()
    await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == pack_id,
        FamilyWordPack.family_id == GLOBAL_PACK_FAMILY_ID,
    ).delete()
    await FamilyPackPointer.find(
        FamilyPackPointer.pack_definition_id == pack_id,
        FamilyPackPointer.family_id == GLOBAL_PACK_FAMILY_ID,
    ).delete()
    await definition.delete()

    return GlobalPackDeleteSummary(
        pack_id=pack_id,
        deleted_definition_count=1,
        deleted_draft_count=draft_count,
        deleted_version_count=version_count,
        deleted_pointer_count=pointer_count,
    )
```

In `schemas/global_pack.py`, add:

```python
class GlobalPackDeleteOut(BaseModel):
    pack_id: str
    deleted_definition_count: int
    deleted_draft_count: int
    deleted_version_count: int
    deleted_pointer_count: int
```

In `admin_global_pack.py`, import `GlobalPackDeleteOut` and add:

```python
@router.delete(
    "/{pack_id}",
    response_model=GlobalPackDeleteOut,
)
async def delete_global_pack(
    pack_id: str,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> GlobalPackDeleteOut:
    _ = admin
    try:
        summary = await svc.delete_definition(pack_id=pack_id)
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    return GlobalPackDeleteOut(**summary.__dict__)
```

- [ ] **Step 5: Verify GREEN**

Run the same targeted command. Expected: both tests pass.

### Task 2: HTML Console Delete

**Files:**
- Modify: `server/tests/test_admin_pages.py`
- Modify: `server/app/services/admin_console_service.py`
- Modify: `server/app/routers/admin_pages.py`
- Modify: `server/app/templates/admin/global_packs.html`

- [ ] **Step 1: Write failing HTML tests**

Add imports:

```python
from app.models.audit_log import AuditLog
from app.models.family_pack_definition import FamilyPackDefinition
```

Add test:

```python
@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_global_packs_page_renders_delete_form(
    client: AsyncClient,
) -> None:
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)

    from app.services import global_pack_service

    await global_pack_service.create_definition(
        name="Delete From HTML",
        admin_id="console-admin",
        pack_id="gpk-html-delete",
    )

    page = await client.get("/admin/global-packs")

    assert page.status_code == 200
    assert "/admin/global-packs/packs/gpk-html-delete/delete" in page.text
    assert "删除" in page.text
```

Add test:

```python
@pytest.mark.asyncio
@pytest.mark.usefixtures("admin_console_admin")
async def test_admin_global_pack_html_delete_removes_pack_and_audits(
    client: AsyncClient,
) -> None:
    login = await client.post(
        "/admin/login",
        data={"username": "console-admin", "password": _CONSOLE_PW},
        follow_redirects=False,
    )
    client.cookies.update(login.cookies)

    from app.services import global_pack_service

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
```

- [ ] **Step 2: Verify RED**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_global_packs_page_renders_delete_form tests/test_admin_pages.py::test_admin_global_pack_html_delete_removes_pack_and_audits -q
```

Expected: fail because route/form do not exist.

- [ ] **Step 3: Add admin wrapper**

In `admin_console_service.py`, add:

```python
async def admin_delete_global_pack_definition(
    *, admin_username: str, pack_id: str, reason: str
) -> gpk_svc.GlobalPackDeleteSummary:
    r = validate_reason_text(reason)
    try:
        summary = await gpk_svc.delete_definition(pack_id=pack_id)
    except gpk_svc.PackNotFound as exc:
        raise LookupError("pack_not_found") from exc
    await record_admin_action(
        admin_username=admin_username,
        action="global_pack.definition_delete",
        target_collection="family_pack_definitions",
        target_id=pack_id,
        payload_summary={"reason": r, **summary.__dict__},
    )
    return summary
```

- [ ] **Step 4: Add HTML route and flash label**

In `admin_pages.py`, add a flash mapping for `gpk_deleted` to `已删除全局词包。`, then add:

```python
@router.post("/global-packs/packs/{pack_id}/delete", response_model=None)
async def admin_global_pack_delete_definition_post(
    request: Request,
    pack_id: str,
    reason: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    try:
        await acs.admin_delete_global_pack_definition(
            admin_username=gate.username,
            pack_id=pid,
            reason=reason,
        )
    except ValueError as e:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(e)),
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    return RedirectResponse(url="/admin/global-packs?flash_ok=gpk_deleted", status_code=303)
```

- [ ] **Step 5: Add list-row form**

In `global_packs.html`, update the action cell to include a small inline form:

```html
<div class="flex flex-wrap justify-end items-center gap-2">
  <a href="/admin/global-packs/packs/{{ d.pack_id }}" class="text-sky-600 hover:underline">管理</a>
  <form method="post" action="/admin/global-packs/packs/{{ d.pack_id }}/delete" class="inline-flex items-center gap-1"
        onsubmit="return confirm('确认永久删除全局词包 {{ d.name }}（{{ d.pack_id }}）？此操作会删除草稿、发布版本和指针，无法撤销。');">
    <input type="text" name="reason" required minlength="4" placeholder="删除原因"
           class="w-28 rounded-md border border-red-200 px-2 py-1 text-xs" />
    <button type="submit" class="rounded-md border border-red-200 px-2 py-1 text-xs text-red-700 hover:bg-red-50">删除</button>
  </form>
</div>
```

- [ ] **Step 6: Verify GREEN**

Run the same targeted HTML command. Expected: both tests pass.

### Task 3: Final Verification

**Files:**
- No new files.

- [ ] **Step 1: Run focused server tests**

```sh
cd server && uv run pytest tests/test_admin_global_pack_router.py tests/test_admin_pages.py -q
```

Expected: all selected tests pass with no warnings.

- [ ] **Step 2: Run full server suite**

```sh
cd server && uv run pytest
```

Expected: full suite passes with 0 errors and 0 warnings.

- [ ] **Step 3: Commit implementation**

```sh
git add docs/superpowers/plans/2026-05-22-admin-global-pack-delete.md server/app/services/global_pack_service.py server/app/schemas/global_pack.py server/app/routers/admin_global_pack.py server/app/services/admin_console_service.py server/app/routers/admin_pages.py server/app/templates/admin/global_packs.html server/tests/test_admin_global_pack_router.py server/tests/test_admin_pages.py
git commit -m "feat: delete admin global packs"
```

Expected: commit succeeds.
