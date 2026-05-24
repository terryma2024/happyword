# Family Pack Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hard-delete action for family word packs in both the admin family-pack management page and the owning parent's family-pack list, matching global pack deletion semantics.

**Architecture:** The core delete operation belongs in `family_pack_service` so it can delete definition, draft, versions, and pointer records with one family-scoped contract. `admin_console_service` wraps it with reason validation, global-sentinel protection, and audit logging. `admin_pages.py` and `family_packs_list.html` expose the admin HTML action; `parent_packs_pages.py` and `pack_row.html` expose the parent-owned action.

**Tech Stack:** Python, FastAPI, Beanie ODM, Jinja2, pytest, httpx ASGI tests.

---

### Task 1: Family-Pack Service Hard Delete

**Files:**
- Modify: `server/app/services/family_pack_service.py`
- Test: `server/tests/test_family_pack_service.py`

- [ ] **Step 1: Write the failing service test**

Add a test that creates a family pack, publishes two versions, calls `svc.delete_definition(pack_id=..., family_id=...)`, then asserts the returned counts and that all four persistence records are gone.

- [ ] **Step 2: Verify RED**

Run:

```sh
cd server && uv run pytest tests/test_family_pack_service.py::test_delete_definition_removes_all_pack_records -q
```

Expected: fails because `family_pack_service.delete_definition` does not exist.

- [ ] **Step 3: Implement minimal service code**

Add `FamilyPackDeleteSummary` and `delete_definition` to `family_pack_service.py`, mirroring `global_pack_service.delete_definition` but scoped to the supplied `family_id`.

- [ ] **Step 4: Verify GREEN**

Run:

```sh
cd server && uv run pytest tests/test_family_pack_service.py::test_delete_definition_removes_all_pack_records -q
```

Expected: passes with no warnings.

### Task 2: Admin Console Wrapper

**Files:**
- Modify: `server/app/services/admin_console_service.py`
- Test: `server/tests/test_admin_pages.py`

- [ ] **Step 1: Write failing HTML delete test**

Add a test that logs into `/admin`, creates a family pack with draft and published versions, posts `/admin/family-packs/{pack_id}/delete` with `reason`, asserts redirect to `/admin/family-packs?flash_ok=deleted`, verifies database records are gone, and verifies an audit log with `action == "family_pack.definition_delete"`.

- [ ] **Step 2: Verify RED**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_pack_html_delete_removes_pack_and_audits -q
```

Expected: fails because the route does not exist.

- [ ] **Step 3: Implement admin wrapper and route**

Add `admin_family_pack_delete` in `admin_console_service.py`. It validates reason, loads the definition, rejects `GLOBAL_PACK_FAMILY_ID`, calls `fps.delete_definition`, and records audit payload. Add `POST /admin/family-packs/{pack_id}/delete` in `admin_pages.py`.

- [ ] **Step 4: Verify GREEN**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_pack_html_delete_removes_pack_and_audits -q
```

Expected: passes with no warnings.

### Task 3: HTML Form and Guard Tests

**Files:**
- Modify: `server/app/templates/admin/family_packs_list.html`
- Modify: `server/tests/test_admin_pages.py`

- [ ] **Step 1: Write failing render and sentinel tests**

Add a render test that checks `/admin/family-packs` includes `/admin/family-packs/{pack_id}/delete` and `删除`. Add a sentinel test that creates a `GLOBAL_PACK_FAMILY_ID` definition, posts the family delete route, and asserts records remain plus an error redirect.

- [ ] **Step 2: Verify RED**

Run:

```sh
cd server && uv run pytest tests/test_admin_pages.py::test_admin_family_packs_page_renders_delete_form tests/test_admin_pages.py::test_admin_family_pack_delete_rejects_global_sentinel -q
```

Expected: render test fails until the template has the form; sentinel test may pass after Task 2 if the route guard already exists.

- [ ] **Step 3: Implement template form**

Add a destructive delete form to each family-pack row with required `reason`, confirmation text, and a submit button.

- [ ] **Step 4: Verify focused tests**

Run:

```sh
cd server && uv run pytest tests/test_family_pack_service.py tests/test_admin_pages.py -q
```

Expected: both files pass with no warnings.

### Task 4: Parent Pack List Delete

**Files:**
- Modify: `server/app/routers/parent_packs_pages.py`
- Modify: `server/app/templates/parent/packs/list.html`
- Modify: `server/app/templates/partials/pack_row.html`
- Test: `server/tests/test_parent_packs_pages.py`

- [ ] **Step 1: Write failing parent list tests**

Add tests that verify `/family/{family_id}/packs/` renders a delete form for a pack and that posting `/family/{family_id}/packs/{pack_id}/delete` removes definition, draft, pointer, and published versions.

- [ ] **Step 2: Verify RED**

Run:

```sh
cd server && uv run pytest tests/test_parent_packs_pages.py::test_parent_packs_list_renders_delete_form tests/test_parent_packs_pages.py::test_parent_pack_delete_form_removes_pack_records -q
```

Expected: fails because the form and parent delete route do not exist.

- [ ] **Step 3: Implement parent route and form**

Add `POST /family/{family_id}/packs/{pack_id}/delete` in `parent_packs_pages.py`, using the session user's `family_id` and `family_pack_service.delete_definition`. Replace the row-wide anchor in `partials/pack_row.html` with a detail link plus independent delete form. Add a small deleted flash message to the list page.

- [ ] **Step 4: Verify GREEN**

Run:

```sh
cd server && uv run pytest tests/test_parent_packs_pages.py::test_parent_packs_list_renders_delete_form tests/test_parent_packs_pages.py::test_parent_pack_delete_form_removes_pack_records -q
```

Expected: both tests pass with no warnings.

### Task 5: Full Server Verification

**Files:**
- No additional code files.

- [ ] **Step 1: Run full server suite**

Run:

```sh
cd server && uv run pytest
```

Expected: 0 errors and 0 warnings.
