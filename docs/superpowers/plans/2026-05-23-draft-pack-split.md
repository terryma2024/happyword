# Draft Pack Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a server-side draft split feature that creates a new family/global word pack from selected draft words, with both copy and move modes.

**Architecture:** Put the split behavior in `family_pack_service` so family packs and global packs share one persistence path. Family and admin routers provide scope-specific schemas, auth, response serialization, and error mapping. HTML pages reuse the API semantics through server-side form handlers, while E2E tests prove the published split output reaches child/public latest endpoints.

**Tech Stack:** Python, FastAPI, Beanie, Pydantic v2, Jinja templates, pytest, httpx ASGITransport, preview E2E pytest.

---

## File Structure

- Modify `server/app/services/family_pack_service.py`: add `DraftWordNotFound`, `DraftSplitResult`, and `split_draft_to_new_pack`.
- Modify `server/app/services/global_pack_service.py`: add thin global split wrapper.
- Modify `server/app/schemas/family_pack.py`: add family split request/response schemas.
- Modify `server/app/schemas/global_pack.py`: add global split request/response schemas.
- Modify `server/app/routers/parent_family_pack.py`: add family split API endpoint.
- Modify `server/app/routers/admin_global_pack.py`: add global split API endpoint and successful admin audit.
- Modify `server/app/routers/parent_packs_pages.py`: add parent HTML split form handler plus split success/error context.
- Modify `server/app/routers/admin_pages.py`: add admin HTML split form handler and flash labels.
- Modify `server/app/templates/parent/packs/detail.html`: add split controls using existing draft checkboxes.
- Modify `server/app/templates/admin/global_pack_detail.html`: add draft checkboxes, select-all behavior, and split controls.
- Modify `server/tests/test_family_pack_service.py`: service-level split tests.
- Modify `server/tests/test_family_pack_routes.py`: family API split tests.
- Modify `server/tests/test_admin_global_pack_router.py`: global API split tests.
- Modify `server/tests/test_parent_packs_pages.py`: parent HTML split tests.
- Modify `server/tests/test_admin_pages.py`: admin HTML split tests and audit assertion.
- Modify `server/tests/e2e/test_parent_family_pack_e2e.py`: parent split/publish/device latest E2E.
- Modify `server/tests/e2e/test_global_packs_e2e.py`: admin global split/publish/public latest E2E.

---

### Task 1: Service Tests for Draft Split

**Files:**
- Modify: `server/tests/test_family_pack_service.py`
- Modify in next task: `server/app/services/family_pack_service.py`

- [ ] **Step 1: Write failing service tests**

Append tests near the existing draft-management tests:

```python
@pytest.mark.asyncio
async def test_split_draft_copy_creates_new_pack_without_changing_source(db: object) -> None:
    family_id, parent = await _new_family()
    source = await svc.create_definition(
        family_id=family_id, name="Source", description=None, parent_user_id=parent
    )
    for word_id in ("global-a", "global-b", "global-c"):
        await svc.upsert_draft_word(
            definition=source,
            word_id=word_id,
            payload=_global_payload(),
            parent_user_id=parent,
        )

    result = await svc.split_draft_to_new_pack(
        source_definition=source,
        word_ids=["global-c", "global-a"],
        new_name="Split Copy",
        new_description="copied words",
        mode="copy",
        parent_user_id=parent,
    )

    assert result.mode == "copy"
    assert result.selected_word_count == 2
    assert result.new_definition.family_id == family_id
    assert result.new_definition.name == "Split Copy"
    assert [w["id"] for w in result.new_draft.words] == ["global-a", "global-c"]
    assert [w["id"] for w in result.source_draft.words] == [
        "global-a",
        "global-b",
        "global-c",
    ]


@pytest.mark.asyncio
async def test_split_draft_move_removes_selected_words_from_source(db: object) -> None:
    family_id, parent = await _new_family()
    source = await svc.create_definition(
        family_id=family_id, name="Source Move", description=None, parent_user_id=parent
    )
    for word_id in ("global-a", "global-b", "global-c"):
        await svc.upsert_draft_word(
            definition=source,
            word_id=word_id,
            payload=_global_payload(),
            parent_user_id=parent,
        )

    result = await svc.split_draft_to_new_pack(
        source_definition=source,
        word_ids=["global-a", "global-c"],
        new_name="Split Move",
        new_description=None,
        mode="move",
        parent_user_id=parent,
    )

    assert [w["id"] for w in result.new_draft.words] == ["global-a", "global-c"]
    assert [w["id"] for w in result.source_draft.words] == ["global-b"]


@pytest.mark.asyncio
async def test_split_draft_deduplicates_requested_ids(db: object) -> None:
    family_id, parent = await _new_family()
    source = await svc.create_definition(
        family_id=family_id, name="Dedup", description=None, parent_user_id=parent
    )
    for word_id in ("global-a", "global-b"):
        await svc.upsert_draft_word(
            definition=source,
            word_id=word_id,
            payload=_global_payload(),
            parent_user_id=parent,
        )

    result = await svc.split_draft_to_new_pack(
        source_definition=source,
        word_ids=["global-b", "global-b", "global-a"],
        new_name="Dedup Split",
        new_description=None,
        mode="copy",
        parent_user_id=parent,
    )

    assert [w["id"] for w in result.new_draft.words] == ["global-a", "global-b"]


@pytest.mark.asyncio
async def test_split_draft_rejects_empty_selection(db: object) -> None:
    family_id, parent = await _new_family()
    source = await svc.create_definition(
        family_id=family_id, name="Empty Split", description=None, parent_user_id=parent
    )

    with pytest.raises(svc.InvalidPayload):
        await svc.split_draft_to_new_pack(
            source_definition=source,
            word_ids=[],
            new_name="No Words",
            new_description=None,
            mode="copy",
            parent_user_id=parent,
        )


@pytest.mark.asyncio
async def test_split_draft_missing_word_raises_draft_word_not_found(db: object) -> None:
    family_id, parent = await _new_family()
    source = await svc.create_definition(
        family_id=family_id, name="Missing", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=source,
        word_id="global-a",
        payload=_global_payload(),
        parent_user_id=parent,
    )

    with pytest.raises(svc.DraftWordNotFound) as exc:
        await svc.split_draft_to_new_pack(
            source_definition=source,
            word_ids=["global-a", "global-missing"],
            new_name="Missing Split",
            new_description=None,
            mode="copy",
            parent_user_id=parent,
        )

    assert exc.value.missing_word_ids == ["global-missing"]


@pytest.mark.asyncio
async def test_split_draft_duplicate_new_name_raises_name_taken(db: object) -> None:
    family_id, parent = await _new_family()
    source = await svc.create_definition(
        family_id=family_id, name="Source Name", description=None, parent_user_id=parent
    )
    await svc.create_definition(
        family_id=family_id, name="Taken", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=source,
        word_id="global-a",
        payload=_global_payload(),
        parent_user_id=parent,
    )

    with pytest.raises(svc.NameTaken):
        await svc.split_draft_to_new_pack(
            source_definition=source,
            word_ids=["global-a"],
            new_name="Taken",
            new_description=None,
            mode="copy",
            parent_user_id=parent,
        )


@pytest.mark.asyncio
async def test_split_draft_supports_global_sentinel_scope(db: object) -> None:
    definition = await svc.create_definition(
        family_id=svc.GLOBAL_PACK_FAMILY_ID,
        name="Global Source",
        description=None,
        parent_user_id="admin",
        pack_id="gpk-split-service",
    )
    await svc.upsert_draft_word(
        definition=definition,
        word_id="fruit-apple",
        payload={
            "source": "global",
            "word": "apple",
            "meaning_zh": "apple zh",
            "category": "fruit",
            "difficulty": 1,
        },
        parent_user_id="admin",
    )

    result = await svc.split_draft_to_new_pack(
        source_definition=definition,
        word_ids=["fruit-apple"],
        new_name="Global Split",
        new_description=None,
        mode="copy",
        parent_user_id="admin",
    )

    assert result.new_definition.family_id == svc.GLOBAL_PACK_FAMILY_ID
    assert result.new_draft.words[0]["id"] == "fruit-apple"
```

- [ ] **Step 2: Run service tests to verify RED**

Run:

```sh
cd server && uv run pytest tests/test_family_pack_service.py -q
```

Expected: FAIL with `AttributeError: module 'app.services.family_pack_service' has no attribute 'split_draft_to_new_pack'` or missing `DraftWordNotFound`.

---

### Task 2: Implement Shared Split Service

**Files:**
- Modify: `server/app/services/family_pack_service.py`
- Test: `server/tests/test_family_pack_service.py`

- [ ] **Step 1: Add imports/types/error/result**

Add `Literal` to typing imports and add these definitions near existing errors/dataclasses:

```python
from typing import TYPE_CHECKING, Any, Literal
```

```python
class DraftWordNotFound(FamilyPackError):
    code = "DRAFT_WORD_NOT_FOUND"

    def __init__(self, missing_word_ids: list[str]) -> None:
        self.missing_word_ids = missing_word_ids
        joined = ", ".join(missing_word_ids)
        super().__init__(f"draft word(s) not found: {joined}")


@dataclass(frozen=True)
class DraftSplitResult:
    source_definition: FamilyPackDefinition
    new_definition: FamilyPackDefinition
    source_draft: FamilyPackDraft
    new_draft: FamilyPackDraft
    selected_word_count: int
    mode: Literal["copy", "move"]
```

- [ ] **Step 2: Add implementation**

Place after `remove_draft_word`:

```python
def _unique_nonblank_word_ids(word_ids: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for raw in word_ids:
        word_id = str(raw).strip()
        if not word_id or word_id in seen:
            continue
        seen.add(word_id)
        out.append(word_id)
    return out


async def split_draft_to_new_pack(
    *,
    source_definition: FamilyPackDefinition,
    word_ids: list[str],
    new_name: str,
    new_description: str | None,
    mode: Literal["copy", "move"],
    parent_user_id: str,
    new_pack_id: str | None = None,
) -> DraftSplitResult:
    if mode not in ("copy", "move"):
        raise InvalidPayload("mode must be 'copy' or 'move'")

    selected_ids = _unique_nonblank_word_ids(word_ids)
    if not selected_ids:
        raise InvalidPayload("word_ids must not be empty")

    source_draft = await get_or_create_draft(
        definition=source_definition,
        parent_user_id=parent_user_id,
    )
    source_ids = {
        str(w.get("id"))
        for w in source_draft.words
        if isinstance(w.get("id"), str)
    }
    missing = [word_id for word_id in selected_ids if word_id not in source_ids]
    if missing:
        raise DraftWordNotFound(missing)

    selected_id_set = set(selected_ids)
    selected_words = [
        dict(word)
        for word in source_draft.words
        if isinstance(word.get("id"), str) and word["id"] in selected_id_set
    ]

    settings = get_settings()
    if len(selected_words) > settings.family_pack_max_words:
        raise WordLimitExceeded(
            f"split selection exceeds {settings.family_pack_max_words}-word cap"
        )

    new_definition = await create_definition(
        family_id=source_definition.family_id,
        name=new_name,
        description=new_description,
        parent_user_id=parent_user_id,
        pack_id=new_pack_id,
    )
    now = _utcnow()
    new_draft = FamilyPackDraft(
        pack_definition_id=new_definition.pack_id,
        family_id=new_definition.family_id,
        words=selected_words,
        updated_at=now,
        updated_by_parent_id=parent_user_id,
    )
    await new_draft.insert()
    new_definition.updated_at = now
    await new_definition.save()

    if mode == "move":
        source_draft.words = [
            word
            for word in source_draft.words
            if not (
                isinstance(word.get("id"), str)
                and word["id"] in selected_id_set
            )
        ]
        source_draft.updated_at = now
        source_draft.updated_by_parent_id = parent_user_id
        await source_draft.save()
        source_definition.updated_at = now
        await source_definition.save()

    return DraftSplitResult(
        source_definition=source_definition,
        new_definition=new_definition,
        source_draft=source_draft,
        new_draft=new_draft,
        selected_word_count=len(selected_words),
        mode=mode,
    )
```

- [ ] **Step 3: Run service tests to verify GREEN**

Run:

```sh
cd server && uv run pytest tests/test_family_pack_service.py -q
```

Expected: PASS.

- [ ] **Step 4: Commit service layer**

```sh
git add server/app/services/family_pack_service.py server/tests/test_family_pack_service.py
git commit -m "feat: add draft pack split service"
```

---

### Task 3: Family API Split Endpoint

**Files:**
- Modify: `server/tests/test_family_pack_routes.py`
- Modify: `server/app/schemas/family_pack.py`
- Modify: `server/app/routers/parent_family_pack.py`

- [ ] **Step 1: Write failing family API tests**

Add tests near draft HTTP tests:

```python
@pytest.mark.asyncio
async def test_split_family_draft_copy_via_http(db: object) -> None:
    ac, _ = await _make_parent_client(email="split-copy@example.com")
    async with ac:
        created = await ac.post("/api/v1/family/_/family-packs", json={"name": "Split Source"})
        pack_id = created.json()["pack_id"]
        for word_id in ("global-a", "global-b", "global-c"):
            await ac.put(
                f"/api/v1/family/_/family-packs/{pack_id}/draft/words/{word_id}",
                json={"source": "global"},
            )

        resp = await ac.post(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/split",
            json={
                "mode": "copy",
                "word_ids": ["global-c", "global-a"],
                "new_pack": {"name": "Split Copy", "description": "copy"},
            },
        )

    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["mode"] == "copy"
    assert body["source_pack_id"] == pack_id
    assert body["copied_count"] == 2
    assert body["moved_count"] == 0
    assert body["source_draft"]["word_count"] == 3
    assert [w["id"] for w in body["new_draft"]["words"]] == ["global-a", "global-c"]


@pytest.mark.asyncio
async def test_split_family_draft_move_via_http(db: object) -> None:
    ac, _ = await _make_parent_client(email="split-move@example.com")
    async with ac:
        created = await ac.post("/api/v1/family/_/family-packs", json={"name": "Move Source"})
        pack_id = created.json()["pack_id"]
        for word_id in ("global-a", "global-b", "global-c"):
            await ac.put(
                f"/api/v1/family/_/family-packs/{pack_id}/draft/words/{word_id}",
                json={"source": "global"},
            )

        resp = await ac.post(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/split",
            json={
                "mode": "move",
                "word_ids": ["global-a", "global-c"],
                "new_pack": {"name": "Split Move"},
            },
        )

    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["moved_count"] == 2
    assert body["copied_count"] == 0
    assert [w["id"] for w in body["source_draft"]["words"]] == ["global-b"]


@pytest.mark.asyncio
async def test_split_family_draft_other_family_404(db: object) -> None:
    ac_a, _ = await _make_parent_client(email="split-a@example.com")
    ac_b, _ = await _make_parent_client(email="split-b@example.com")
    async with ac_a, ac_b:
        created = await ac_a.post("/api/v1/family/_/family-packs", json={"name": "Private Split"})
        pack_id = created.json()["pack_id"]
        resp = await ac_b.post(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/split",
            json={
                "mode": "copy",
                "word_ids": ["global-a"],
                "new_pack": {"name": "Bad Split"},
            },
        )

    assert resp.status_code == 404
    assert resp.json()["detail"]["error"]["code"] == "PACK_NOT_FOUND"


@pytest.mark.asyncio
async def test_split_family_draft_missing_word_404(db: object) -> None:
    ac, _ = await _make_parent_client(email="split-missing@example.com")
    async with ac:
        created = await ac.post("/api/v1/family/_/family-packs", json={"name": "Missing Source"})
        pack_id = created.json()["pack_id"]
        await ac.put(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/words/global-a",
            json={"source": "global"},
        )
        resp = await ac.post(
            f"/api/v1/family/_/family-packs/{pack_id}/draft/split",
            json={
                "mode": "copy",
                "word_ids": ["global-a", "global-x"],
                "new_pack": {"name": "Missing Split"},
            },
        )

    assert resp.status_code == 404
    assert resp.json()["detail"]["error"]["code"] == "DRAFT_WORD_NOT_FOUND"
```

- [ ] **Step 2: Run family API tests to verify RED**

Run:

```sh
cd server && uv run pytest tests/test_family_pack_routes.py -q
```

Expected: FAIL with 404 route not found for `/draft/split`.

- [ ] **Step 3: Add schemas**

In `server/app/schemas/family_pack.py`, add:

```python
class FamilyPackSplitNewPackIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, Field(min_length=1, max_length=32)]
    description: Annotated[str | None, Field(default=None, max_length=200)]


class FamilyPackDraftSplitIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: Literal["copy", "move"]
    word_ids: Annotated[list[str], Field(min_length=1, max_length=100)]
    new_pack: FamilyPackSplitNewPackIn


class FamilyPackDraftSplitOut(BaseModel):
    mode: Literal["copy", "move"]
    source_pack_id: str
    new_pack: FamilyPackDefinitionOut
    source_draft: FamilyPackDraftOut
    new_draft: FamilyPackDraftOut
    moved_count: int
    copied_count: int
```

- [ ] **Step 4: Add router endpoint**

Import `FamilyPackDraftSplitIn` and `FamilyPackDraftSplitOut` in `parent_family_pack.py`, then add before publish routes:

```python
@router.post(
    "/{family_scope}/family-packs/{pack_id}/draft/split",
    response_model=FamilyPackDraftSplitOut,
    status_code=status.HTTP_201_CREATED,
)
async def split_draft_to_new_pack(
    body: FamilyPackDraftSplitIn,
    pack_id: str = Path(min_length=1, max_length=128),
    family_scope: str = Path(min_length=1, max_length=128),
    user: User = Depends(current_parent_user),
) -> FamilyPackDraftSplitOut:
    family_id = user.family_id or ""
    definition = await _load_definition_or_404(pack_id, family_id)
    try:
        result = await svc.split_draft_to_new_pack(
            source_definition=definition,
            word_ids=body.word_ids,
            new_name=body.new_pack.name,
            new_description=body.new_pack.description,
            mode=body.mode,
            parent_user_id=user.username,
        )
    except svc.DraftWordNotFound as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": exc.code,
                    "message": str(exc),
                    "missing_word_ids": exc.missing_word_ids,
                }
            },
        ) from exc
    except svc.NameTaken as exc:
        raise _conflict("NAME_TAKEN", "Pack name already in use") from exc
    except svc.WordLimitExceeded as exc:
        raise _conflict(
            "WORD_LIMIT_EXCEEDED",
            f"Pack exceeds {get_settings().family_pack_max_words}-word cap",
        ) from exc
    except svc.InvalidPayload as exc:
        raise _bad_payload(str(exc)) from exc

    count = result.selected_word_count
    return FamilyPackDraftSplitOut(
        mode=result.mode,
        source_pack_id=pack_id,
        new_pack=_serialize_definition(result.new_definition),
        source_draft=_serialize_draft(result.source_draft),
        new_draft=_serialize_draft(result.new_draft),
        moved_count=count if result.mode == "move" else 0,
        copied_count=count if result.mode == "copy" else 0,
    )
```

- [ ] **Step 5: Run family API tests to verify GREEN**

Run:

```sh
cd server && uv run pytest tests/test_family_pack_routes.py tests/test_family_pack_batch.py -q
```

Expected: PASS.

- [ ] **Step 6: Commit family API**

```sh
git add server/app/schemas/family_pack.py server/app/routers/parent_family_pack.py server/tests/test_family_pack_routes.py
git commit -m "feat: add family draft split API"
```

---

### Task 4: Global API Split Endpoint

**Files:**
- Modify: `server/tests/test_admin_global_pack_router.py`
- Modify: `server/app/services/global_pack_service.py`
- Modify: `server/app/schemas/global_pack.py`
- Modify: `server/app/routers/admin_global_pack.py`

- [ ] **Step 1: Write failing global API tests**

Add tests after `test_admin_draft_publish_rollback_versions`:

```python
@pytest.mark.asyncio
async def test_admin_split_global_draft_copy(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "Global Split Source", "pack_id": "gpk-split-src"},
        headers=headers,
    )
    for word_id, word in (("fruit-apple", "apple"), ("fruit-banana", "banana"), ("fruit-pear", "pear")):
        await client.put(
            f"/api/v1/admin/global-packs/gpk-split-src/draft/words/{word_id}",
            json={
                "id": word_id,
                "word": word,
                "meaningZh": f"{word} zh",
                "category": "fruit",
                "difficulty": 1,
            },
            headers=headers,
        )

    resp = await client.post(
        "/api/v1/admin/global-packs/gpk-split-src/draft/split",
        json={
            "mode": "copy",
            "word_ids": ["fruit-pear", "fruit-apple"],
            "new_pack": {"name": "Global Split Copy", "description": "copy"},
        },
        headers=headers,
    )

    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["new_pack"]["pack_id"].startswith("gpk-")
    assert body["new_pack"]["created_by_admin_id"] == admin.username
    assert body["source_draft"]["word_count"] == 3
    assert [w["id"] for w in body["new_draft"]["words"]] == ["fruit-apple", "fruit-pear"]


@pytest.mark.asyncio
async def test_admin_split_global_draft_move_removes_source_words(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "Global Split Move Source", "pack_id": "gpk-split-move"},
        headers=headers,
    )
    for word_id in ("fruit-apple", "fruit-banana", "fruit-pear"):
        await client.put(
            f"/api/v1/admin/global-packs/gpk-split-move/draft/words/{word_id}",
            json={
                "id": word_id,
                "word": word_id,
                "meaningZh": word_id,
                "category": "fruit",
                "difficulty": 1,
            },
            headers=headers,
        )

    resp = await client.post(
        "/api/v1/admin/global-packs/gpk-split-move/draft/split",
        json={
            "mode": "move",
            "word_ids": ["fruit-apple", "fruit-pear"],
            "new_pack": {"name": "Global Split Move"},
        },
        headers=headers,
    )

    assert resp.status_code == 201, resp.text
    assert [w["id"] for w in resp.json()["source_draft"]["words"]] == ["fruit-banana"]


@pytest.mark.asyncio
async def test_admin_split_global_draft_duplicate_name_409(
    client: AsyncClient, admin: User
) -> None:
    headers = _bearer(admin.username)
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "Global Split Source Dup", "pack_id": "gpk-split-dup-src"},
        headers=headers,
    )
    await client.post(
        "/api/v1/admin/global-packs",
        json={"name": "Global Split Taken", "pack_id": "gpk-split-dup-taken"},
        headers=headers,
    )
    await client.put(
        "/api/v1/admin/global-packs/gpk-split-dup-src/draft/words/fruit-apple",
        json={
            "id": "fruit-apple",
            "word": "apple",
            "meaningZh": "apple zh",
            "category": "fruit",
            "difficulty": 1,
        },
        headers=headers,
    )

    resp = await client.post(
        "/api/v1/admin/global-packs/gpk-split-dup-src/draft/split",
        json={
            "mode": "copy",
            "word_ids": ["fruit-apple"],
            "new_pack": {"name": "Global Split Taken"},
        },
        headers=headers,
    )

    assert resp.status_code == 409
    assert resp.json()["detail"]["error"]["code"] == "NAME_TAKEN"
```

- [ ] **Step 2: Run global API tests to verify RED**

Run:

```sh
cd server && uv run pytest tests/test_admin_global_pack_router.py -q
```

Expected: FAIL with 404 route not found.

- [ ] **Step 3: Add global service wrapper**

In `global_pack_service.py`, expose `DraftSplitResult` and `DraftWordNotFound`, then add:

```python
DraftSplitResult = fps.DraftSplitResult
DraftWordNotFound = fps.DraftWordNotFound
```

```python
async def split_draft_to_new_pack(
    *,
    pack_id: str,
    admin_id: str,
    word_ids: list[str],
    new_name: str,
    new_description: str | None,
    mode: Literal["copy", "move"],
) -> DraftSplitResult:
    definition = await get_definition(pack_id=pack_id)
    return await fps.split_draft_to_new_pack(
        source_definition=definition,
        word_ids=word_ids,
        new_name=new_name,
        new_description=new_description,
        mode=mode,
        parent_user_id=admin_id,
        new_pack_id=_gen_pack_id(),
    )
```

Add `Literal` to imports.

- [ ] **Step 4: Add global schemas**

In `global_pack.py`:

```python
class GlobalPackSplitNewPackIn(BaseModel):
    name: str
    description: str | None = None


class GlobalPackDraftSplitIn(BaseModel):
    mode: Literal["copy", "move"]
    word_ids: list[str]
    new_pack: GlobalPackSplitNewPackIn


class GlobalPackDraftSplitOut(BaseModel):
    mode: Literal["copy", "move"]
    source_pack_id: str
    new_pack: GlobalPackDefinitionOut
    source_draft: FamilyPackDraftOut
    new_draft: FamilyPackDraftOut
    moved_count: int
    copied_count: int
```

Add `Literal` to imports.

- [ ] **Step 5: Add admin router endpoint**

Import the schemas and add before publish:

```python
@router.post(
    "/{pack_id}/draft/split",
    status_code=status.HTTP_201_CREATED,
    response_model=GlobalPackDraftSplitOut,
)
async def split_global_pack_draft(
    pack_id: str,
    body: GlobalPackDraftSplitIn,
    admin: User = Depends(current_admin_user),  # noqa: B008
) -> GlobalPackDraftSplitOut:
    try:
        result = await svc.split_draft_to_new_pack(
            pack_id=pack_id,
            admin_id=admin.username,
            word_ids=body.word_ids,
            new_name=body.new_pack.name,
            new_description=body.new_pack.description,
            mode=body.mode,
        )
    except svc.PackNotFound as exc:
        raise _err("PACK_NOT_FOUND", str(exc), 404) from exc
    except svc.DraftWordNotFound as exc:
        raise _err("DRAFT_WORD_NOT_FOUND", str(exc), 404) from exc
    except svc.NameTaken as exc:
        raise _err("NAME_TAKEN", str(exc), 409) from exc
    except svc.WordLimitExceeded as exc:
        raise _err("WORD_LIMIT_EXCEEDED", str(exc), 409) from exc
    except svc.InvalidPayload as exc:
        raise _err("INVALID_PAYLOAD", str(exc), 400) from exc

    await record_admin_action(
        admin_username=admin.username,
        action="global_pack.draft_split",
        target_collection="family_pack_definitions",
        target_id=pack_id,
        payload_summary={
            "source_pack_id": pack_id,
            "new_pack_id": result.new_definition.pack_id,
            "mode": result.mode,
            "selected_count": result.selected_word_count,
            "via": "admin_api",
        },
    )

    count = result.selected_word_count
    return GlobalPackDraftSplitOut(
        mode=result.mode,
        source_pack_id=pack_id,
        new_pack=_serialize_definition(result.new_definition),
        source_draft=_serialize_draft(result.source_draft),
        new_draft=_serialize_draft(result.new_draft),
        moved_count=count if result.mode == "move" else 0,
        copied_count=count if result.mode == "copy" else 0,
    )
```

- [ ] **Step 6: Run global API tests to verify GREEN**

Run:

```sh
cd server && uv run pytest tests/test_admin_global_pack_router.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit global API**

```sh
git add server/app/services/global_pack_service.py server/app/schemas/global_pack.py server/app/routers/admin_global_pack.py server/tests/test_admin_global_pack_router.py
git commit -m "feat: add global draft split API"
```

---

### Task 5: Parent HTML Split Flow

**Files:**
- Modify: `server/tests/test_parent_packs_pages.py`
- Modify: `server/app/routers/parent_packs_pages.py`
- Modify: `server/app/templates/parent/packs/detail.html`

- [ ] **Step 1: Write failing parent HTML tests**

Add tests near batch-delete tests:

```python
async def test_pack_detail_renders_split_controls(parent_client: tuple[AsyncClient, str]) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Split UI"})
    pack_id = created.json()["pack_id"]
    resp = await ac.get(f"/family/{fid}/packs/{pack_id}")

    assert resp.status_code == 200
    assert 'id="draft-split-form"' in resp.text
    assert 'name="new_name"' in resp.text
    assert 'name="mode"' in resp.text


async def test_split_form_moves_selected_words_to_new_pack(parent_client: tuple[AsyncClient, str]) -> None:
    ac, fid = parent_client
    created = await ac.post(f"/api/v1/family/{fid}/family-packs", json={"name": "Split Form Source"})
    pack_id = created.json()["pack_id"]
    for word_id in ("global-a", "global-b", "global-c"):
        await ac.put(
            f"/api/v1/family/{fid}/family-packs/{pack_id}/draft/words/{word_id}",
            json={"source": "global"},
        )

    resp = await ac.post(
        f"/family/{fid}/packs/{pack_id}/draft/split",
        data=[
            ("word_ids", "global-a"),
            ("word_ids", "global-c"),
            ("new_name", "Split Form New"),
            ("new_description", "from form"),
            ("mode", "move"),
        ],
        follow_redirects=False,
    )

    assert resp.status_code == 303
    assert resp.headers["location"].startswith(f"/family/{fid}/packs/pck-")
    assert "split_ok=move" in resp.headers["location"]

    source = await ac.get(f"/api/v1/family/{fid}/family-packs/{pack_id}")
    assert [w["id"] for w in source.json()["draft"]["words"]] == ["global-b"]
```

- [ ] **Step 2: Run parent HTML tests to verify RED**

Run:

```sh
cd server && uv run pytest tests/test_parent_packs_pages.py -q
```

Expected: FAIL because split controls/route are absent.

- [ ] **Step 3: Add parent HTML handler**

In `parent_packs_pages.py`, extend `_render_pack_detail` with `split_error: str = ""` and include `"split_error": split_error` in the template context. In `detail_page`, read `split_ok = request.query_params.get("split_ok", "")` and include `"split_ok": split_ok` in the direct `TemplateResponse` context; also pass `"split_ok": ""` from `_render_pack_detail`.

Add route after batch delete:

```python
@router.post("/{family_id}/packs/{pack_id}/draft/split", response_model=None)
async def draft_split_words(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)

    form = await request.form()
    word_ids = []
    seen: set[str] = set()
    for raw in form.getlist("word_ids"):
        word_id = str(raw).strip()
        if word_id and word_id not in seen:
            seen.add(word_id)
            word_ids.append(word_id)
    mode = str(form.get("mode", "copy")).strip()
    new_name = str(form.get("new_name", "")).strip()
    new_description_raw = str(form.get("new_description", "")).strip()
    new_description = new_description_raw or None

    try:
        result = await svc.split_draft_to_new_pack(
            source_definition=definition,
            word_ids=word_ids,
            new_name=new_name,
            new_description=new_description,
            mode=mode,
            parent_user_id=user.username,
        )
    except (svc.InvalidPayload, svc.DraftWordNotFound, svc.NameTaken, svc.WordLimitExceeded) as exc:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            split_error=getattr(exc, "code", "INVALID_PAYLOAD"),
        )

    return RedirectResponse(
        url=f"/family/{user.family_id or '_'}/packs/{result.new_definition.pack_id}?split_ok={result.mode}",
        status_code=303,
    )
```

- [ ] **Step 4: Add parent template controls**

In `detail.html`, add success/error blocks near the existing flash messages:

```html
{% if split_ok %}
  <div class="rounded-md border border-emerald-200 bg-emerald-50 text-emerald-900 px-4 py-3 text-sm">
    {% if split_ok == "copy" %}
      已复制所选词条到新的词包。
    {% elif split_ok == "move" %}
      已移动所选词条到新的词包。
    {% endif %}
  </div>
{% endif %}

{% if split_error %}
  <div class="rounded-md border border-rose-200 bg-rose-50 text-rose-900 px-4 py-3 text-sm">
    {% if split_error == "INVALID_PAYLOAD" %}
      请选择要拆分的词条，并填写新词包名称。
    {% elif split_error == "DRAFT_WORD_NOT_FOUND" %}
      所选词条已不在草稿中，请刷新后重试。
    {% elif split_error == "NAME_TAKEN" %}
      已有同名词包，请换一个名称。
    {% elif split_error == "WORD_LIMIT_EXCEEDED" %}
      所选词条超过单个词包上限。
    {% endif %}
  </div>
{% endif %}
```

Place split controls next to the batch delete form:

```html
<form id="draft-split-form" method="post" action="/family/{{ (user.family_id if (user is defined and user) else '_') }}/packs/{{ definition.pack_id }}/draft/split" class="flex flex-wrap items-end gap-2">
  <label class="text-xs text-slate-600">新词包名称
    <input name="new_name" required maxlength="32" class="mt-1 w-40 rounded-md border border-slate-300 px-2 py-1.5 text-xs" />
  </label>
  <label class="text-xs text-slate-600">模式
    <select name="mode" class="mt-1 rounded-md border border-slate-300 px-2 py-1.5 text-xs">
      <option value="move">移动</option>
      <option value="copy">复制</option>
    </select>
  </label>
  <input name="new_description" maxlength="200" placeholder="描述（可选）" class="rounded-md border border-slate-300 px-2 py-1.5 text-xs" />
  <button id="draft-split-submit" type="submit" disabled class="rounded-md bg-emerald-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300">拆分所选</button>
</form>
```

Keep existing checkboxes owned by `draft-batch-delete-form`; HTML `form` only accepts one owner form. Add JavaScript that mirrors selected ids into hidden inputs inside `draft-split-form` before submit:

```javascript
const syncSelectionInputs = (form) => {
  form.querySelectorAll('input[data-generated-word-id="1"]').forEach((node) => node.remove());
  draftCheckboxes.filter((box) => box.checked).forEach((box) => {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = "word_ids";
    input.value = box.value;
    input.dataset.generatedWordId = "1";
    form.appendChild(input);
  });
};
const draftSplitForm = document.getElementById("draft-split-form");
if (draftSplitForm) {
  draftSplitForm.addEventListener("submit", () => syncSelectionInputs(draftSplitForm));
}
```

- [ ] **Step 5: Enable split submit in existing selection script**

Add `draftSplitSubmit` lookup and set disabled with the same checked count:

```javascript
const draftSplitSubmit = document.getElementById("draft-split-submit");
const updateDraftBatchState = () => {
  const checkedCount = draftCheckboxes.filter((box) => box.checked).length;
  draftBatchDeleteSubmit.disabled = checkedCount === 0;
  if (draftSplitSubmit) {
    draftSplitSubmit.disabled = checkedCount === 0;
  }
};
```

- [ ] **Step 6: Run parent HTML tests to verify GREEN**

Run:

```sh
cd server && uv run pytest tests/test_parent_packs_pages.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit parent HTML**

```sh
git add server/app/routers/parent_packs_pages.py server/app/templates/parent/packs/detail.html server/tests/test_parent_packs_pages.py
git commit -m "feat: add parent draft split form"
```

---

### Task 6: Admin HTML Split Flow

**Files:**
- Modify: `server/tests/test_admin_pages.py`
- Modify: `server/app/routers/admin_pages.py`
- Modify: `server/app/templates/admin/global_pack_detail.html`

- [ ] **Step 1: Write failing admin HTML tests**

Add tests near existing global pack HTML tests:

```python
async def test_admin_global_pack_detail_renders_split_form(
    client: AsyncClient,
) -> None:
    from app.services import global_pack_service

    await _login_admin(client)
    await global_pack_service.create_definition(
        name="Split UI",
        admin_id="console-admin",
        pack_id="gpk-html-split-ui",
    )

    page = await client.get("/admin/global-packs/packs/gpk-html-split-ui")
    assert page.status_code == 200
    assert 'id="global-draft-split-form"' in page.text
    assert 'name="new_name"' in page.text
    assert 'name="mode"' in page.text


async def test_admin_global_pack_split_form_moves_words_and_audits(
    client: AsyncClient,
) -> None:
    from app.models.audit_log import AuditLog
    from app.services import global_pack_service

    await _login_admin(client)
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
        data=[
            ("word_ids", "fruit-apple"),
            ("word_ids", "fruit-pear"),
            ("new_name", "Split HTML New"),
            ("new_description", "from html"),
            ("mode", "move"),
        ],
        follow_redirects=False,
    )

    assert resp.status_code == 303
    assert resp.headers["location"].startswith("/admin/global-packs/packs/gpk-")
    assert "flash_ok=gpk_split_move" in resp.headers["location"]

    from app.services import admin_console_service as acs

    source_detail = await acs.load_global_pack_definition_console(
        pack_id="gpk-html-split-src"
    )
    assert [w["id"] for w in source_detail["draft_words"]] == ["fruit-banana"]

    audit = await AuditLog.find_one(AuditLog.action == "global_pack.draft_split")
    assert audit is not None
```

Use the actual login helper names already present in `test_admin_pages.py`; if `_login_admin` does not exist, reuse the file's existing login setup.

- [ ] **Step 2: Run admin HTML tests to verify RED**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py -q
```

Expected: FAIL because split form/route is absent.

- [ ] **Step 3: Add admin HTML route**

In `admin_pages.py`, add after draft delete:

```python
@router.post("/global-packs/packs/{pack_id}/draft/split", response_model=None)
async def admin_global_pack_draft_split_post(
    request: Request,
    pack_id: str,
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    form = await request.form()
    word_ids = []
    seen: set[str] = set()
    for raw in form.getlist("word_ids"):
        word_id = str(raw).strip()
        if word_id and word_id not in seen:
            seen.add(word_id)
            word_ids.append(word_id)
    mode = str(form.get("mode", "copy")).strip()
    new_name = str(form.get("new_name", "")).strip()
    desc_raw = str(form.get("new_description", "")).strip()
    new_description = desc_raw or None

    try:
        result = await gps.split_draft_to_new_pack(
            pack_id=pid,
            admin_id=gate.username,
            word_ids=word_ids,
            new_name=new_name,
            new_description=new_description,
            mode=mode,
        )
    except gps.PackNotFound:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    except gps.GlobalPackError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(exc)),
            status_code=303,
        )

    await record_admin_action(
        admin_username=gate.username,
        action="global_pack.draft_split",
        target_collection="family_pack_definitions",
        target_id=pid,
        payload_summary={
            "source_pack_id": pid,
            "new_pack_id": result.new_definition.pack_id,
            "mode": result.mode,
            "selected_count": result.selected_word_count,
            "via": "admin_html_detail",
        },
    )
    return RedirectResponse(
        url=_global_pack_detail_url(
            result.new_definition.pack_id,
            flash_ok=f"gpk_split_{result.mode}",
        ),
        status_code=303,
    )
```

- [ ] **Step 4: Add admin template checkboxes and controls**

In `global_pack_detail.html`, add a select-all column and checkbox per non-hidden row:

```html
<input id="global-draft-select-all" type="checkbox" class="h-4 w-4 rounded border-slate-300 text-sky-600 focus:ring-sky-500" />
```

```html
<input type="checkbox" class="global-draft-word-checkbox h-4 w-4 rounded border-slate-300 text-sky-600 focus:ring-sky-500" value="{{ w.id }}" />
```

Add split form near the table:

```html
<form id="global-draft-split-form" method="post" action="/admin/global-packs/packs/{{ pack_id }}/draft/split" class="flex flex-wrap items-end gap-2">
  <label class="text-xs text-slate-600">新词包名称
    <input name="new_name" required maxlength="32" class="mt-1 w-44 rounded-md border border-slate-300 px-2 py-1.5 text-xs" />
  </label>
  <label class="text-xs text-slate-600">模式
    <select name="mode" class="mt-1 rounded-md border border-slate-300 px-2 py-1.5 text-xs">
      <option value="move">移动</option>
      <option value="copy">复制</option>
    </select>
  </label>
  <input name="new_description" maxlength="200" placeholder="描述（可选）" class="rounded-md border border-slate-300 px-2 py-1.5 text-xs" />
  <span id="global-draft-selection-count" class="text-xs text-slate-500">已选择 0 项</span>
  <button id="global-draft-split-submit" type="submit" disabled class="rounded-md bg-emerald-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-slate-300">拆分所选</button>
</form>
```

Add script to enable submit and mirror selected ids into hidden inputs:

```javascript
(() => {
  const selectAll = document.getElementById("global-draft-select-all");
  const checkboxes = Array.from(document.querySelectorAll(".global-draft-word-checkbox"));
  const form = document.getElementById("global-draft-split-form");
  const submit = document.getElementById("global-draft-split-submit");
  const count = document.getElementById("global-draft-selection-count");
  if (!selectAll || !form || !submit) {
    return;
  }
  const syncHiddenInputs = () => {
    form.querySelectorAll('input[data-generated-word-id="1"]').forEach((node) => node.remove());
    checkboxes.filter((box) => box.checked).forEach((box) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "word_ids";
      input.value = box.value;
      input.dataset.generatedWordId = "1";
      form.appendChild(input);
    });
  };
  const update = () => {
    const checked = checkboxes.filter((box) => box.checked).length;
    submit.disabled = checked === 0;
    if (count) {
      count.textContent = `已选择 ${checked} 项`;
    }
    selectAll.checked = checked > 0 && checked === checkboxes.length;
    selectAll.indeterminate = checked > 0 && checked < checkboxes.length;
    syncHiddenInputs();
  };
  selectAll.addEventListener("change", () => {
    checkboxes.forEach((box) => {
      box.checked = selectAll.checked;
    });
    update();
  });
  checkboxes.forEach((box) => box.addEventListener("change", update));
  form.addEventListener("submit", syncHiddenInputs);
  update();
})();
```

- [ ] **Step 5: Add flash labels**

In `_flash_map_global`, add:

```python
"gpk_split_copy": "已复制所选草稿词条到新的全局词包。",
"gpk_split_move": "已移动所选草稿词条到新的全局词包。",
```

- [ ] **Step 6: Run admin HTML tests to verify GREEN**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit admin HTML**

```sh
git add server/app/routers/admin_pages.py server/app/templates/admin/global_pack_detail.html server/tests/test_admin_pages.py
git commit -m "feat: add admin global draft split form"
```

---

### Task 7: E2E Split Coverage

**Files:**
- Modify: `server/tests/e2e/test_parent_family_pack_e2e.py`
- Modify: `server/tests/e2e/test_global_packs_e2e.py`

- [ ] **Step 1: Add parent E2E test**

Append to `test_parent_family_pack_e2e.py`:

```python
from tests.e2e._utils.auth import DeviceSession, device_headers
```

```python
@pytest.mark.e2e
def test_pack_split_move_publish_then_child_latest_groups_words(
    http: httpx.Client,
    parent: ParentSession,
    device: DeviceSession,
    run_id: str,
) -> None:
    create = http.post(
        "/api/v1/family/_/family-packs",
        json={"name": f"E2E {run_id} split-source"},
    )
    assert create.status_code == 201, create.text
    source_pack_id = create.json()["pack_id"]
    prefix = _custom_prefix(parent.family_id)
    ids = {
        "apple": f"{prefix}{run_id[:6]}-split-apple",
        "banana": f"{prefix}{run_id[:6]}-split-banana",
        "carrot": f"{prefix}{run_id[:6]}-split-carrot",
    }
    for word, word_id in ids.items():
        upsert = http.put(
            f"/api/v1/family/_/family-packs/{source_pack_id}/draft/words/{word_id}",
            json=_custom_word_payload(word=word, meaning=f"{word} zh"),
        )
        assert upsert.status_code == 200, upsert.text

    split = http.post(
        f"/api/v1/family/_/family-packs/{source_pack_id}/draft/split",
        json={
            "mode": "move",
            "word_ids": [ids["apple"], ids["banana"]],
            "new_pack": {"name": f"E2E {run_id} split-new"},
        },
    )
    assert split.status_code == 201, split.text
    new_pack_id = split.json()["new_pack"]["pack_id"]

    source_publish = http.post(
        f"/api/v1/family/_/family-packs/{source_pack_id}/publish",
        json={"notes": "source after split"},
    )
    assert source_publish.status_code == 201, source_publish.text
    new_publish = http.post(
        f"/api/v1/family/_/family-packs/{new_pack_id}/publish",
        json={"notes": "new after split"},
    )
    assert new_publish.status_code == 201, new_publish.text

    latest = http.get(
        "/api/v1/family/_/family-packs/latest.json",
        headers=device_headers(device),
    )
    assert latest.status_code == 200, latest.text
    packs = {pack["pack_id"]: pack for pack in latest.json()["packs"]}
    assert [w["id"] for w in packs[source_pack_id]["words"]] == [ids["carrot"]]
    assert [w["id"] for w in packs[new_pack_id]["words"]] == [
        ids["apple"],
        ids["banana"],
    ]
```

- [ ] **Step 2: Add global E2E test**

Append to `test_global_packs_e2e.py`:

```python
@pytest.mark.e2e
def test_global_pack_split_copy_publish_then_public_latest_contains_both(
    http: httpx.Client,
    admin_token: str,
    run_id: str,
) -> None:
    headers = admin_headers(admin_token)
    source_pack_id = f"e2e-gpk-split-src-{run_id}"
    create = http.post(
        "/api/v1/admin/global-packs",
        headers=headers,
        json={
            "name": f"E2E {run_id} global split source",
            "pack_id": source_pack_id,
            "description": "global split e2e",
        },
    )
    assert create.status_code in (200, 201), create.text
    word_ids = [
        f"e2e-{run_id}-split-ant",
        f"e2e-{run_id}-split-bee",
        f"e2e-{run_id}-split-cat",
    ]
    for word_id in word_ids:
        upsert = http.put(
            f"/api/v1/admin/global-packs/{source_pack_id}/draft/words/{word_id}",
            headers=headers,
            json={
                "id": word_id,
                "word": word_id,
                "meaningZh": word_id,
                "category": "e2e-split",
                "difficulty": 1,
            },
        )
        assert upsert.status_code == 200, upsert.text

    split = http.post(
        f"/api/v1/admin/global-packs/{source_pack_id}/draft/split",
        headers=headers,
        json={
            "mode": "copy",
            "word_ids": [word_ids[0], word_ids[1]],
            "new_pack": {"name": f"E2E {run_id} global split copy"},
        },
    )
    assert split.status_code == 201, split.text
    new_pack_id = split.json()["new_pack"]["pack_id"]

    source_publish = http.post(
        f"/api/v1/admin/global-packs/{source_pack_id}/publish",
        headers=headers,
        json={"notes": "source split copy"},
    )
    assert source_publish.status_code == 201, source_publish.text
    new_publish = http.post(
        f"/api/v1/admin/global-packs/{new_pack_id}/publish",
        headers=headers,
        json={"notes": "new split copy"},
    )
    assert new_publish.status_code == 201, new_publish.text

    latest = http.get("/api/v1/public/global-packs/latest.json")
    assert latest.status_code == 200, latest.text
    packs = {pack["pack_id"]: pack for pack in latest.json()["packs"]}
    assert source_pack_id in packs
    assert new_pack_id in packs
    assert [w["id"] for w in packs[source_pack_id]["words"]] == word_ids
    assert [w["id"] for w in packs[new_pack_id]["words"]] == word_ids[:2]
```

- [ ] **Step 3: Run E2E policy test locally**

Run:

```sh
cd server && uv run pytest tests/test_e2e_async_runner_policy.py -q
```

Expected: PASS.

- [ ] **Step 4: Do not require preview E2E locally**

The preview E2E tests require `E2E_BASE_URL` and credentials. Do not block local completion on live preview E2E unless those env vars are present. The required local coverage is the normal offline pytest suite plus the E2E policy test.

- [ ] **Step 5: Commit E2E tests**

```sh
git add server/tests/e2e/test_parent_family_pack_e2e.py server/tests/e2e/test_global_packs_e2e.py
git commit -m "test: cover draft split e2e flows"
```

---

### Task 8: Full Verification

**Files:**
- All modified server files.

- [ ] **Step 1: Run targeted test set**

Run:

```sh
cd server && uv run pytest \
  tests/test_family_pack_service.py \
  tests/test_family_pack_routes.py \
  tests/test_admin_global_pack_router.py \
  tests/test_parent_packs_pages.py \
  tests/test_admin_pages.py \
  tests/test_e2e_async_runner_policy.py \
  -q
```

Expected: PASS with 0 warnings.

- [ ] **Step 2: Run full server suite**

Run:

```sh
cd server && uv run pytest
```

Expected: PASS with 0 errors and 0 warnings.

- [ ] **Step 3: Inspect git status**

Run:

```sh
git status --short
```

Expected: clean except any intentionally uncommitted final changes. If all task commits were made, clean.

- [ ] **Step 4: Final response**

Summarize:

- Shared split service added.
- Family/global APIs added.
- Parent/admin HTML split controls added.
- E2E scenarios added.
- Tests run and result.
