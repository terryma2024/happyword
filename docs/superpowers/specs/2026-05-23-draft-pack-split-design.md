# Draft Pack Split Design

## Summary

Parents and admins need to split selected draft words from an oversized or mixed-category word pack into a new pack. The feature applies to both family packs and global packs, supports both copy and move semantics, and operates only on the current draft state.

The implementation should use one shared service operation in `family_pack_service`, with thin family and global wrappers/routes. This matches the current architecture: global packs already reuse the family-pack persistence stack through the `GLOBAL_PACK_FAMILY_ID` sentinel.

## Scope

In scope:

- Split selected words from a source draft into a newly-created pack draft.
- Support `mode="copy"` and `mode="move"`.
- Preserve the selected words in their source draft order.
- Add parent API and parent HTML support for family packs.
- Add admin API and admin HTML support for global packs.
- Record admin audit history for global-pack HTML/API split actions.
- Cover service, API, and HTML behavior with server tests.

Out of scope:

- Splitting from published snapshots.
- Splitting into an existing pack.
- Auto-publishing the new pack.
- Client-native HarmonyOS/iOS/Android UI changes.
- Cross-scope split, such as family draft to global draft or global draft to family draft.

## Core Service Design

Add a shared operation in `server/app/services/family_pack_service.py`:

```python
async def split_draft_to_new_pack(
    *,
    source_definition: FamilyPackDefinition,
    word_ids: list[str],
    new_name: str,
    new_description: str | None,
    mode: Literal["copy", "move"],
    parent_user_id: str,
) -> DraftSplitResult:
    """Split selected draft words into a newly-created pack draft."""
```

`DraftSplitResult` should include:

- `source_definition`
- `new_definition`
- `source_draft`
- `new_draft`
- `selected_word_count`
- `mode`

Behavior:

1. Validate `mode` and non-empty `word_ids`.
2. Load or create the source draft.
3. De-duplicate `word_ids` while preserving request order for validation.
4. Verify every requested word id exists in the source draft.
5. Build selected entries in source draft order, not request order.
6. Validate selected count does not exceed `family_pack_max_words`.
7. Create a new pack definition in the same `family_id` as the source definition.
8. Create the new draft with copies of the selected word entry dictionaries.
9. If `mode == "move"`, remove selected ids from the source draft and update source timestamps.
10. Update the new definition timestamp via normal draft creation/update behavior.

Error types:

- `InvalidPayload`: invalid mode, empty selection, blank name.
- `DraftWordNotFound`: one or more requested ids are absent from the source draft.
- `NameTaken`: new pack name collides with an active pack in the same scope.
- `WordLimitExceeded`: selected word count exceeds the configured max.
- `PackNotFound`: stays in existing lookup helpers and routes.

`DraftWordNotFound` should inherit from `FamilyPackError` and carry the missing ids. Its `code` should be `DRAFT_WORD_NOT_FOUND`.

## Family API

Add request/response schemas in `server/app/schemas/family_pack.py`:

```json
{
  "mode": "move",
  "word_ids": ["fruit-apple", "fruit-banana"],
  "new_pack": {
    "name": "Fruit",
    "description": "Split from the source draft"
  }
}
```

Endpoint:

`POST /api/v1/family/{family_scope}/family-packs/{pack_id}/draft/split`

Response should include enough information for callers to refresh both source and destination:

- `mode`
- `source_pack_id`
- `new_pack`
- `source_draft`
- `new_draft`
- `moved_count`
- `copied_count`

The family router should:

- Resolve the authenticated parent's `family_id`.
- Load source definition using existing family-scoped lookup.
- Call `split_draft_to_new_pack`.
- Map errors consistently with existing family-pack endpoints:
  - `INVALID_PAYLOAD` to 422.
  - `PACK_NOT_FOUND` to 404.
  - `DRAFT_WORD_NOT_FOUND` to 404.
  - `NAME_TAKEN` to 409.
  - `WORD_LIMIT_EXCEEDED` to 409.

## Global API

Add request/response schemas in `server/app/schemas/global_pack.py`.

Endpoint:

`POST /api/v1/admin/global-packs/{pack_id}/draft/split`

The global service should expose a thin wrapper in `server/app/services/global_pack_service.py`:

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
    """Split selected global draft words into a newly-created global pack draft."""
```

The wrapper should load the source definition via `get_definition` and call the family-pack service. Because global packs already use `family_id == GLOBAL_PACK_FAMILY_ID`, natural global word ids remain valid and no family custom-id prefix is required.

The admin API router should map errors using existing admin error shapes. On successful splits it should record `global_pack.draft_split` with:

- source pack id
- new pack id
- mode
- selected count

## Parent HTML

Extend `server/app/templates/parent/packs/detail.html`.

The draft table already has checkboxes used by batch delete. Reuse the same checkboxes for split. Add a compact split form near the draft actions:

- New pack name.
- Optional description.
- Mode selector: copy or move.
- Submit button disabled until at least one row is selected.

Add route:

`POST /family/{family_id}/packs/{pack_id}/draft/split`

The HTML handler should:

- Parse selected `word_ids`.
- Parse `mode`, `new_name`, and `new_description`.
- Call the shared service operation through `family_pack_service`.
- Redirect to the new pack detail on success:
  - `/family/{family_id}/packs/{new_pack_id}?split_ok=copy`
  - `/family/{family_id}/packs/{new_pack_id}?split_ok=move`
- Redirect or render the source detail with a clear error for invalid selection, missing words, name conflict, or invalid payload.

## Admin HTML

Extend `server/app/templates/admin/global_pack_detail.html`.

The global draft table currently has per-row edit/delete actions but no batch selection. Add checkboxes and select-all behavior, then add a split form:

- New global pack name.
- Optional description.
- Mode selector: copy or move.
- Submit button disabled until at least one row is selected.

Add route:

`POST /admin/global-packs/packs/{pack_id}/draft/split`

On success, redirect to the new global pack detail page:

`/admin/global-packs/packs/{new_pack_id}?flash_ok=gpk_split_copy`

or:

`/admin/global-packs/packs/{new_pack_id}?flash_ok=gpk_split_move`

Record an admin audit action `global_pack.draft_split` with source pack, new pack, mode, and selected count.

## Testing Strategy

Use TDD for implementation. Tests should be added before production code.

Service tests in `server/tests/test_family_pack_service.py`:

- Copy creates a new definition and draft while source draft remains unchanged.
- Move creates a new definition and draft while source draft removes selected words.
- Selected entries preserve source draft order.
- Duplicate `word_ids` do not duplicate entries.
- Empty selection raises `InvalidPayload`.
- Missing word raises `DraftWordNotFound`.
- Duplicate new pack name raises `NameTaken`.
- Global sentinel scope works through the same service behavior.

Family API tests in `server/tests/test_family_pack_routes.py`:

- Parent can split own draft with `copy`.
- Parent can split own draft with `move`.
- Cross-family access still returns `PACK_NOT_FOUND`.
- Response includes source and new draft counts.
- Missing draft word returns `DRAFT_WORD_NOT_FOUND`.

Global API tests in `server/tests/test_admin_global_pack_router.py`:

- Admin can split a global draft with natural ids.
- Move removes selected ids from the source global draft.
- Duplicate destination name returns `NAME_TAKEN`.
- Successful split response uses global definition wire shape.

HTML tests:

- `server/tests/test_parent_packs_pages.py` verifies the parent detail page renders split controls and a successful form submission redirects to the new pack.
- `server/tests/test_admin_pages.py` verifies global pack detail renders split controls, successful form submission redirects to the new global pack, and audit log is created.

Final verification:

```sh
cd server && uv run pytest
```

The suite must finish with 0 errors and 0 warnings.
