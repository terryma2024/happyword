---
name: hw-seed-lesson-pending-review
description: Seed a lesson-import draft on a deployed Happyword API (Preview or prod) and optionally run the extract-pending cron so it reaches `pending` (待复核). Uses tools starting with `hw_`. Invoke when the user wants to upload a textbook photo for review against a specific Vercel URL, mirror E2E `test_lesson_import_cron_e2e`, or smoke-test lesson import + cron on a branch deployment.
---

# hw-seed-lesson-pending-review

## Canonical entrypoints

From **repository root**:

```bash
bash tools/hw_seed_lesson_pending_review.sh \
  --base-url https://happyword-xxxx-terrymas-projects.vercel.app \
  --family-id fam-01234567
```

- **`--base-url`** — Deployment origin (scheme optional; trailing slash stripped).
- **`--family-id`** — Operator label only; echoed in JSON. Lesson drafts are **not** family-scoped in open-admin V0.7; use this to correlate runs with a HarmonyOS device / parent session.
- **`--image`** — Optional path to JPEG/PNG/WebP (defaults to `server/tests/e2e/_fixtures/lesson_import_fixture.jpg`).
- **`--skip-cron`** — Only `POST /api/v1/admin/lessons/import` (draft stays `extracting` until Vercel cron or a manual cron trigger).

Direct Python (same behaviour):

```bash
uv run --project server python tools/hw_seed_lesson_pending_review.py --help
```

## Secrets (`~/.env`)

The shell wrapper **sources `~/.env`** when readable (like other operator scripts). Do **not** print secrets.

| Purpose | Env vars tried (first wins) |
| --- | --- |
| Vercel Deployment Protection bypass | `HW_VERCEL_BYPASS`, `E2E_VERCEL_PROTECTION_BYPASS`, `VERCEL_AUTOMATION_BYPASS_SECRET` |
| Cron `Authorization` for `POST /api/v1/admin/cron/extract-pending` | `HW_CRON_SECRET`, `E2E_CRON_SECRET`, `VERCEL_CRON_SECRET`, `CRON_SECRET` |

Preview deployments without a bypass header typically return **401** HTML from Vercel — match production/staging **`CRON_SECRET`** on the target deployment when invoking cron.

## Behaviour (matches E2E)

Aligned with `server/tests/e2e/test_lesson_import_cron_e2e.py`:

1. `POST /api/v1/admin/lessons/import` → `201`, draft `extracting`.
2. Unless `--skip-cron`: `POST /api/v1/admin/cron/extract-pending` with `Authorization: Bearer …`.
3. `GET /api/v1/admin/lesson-drafts/{id}` → expect `pending` (success) or `extract_failed` (LLM/config failure on server).

Exit **0** only when final draft status is **`pending`**. Mongo queue cleanup (deleting other `extracting` rows) is **not** performed — if multiple drafts are extracting, cron may claim another row first; see E2E test for deterministic DB cleanup when needed.

## Related

- Cron manual trigger: skill **`vercel-trigger-cron`** (`bash tools/vercel/trigger-cron.sh`).
- Vercel Root Directory for this repo: **`.cursor/rules/vercel-root-directory.mdc`** (`server/`).
