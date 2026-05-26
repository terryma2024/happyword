# Admin Family Pack Copy Design

- **Date:** 2026-05-26
- **Status:** approved for implementation
- **Scope:** Server admin console for copying family-created word packs.

## Background

The administrator family vocabulary page at `/admin/family-packs` can search
family-created pack definitions, restore archived packs, rollback pointers, and
delete packs. Operators now need a controlled way to reuse a family-created
pack in two directions:

- copy a family pack into the official global-pack area;
- copy a family pack into another family.

Family and global packs already share the same persistence stack. Global packs
are stored as `FamilyPackDefinition` rows with the reserved
`family_id="__global__"` sentinel, while real family packs use `fam-<8hex>`
business IDs. The copy operation should reuse that stack without copying
published history across ownership boundaries.

## Goals

- Add an admin-only copy action for family packs on `/admin/family-packs`.
- Support copying a family pack to a new global pack.
- Support copying a family pack to a new pack owned by another family.
- Copy only the definition metadata and current draft words.
- Optionally delete the source family pack after a successful copy.
- Require an admin reason and write an audit log for every copy.
- Prevent using the family-pack copy flow on official global sentinel packs.

## Non-Goals

- Do not copy published `FamilyWordPack` versions.
- Do not copy `FamilyPackPointer` records.
- Do not automatically publish the copied pack.
- Do not add parent-facing copy controls.
- Do not change HarmonyOS, iOS, Android, or public pack sync contracts.
- Do not delete or move uploaded resource assets; this change only creates or
  removes database pack records.

## Behavior

The copy operation creates a fresh target pack. It copies:

- source definition name;
- source definition description;
- source definition scene metadata;
- current source draft words, preserving their order and word entry shape.

The operation does not copy published versions or pointers. The target pack
therefore starts as an unpublished draft in the target scope. Global targets
receive a generated `gpk-...` pack ID through the global-pack service. Family
targets receive a generated `pck-...` pack ID through the family-pack service.

The source pack must be a real family pack. If the source pack belongs to
`GLOBAL_PACK_FAMILY_ID`, the operation fails with a validation message telling
the admin to use the global-pack page for official global packs.

When copying to another family, the target `family_id` must exist and must not
equal the source family. The service allocates a non-conflicting target name in
the target scope. The first collision appends ` (copy)` to the source name, and
later collisions append ` (copy 2)`, ` (copy 3)`, and so on. The same naming
rule applies when copying to global. This avoids blocking an operational copy
just because the source family or global scope already has a pack with the same
name.

If `delete_source` is true, the service deletes the source family pack only
after the target definition and target draft have been created successfully.
Deletion uses the existing hard-delete semantics: remove source definition,
draft, versions, and pointer records. If the delete step fails, the copied pack
remains and the admin sees the failure; this avoids losing the source before
the copy is durable.

## HTML Console

Add copy controls to each row in `server/app/templates/admin/family_packs_list.html`.

For copying to global, the row posts to:

```text
POST /admin/family-packs/{pack_id}/copy-to-global
```

The form includes:

- required `reason` text using the existing minimum length rule;
- optional `delete_source` checkbox;
- browser confirmation that the target is a new global draft and published
  history will not be copied.

For copying to another family, the row posts to:

```text
POST /admin/family-packs/{pack_id}/copy-to-family
```

The form includes:

- required `target_family_id`;
- required `reason` text using the existing minimum length rule;
- optional `delete_source` checkbox;
- browser confirmation that the target is a new family draft and published
  history will not be copied.

On success, both routes redirect back to `/admin/family-packs` with a success
flash. The success message names whether the target was global or another
family.

## Service Design

Add an admin-console service operation, for example:

```text
admin_family_pack_copy(
    admin_username,
    source_pack_id,
    target_kind,
    target_family_id,
    delete_source,
    reason,
)
```

The service:

1. Validates the reason.
2. Loads the source definition by `pack_id`.
3. Rejects missing packs and global sentinel source packs.
4. Resolves the target scope: `GLOBAL_PACK_FAMILY_ID` for `target_kind=global`,
   or an existing real `Family.family_id` for `target_kind=family`.
5. Allocates a non-conflicting target name in the target scope.
6. Creates a target definition.
7. Creates a target draft with copied source draft words.
8. Optionally deletes the source pack.
9. Records an audit log.

The audit log uses:

- `action`: `family_pack.copy_to_global` or `family_pack.copy_to_family`
- `target_collection`: `family_pack_definitions`
- `target_id`: source `pack_id`
- `payload_summary`: reason, source pack ID, source family ID, target pack ID,
  target family ID, copied word count, and whether the source was deleted.

The service should return a summary with enough information for tests and flash
messages:

- source pack ID;
- source family ID;
- target pack ID;
- target family ID;
- copied word count;
- deleted source flag.

## Error Handling

- Missing source pack: raise `LookupError`; HTML redirects with
  `flash_err=not_found`.
- Global sentinel source pack: raise `ValueError` with a message pointing
  admins to the global-pack page.
- Missing target family: raise `LookupError` or `ValueError`; HTML redirects
  with a readable validation message.
- Target family equals source family: raise `ValueError`; HTML redirects with a
  message explaining that this action is for copying to another family.
- Empty or too-short reason: reuse `validate_reason_text`; HTML redirects with
  the validation message.
- Empty source draft: allowed. The target draft is created with zero words so
  the admin can continue editing before publish.
- Failed source deletion after successful copy: surface the deletion failure,
  keep the copied target pack, and include enough audit context to understand
  that the copy was created.

## Testing

Use test-first implementation.

Service tests:

- Copy a family pack to global creates a `gpk-...` definition and draft with
  copied words, without versions or pointer.
- Copy a family pack to another family creates a `pck-...` definition and draft
  under the target family, without versions or pointer.
- Copy with `delete_source=true` deletes the source definition, draft, versions,
  and pointer only after creating the target.
- Copy rejects a source pack owned by `GLOBAL_PACK_FAMILY_ID`.
- Copy rejects a missing target family.
- Copy rejects a target family that equals the source family.
- Copy allocates a non-conflicting target name when the target scope already
  has the source name.

HTML tests:

- `/admin/family-packs` renders both copy forms for real family packs.
- `POST /admin/family-packs/{pack_id}/copy-to-global` copies the pack, redirects
  with success, and writes `family_pack.copy_to_global`.
- `POST /admin/family-packs/{pack_id}/copy-to-family` copies the pack, redirects
  with success, and writes `family_pack.copy_to_family`.
- The delete-source checkbox removes the original pack after a successful copy.
- The copy routes reject global sentinel source packs.

Verification command:

```sh
cd server && uv run pytest
```

Per repository rules, the suite must finish with 0 errors and 0 warnings for
server changes.
