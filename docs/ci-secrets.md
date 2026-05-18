# CI configuration & secrets

Single source of truth for everything you need to set on a fork (or fresh
installation) of this repository to make the GitHub Actions workflows work
end-to-end. If you only want one section, jump straight to
[Bring-up checklist](#bring-up-checklist).

## Workflows at a glance

| Workflow | File | Trigger | Purpose |
| --- | --- | --- | --- |
| `server-ci` | [`.github/workflows/server-ci.yml`](../.github/workflows/server-ci.yml) | PR touching `server/**` or workflow itself | Offline pytest → E2E pytest against a Vercel Preview → branches: success ⇒ rebuild Vercel Blob preview manifest; failure ⇒ Cursor autofix |
| `server-cd` | [`.github/workflows/server-cd.yml`](../.github/workflows/server-cd.yml) | Push to `main` touching `server/**` | Wait for Vercel **production** deploy, run staging smoke (`pytest -m smoke`) |
| `cursor-autofix-e2e` | [`.github/workflows/cursor-autofix-e2e.yml`](../.github/workflows/cursor-autofix-e2e.yml) | `workflow_dispatch` | Manually trigger a Cursor Cloud Agent for an open PR |
| `preview-manifest` | [`.github/workflows/preview-manifest.yml`](../.github/workflows/preview-manifest.yml) | PR `closed` + dispatch | Cleanup-on-close + manual repair for the Vercel Blob preview manifest (the open-PR refresh path lives in the `update_manifest` job inside `server-ci`) |
| `atlas-cleanup` | [`.github/workflows/atlas-cleanup.yml`](../.github/workflows/atlas-cleanup.yml) | Cron Mon 09:00 UTC + dispatch | Drop stale per-PR Mongo Atlas DBs older than 14 days |
| `vercel-prune` | [`.github/workflows/vercel-prune.yml`](../.github/workflows/vercel-prune.yml) | Cron Mon 10:00 UTC + dispatch | Keep only the newest Vercel deployment per non-`main` branch (production alias preserved) |

`server-ci` is the most important one — its `server_e2e` job branches into
either the manifest refresh (`update_manifest`) or the Cursor autofix path
(`cursor_autofix_e2e`) depending on the E2E result. `preview-manifest.yml`
now only handles cleanup-on-close and manual repair runs.

## All secrets, in one table

`Required` means the workflow's main job will not actually do work without it
(it usually still completes green via gate steps that print warnings, so the
**absence does not block CI**, it just disables that path).

| Secret | Required by | Optional? | Effect when missing |
| --- | --- | --- | --- |
| `GITHUB_TOKEN` | every workflow | **Auto-provided.** No setup. | n/a |
| [`VERCEL_TOKEN`](#vercel_token) | `server-ci` | optional | `server / e2e (preview)` job is skipped (warning only) |
| [`VERCEL_ORG_ID`](#vercel_org_id--vercel_project_id) | `server-ci` (fallback deploy) | optional | E2E job tries the auto-deploy fallback and fails if no preview was detected on the SHA |
| [`VERCEL_PROJECT_ID`](#vercel_org_id--vercel_project_id) | `server-ci` (fallback deploy) | optional | same as above |
| [`BLOB_READ_WRITE_TOKEN`](#blob_read_write_token) | `server-ci`, `preview-manifest` | **required** for the manifest rebuild path | The `update_manifest` jobs skip with a warning; `GET /api/v1/public/preview-urls.json` keeps serving whatever is currently in Blob (or `503` until the env var is wired up the first time) |
| [`VERCEL_AUTOMATION_BYPASS_SECRET`](#vercel_automation_bypass_secret) | `server-ci` E2E | optional | E2E hits the **Vercel deployment protection** login page and every request fails |
| _operator_ [**`VERCEL_CRON_SECRET`**](#vercel_cron_secret-lesson-import-extraction-cron) | workstation `~/.env` | optional | Mirrors Vercel **`CRON_SECRET`** for [`tools/vercel/trigger-cron.sh`](../tools/vercel/trigger-cron.sh); not a GitHub Actions secret |
| [`E2E_MONGODB_URI`](#e2e_mongodb_uri) | `server-ci`, `server-cd`, `atlas-cleanup` | optional | E2E DB reset + Mongo-dependent tests skip; cron cleanup is a no-op |
| [`E2E_ADMIN_USER`](#e2e_admin_user--e2e_admin_pass), [`E2E_ADMIN_PASS`](#e2e_admin_user--e2e_admin_pass) | `server-ci` E2E | optional | E2E tests that need an admin login skip |
| [`E2E_CRON_SECRET`](#e2e_cron_secret) | `server-ci` E2E | optional | [`test_lesson_import_cron_e2e`](../server/tests/e2e/test_lesson_import_cron_e2e.py) skips if unset; must equal Preview **`CRON_SECRET`** |
| [`E2E_STAGING_DB_NAME`](#e2e_staging_db_name) | `server-cd` | optional | `pytest -m smoke` runs without a DB target → likely fails |
| [`SLACK_WEBHOOK_URL`](#slack_webhook_url) | `server-ci`, `server-cd` | optional | Failure alert step prints a warning; CI itself unaffected |
| [`CURSOR_API_KEY`](#cursor_api_key) | `server-ci` (autofix), `cursor-autofix-e2e` | optional | The whole `cursor / autofix e2e` path warns once and exits — no agent is spawned |
| [`TCB_SECRET_ID`](#cloudbase-run-migration-secrets) | CloudBase CD | optional during migration | CloudBase deploy workflow cannot authenticate to Tencent Cloud. |
| [`TCB_SECRET_KEY`](#cloudbase-run-migration-secrets) | CloudBase CD | optional during migration | CloudBase deploy workflow cannot authenticate to Tencent Cloud. |
| [`TCB_ENV_ID`](#cloudbase-run-migration-secrets) | CloudBase CD | optional during migration | CloudBase deploy workflow does not know which environment to deploy to. |
| [`CLOUDBASE_STAGING_BASE_URL`](#cloudbase-run-migration-secrets) | CloudBase smoke | optional during migration | Staging smoke checks cannot run against CloudBase. |
| [`CLOUDBASE_PROD_BASE_URL`](#cloudbase-run-migration-secrets) | CloudBase smoke | optional during migration | Production smoke checks cannot run against CloudBase. |

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

The current M3 implementation deploys `cloudbase/functions/cron-extract-pending`
manually through the CloudBase CLI and stores function env vars in CloudBase,
not in GitHub Actions. The `CLOUDBASE_CRON_*` names are reserved for future CI/CD
automation if function deployment is moved into GitHub Actions.

### `VERCEL_TOKEN`

A Vercel API token used to:

1. let `actions/github-script` query the Vercel deployment status API,
2. let the **fallback deploy** step (`amondnet/vercel-action@v25`) deploy
   the PR if no preview was created.

**Get it:**

1. Sign in at <https://vercel.com> with an account that has access to the
   target Vercel team / project.
2. Profile → **Account Settings** → **Tokens**.
3. **Create Token**, name it (e.g. `github-actions-happyword`), scope to
   the project's team, set an expiry that matches your rotation policy.
4. Copy the token **immediately** (only shown once).
5. Save it as repo secret `VERCEL_TOKEN`.

### `VERCEL_ORG_ID` & `VERCEL_PROJECT_ID`

Only needed for the **fallback deploy** path (when a Vercel Preview was not
detected for the head SHA — typically because Vercel is misconfigured or
slow). The detect-only path doesn't need them.

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

Further detail: Cursor skill **`vercel-trigger-cron`** and
[`tools/vercel/trigger-cron.sh`](../tools/vercel/trigger-cron.sh).

### `E2E_CRON_SECRET`

Repository secret used only by GitHub Actions: the E2E job exports it so
[`server/tests/e2e/test_lesson_import_cron_e2e.py`](../server/tests/e2e/test_lesson_import_cron_e2e.py)
can call **`POST /api/v1/admin/cron/extract-pending`** with
**`Authorization: Bearer …`**. Use the **same value** as Vercel **Preview**
environment variable **`CRON_SECRET`** (see [`VERCEL_CRON_SECRET` §](#vercel_cron_secret-lesson-import-extraction-cron)).
When this secret is not configured, the test is **skipped** (the suite stays green).

### `E2E_MONGODB_URI`

Mongo connection string used by:

- `server / e2e` to reset the per-PR test DB before the suite, and to inject
  OTP codes for verification flows;
- `server-cd` staging smoke;
- `atlas-cleanup` weekly cron to drop stale per-PR DBs.

**Must be a dedicated test cluster** — the reset script refuses to run
against any DB whose name doesn't end in `_e2e` / `_test` / `_ci`, and
refuses any name that contains `prod`. Still, do not point this at your
production cluster credentials.

**Get it (Mongo Atlas):**

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

The per-PR DB name is computed inside the workflow from the PR number
(`happyword_pr_<N>_e2e`); you do **not** set `E2E_MONGO_DB_NAME` as a
secret for `server-ci`.

### `E2E_ADMIN_USER` & `E2E_ADMIN_PASS`

Bootstrap admin credentials the E2E tests use to call admin-only endpoints
(`/api/v1/admin/auth/login`). They must match the `ADMIN_BOOTSTRAP_USER` /
`ADMIN_BOOTSTRAP_PASS` env vars you set on the Vercel **Preview**
deployment, since the FastAPI startup hook seeds the admin row from those.

**Pick any two strings** (treat as secrets), and:

1. Save them as repo secrets `E2E_ADMIN_USER` / `E2E_ADMIN_PASS`.
2. Save the **same** values as `ADMIN_BOOTSTRAP_USER` /
   `ADMIN_BOOTSTRAP_PASS` on the Vercel project under **Settings →
   Environment variables → Preview**.

### `E2E_STAGING_DB_NAME`

Static DB name that the post-merge **staging smoke** (`server-cd`) connects
to — typically `happyword_staging`. The DB sits inside the same Atlas
cluster pointed at by `E2E_MONGODB_URI`. The reset script's `_e2e/_test/_ci`
suffix rule does not apply to smoke (smoke is read-mostly), but the name
must still avoid `prod`.

**Get it:** decide on a name (e.g. `happyword_staging`) and save it.

### `SLACK_WEBHOOK_URL`

Slack [Incoming Webhook](https://api.slack.com/messaging/webhooks) URL used
by the failure alert steps in `server-ci` (E2E failure on a PR) and
`server-cd` (post-merge smoke failure).

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

### `CURSOR_API_KEY`

Lets `server-ci` (auto, on failed E2E) and `cursor-autofix-e2e` (manual)
spawn a [Cursor Cloud Agent](https://cursor.com/docs/background-agent/api/overview)
that commits a fix to the PR branch.

**Get it:**

1. <https://cursor.com/dashboard/cloud-agents> → **API keys**.
2. Create a key. **Service-account keys** are recommended for CI; user keys
   work but follow the user's permissions.
3. Save as `CURSOR_API_KEY`.

**Also required:** the **Cursor GitHub App** must be installed on the
repository (or the org) so the agent can push commits to the PR's head
branch. Install at <https://github.com/apps/cursor-com>. Without it the
agent's `git push` fails.

If you protect the PR branch (Settings → Branches → Branch protection
rules), the agent's push will be rejected. The current setup assumes only
`main` is protected.

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

4. **Cursor** *(optional)*

   - [ ] Install the Cursor GitHub App on the repo.
   - [ ] Mint a `CURSOR_API_KEY` from the Cursor dashboard.

5. **GitHub repo secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value source |
   | --- | --- |
   | `VERCEL_TOKEN` | Vercel Account Settings → Tokens |
   | `VERCEL_ORG_ID` | `server/.vercel/project.json` `.orgId` |
   | `VERCEL_PROJECT_ID` | `server/.vercel/project.json` `.projectId` |
   | `VERCEL_AUTOMATION_BYPASS_SECRET` | Vercel project → Deployment Protection |
   | `E2E_MONGODB_URI` | Atlas connect string |
   | `E2E_ADMIN_USER` | freely chosen, mirrors Vercel `ADMIN_BOOTSTRAP_USER` |
   | `E2E_ADMIN_PASS` | freely chosen, mirrors Vercel `ADMIN_BOOTSTRAP_PASS` |
   | `E2E_STAGING_DB_NAME` | e.g. `happyword_staging` |
   | `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL |
   | `CURSOR_API_KEY` | Cursor Dashboard → Cloud agents → API keys |

6. **Smoke test**

   - [ ] Open a tiny PR that touches `server/`. `server-ci` should run
         `pytest`, then `e2e (preview)`. Check that `Reset E2E database`
         no longer prints the `E2E_MONGODB_URI not configured` warning.
   - [ ] Force an E2E failure (e.g. break an assertion). Watch
         `cursor / autofix e2e (preview)` spawn an agent and post a comment
         linking to the [Cursor Cloud Agents dashboard](https://cursor.com/dashboard/cloud-agents).
   - [ ] Merge a `server/**` change to `main`. Watch `server-cd` poll for
         the production deploy and run `pytest -m smoke`.
   - [ ] Wait until Monday 09:00 UTC (or trigger `atlas-cleanup` manually)
         to confirm the cleanup script connects.

## Operational notes

- **Forks & PRs from forks.** GitHub does not pass repository secrets to
  workflows for PRs from forks (`pull_request` event). Every gated step in
  this repo will skip — the workflow stays green and prints a warning.
  Push the branch into this repository and open the PR from there to
  exercise the full pipeline.
- **Rotation.** Vercel tokens, Cursor keys, and Slack webhooks expire or
  get invalidated. The first symptom is silent skipping (the gate steps
  print warnings). When a workflow stops doing E2E or autofix, check secret
  presence and freshness first.
- **Scope.** All current secrets are **repository-level**. None are tied to
  a GitHub Environment, so a workflow re-run will not require approval.
- **Cursor autofix loop.** The autofix script enforces `MAX_ROUNDS = 20`
  per PR (counted across SHAs; raised from 10 after long-lived branches
  hit the cap mid-debug). If you hit the cap on a long-running PR, either
  delete some of the `<!-- cursor-autofix-triggered:* -->` marker comments
  on the PR, raise `DEFAULT_MAX_ROUNDS` in
  [`.github/scripts/trigger-cursor-fix-e2e.mjs`](../.github/scripts/trigger-cursor-fix-e2e.mjs),
  or pass a one-off override via the `cursor-autofix-e2e` workflow's
  `max_rounds` input.
- **Per-PR DB hygiene.** `atlas-cleanup` drops `happyword_pr_<N>_e2e` DBs
  older than 14 days. If you keep a PR open longer, the next CI run on it
  re-creates the DB from scratch — no manual action needed.
- **Lesson extract cron.** Vercel only runs declarative Cron against
  **Production**. To tick extraction from your machine or smoke a Preview, use
  **`bash tools/vercel/trigger-cron.sh`** with workstation
  **`VERCEL_CRON_SECRET`** in **`~/.env`** (matching the target deployment's
  Vercel `CRON_SECRET`). Details in **`VERCEL_CRON_SECRET` §**.
