# Family Pack Delete Design

- **Date:** 2026-05-24
- **Status:** approved for implementation
- **Scope:** Server admin console and parent family-pack page.

## Background

The administrator family vocabulary page at `/admin/family-packs` can search family-created pack definitions, restore archived packs, and rollback pack pointers. The parent vocabulary page at `/family/{family_id}/packs/` lets a family manage its own packs. Neither page could permanently delete a family pack. The global pack console already supports a hard-delete operation that removes a definition, its draft, published versions, and pointer records after an admin supplies an audit reason.

Family packs use the same persistence stack as global packs:

- `FamilyPackDefinition` stores metadata.
- `FamilyPackDraft` stores the working draft.
- `FamilyWordPack` stores published versions.
- `FamilyPackPointer` selects current and previous versions.

## Goals

- Add a permanent delete action to `/admin/family-packs`.
- Add the same permanent delete action to `/family/{family_id}/packs/` for the owning parent.
- Align semantics with global pack deletion: delete the definition, draft, published versions, and pointer records.
- Require an explicit admin reason and record an audit log.
- Prevent accidental management of official global sentinel packs from the family-pack page.

## Non-Goals

- Do not add undo, restore, or archive semantics for this delete path.
- Do not change HarmonyOS, iOS, Android, or public pack sync contracts.
- Do not delete uploaded source assets; this change removes database pack records only.

## Behavior

Deletion is a hard delete. When an admin or owning parent deletes a family `pack_id`, the server removes all records for that pack and that pack's owning `family_id` from:

- `family_pack_definitions`
- `family_pack_drafts`
- `family_word_packs`
- `family_pack_pointers`

The operation is allowed for active and archived family packs, including packs with published versions. After deletion, the pack is gone from the admin family-pack list, the parent family-pack list, and the child-facing family merged pack payload because its definition and versions no longer exist.

If the `pack_id` does not exist, the HTML flow redirects to `/admin/family-packs?flash_err=not_found`. If the `pack_id` belongs to the official global sentinel family, the operation fails with a validation message telling the admin to use the global-pack page.

For the parent page, the existing parent session determines the family scope. Missing or already-deleted packs redirect back to `/family/{family_id}/packs/?flash_ok=deleted` without leaking cross-family existence.

## HTML Console

Add a delete form to each row in `server/app/templates/admin/family_packs_list.html`.

The form posts to:

```text
POST /admin/family-packs/{pack_id}/delete
```

The form includes:

- a required `reason` field with the same minimum length rule as other high-risk admin actions;
- browser confirmation that names the target pack and states that draft, versions, and pointer records will be permanently deleted;
- destructive styling consistent with the global pack delete button.

On success, redirect to:

```text
/admin/family-packs?flash_ok=deleted
```

## Parent HTML Page

Add a delete form to each row in `server/app/templates/partials/pack_row.html`.

The form posts to:

```text
POST /family/{family_id}/packs/{pack_id}/delete
```

The row keeps a normal detail link so parents can still open the pack editor. The delete form is independent from the link, uses browser confirmation, and warns that drafts and published versions will be permanently deleted. Parent deletion does not require a reason and does not write an admin audit log.

On success, redirect to:

```text
/family/{family_id}/packs/?flash_ok=deleted
```

## Service Design

Add a reusable family-pack service operation, for example `delete_definition(pack_id, family_id)`, that:

1. Confirms the definition exists in the requested family.
2. Counts draft, version, and pointer records scoped to the same `pack_id` and `family_id`.
3. Deletes those records plus the definition.
4. Returns a deletion summary.

Add an admin-console wrapper:

```text
admin_family_pack_delete(admin_username, pack_id, reason)
```

It validates the reason, loads the definition, rejects `GLOBAL_PACK_FAMILY_ID`, delegates to the delete operation, and writes an audit log:

- `action`: `family_pack.definition_delete`
- `target_collection`: `family_pack_definitions`
- `target_id`: `pack_id`
- `payload_summary`: reason, family ID, and deletion counts

## Error Handling

- Missing pack: raise `LookupError`; HTML redirects with `flash_err=not_found`.
- Empty or too-short reason: reuse `validate_reason_text`; HTML redirects with the validation message.
- Global sentinel pack: raise `ValueError` with a message pointing admins to the global-pack page.
- Repeated delete: after the first success, later calls return not found.

## Testing

Use test-first implementation.

Server tests:

- Service delete removes one family pack's definition, draft, pointer, and published versions.
- Service delete does not remove records for another family that happens to use the same `pack_id` in older/nonstandard data.
- HTML console renders a delete form on `/admin/family-packs`.
- HTML delete redirects on success, removes records, and writes `family_pack.definition_delete`.
- HTML delete refuses the global sentinel pack path.
- Parent pack list renders a delete form for each family pack.
- Parent delete redirects to the parent list, removes records, and makes the pack detail return 404.

Verification command:

```sh
cd server && uv run pytest
```

Per repository rules, the suite must finish with 0 errors and 0 warnings for server changes.
