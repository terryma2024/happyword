# Admin Global Pack Delete Design

- **Date:** 2026-05-22
- **Status:** approved for implementation
- **Scope:** Server admin console and admin JSON API only.

## Background

The system administrator global vocabulary page at `/admin/global-packs` can create global pack definitions, manage drafts, publish pack-specific versions, and rollback pack pointers. It cannot delete global pack definitions. This leaves test packs and accidentally created packs visible in the admin list, and published test packs can continue to affect the public global-pack merge.

Global pack definitions reuse the family-pack persistence stack with the `GLOBAL_PACK_FAMILY_ID` sentinel:

- `FamilyPackDefinition` stores metadata.
- `FamilyPackDraft` stores the working draft.
- `FamilyWordPack` stores published versions.
- `FamilyPackPointer` selects current and previous versions.

## Goals

- Let system administrators permanently delete a global pack definition, including published packs.
- Remove the deleted pack from admin listings and public global-pack sync results.
- Keep the operation auditable with an explicit reason.
- Provide both an HTML console action and a JSON API action for scripted cleanup.

## Non-Goals

- Do not add soft-delete, archive, restore, or undo semantics in this change.
- Do not change the legacy platform `WordPack` snapshot publish/rollback flow.
- Do not add client-side HarmonyOS, iOS, or Android changes.
- Do not delete source assets or uploaded images associated with prior imports; this change deletes database pack records only.

## Behavior

Deletion is a hard delete. When an admin deletes `pack_id`, the server removes all records for that global pack from:

- `family_pack_definitions`
- `family_pack_drafts`
- `family_word_packs`
- `family_pack_pointers`

The action is allowed even if the pack has published versions. After deletion, `global_pack_service.collect_merged()` no longer includes that pack because both its definition and versions are gone.

If the pack does not exist, the JSON API returns `404 PACK_NOT_FOUND`, and the HTML flow redirects to `/admin/global-packs` with a not-found flash message.

## HTML Console

Add a delete form to each row in `server/app/templates/admin/global_packs.html`.

The form posts to:

```text
POST /admin/global-packs/packs/{pack_id}/delete
```

The form includes:

- a required `reason` field;
- browser confirmation that names the target pack;
- a destructive button styled consistently with other admin high-risk actions.

On success, redirect to:

```text
/admin/global-packs?flash_ok=gpk_deleted
```

The existing flash mapper should render this as a clear Chinese success message.

## JSON API

Add:

```text
DELETE /api/v1/admin/global-packs/{pack_id}
```

Authentication remains `current_admin_user` with role `ADMIN`.

The response returns deletion counts so scripts can verify the cleanup:

```json
{
  "pack_id": "gpk-example",
  "deleted_definition_count": 1,
  "deleted_draft_count": 1,
  "deleted_version_count": 2,
  "deleted_pointer_count": 1
}
```

## Service Design

Add a reusable service operation in `global_pack_service`, for example `delete_definition(pack_id)`, that:

1. Confirms the definition exists under `GLOBAL_PACK_FAMILY_ID`.
2. Deletes drafts, versions, pointer, and definition for that `pack_id`.
3. Returns a small deletion summary.

Add an admin-console wrapper in `admin_console_service`:

```text
admin_delete_global_pack_definition(admin_username, pack_id, reason)
```

It validates the reason using existing high-risk-action rules, delegates to the global pack delete operation, and writes an audit log:

- `action`: `global_pack.definition_delete`
- `target_collection`: `family_pack_definitions`
- `target_id`: `pack_id`
- `payload_summary`: reason and deletion counts

## Error Handling

- Missing pack: `PackNotFound`; API maps to `404 PACK_NOT_FOUND`; HTML maps to a flash error.
- Empty or too-short reason in the HTML wrapper: reuse `validate_reason_text`, redirect with the validation message.
- Repeated delete: after the first success, later calls return not found.

## Testing

Use test-first implementation.

Server tests:

- JSON API deletes a published global pack and removes definition, draft, pointer, and versions.
- JSON API returns `404 PACK_NOT_FOUND` for an unknown pack.
- HTML console renders a delete form on `/admin/global-packs`.
- HTML delete requires an admin session, redirects on success, removes the pack from the list, and writes an audit log.

Verification command:

```sh
cd server && uv run pytest
```

Per repository rules, the suite must finish with 0 errors and 0 warnings for server changes.
