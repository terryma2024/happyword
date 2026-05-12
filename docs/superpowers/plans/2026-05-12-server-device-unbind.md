# Server Device Unbind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure parent device unbind soft-deletes both the device binding and its child profile, while preserving admin restore and same-device reactivation.

**Architecture:** The existing parent unbind route already performs OTP verification and revokes the binding. Extend that successful path to mark the loaded `ChildProfile` deleted with the same timestamp. Existing admin restore and pair reactivation already clear `ChildProfile.deleted_at`, so targeted tests verify the whole lifecycle.

**Tech Stack:** Python, FastAPI, Beanie, pytest, httpx ASGI tests.

---

### Task 1: Parent Unbind Soft-Deletes Child Profile

**Files:**
- Modify: `server/tests/test_device_management.py`
- Modify: `server/app/routers/parent_pages.py`

- [ ] **Step 1: Write the failing test**

In `test_parent_unbind_form_verifies_code_before_revoking`, import `ChildProfile`, then after the successful POST assert the related child profile has `deleted_at` set:

```python
from app.models.child_profile import ChildProfile
```

```python
child = await ChildProfile.find_one(
    ChildProfile.profile_id == binding.child_profile_id
)
assert child is not None
assert child.deleted_at is not None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && uv run pytest tests/test_device_management.py::test_parent_unbind_form_verifies_code_before_revoking -q`

Expected: FAIL because `child.deleted_at` is still `None`.

- [ ] **Step 3: Write minimal implementation**

In `post_device_unbind_confirm`, use one `now` timestamp for both records:

```python
now = datetime.now(tz=UTC)
binding.revoked_at = now
child.deleted_at = now
child.updated_at = now
await binding.save()
await child.save()
```

- [ ] **Step 4: Run narrow test to verify it passes**

Run: `cd server && uv run pytest tests/test_device_management.py::test_parent_unbind_form_verifies_code_before_revoking -q`

Expected: PASS.

- [ ] **Step 5: Run lifecycle regression tests**

Run: `cd server && uv run pytest tests/test_device_management.py::test_parent_unbind_form_verifies_code_before_revoking tests/test_pair_service.py::test_redeem_same_device_same_family_reactivates_revoked_binding tests/test_admin_pages.py::test_admin_can_restore_revoked_device_binding -q`

Expected: PASS with no warnings.
