# CI configuration & secrets

Single source of truth for everything you need to set on a fork (or fresh
installation) of this repository to make the GitHub Actions workflows work
end-to-end. If you only want one section, jump straight to
[Bring-up checklist](#bring-up-checklist).

## Workflows at a glance

| Workflow | File | Trigger | Purpose |
| --- | --- | --- | --- |
| `server-ci` | [`.github/workflows/server-ci.yml`](../.github/workflows/server-ci.yml) | PR touching `server/**` or workflow itself; manual dispatch | Offline pytest plus opt-in shared CloudBase staging E2E through `workflow_dispatch` or the `cloudbase-smoke` PR label |
| `server-cd` | [`.github/workflows/server-cd.yml`](../.github/workflows/server-cd.yml) | Push to `main` touching `server/**` | Wait for Vercel **production** deploy, run staging smoke (`pytest -m smoke`) |
| `server-cloudbase-cd` | [`.github/workflows/server-cloudbase-cd.yml`](../.github/workflows/server-cloudbase-cd.yml) | Push to `main` touching `server/**`; manual dispatch | Deploy server to CloudBase Run, then health check and smoke test |
| `preview-manifest` | [`.github/workflows/preview-manifest.yml`](../.github/workflows/preview-manifest.yml) | PR `closed` + dispatch | Legacy cleanup-on-close + manual repair for the Vercel Blob preview manifest |
| `atlas-cleanup` | [`.github/workflows/atlas-cleanup.yml`](../.github/workflows/atlas-cleanup.yml) | Cron Mon 09:00 UTC + dispatch | Drop stale per-PR Mongo Atlas DBs older than 14 days |
| `vercel-prune` | [`.github/workflows/vercel-prune.yml`](../.github/workflows/vercel-prune.yml) | Cron Mon 10:00 UTC + dispatch | Keep only the newest Vercel deployment per non-`main` branch (production alias preserved) |

During the transition, both Vercel and CloudBase deployment workflows stay
alive. PR online E2E no longer deploys Vercel previews; it uses the shared
CloudBase staging service and the Beijing Lighthouse E2E database, opt-in so it
does not reset shared staging data on every PR. Pushes to `main` run both Vercel
`server-cd` and CloudBase `server-cloudbase-cd`.

The shared CloudBase staging E2E job runs on the Beijing self-hosted runner. The
runner must have system `git`, `jq`, and `python3.12`; the workflow verifies
those tools and uses `uv sync --python 3.12` instead of `actions/setup-python`
because the runner OS is OpenCloudOS 9.4.

## All secrets, in one table

`Required` means the workflow's main job will not actually do work without it
(it usually still completes green via gate steps that print warnings, so the
**absence does not block CI**, it just disables that path).

| Secret | Required by | Optional? | Effect when missing |
| --- | --- | --- | --- |
| `GITHUB_TOKEN` | every workflow | **Auto-provided.** No setup. | n/a |
| [`VERCEL_TOKEN`](#vercel_token) | `preview-manifest`, `vercel-prune`, legacy Vercel workflows | optional during M8A | Legacy Vercel cleanup / manifest repair jobs skip with a warning |
| [`VERCEL_ORG_ID`](#vercel_org_id--vercel_project_id) | legacy Vercel workflows | optional during M8A | Legacy Vercel fallback operations cannot identify the project |
| [`VERCEL_PROJECT_ID`](#vercel_org_id--vercel_project_id) | legacy Vercel workflows | optional during M8A | same as above |
| [`BLOB_READ_WRITE_TOKEN`](#blob_read_write_token) | `server-ci`, `preview-manifest` legacy path | **required** only for the legacy manifest rebuild path | The legacy refresh / repair job skips with a warning; CloudBase inline manifest does not need it |
| [`VERCEL_AUTOMATION_BYPASS_SECRET`](#vercel_automation_bypass_secret) | legacy Vercel E2E only | optional during M8A | No longer used by `server-ci`; keep only while any protected Vercel preview automation remains |
| _operator_ [**`VERCEL_CRON_SECRET`**](#vercel_cron_secret-lesson-import-extraction-cron) | workstation `~/.env` | optional | Mirrors Vercel **`CRON_SECRET`** for [`tools/vercel/trigger-cron.sh`](../tools/vercel/trigger-cron.sh); not a GitHub Actions secret |
| [`E2E_MONGODB_URI`](#e2e_mongodb_uri) | `server-ci`, `server-cd`, `server-cloudbase-cd`, `atlas-cleanup` | optional | Mongo-dependent tests may skip or fail depending on target; cron cleanup is a no-op |
| [`E2E_ADMIN_USER`](#e2e_admin_user--e2e_admin_pass), [`E2E_ADMIN_PASS`](#e2e_admin_user--e2e_admin_pass) | `server-ci`, `server-cloudbase-cd` | optional | E2E/smoke tests that need an admin login skip |
| [`E2E_CRON_SECRET`](#e2e_cron_secret) | `server-ci`, `server-cloudbase-cd` | optional | [`test_lesson_import_cron_e2e`](../server/tests/e2e/test_lesson_import_cron_e2e.py) skips if unset; must equal target **`CRON_SECRET`** |
| [`E2E_STAGING_DB_NAME`](#e2e_staging_db_name) | `server-ci` CloudBase staging E2E, `server-cd`, `server-cloudbase-cd` | optional | Shared staging E2E cannot reset or validate the target DB |
| [`SLACK_WEBHOOK_URL`](#slack_webhook_url) | `server-ci`, `server-cd` | optional | Failure alert step prints a warning; CI itself unaffected |
| [`TCB_SECRET_ID`](#cloudbase-run-migration-secrets) | CloudBase CD | optional during migration | CloudBase deploy workflow cannot authenticate to Tencent Cloud. |
| [`TCB_SECRET_KEY`](#cloudbase-run-migration-secrets) | CloudBase CD | optional during migration | CloudBase deploy workflow cannot authenticate to Tencent Cloud. |
| [`TCB_ENV_ID`](#cloudbase-run-migration-secrets) | CloudBase CD | optional during migration | CloudBase deploy workflow does not know which environment to deploy to. |
| [`CLOUDBASE_STAGING_BASE_URL`](#cloudbase-run-migration-secrets) | CloudBase smoke | optional during migration | Staging smoke checks cannot run against CloudBase. |
| [`CLOUDBASE_PROD_BASE_URL`](#cloudbase-run-migration-secrets) | CloudBase smoke | optional during migration | Production smoke checks cannot run against CloudBase. |
| `ASSET_STORAGE_PROVIDER` | CloudBase runtime env | optional until M7 | Defaults to Vercel Blob; set to `tencent_cos` after COS staging validation. |
| `COS_SECRET_ID` / `COS_SECRET_KEY` | CloudBase runtime env | optional until M7 | New COS uploads cannot run without these when `ASSET_STORAGE_PROVIDER=tencent_cos`. |
| `COS_REGION` / `COS_BUCKET` / `COS_PUBLIC_BASE_URL` | CloudBase runtime env | optional until M7 | COS URLs cannot be generated correctly without bucket and public base URL config. |
| `FLEXDB_ENV_ID` / `FLEXDB_TAG` | Operator secret inventory | optional until M7A | Identifies the CloudBase FlexDB document database target for the M7A spike. |
| `FLEXDB_MONGODB_URI` | Tencent/CloudBase secret store, if available | optional until M7A | Holds a direct FlexDB URI only if Tencent confirms built-in FlexDB supports MongoDB driver access. |
| `FLEXDB_API_SECRET_ID` / `FLEXDB_API_SECRET_KEY` | Tencent secret store only | optional until M7A | Runtime CloudBase document database API credentials if the adapter path is chosen. |
| `TENCENTDB_MONGODB_URI` | Operator secret inventory | optional until M7A | TencentDB fallback URI if FlexDB cannot satisfy the migration path. |
| `PREVIEW_MANIFEST_INLINE_JSON` | CloudBase runtime env | optional until M8 | Lets `/api/v1/public/preview-urls.json` serve CloudBase staging without Vercel Blob. |
| `CLOUDBASE_PREVIEW_MODE` | CloudBase preview workflow | optional until M8B | Documents whether preview publishing is shared staging or on-demand CloudBase preview. |

## Setting secrets in the repo

**GitHub → repo → Settings → Secrets and variables → Actions → New repository secret.**

- Names are **case-sensitive** and must match exactly.
- Repository secrets are visible to **all workflows** in the repo.
- Secrets are **not exposed** to workflows triggered by PRs from forks. If
  you accept fork PRs, expect those PRs to skip every gated step.
- Use **Environments** (Settings → Environments) only if you want
  per-environment scoping or required-reviewer gating; the current workflows
  do not use environments.

## How to obtain each secret

### CloudBase Run migration secrets

These secrets are only needed once the backend migration starts deploying
`server/` to Tencent CloudBase Run. They do not replace the existing Vercel
secrets until the Vercel retirement phase.

| Secret | Required by | Purpose |
| --- | --- | --- |
| `TCB_SECRET_ID` | CloudBase CD | Tencent Cloud API credential id for CloudBase CLI login. |
| `TCB_SECRET_KEY` | CloudBase CD | Tencent Cloud API credential key for CloudBase CLI login. |
| `TCB_ENV_ID` | CloudBase CD | CloudBase environment id. |
| `CLOUDBASE_STAGING_BASE_URL` | CloudBase smoke | Staging CloudBase HTTP Access URL. |
| `CLOUDBASE_PROD_BASE_URL` | CloudBase smoke | First CloudBase production validation URL, normally `https://happyword.com.cn`; switch to `https://happyword.cool` only after the final DNS cutover. |
| `CLOUDBASE_CRON_TARGET_URL` | CloudBase cron function | Target FastAPI cron endpoint, e.g. staging `/api/v1/admin/cron/extract-pending`. |
| `CLOUDBASE_CRON_SECRET` | CloudBase cron function | Same bearer secret as the target CloudBase Run service `CRON_SECRET`. |

Create the Tencent Cloud API credential with the narrowest permissions that can
deploy the target CloudBase Run service and read deployment status. Store the
credential only as GitHub Actions secrets or in Tencent Cloud Secret Manager;
do not commit the values to this repository.

Operational note, 2026-05-21: GitHub Actions run `server-cloudbase-cd`
`26199672079` succeeded after the CI API key was granted `QcloudTCBFullAccess`.
The narrower `QcloudTCBRFullAccess` policy was not sufficient for
`tcb login --apiKeyId "$TCB_SECRET_ID" --apiKey "$TCB_SECRET_KEY"` and failed
with Tencent Cloud key verification errors both locally and in CI. Keep the
working key restricted to GitHub Actions while migrating, then replace it with a
custom least-privilege policy once the exact CloudBase Run deploy, HTTP access,
function cron, and smoke-test actions are known.

The current M3 implementation deploys `cloudbase/functions/cron-extract-pending`
manually through the CloudBase CLI and stores function env vars in CloudBase,
not in GitHub Actions. The `CLOUDBASE_CRON_*` names are reserved for future CI/CD
automation if function deployment is moved into GitHub Actions.

### CloudBase storage and database replacement secrets

These names are for post-runtime migration waves. They are not required for the
initial CloudBase Run cutover.

#### Tencent COS asset storage

Use these after M7 switches new uploads away from Vercel Blob:

| Name | Where to store | Purpose |
| --- | --- | --- |
| `ASSET_STORAGE_PROVIDER` | CloudBase env | `vercel_blob` by default; set `tencent_cos` after staging validation. |
| `COS_SECRET_ID` | CloudBase/Tencent secret store | Tencent COS API credential id. |
| `COS_SECRET_KEY` | CloudBase/Tencent secret store | Tencent COS API credential key. |
| `COS_REGION` | CloudBase env | Bucket region. |
| `COS_BUCKET` | CloudBase env | Separate staging and production bucket names. |
| `COS_PUBLIC_BASE_URL` | CloudBase env | Public HTTPS base URL, CDN domain, or custom asset domain used to form stored URLs. |

Keep `BLOB_READ_WRITE_TOKEN` until all write paths use COS and any remaining
Vercel Blob URLs are intentionally retained or backfilled.

After the staging bucket exists, validate the runtime credentials before
switching CloudBase staging:

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

#### CloudBase FlexDB / TencentDB database replacement

Use these during M7A. FlexDB is the first spike target because the existing
CloudBase shared instance is acceptable at the current user volume. TencentDB
for MongoDB remains the fallback if FlexDB cannot provide a driver-compatible
URI and the API adapter path is too broad.

| Name | Where to store | Purpose |
| --- | --- | --- |
| `FLEXDB_ENV_ID` | CloudBase env / operator password manager | CloudBase environment id for the built-in document database. |
| `FLEXDB_TAG` | CloudBase env / operator password manager | FlexDB instance id, e.g. `tnt-jw1cesl68`; not a secret, but keep it with deployment config. |
| `FLEXDB_MONGODB_URI` | Tencent/CloudBase secret store, if available | Optional URI if Tencent confirms built-in FlexDB supports direct MongoDB driver access from CloudBase Run. |
| `FLEXDB_API_SECRET_ID` / `FLEXDB_API_SECRET_KEY` | Tencent secret store only | Runtime API credential pair only if the server must call CloudBase document database APIs directly. The smoke script also accepts `TCB_SECRET_ID` / `TCB_SECRET_KEY` and Tencent SDK-style `TENCENTCLOUD_SECRET_ID` / `TENCENTCLOUD_SECRET_KEY`; scope with a narrow CAM policy before production. |
| `LIGHTHOUSE_MONGODB_URI` | Tencent secret store / operator password manager | Optional single-node MongoDB fallback URI for the Lighthouse instance; do not put it in GitHub logs. |
| `TENCENTDB_MONGODB_URI` | Operator password manager / Tencent secret store | Future TencentDB URI before it replaces runtime `MONGODB_URI`. |
| `TENCENTDB_MONGO_DB_NAME` | Operator password manager / Tencent secret store | Target database name if different from current `MONGO_DB_NAME`. |
| `ATLAS_MONGODB_URI_ROLLBACK` | Operator password manager only | Old Atlas URI retained for rollback; do not put this in GitHub logs. |

Do not remove Atlas credentials until the database rollback window is complete.

### CloudBase preview replacement secrets

These names replace the Vercel Preview publishing path during M8.

| Name | Where to store | Purpose |
| --- | --- | --- |
| `CLOUDBASE_STAGING_BASE_URL` | GitHub Actions / CloudBase env | Shared staging URL used for M8A smoke and DevMenu manifest. |
| `PREVIEW_MANIFEST_INLINE_JSON` | CloudBase env | Inline manifest payload used before a Mongo-backed manifest exists. |
| `CLOUDBASE_PREVIEW_MODE` | GitHub Actions variable or CloudBase env | Suggested values: `shared_staging`, `on_demand_version`, `on_demand_service`. |

M8A no longer uses the legacy Vercel Preview path for `server-ci` online E2E.
Keep `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`,
`VERCEL_AUTOMATION_BYPASS_SECRET`, and `BLOB_READ_WRITE_TOKEN` configured only
for the remaining legacy cleanup / repair workflows until M8C/M9 retirement.

### `VERCEL_TOKEN`

A Vercel API token used by legacy preview deploy/E2E, cleanup, and manifest
repair workflows while the old Preview path remains available.

**Get it:**

1. Sign in at <https://vercel.com> with an account that has access to the
   target Vercel team / project.
2. Profile → **Account Settings** → **Tokens**.
3. **Create Token**, name it (e.g. `github-actions-happyword`), scope to
   the project's team, set an expiry that matches your rotation policy.
4. Copy the token **immediately** (only shown once).
5. Save it as repo secret `VERCEL_TOKEN`.

### `VERCEL_ORG_ID` & `VERCEL_PROJECT_ID`

Needed by legacy workflows that deploy, query, or repair Vercel Preview state,
including the transitional `server-ci` preview deploy.

### `BLOB_READ_WRITE_TOKEN`

Used by `server/scripts/update_preview_manifest.mjs` to publish the public
preview manifest to Vercel Blob at `preview/preview-urls.json`. The Blob is
the **only** output of the script — there is no repo-tracked audit copy any
more, so without this token the rebuild jobs skip with a warning and the
runtime endpoint `GET /api/v1/public/preview-urls.json` keeps serving whatever is
currently in Blob (or returns `503` until the env var is wired up the first
time).

**Get it:**

1. In the Vercel project, create or open the Blob store used by `happyword`.
2. Copy the read-write token and save it as repo secret `BLOB_READ_WRITE_TOKEN`.
3. Run `preview-manifest` manually once and copy the log line
   `Uploaded Blob mirror: <url>`.
4. Save that URL as the Vercel project env var `PREVIEW_MANIFEST_BLOB_URL` for
   Production and Preview. The backend endpoint returns `503` until this env var
   is set.

**Get them** (after `VERCEL_TOKEN` is set):

```bash
cd server
npx vercel link        # interactive: pick Team + Project
cat .vercel/project.json   # → { "orgId": "...", "projectId": "..." }
```

Save:

- `VERCEL_ORG_ID` ← `orgId`
- `VERCEL_PROJECT_ID` ← `projectId`

(`server/.vercel/` is gitignored.)

### `VERCEL_AUTOMATION_BYPASS_SECRET`

If your Vercel project has [Deployment Protection]
(<https://vercel.com/docs/security/deployment-protection>) enabled (default
for Pro accounts), every preview URL is gated by Vercel's SSO login page —
which the E2E tests cannot pass.

**Get it:**

1. Vercel project → **Settings → Deployment Protection** → enable
   **Protection Bypass for Automation**.
2. Click **Generate Secret**, copy the value.
3. Save as repo secret `VERCEL_AUTOMATION_BYPASS_SECRET`.

The E2E test driver passes this to every request as
`x-vercel-protection-bypass: <secret>` (see
[`server/tests/e2e/conftest.py`](../server/tests/e2e/conftest.py)).

**HarmonyOS debug builds:** paste the **same** secret in the app Developer
Options → **Bypass Secret** dialog (value from Vercel **Protection Bypass for
Automation**) so preview URL health checks succeed from a device.

| Dev menu (debug) | Vercel bypass secret |
| --- | --- |
| ![Dev menu](../assets/screenshots/harmonyos/dev-menu.png) | ![Bypass](../assets/screenshots/harmonyos/bypass-secret.png) |

### `VERCEL_CRON_SECRET` (lesson import extraction cron)

**What it does**

The deployed server route **`POST /api/v1/admin/cron/extract-pending`** (see
[`server/app/routers/admin_cron.py`](../server/app/routers/admin_cron.py)) claims one
lesson-import draft stuck in **`status="extracting"`**, calls the vision LLM,
and promotes it to **`pending`** or records failure. Only callers that present
matching **`Authorization: Bearer <secret>`** are allowed.

**On Vercel**

1. Generate a strong random secret (same idea as a webhook signing key):

   ```bash
   openssl rand -hex 32
   ```

2. Add **`CRON_SECRET`** under **Project → Settings → Environment Variables**
   for **Production** (required for scheduled cron) and **Preview** (needed if you
   manually hit a preview URL).

3. Scheduled invocations configured in **`server/vercel.json`** `crons[].path` (Vercel Root Directory = `server`)
   are sent by Vercel with that Bearer token when **`CRON_SECRET`** is defined
   for the deployment.

Without **`CRON_SECRET`** on the server, the route rejects every request (**401 /
`CRON_SECRET_NOT_CONFIGURED`**), including legitimate cron ticks.

**On your workstation**

Put the **same literal value** in **`~/.env`** as `VERCEL_CRON_SECRET=…` next to other
operator secrets (**never commit** `~/.env`). Then run from the repo root:

```bash
bash tools/vercel/trigger-cron.sh
```

Trigger a specific job by name (suffix after `/api/v1/admin/cron/`):

```bash
bash tools/vercel/trigger-cron.sh --job extract-pending
```

Override the target host when calling a Preview:

```bash
bash tools/vercel/trigger-cron.sh --url https://your-preview.vercel.app --job extract-pending
```

Or just the URL fragment (happyword-<frag>-terrymas-projects.vercel.app):

```bash
bash tools/vercel/trigger-cron.sh --url-fragment 9y7uijs1p --job extract-pending
```

Further detail: [`tools/vercel/trigger-cron.sh`](../tools/vercel/trigger-cron.sh).

### `E2E_CRON_SECRET`

Repository secret used only by GitHub Actions: the E2E job exports it so
[`server/tests/e2e/test_lesson_import_cron_e2e.py`](../server/tests/e2e/test_lesson_import_cron_e2e.py)
can call **`POST /api/v1/admin/cron/extract-pending`** with
**`Authorization: Bearer …`**. Use the **same value** as the target CloudBase
staging environment variable **`CRON_SECRET`**.
When this secret is not configured, the test is **skipped** (the suite stays green).

### `E2E_MONGODB_URI`

Mongo connection string used by:

- `server-ci` shared CloudBase staging E2E;
- `server-cd` staging smoke;
- `server-cloudbase-cd` smoke;
- `atlas-cleanup` weekly cron to drop stale per-PR DBs.

**Must be a dedicated test cluster** — the reset script refuses to run
against any DB whose name doesn't end in `_e2e` / `_test` / `_ci`, and
refuses any name that contains `prod`. Still, do not point this at your
production cluster credentials.

For `server-ci`, this secret is currently the Beijing self-hosted runner's
loopback URI for `happyword_cloudbase_staging_e2e`, not a public CloudBase
runtime URI. The CloudBase staging service has its own public TLS MongoDB URI in
CloudBase runtime env.

**Get it (Mongo Atlas, for legacy/fallback setups):**

1. <https://cloud.mongodb.com> → create a Project + a dedicated **test**
   cluster (M0 free tier is enough).
2. **Database Access** → create a user with `readWriteAnyDatabase` on this
   cluster (the per-PR DB names are dynamic, so a single-DB role won't fit).
3. **Network Access** → either add `0.0.0.0/0` (open; OK for an isolated
   test cluster) or use a VPC peering / IP allowlist that includes GitHub
   Hosted Runner IPs. GitHub does not publish stable runner IP ranges, so
   most teams just use `0.0.0.0/0` on the test cluster.
4. **Connect → Drivers**, copy the `mongodb+srv://...` URI, fill in the
   user / password.
5. Save as `E2E_MONGODB_URI`.

M8A `server-ci` uses the static `E2E_STAGING_DB_NAME` for the shared CloudBase
staging E2E database.

### `E2E_ADMIN_USER` & `E2E_ADMIN_PASS`

Bootstrap admin credentials the E2E/smoke tests use to call admin-only endpoints
(`/api/v1/admin/auth/login`). They must match the `ADMIN_BOOTSTRAP_USER` /
`ADMIN_BOOTSTRAP_PASS` env vars on CloudBase staging, since the FastAPI startup
hook seeds the admin row from those.

**Pick any two strings** (treat as secrets), and:

1. Save them as repo secrets `E2E_ADMIN_USER` / `E2E_ADMIN_PASS`.
2. Save the **same** values as `ADMIN_BOOTSTRAP_USER` /
   `ADMIN_BOOTSTRAP_PASS` on CloudBase staging.

### `E2E_STAGING_DB_NAME`

Static DB name that CloudBase staging E2E resets and validates. Current value:
`happyword_cloudbase_staging_e2e`. The reset script requires `_e2e`, `_test`, or
`_ci` and refuses any name containing `prod`.

**Get it:** use the fixed Beijing staging E2E database name and save it.

### `SLACK_WEBHOOK_URL`

Slack [Incoming Webhook](https://api.slack.com/messaging/webhooks) URL used
by failure alert steps such as `server-cd` post-merge smoke failure.

**Get it:**

1. <https://api.slack.com/apps> → **Create New App** → **From scratch**.
2. Pick the Slack workspace.
3. **Incoming Webhooks** → toggle **Activate Incoming Webhooks**.
4. **Add New Webhook to Workspace** → choose the alert channel (e.g.
   `#happyword-ci`).
5. Copy the URL `https://hooks.slack.com/services/T.../B.../...` and save
   as `SLACK_WEBHOOK_URL`.

If your team already has a CI-alert Slack App, ask the admin to add a
webhook for your channel under that app and reuse the URL.

## Vercel-side environment variables

Secrets above only let CI **talk to** Vercel. The deployed FastAPI server
itself needs its own env vars on **Vercel → Project → Settings →
Environment Variables**. Set these on **Preview** (used by E2E) and
**Production** (used by the staging smoke):

| Variable | Purpose | Notes |
| --- | --- | --- |
| `MONGODB_URI` | App's Mongo URI | **Must be the same Atlas cluster** as `E2E_MONGODB_URI`, or the per-PR reset and the API will work on different DBs and E2E will drift. |
| `MONGO_DB_NAME` | App's DB name | For Preview: leave it templated/per-PR (see [`server/.env.local.example`](../server/.env.local.example)). For Production: `happyword_staging` (matches `E2E_STAGING_DB_NAME`). |
| `JWT_SECRET` | JWT signing | Generate `openssl rand -base64 32`. Must be ≥32 bytes. |
| `JWT_EXPIRE_HOURS` | Token TTL | e.g. `24`. |
| `ADMIN_BOOTSTRAP_USER` / `ADMIN_BOOTSTRAP_PASS` | Seed admin row at startup | **Must equal** `E2E_ADMIN_USER` / `E2E_ADMIN_PASS`. |
| `CRON_SECRET` | Bearer for **`POST /api/v1/admin/cron/extract-pending`** | Required for lesson-import async extraction cron + manual trigger script. **`openssl rand -hex 32`**. Preview + Production. See [`VERCEL_CRON_SECRET` §](#vercel_cron_secret-lesson-import-extraction-cron). |
| `OPENAI_API_KEY` | LLM features | Leave **empty** for E2E previews (E2E never calls real OpenAI). |
| `SMTP_USERNAME` / `SMTP_PASSWORD` / `SMTP_HOST` / `SMTP_PORT` | Email | Leave **`SMTP_USERNAME` blank** on Preview so E2E uses DB OTP injection instead of real email. |
| `CORS_ALLOW_ORIGINS` | CORS | `*` for non-production; lock down for production. |
| `LOG_LEVEL` | Logging | `info`. |

The exhaustive server env reference is in
[`server/.env.local.example`](../server/.env.local.example).

## Bring-up checklist

For someone forking this repo and wanting CI fully working:

1. **Vercel**

   - [ ] Import the repo into Vercel; let it run a Preview deploy on a PR.
   - [ ] Settings → Environment Variables → fill in every row of the
         [Vercel-side env table](#vercel-side-environment-variables) for
         **Preview** and **Production** (**`CRON_SECRET`** is required for
         `/api/v1/admin/cron/extract-pending` — see
         [**`VERCEL_CRON_SECRET` §**](#vercel_cron_secret-lesson-import-extraction-cron)).
   - [ ] Settings → Deployment Protection → enable **Protection Bypass for
         Automation**, copy the secret.
   - [ ] Run `cd server && npx vercel link` to capture `orgId` /
         `projectId`.

2. **Mongo Atlas**

   - [ ] Create a dedicated test cluster.
   - [ ] Create a user with `readWriteAnyDatabase` on it.
   - [ ] Network Access → allow `0.0.0.0/0` (or explicit allowlist).
   - [ ] Copy the connection string.

3. **Slack** *(optional but recommended)*

   - [ ] Create / reuse a Slack App with Incoming Webhooks for your alert
         channel.

4. **GitHub repo secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value source |
   | --- | --- |
   | `VERCEL_TOKEN` | Vercel Account Settings → Tokens |
   | `VERCEL_ORG_ID` | `server/.vercel/project.json` `.orgId` |
   | `VERCEL_PROJECT_ID` | `server/.vercel/project.json` `.projectId` |
   | `VERCEL_AUTOMATION_BYPASS_SECRET` | Vercel project → Deployment Protection |
   | `BLOB_READ_WRITE_TOKEN` | Vercel Blob store read-write token |
   | `TCB_SECRET_ID` | Tencent Cloud API credential id |
   | `TCB_SECRET_KEY` | Tencent Cloud API credential key |
   | `TCB_ENV_ID` | CloudBase environment id |
   | `CLOUDBASE_STAGING_BASE_URL` | CloudBase staging HTTP access URL |
   | `CLOUDBASE_PROD_BASE_URL` | CloudBase production HTTP access URL during transition |
   | `E2E_MONGODB_URI` | Beijing self-hosted runner loopback URI for shared staging E2E |
   | `E2E_ADMIN_USER` | freely chosen, mirrors target `ADMIN_BOOTSTRAP_USER` |
   | `E2E_ADMIN_PASS` | freely chosen, mirrors target `ADMIN_BOOTSTRAP_PASS` |
   | `E2E_STAGING_DB_NAME` | `happyword_cloudbase_staging_e2e` |
   | `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL |

5. **Smoke test**

   - [ ] Open a tiny PR that touches `server/`. `server-ci` should run
         offline `pytest` by default.
   - [ ] Add the `cloudbase-smoke` label, or manually dispatch `server-ci`.
         Confirm `server / cloudbase staging e2e` runs against
         `CLOUDBASE_STAGING_BASE_URL`.
   - [ ] Merge a `server/**` change to `main`. Watch both `server-cd` and
         `server-cloudbase-cd`; Vercel should smoke after production deploy,
         and CloudBase should deploy, health check, and smoke.
         First green main run: `server-cloudbase-cd` `26199672079` on
         2026-05-21 after PR #118 merged.
   - [ ] Wait until Monday 09:00 UTC (or trigger `atlas-cleanup` manually)
         to confirm the cleanup script connects.

## Operational notes

- **Forks & PRs from forks.** GitHub does not pass repository secrets to
  workflows for PRs from forks (`pull_request` event). Every gated step in
  this repo will skip — the workflow stays green and prints a warning.
  Push the branch into this repository and open the PR from there to
  exercise the full pipeline.
- **Rotation.** Vercel tokens and Slack webhooks expire or
  get invalidated. The first symptom is silent skipping (the gate steps
  print warnings). When a workflow stops doing E2E, check secret presence
  and freshness first.
- **Scope.** All current secrets are **repository-level**. None are tied to
  a GitHub Environment, so a workflow re-run will not require approval.
- **Per-PR DB hygiene.** `atlas-cleanup` drops `happyword_pr_<N>_e2e` DBs
  older than 14 days. If you keep a PR open longer, the next CI run on it
  re-creates the DB from scratch — no manual action needed.
- **Lesson extract cron.** Vercel only runs declarative Cron against
  **Production**. To tick extraction from your machine or smoke a Preview, use
  **`bash tools/vercel/trigger-cron.sh`** with workstation
  **`VERCEL_CRON_SECRET`** in **`~/.env`** (matching the target deployment's
  Vercel `CRON_SECRET`). Details in **`VERCEL_CRON_SECRET` §**.
