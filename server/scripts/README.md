# Server scripts

## Retired Vercel Preview scripts

The Vercel Preview manifest and deployment-prune paths were retired during the
CloudBase cutover. `server/scripts/update_preview_manifest.mjs` and
`server/scripts/vercel_prune_branch_deployments.mjs` were removed; the public
manifest endpoint now serves CloudBase production/staging rows directly from
`server/app/services/preview_manifest_service.py`.

PR online E2E deploys the tested server artifact to the shared CloudBase staging
service. There is no repository workflow that rebuilds `preview/preview-urls.json`
in Vercel Blob.

## cos_storage_smoke.py

Live M7 smoke for Tencent COS. It exercises the same high-level asset upload
helpers the app uses (`upload_word_illustration`, `upload_word_audio`, and
`upload_lesson_image`), verifies each returned public URL is readable with
`HEAD` (falling back to `GET` on 405), then deletes the smoke objects by
default.

Run it only against a staging bucket until M7 has passed:

```bash
cd server
ASSET_STORAGE_PROVIDER=tencent_cos \
COS_SECRET_ID=... \
COS_SECRET_KEY=... \
COS_REGION=ap-shanghai \
COS_BUCKET=happyword-assets-staging-1429584068 \
COS_PUBLIC_BASE_URL=https://happyword-assets-staging-1429584068.cos.ap-shanghai.myqcloud.com \
uv run python -m scripts.cos_storage_smoke
```

Set `COS_SMOKE_KEEP_OBJECTS=1` when you want to inspect the uploaded objects in
the COS console instead of deleting them at the end of the run.

## migrate_vercel_blob_to_cos.py

Backfills historical Vercel Blob asset URLs in MongoDB to Tencent COS. The
default mode is read-only and prints collection-level counts only; it does not
print MongoDB credentials, document payloads, or asset URLs.

Covered locations:

- `words.illustration_url`, `words.audio_url`
- `categories.source_image_url`
- `lesson_import_drafts.source_image_url`
- global/family pack snapshot word asset URLs
- `family_pack_definitions.scene.spellbookCoverUrl`

Dry-run:

```bash
cd server
MONGODB_URI=... MONGO_DB_NAME=happyword \
  uv run python -m scripts.migrate_vercel_blob_to_cos
```

Apply and verify:

```bash
cd server
MONGODB_URI=... MONGO_DB_NAME=happyword \
ASSET_STORAGE_PROVIDER=tencent_cos \
COS_SECRET_ID=... COS_SECRET_KEY=... \
COS_REGION=ap-shanghai \
COS_BUCKET=happyword-assets-prod-1429584068 \
COS_PUBLIC_BASE_URL=https://happyword-assets-prod-1429584068.cos.ap-shanghai.myqcloud.com \
  uv run python -m scripts.migrate_vercel_blob_to_cos --apply --verify
```

Production backfill on 2026-06-04 copied and verified 10 historical Vercel Blob
objects to the production COS bucket; a follow-up dry-run reported `0` remaining
Vercel Blob URL refs.

## db_inventory.py

Redacted MongoDB inventory helper for the M7A Atlas -> Tencent-side migration. It
prints schema and operational metadata only: collection names, document counts,
indexes, TTL/unique flags, and collection stats when available. It does not
print the MongoDB URI, credentials, or document payloads.

Use `--skip-stats` when running against remote Atlas/TencentDB targets where
`collStats` may be slow or unavailable:

```bash
cd server
MONGODB_URI=... MONGO_DB_NAME=happyword \
  uv run python -m scripts.db_inventory \
  --format markdown \
  --skip-stats \
  --count-timeout-ms 5000
```

For a machine-readable report, switch `--format json`. Keep generated reports
out of Git unless they have been reviewed for secret-free metadata only.

## db_connectivity_smoke.py

Redacted MongoDB connectivity smoke for M7A staging/prod cutovers. It verifies
that a URI can authenticate, `ping`, read server metadata, and list collections.
Add `--write-probe` to perform a tiny insert/read/delete round trip in
`_migration_probe`; leave it off when validating read-only rollback URIs.

```bash
cd server
MONGODB_URI=... MONGO_DB_NAME=happyword_cloudbase_staging \
  uv run python -m scripts.db_connectivity_smoke \
  --write-probe
```

The output contains only redacted hosts and operational metadata. It should be
safe to paste into the migration notes after checking that no provider-specific
error text includes credentials.

## flexdb_api_smoke.py

CloudBase FlexDB API smoke for the M7A spike. It talks to Tencent Cloud API 3.0
directly instead of shelling out to the local `tcb` CLI, so the same code path
can be run from CloudBase Run after API credentials are scoped.

Required env vars:

```text
FLEXDB_ENV_ID or TCB_ENV_ID
FLEXDB_TAG
FLEXDB_API_SECRET_ID or TCB_SECRET_ID or TENCENTCLOUD_SECRET_ID
FLEXDB_API_SECRET_KEY or TCB_SECRET_KEY or TENCENTCLOUD_SECRET_KEY
```

Run:

```bash
cd server
FLEXDB_ENV_ID=happyword-d5g66zmq8ef2430b8 \
FLEXDB_TAG=tnt-jw1cesl68 \
FLEXDB_API_SECRET_ID=... \
FLEXDB_API_SECRET_KEY=... \
  uv run python -m scripts.flexdb_api_smoke
```

The probe creates a temporary table, inserts/query/updates a document, creates a
unique index, verifies duplicate-key enforcement, and deletes the temporary
table. Use `--keep-table` only when debugging in the CloudBase console.

## vercel_should_skip_build.sh

Optional `ignoreCommand` can live in repo-root `vercel.json`. When the Vercel project **Root Directory** is `server/`, exit **0** skips a deployment if `VERCEL_GIT_PREVIOUS_SHA`..`VERCEL_GIT_COMMIT_SHA` touches no files under that directory; exit **1** runs the build. If the Vercel project root is the **repository** root instead, do not use this file as-is: use `git diff ... -- server/` in a small wrapper or set the Root Directory to `server/`.
