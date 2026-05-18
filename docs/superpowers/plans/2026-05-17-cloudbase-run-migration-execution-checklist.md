# CloudBase Run Migration Execution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the `server/` FastAPI backend from Vercel to Tencent CloudBase Run through small, reversible milestones that can be executed over multiple work sessions.

**Architecture:** Treat the migration as a long-running project with four gates: prepare, prove CloudBase staging, cut over production, then retire Vercel-specific dependencies. The first production cutover keeps MongoDB Atlas and Vercel Blob in place so runtime migration can be verified independently from storage and preview-system migration.

**Tech Stack:** Python 3.12, FastAPI, Uvicorn, uv, Docker, CloudBase Run, CloudBase HTTP Access Service, CloudBase Cloud Functions timer trigger, GitHub Actions, MongoDB Atlas, Vercel Blob compatibility during Wave A, CloudBase Storage or Tencent COS during Wave B.

---

## Related Documents

- Architecture plan: `docs/superpowers/plans/2026-05-17-cloudbase-run-backend-migration.md`
- Existing CI/secrets runbook: `docs/ci-secrets.md`
- Current Vercel config: `server/vercel.json`
- Current Vercel ASGI shim: `server/api/index.py`
- Current FastAPI app: `server/app/main.py`
- Current Blob service: `server/app/services/blob_service.py`
- Current preview manifest proxy: `server/app/services/preview_manifest_service.py`
- Current Vercel preview manifest builder: `server/scripts/update_preview_manifest.mjs`

## Project-Level Rules

- Keep Vercel production deploy and environment variables intact until CloudBase production has passed the stability gate.
- Do not migrate storage in the same release as the first runtime cutover.
- Do not change MongoDB production schema during the first runtime cutover.
- Do not delete Vercel workflows, Blob tokens, or Vercel project resources until the Vercel retirement phase.
- Use `happyword.com.cn` as the first CloudBase production validation host.
  Keep `happyword.cool` on Vercel until `happyword.com.cn` is fully green, then
  move `happyword.cool` CNAME/DNS to CloudBase as the final cutover.
- Use `GET /api/v1/public/health` as the first health signal for every deployed environment.
- Every commit touching `server/` must run `cd server && uv run pytest -v` with `0 errors` and `0 warnings`.

## Milestone Map

- [x] **M0: Migration control plane ready** - accounts, domain, secrets inventory, and rollback policy are documented.
- [x] **M1: Container runtime ready** - `server/` builds and runs locally as a CloudBase-compatible container.
- [ ] **M2: CloudBase staging online** - default CloudBase domain serves health, public pages, admin login, and pack JSON.
- [x] **M3: Cron replacement online** - CloudBase timer calls the existing cron endpoint successfully.
- [ ] **M4: Production domain ready** - `happyword.com.cn` can be bound to CloudBase with SSL and required filing state confirmed.
- [ ] **M5: Production cutover complete** - `happyword.com.cn` points to CloudBase and smoke validation passes; `happyword.cool` moves only after that.
- [ ] **M6: CloudBase CI/CD active** - `main` deployment and smoke checks no longer depend on Vercel production deployment status.
- [ ] **M7: Storage migration complete** - new uploads use CloudBase Storage or Tencent COS, existing Vercel Blob URLs stay readable.
- [ ] **M8: Preview/QA replacement complete** - Vercel Preview dependency is removed from the QA path.
- [ ] **M9: Vercel retired** - Vercel deploy, cron, preview, prune, and Blob-specific secrets are removed or archived.

## M0: Migration Control Plane

**Goal:** Make the project safe to run over many days without losing track of current state, secrets, or rollback.

**Files:**

- Create: `docs/server/cloudbase-run.md`
- Modify: `docs/ci-secrets.md`

- [x] **Step 1: Create the CloudBase runbook skeleton**

  Create `docs/server/cloudbase-run.md` with this initial structure:

  ````markdown
  # CloudBase Run Operations Runbook

  ## Current State

  - Runtime owner: CloudBase Run
  - Production domain: happyword.cool
  - Production service name: happyword-server
  - Staging service name: happyword-server-staging
  - MongoDB provider: MongoDB Atlas
  - Asset storage provider during Wave A: Vercel Blob
  - Asset storage provider during Wave B: undecided, CloudBase Storage or Tencent COS

  ## CloudBase Environment

  - Environment ID:
  - Region: Shanghai
  - HTTP Access Service:
  - Production default domain:
  - Staging default domain:

  ## Deployment Commands

  ```bash
  cd server
  tcb cloudrun deploy -e "$TCB_ENV_ID" -s happyword-server --port 8080 --source . --force
  ```

  ## Health Checks

  ```bash
  curl -fsS "$CLOUDBASE_BASE_URL/api/v1/public/health"
  curl -fsS -I "$CLOUDBASE_BASE_URL/api/v1/public/packs/latest.json"
  curl -fsS -I "$CLOUDBASE_BASE_URL/privacy"
  curl -fsS -I "$CLOUDBASE_BASE_URL/admin/login"
  ```

  ## Rollback

  - CloudBase version rollback:
  - DNS rollback to Vercel:
  - Known-good Vercel production URL:
  ````

- [x] **Step 2: Inventory current Vercel production variables**

  Record these names in `docs/server/cloudbase-run.md`; do not write secret values:

  ```text
  MONGODB_URI
  MONGO_DB_NAME
  JWT_SECRET
  ADMIN_BOOTSTRAP_USER
  ADMIN_BOOTSTRAP_PASS
  CRON_SECRET
  OPENAI_API_KEY
  CORS_ALLOW_ORIGINS
  LOG_LEVEL
  PARENT_WEB_BASE_URL
  OAUTH_CANONICAL_BASE_URL
  SESSION_COOKIE_DOMAIN
  ADMIN_SESSION_COOKIE_NAME
  PREVIEW_MANIFEST_BLOB_URL
  BLOB_READ_WRITE_TOKEN
  GOOGLE_OAUTH_CLIENT_ID
  GOOGLE_OAUTH_CLIENT_SECRET
  APPLE_OAUTH_CLIENT_ID
  APPLE_OAUTH_TEAM_ID
  APPLE_OAUTH_KEY_ID
  APPLE_OAUTH_PRIVATE_KEY
  WECHAT_OAUTH_APP_ID
  WECHAT_OAUTH_APP_SECRET
  ALIPAY_OAUTH_APP_ID
  ALIPAY_OAUTH_APP_PRIVATE_KEY
  ALIPAY_OAUTH_PUBLIC_KEY
  ```

  Acceptance: the runbook clearly marks which variables are required for staging, production, cron, OAuth, and Wave A Blob compatibility.

- [x] **Step 3: Add CloudBase secrets to CI docs**

  Append a section to `docs/ci-secrets.md`:

  ```markdown
  ## CloudBase Run migration secrets

  | Secret | Required by | Purpose |
  | --- | --- | --- |
  | `TCB_SECRET_ID` | CloudBase CD | Tencent Cloud API credential id for CloudBase CLI login. |
  | `TCB_SECRET_KEY` | CloudBase CD | Tencent Cloud API credential key for CloudBase CLI login. |
  | `TCB_ENV_ID` | CloudBase CD | CloudBase environment id. |
  | `CLOUDBASE_STAGING_BASE_URL` | CloudBase smoke | Staging CloudBase HTTP Access URL. |
  | `CLOUDBASE_PROD_BASE_URL` | CloudBase smoke | Production canonical URL, normally `https://happyword.cool`. |
  ```

  Acceptance: the existing Vercel secret table is not removed; CloudBase secrets are clearly marked as migration/new path.

- [x] **Step 4: Confirm domain management path**

  Use the logged-in browser only for read-only checks:

  - Confirm where `happyword.cool` DNS is hosted today.
  - Confirm whether Vercel currently controls the nameservers.
  - Confirm whether Tencent Cloud/CloudBase requires ICP access filing before binding `happyword.cool`.
  - Confirm SSL certificate availability for `happyword.cool`.

  Record the result in `docs/server/cloudbase-run.md`.

- [x] **Step 5: Commit M0 documentation**

  Run:

  ```bash
  git add docs/server/cloudbase-run.md docs/ci-secrets.md
  git commit -m "docs: add cloudbase migration runbook"
  ```

  Acceptance: commit contains only the M0 documentation changes.

## M1: Container Runtime Readiness

**Goal:** Make the backend runnable as a CloudBase-compatible container without changing application behavior.

**Files:**

- Create: `server/Dockerfile`
- Create: `server/.dockerignore`
- Test with: `server/tests/test_health.py`

- [x] **Step 1: Add `server/Dockerfile`**

  Use:

  ```dockerfile
  FROM python:3.12-slim

  ENV PYTHONDONTWRITEBYTECODE=1
  ENV PYTHONUNBUFFERED=1
  ENV UV_COMPILE_BYTECODE=1
  ENV UV_LINK_MODE=copy
  ENV UV_INDEX_URL=https://mirrors.cloud.tencent.com/pypi/simple
  ENV PIP_INDEX_URL=https://mirrors.cloud.tencent.com/pypi/simple

  WORKDIR /app

  RUN pip install --no-cache-dir uv

  COPY pyproject.toml uv.lock ./
  RUN uv sync --frozen --no-dev

  COPY app ./app
  COPY api ./api
  COPY scripts ./scripts

  EXPOSE 8080

  CMD ["/app/.venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers"]
  ```

- [x] **Step 2: Add `server/.dockerignore`**

  Use:

  ```text
  .env.local
  .venv
  __pycache__
  .pytest_cache
  .ruff_cache
  .mypy_cache
  artifacts
  tests
  *.pyc
  ```

- [x] **Step 3: Run server tests**

  Run:

  ```bash
  cd server
  uv run pytest -v
  ```

  Expected: full server test suite finishes with `0 errors` and `0 warnings`.

- [x] **Step 4: Build AMD64 image locally**

  Run:

  ```bash
  cd server
  docker buildx build --platform linux/amd64 -t happyword-server:cloudbase .
  ```

  Expected: image builds successfully.

- [x] **Step 5: Run local container**

  Run:

  ```bash
  cd server
  docker run --rm -p 8080:8080 --env-file .env.local happyword-server:cloudbase
  ```

  In another terminal:

  ```bash
  curl -fsS http://127.0.0.1:8080/api/v1/public/health
  curl -fsS -I http://127.0.0.1:8080/admin/login
  curl -fsS -I http://127.0.0.1:8080/privacy
  ```

  Expected: health returns JSON, admin/login and privacy return HTTP 200 or 3xx HTML responses.

  Execution note, 2026-05-17: local smoke used a temporary MongoDB Docker
  container and dummy local environment variables. `GET /api/v1/public/health`
  returned `200` with `{"ok":true,...}`; `GET /admin/login` and `GET /privacy`
  both returned `200`. Existing page routes return `405` for `HEAD`, so GET was
  used for the page reachability checks.

- [x] **Step 6: Commit container runtime**

  Run:

  ```bash
  git add server/Dockerfile server/.dockerignore
  git commit -m "build: add cloudbase run container"
  ```

  Acceptance: commit contains only the Docker runtime files unless a path fix in `server/app/main.py` was strictly required.

## M2: CloudBase Staging

**Goal:** Prove the CloudBase Run service can boot and serve traffic on a CloudBase default domain before touching production DNS.

**Files:**

- Modify: `docs/server/cloudbase-run.md`

- [ ] **Step 1: Confirm CloudBase environment**

  In Tencent Cloud console:

  - CloudBase environment exists.
  - Region is Shanghai.
  - Over-limit pay-as-you-go is enabled for CloudBase Run.
  - CloudBase Run service quota is sufficient for `happyword-server-staging`.

  Record the environment id and service URL in `docs/server/cloudbase-run.md`.

  Execution note, 2026-05-18: environment and Cloud Run console were confirmed,
  but M2 is blocked before service creation because the package pay-as-you-go
  toggle is off and staging secrets are not yet available in the local context.
  Findings are recorded in `docs/server/cloudbase-run.md`.

  Follow-up note, 2026-05-18: attempting to enable pay-as-you-go showed that
  the CloudBase free trial tier cannot enable pay-as-you-go or add resource
  packs. The operator must upgrade to a paid package before this acceptance
  item can pass.

- [ ] **Step 2: Create staging service**

  Create CloudBase Run service:

  ```text
  Service name: happyword-server-staging
  Source path: server/
  Dockerfile: server/Dockerfile
  Port: 8080
  Traffic after deploy: 100% for staging
  Replica mode: low-cost or high-availability, choose low-cost if only used manually
  InitialDelaySeconds: 15
  Logs: stdout,stderr
  ```

  Acceptance: service deploys and shows healthy version status.

- [ ] **Step 3: Configure staging environment variables**

  Set:

  ```text
  MONGODB_URI=use-staging-test-mongo-uri-from-secret-store
  MONGO_DB_NAME=happyword_cloudbase_staging
  JWT_SECRET=use-new-staging-secret-from-secret-store
  ADMIN_BOOTSTRAP_USER=use-staging-admin-user
  ADMIN_BOOTSTRAP_PASS=use-staging-admin-password
  CRON_SECRET=use-staging-cron-secret
  OPENAI_API_KEY=use-staging-openai-api-key-from-secret-store
  CORS_ALLOW_ORIGINS=*
  LOG_LEVEL=info
  PARENT_WEB_BASE_URL=https://staging-domain-recorded-in-docs-server-cloudbase-run-md
  OAUTH_CANONICAL_BASE_URL=https://staging-domain-recorded-in-docs-server-cloudbase-run-md
  SESSION_COOKIE_DOMAIN=
  PREVIEW_MANIFEST_BLOB_URL=use-existing-public-preview-manifest-blob-url
  BLOB_READ_WRITE_TOKEN=use-existing-vercel-blob-token-only-if-upload-path-must-be-tested
  ```

  Acceptance: values are set in CloudBase console; secrets are not committed to repo.

- [ ] **Step 4: Smoke staging**

  Run:

  ```bash
  export CLOUDBASE_STAGING_BASE_URL=https://staging-domain-recorded-in-docs-server-cloudbase-run-md
  curl -fsS "$CLOUDBASE_STAGING_BASE_URL/api/v1/public/health"
  curl -fsS -I "$CLOUDBASE_STAGING_BASE_URL/api/v1/public/packs/latest.json"
  curl -fsS -I "$CLOUDBASE_STAGING_BASE_URL/privacy"
  curl -fsS -I "$CLOUDBASE_STAGING_BASE_URL/admin/login"
  ```

  Expected: no `404`, no platform error page, no startup exception in CloudBase logs.

- [ ] **Step 5: Verify staging outbound dependency connectivity**

  Verify these server-to-server paths from the CloudBase Run staging service,
  not only from the developer machine:

  - CloudBase Run -> MongoDB Atlas
  - CloudBase Run -> OpenAI API

  Atlas acceptance:

  - CloudBase Run startup logs show Beanie/Mongo initialization completes.
  - `GET /api/v1/public/health` returns `200`.
  - At least one staging smoke case performs a real MongoDB read/write through
    the CloudBase service.

  OpenAI acceptance:

  - `OPENAI_API_KEY` is configured in CloudBase staging from the secret store.
  - Trigger one low-cost, controlled LLM route through the CloudBase staging
    service, such as the admin scan/import flow, using a staging admin account
    and a small fixture image.
  - Expected result is either a successful parsed response or an application
    level LLM validation error from OpenAI. DNS/connectivity errors, timeout
    before reaching OpenAI, TLS failures, or CloudBase egress failures block M2.

  Record the exact command, endpoint, HTTP status, and redacted result summary
  in `docs/server/cloudbase-run.md`. Do not commit API keys, bearer tokens, or
  full provider responses.

- [ ] **Step 6: Run staging E2E smoke**

  Run:

  ```bash
  cd server
  E2E_BASE_URL="$CLOUDBASE_STAGING_BASE_URL" \
  E2E_MONGODB_URI=use-staging-test-mongo-uri-from-secret-store \
  E2E_MONGO_DB_NAME=happyword_cloudbase_staging \
  E2E_ADMIN_USER=use-staging-admin-user \
  E2E_ADMIN_PASS=use-staging-admin-password \
  E2E_CRON_SECRET=use-staging-cron-secret \
  uv run pytest -v -m smoke
  ```

  Expected: smoke tests pass or failures are triaged as pre-existing staging data/setup issues and documented before continuing.

- [ ] **Step 7: Commit staging runbook updates**

  Run:

  ```bash
  git add docs/server/cloudbase-run.md
  git commit -m "docs: record cloudbase staging setup"
  ```

## M3: Cron Replacement

**Goal:** Replace Vercel Cron with a CloudBase-native or GitHub-controlled caller while preserving the existing FastAPI cron endpoint.

**Files:**

- Create: `cloudbase/functions/cron-extract-pending/index.js`
- Create: `cloudbase/functions/cron-extract-pending/package.json`
- Create or modify: `cloudbaserc.json`
- Modify: `docs/server/cloudbase-run.md`
- Modify: `docs/ci-secrets.md`

- [x] **Step 1: Add timer function package**

  Create `cloudbase/functions/cron-extract-pending/package.json`:

  ```json
  {
    "name": "happyword-cron-extract-pending",
    "version": "0.0.1",
    "private": true,
    "type": "commonjs"
  }
  ```

- [x] **Step 2: Add timer function implementation**

  Create `cloudbase/functions/cron-extract-pending/index.js`. The deployed
  implementation follows this contract and additionally includes short retries
  for transient CloudBase Run gateway `502` / `503` / `504` responses:

  ```js
  exports.main = async () => {
    const url = process.env.CRON_TARGET_URL;
    const secret = process.env.CRON_SECRET;

    if (!url || !secret) {
      throw new Error("CRON_TARGET_URL and CRON_SECRET must be configured");
    }

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secret}`,
      },
    });
    const body = await response.text();

    if (!response.ok) {
      throw new Error(`Cron target returned ${response.status}: ${body}`);
    }

    return {
      status: response.status,
      body,
    };
  };
  ```

- [x] **Step 3: Add trigger config**

  Create or extend `cloudbaserc.json`:

  ```json
  {
    "version": "2.0",
    "envId": "cloudbase-env-id-recorded-in-docs-server-cloudbase-run-md",
    "functions": [
      {
        "name": "cron-extract-pending",
        "triggers": [
          {
            "name": "extractPendingEveryMinute",
            "type": "timer",
            "config": "0 * * * * * *"
          }
        ]
      }
    ]
  }
  ```

  Before committing, use the real CloudBase environment id if this repo convention accepts environment-specific config. If environment id should remain local-only, do not commit `cloudbaserc.json`; instead record the exact trigger JSON in `docs/server/cloudbase-run.md`.

- [x] **Step 4: Deploy function**

  Run:

  ```bash
  tcb fn deploy cron-extract-pending --dir cloudbase/functions/cron-extract-pending -e "$TCB_ENV_ID" --force
  ```

  Executed with a temporary `/tmp` CloudBase config carrying function env vars.
  `cloudbaserc.json` was intentionally not committed. Deploy succeeded on
  2026-05-18 with runtime `Nodejs20.19`.

- [x] **Step 5: Create timer trigger**

  Run:

  ```bash
  tcb fn trigger create cron-extract-pending -e "$TCB_ENV_ID" --trigger-name extractPendingEveryMinute --cron "0 * * * * * *"
  ```

  Trigger creation returned `Trigger created`; function detail shows
  `extractPendingEveryMinute` bound to `$LATEST`.

- [x] **Step 6: Configure function env vars**

  Configured through the temporary deployment config:

  ```text
  CRON_TARGET_URL=https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com/api/v1/admin/cron/extract-pending
  CRON_SECRET=use-same-value-as-staging-cloudbase-run-cron-secret
  ```

- [x] **Step 7: Validate cron manually**

  Trigger function manually and check:

  - Cloud Function invocation succeeds.
  - CloudBase Run logs show a request to `/api/v1/admin/cron/extract-pending`.
  - Response body is one of:

  ```json
  {"claimed":0,"succeeded":0,"failed":0}
  ```

  or:

  ```json
  {"claimed":1,"succeeded":1,"failed":0}
  ```

  Manual invocation result on 2026-05-18:

  ```json
  {"status":200,"body":"{\"claimed\":0,\"succeeded\":0,\"failed\":0}","attempt":1}
  ```

- [ ] **Step 8: Commit cron replacement**

  Run:

  ```bash
  git add cloudbase/functions/cron-extract-pending docs/server/cloudbase-run.md docs/ci-secrets.md
  git commit -m "ops: add cloudbase cron extractor"
  ```

  If `cloudbaserc.json` was intentionally committed, include it in the same commit.

## M4: Production Domain Readiness

**Goal:** Prepare `happyword.com.cn` for CloudBase production validation without cutting `happyword.cool` traffic.

**Files:**

- Modify: `docs/server/cloudbase-run.md`

- [x] **Step 1: Confirm domain path**

  Record in `docs/server/cloudbase-run.md`:

  ```text
  First CloudBase production validation domain: happyword.com.cn
  DNS host for happyword.com.cn:
  Current happyword.cool production target:
  Planned CloudBase CNAME for happyword.com.cn:
  Final happyword.cool CloudBase CNAME target:
  DNS rollback target for happyword.cool:
  ```

  Execution note, 2026-05-18:

  ```text
  First CloudBase production validation domain: happyword.com.cn
  DNS host for happyword.com.cn: DNSPod
  Current happyword.cool production target: Vercel DNS, apex A 216.150.1.193 / 216.150.1.129
  Planned CloudBase CNAME for happyword.com.cn: blocked until CloudBase custom-domain binding creates one
  Final happyword.cool CloudBase CNAME target: same CloudBase custom-domain target after happyword.com.cn is green
  DNS rollback target for happyword.cool: keep Vercel DNS/ns1.vercel-dns.com and ns2.vercel-dns.com until final cutover
  ```

- [ ] **Step 2: Confirm filing and certificate**

  In Tencent Cloud console:

  - Check ICP filing/access filing requirement for `happyword.com.cn`.
  - Confirm SSL certificate can be issued or uploaded.
  - Confirm CloudBase custom domain page accepts `happyword.com.cn`.

  If filing blocks the bind, pause production cutover and continue only with staging.

  Execution note, 2026-05-18: CloudBase CLI and official docs require a valid
  Tencent Cloud SSL certificate ID and completed ICP filing before adding an
  HTTP Access custom domain. Tencent Cloud SSL certificate `XjNs7qFU` for
  `happyword.com.cn` was issued on 2026-05-18 and covers both
  `happyword.com.cn` and `www.happyword.com.cn`, so certificate availability is
  no longer a blocker. ICP remains blocked: the ICP console shows
  `happyword.com.cn` as `未备案`, and the filing form requires an eligible cloud
  resource. The current CloudBase Standard monthly package is not listed as an
  eligible filing resource. Tencent Cloud ICP docs require CloudBase resources
  to have more than 6 months remaining during filing and fixed public IP
  enabled; the current CloudBase package period ends on 2026-06-18 and fixed
  public IP is disabled.

- [x] **Step 3: Create CloudBase production service**

  Create service:

  ```text
  Service name: happyword-server
  Source path: server/
  Dockerfile: server/Dockerfile
  Port: 8080
  Traffic after deploy: 0% for first production version
  Replica mode: high-availability
  Min replicas: 1
  Max replicas: 3
  InitialDelaySeconds: 15
  Logs: stdout,stderr
  ```

  Acceptance: production service has a healthy version with no public production traffic.

  Execution note, 2026-05-18: production service `happyword-server` was created
  from `server/` with Dockerfile `server/Dockerfile`, port `8080`, min replicas
  `1`, max replicas `3`, `InitialDelaySeconds=15`, and logs
  `stdout,stderr`. Version `001` failed because it was submitted before
  required env vars were configured. After env configuration, version
  `happyword-server-002` deployed successfully with 100% traffic on the
  CloudBase Run default domain only:
  `https://happyword-server-255236-5-1429584068.sh.run.tcloudbase.com`.
  `happyword.com.cn` and `happyword.cool` were not pointed at CloudBase.

- [x] **Step 4: Configure production env vars**

  Set the same production values currently used by Vercel for:

  ```text
  MONGODB_URI
  MONGO_DB_NAME
  JWT_SECRET
  ADMIN_BOOTSTRAP_USER
  ADMIN_BOOTSTRAP_PASS
  CRON_SECRET
  OPENAI_API_KEY
  CORS_ALLOW_ORIGINS
  LOG_LEVEL
  PARENT_WEB_BASE_URL=https://happyword.com.cn
  OAUTH_CANONICAL_BASE_URL=https://happyword.com.cn
  SESSION_COOKIE_DOMAIN=.happyword.com.cn
  ADMIN_SESSION_COOKIE_NAME=wm_admin_session
  PREVIEW_MANIFEST_BLOB_URL=use-current-public-blob-url
  BLOB_READ_WRITE_TOKEN=use-current-vercel-blob-token-during-wave-a
  ```

  Acceptance: production CloudBase service boots with the production DB name in logs and no missing-settings exception.

  Execution note, 2026-05-18: production env vars were configured from local
  secret source values without committing secret values. CloudBase production
  validation currently uses `PARENT_WEB_BASE_URL=https://happyword.com.cn`,
  `OAUTH_CANONICAL_BASE_URL=https://happyword.com.cn`, and
  `SESSION_COOKIE_DOMAIN=.happyword.com.cn`. Read-only default-domain smoke
  passed after redeploy:

  ```text
  GET /api/v1/public/health -> 200
  GET /api/v1/public/packs/latest.json -> 200
  GET /privacy -> 200
  GET /admin/login -> 200
  ```

- [ ] **Step 5: Bind `happyword.com.cn` custom domain**

  In CloudBase HTTP Access Service:

  - Add `happyword.com.cn`.
  - Attach SSL certificate.
  - Route path `/` to CloudBase Run service `happyword-server`.
  - Copy the CloudBase CNAME target.

  Acceptance: CloudBase produces a CNAME target for `happyword.com.cn`; current
  public `happyword.cool` DNS still points to Vercel.

  Status, 2026-05-18: blocked. CloudBase HTTP Access has no custom domains or
  routes. Binding with certificate `XjNs7qFU` was attempted and failed with
  `CreateHTTPServiceRoute: 域名未备案`. Binding cannot proceed until
  `happyword.com.cn` has a valid ICP filing/access filing state.

- [ ] **Step 6: Commit domain readiness notes**

  Run:

  ```bash
  git add docs/server/cloudbase-run.md
  git commit -m "docs: record cloudbase production domain readiness"
  ```

## M5: Production Cutover

**Goal:** Move `https://happyword.com.cn` to CloudBase first, prove production behavior, then move `https://happyword.cool` after the `.com.cn` route is fully green.

**Files:**

- Modify: `docs/server/cloudbase-run.md`

- [ ] **Step 1: Pre-cutover Vercel baseline for `happyword.cool`**

  Run:

  ```bash
  curl -fsS https://happyword.cool/api/v1/public/health
  curl -fsS -I https://happyword.cool/api/v1/public/packs/latest.json
  curl -fsS -I https://happyword.cool/privacy
  curl -fsS -I https://happyword.cool/admin/login
  ```

  Record response status, timestamp, and current DNS target in `docs/server/cloudbase-run.md`.

- [ ] **Step 2: Pre-cutover CloudBase baseline**

  Use CloudBase default or test-access URL:

  ```bash
  export CLOUDBASE_PROD_TEST_URL=https://production-cloudbase-domain-recorded-in-runbook
  curl -fsS "$CLOUDBASE_PROD_TEST_URL/api/v1/public/health"
  curl -fsS -I "$CLOUDBASE_PROD_TEST_URL/api/v1/public/packs/latest.json"
  curl -fsS -I "$CLOUDBASE_PROD_TEST_URL/privacy"
  curl -fsS -I "$CLOUDBASE_PROD_TEST_URL/admin/login"
  ```

  Acceptance: all checks are healthy before DNS change.

- [ ] **Step 3: Lower `happyword.com.cn` DNS TTL**

  If DNSPod allows TTL changes, lower `happyword.com.cn` TTL to 60 seconds at least 30 minutes before cutover. Do not change `happyword.cool` TTL yet.

- [ ] **Step 4: Change `happyword.com.cn` DNS to CloudBase CNAME**

  Update DNS record:

  ```text
  Host: @ or happyword.com.cn, according to DNSPod record rules
  Type: CNAME or provider-supported alias/flattened CNAME
  Value: CloudBase CNAME target for `happyword.com.cn` recorded in `docs/server/cloudbase-run.md`
  ```

  Do not change `happyword.cool` DNS in this step.

- [ ] **Step 5: Poll production health**

  Run until result comes from CloudBase:

  ```bash
  for i in 1 2 3 4 5 6 7 8 9 10; do
    date
    dig +short happyword.com.cn
    curl -fsS https://happyword.com.cn/api/v1/public/health
    sleep 30
  done
  ```

  Acceptance: health remains 200 during propagation.

- [ ] **Step 6: Run production smoke**

  Run:

  ```bash
  cd server
  E2E_BASE_URL=https://happyword.com.cn \
  E2E_MONGODB_URI=use-production-observation-uri-or-staging-uri \
  E2E_MONGO_DB_NAME=use-production-db-name \
  uv run pytest -v -m smoke
  ```

  Acceptance: smoke tests pass. If any smoke case mutates production data unexpectedly, stop and document the skipped case before continuing.

- [ ] **Step 7: Manual browser validation on `happyword.com.cn`**

  Validate:

  - `/family/login` loads.
  - `/admin/login` loads.
  - Admin login succeeds.
  - `/api/v1/public/packs/latest.json` downloads.
  - `/api/v1/public/preview-urls.json` returns JSON or a known Wave A compatibility response.
  - One parent web page flow works.

- [ ] **Step 8: Roll back if cutover fails**

  If health, admin login, pack download, or OAuth callback fails:

  - Repoint DNS to the previous Vercel target.
  - Set CloudBase Run production traffic to 0 for the failing version.
  - Keep MongoDB and Vercel Blob unchanged.

- [ ] **Step 9: Final `happyword.cool` CNAME cutover**

  After `happyword.com.cn` has passed all smoke checks, bind/route
  `happyword.cool` to the same CloudBase production service and update
  `happyword.cool` DNS/CNAME from Vercel to CloudBase.

  Acceptance: `https://happyword.cool/api/v1/public/health` is served by
  CloudBase, and the same production smoke subset passes on `happyword.cool`.
  - Record failure timestamp, CloudBase version, and log snippet in `docs/server/cloudbase-run.md`.

- [ ] **Step 9: Commit production cutover notes**

  Run:

  ```bash
  git add docs/server/cloudbase-run.md
  git commit -m "docs: record cloudbase production cutover"
  ```

## M6: CloudBase CI/CD

**Goal:** Make `main` production deployment and smoke checks CloudBase-aware while Vercel remains rollback-only.

**Files:**

- Create: `.github/workflows/server-cloudbase-cd.yml`
- Modify: `.github/workflows/server-cd.yml`
- Modify: `.github/workflows/server-ci.yml`
- Modify: `docs/ci-secrets.md`

- [ ] **Step 1: Add CloudBase CD workflow**

  Create `.github/workflows/server-cloudbase-cd.yml`:

  ```yaml
  name: server-cloudbase-cd

  on:
    push:
      branches: [main]
      paths:
        - "server/**"
        - ".github/workflows/server-cloudbase-cd.yml"

  concurrency:
    group: server-cloudbase-cd
    cancel-in-progress: false

  jobs:
    deploy:
      runs-on: ubuntu-latest
      defaults:
        run:
          working-directory: server
      steps:
        - name: Checkout
          uses: actions/checkout@v5

        - name: Set up Python
          uses: actions/setup-python@v6
          with:
            python-version: "3.12"

        - name: Install uv
          uses: astral-sh/setup-uv@v8.1.0

        - name: Sync dependencies
          run: uv sync --dev

        - name: Run pytest
          run: uv run pytest -v

        - name: Set up Node
          uses: actions/setup-node@v5
          with:
            node-version: "24"

        - name: Install CloudBase CLI
          run: npm install -g @cloudbase/cli

        - name: Login to CloudBase
          run: tcb login --apiKeyId "$TCB_SECRET_ID" --apiKey "$TCB_SECRET_KEY"
          env:
            TCB_SECRET_ID: ${{ secrets.TCB_SECRET_ID }}
            TCB_SECRET_KEY: ${{ secrets.TCB_SECRET_KEY }}

        - name: Deploy CloudBase Run
          run: tcb cloudrun deploy -e "$TCB_ENV_ID" -s happyword-server --port 8080 --source . --force
          env:
            TCB_ENV_ID: ${{ secrets.TCB_ENV_ID }}

        - name: Health check
          run: curl -fsS "$CLOUDBASE_PROD_BASE_URL/api/v1/public/health"
          env:
            CLOUDBASE_PROD_BASE_URL: ${{ secrets.CLOUDBASE_PROD_BASE_URL }}

        - name: Smoke test
          run: uv run pytest -v -m smoke
          env:
            E2E_BASE_URL: ${{ secrets.CLOUDBASE_PROD_BASE_URL }}
            E2E_MONGODB_URI: ${{ secrets.E2E_MONGODB_URI }}
            E2E_MONGO_DB_NAME: ${{ secrets.E2E_STAGING_DB_NAME }}
  ```

- [ ] **Step 2: Add GitHub secrets**

  Configure repository secrets:

  ```text
  TCB_SECRET_ID
  TCB_SECRET_KEY
  TCB_ENV_ID
  CLOUDBASE_PROD_BASE_URL=https://happyword.cool
  CLOUDBASE_STAGING_BASE_URL=https://staging-domain-recorded-in-docs-server-cloudbase-run-md
  ```

- [ ] **Step 3: Run workflow manually through a test branch**

  Push a docs-only or no-op server change branch and confirm:

  - Offline pytest runs.
  - CloudBase CLI login works.
  - Deploy command reaches the right service.
  - Health check hits CloudBase production URL.
  - Smoke result is visible in GitHub Actions.

- [ ] **Step 4: Disable old Vercel production wait**

  Modify `.github/workflows/server-cd.yml` so it no longer waits for Vercel production deployment after CloudBase CD is stable. Either:

  - delete `server-cd.yml` in the Vercel retirement phase; or
  - change it to a documentation-only disabled workflow with a clear note that CloudBase CD replaced it.

- [ ] **Step 5: Keep PR CI unchanged for now**

  Preserve `.github/workflows/server-ci.yml` Vercel preview E2E until M8. Do not remove the preview job in M6.

- [ ] **Step 6: Commit CI/CD migration**

  Run:

  ```bash
  git add .github/workflows/server-cloudbase-cd.yml .github/workflows/server-cd.yml docs/ci-secrets.md
  git commit -m "ci: deploy server to cloudbase run"
  ```

## M7: Storage Migration

**Goal:** Stop creating new Vercel Blob assets while preserving existing asset URLs.

**Files:**

- Modify: `server/app/services/blob_service.py`
- Add: `server/app/services/storage_provider.py`
- Add tests: `server/tests/test_storage_provider.py`
- Modify tests if needed: `server/tests/test_admin_assets.py`, `server/tests/test_lessons_import_anonymous.py`
- Modify: `docs/ci-secrets.md`
- Modify: `docs/server/cloudbase-run.md`

- [ ] **Step 1: Choose storage provider**

  Pick one:

  - CloudBase Storage if public URL generation and server-side upload are straightforward.
  - Tencent COS Python SDK if Python backend support and CDN/domain controls are clearer.

  Record the selected provider and required env vars in `docs/server/cloudbase-run.md`.

- [ ] **Step 2: Add failing storage-provider tests**

  Add `server/tests/test_storage_provider.py` with tests for:

  ```python
  def test_storage_provider_defaults_to_vercel_blob(monkeypatch):
      monkeypatch.delenv("ASSET_STORAGE_PROVIDER", raising=False)
      from app.services.storage_provider import current_provider

      assert current_provider() == "vercel_blob"


  def test_storage_provider_accepts_cos(monkeypatch):
      monkeypatch.setenv("ASSET_STORAGE_PROVIDER", "tencent_cos")
      from app.services.storage_provider import current_provider

      assert current_provider() == "tencent_cos"
  ```

  Run:

  ```bash
  cd server
  uv run pytest -v tests/test_storage_provider.py
  ```

  Expected before implementation: import or assertion failure.

- [ ] **Step 3: Implement provider selection**

  Add `server/app/services/storage_provider.py`:

  ```python
  import os
  from typing import Literal

  StorageProvider = Literal["vercel_blob", "tencent_cos", "cloudbase_storage"]


  def current_provider() -> StorageProvider:
      raw = os.environ.get("ASSET_STORAGE_PROVIDER", "vercel_blob").strip().lower()
      if raw in {"vercel_blob", "tencent_cos", "cloudbase_storage"}:
          return raw  # type: ignore[return-value]
      raise RuntimeError(f"Unsupported ASSET_STORAGE_PROVIDER={raw!r}")
  ```

- [ ] **Step 4: Refactor `blob_service.py` without changing callers**

  Keep public functions stable:

  ```python
  async def upload_word_illustration(word_id: str, image_bytes: bytes, mime: str) -> str
  async def upload_word_audio(word_id: str, audio_bytes: bytes, mime: str) -> str
  async def upload_lesson_image(image_bytes: bytes, mime: str) -> str
  async def delete_object(url: str) -> None
  ```

  Internally route to the selected provider. Preserve Vercel Blob behavior as the default.

- [ ] **Step 5: Add provider-specific implementation**

  For Tencent COS, create:

  ```text
  COS_SECRET_ID
  COS_SECRET_KEY
  COS_REGION
  COS_BUCKET
  COS_PUBLIC_BASE_URL
  ```

  Acceptance: upload returns a stable public URL and existing callers do not change.

- [ ] **Step 6: Run storage tests**

  Run:

  ```bash
  cd server
  uv run pytest -v tests/test_storage_provider.py tests/test_admin_assets.py tests/test_lessons_import_anonymous.py
  uv run pytest -v
  ```

  Expected: `0 errors`, `0 warnings`.

- [ ] **Step 7: Deploy storage switch to staging**

  Set staging:

  ```text
  ASSET_STORAGE_PROVIDER=tencent_cos
  ```

  Upload one test illustration/audio from admin UI and verify the returned URL renders publicly.

- [ ] **Step 8: Deploy storage switch to production**

  Set production `ASSET_STORAGE_PROVIDER` after staging passes. Do not rewrite existing Vercel Blob URLs.

- [ ] **Step 9: Commit storage migration**

  Run:

  ```bash
  git add server/app/services/storage_provider.py server/app/services/blob_service.py server/tests/test_storage_provider.py docs/ci-secrets.md docs/server/cloudbase-run.md
  git commit -m "feat: support cloud storage provider for assets"
  ```

## M8: Preview and QA Replacement

**Goal:** Remove dependency on Vercel Preview while keeping a useful QA target for server and mobile DevMenu validation.

**Files:**

- Modify: `.github/workflows/server-ci.yml`
- Modify or replace: `.github/workflows/preview-manifest.yml`
- Modify or replace: `server/scripts/update_preview_manifest.mjs`
- Modify: `server/app/services/preview_manifest_service.py`
- Modify tests: `server/tests/test_preview_manifest_endpoint.py`
- Modify docs: `docs/superpowers/runbooks/dev-menu-runbook.md`, `docs/ci-secrets.md`, `docs/server/cloudbase-run.md`

- [ ] **Step 1: Choose preview model**

  Use this first:

  ```text
  Model: shared CloudBase staging service
  Manifest source: static/Mongo-maintained row for the staging URL
  PR-specific previews: disabled until service quota and routing strategy are clear
  ```

  Record this in `docs/server/cloudbase-run.md`.

- [ ] **Step 2: Preserve endpoint contract**

  Keep client-facing endpoint:

  ```text
  GET /api/v1/public/preview-urls.json
  ```

  The response must continue to include preview rows compatible with current DevMenu expectations.

- [ ] **Step 3: Add failing endpoint test for CloudBase manifest**

  Extend `server/tests/test_preview_manifest_endpoint.py` so it verifies a CloudBase staging row can be served without Vercel Blob.

  Expected before implementation: test fails because service still requires `PREVIEW_MANIFEST_BLOB_URL`.

- [ ] **Step 4: Implement non-Vercel manifest source**

  Recommended minimal implementation:

  - Add env var `PREVIEW_MANIFEST_INLINE_JSON`.
  - If set, serve it after JSON validation.
  - If unset, fall back to `PREVIEW_MANIFEST_BLOB_URL` for compatibility.

  Acceptance: endpoint works on CloudBase without Vercel Blob.

- [ ] **Step 5: Update DevMenu runbook**

  Modify `docs/superpowers/runbooks/dev-menu-runbook.md`:

  - Explain that production `happyword.cool` still serves the manifest.
  - Mark Vercel Preview as retired after M8.
  - Add CloudBase staging target instructions.

- [ ] **Step 6: Simplify PR server CI**

  In `.github/workflows/server-ci.yml`:

  - Keep offline pytest.
  - Replace Vercel preview deploy/E2E with CloudBase staging E2E only if staging can safely be reused by PRs.
  - Keep Cursor autofix only if its prompt reflects CloudBase staging, not Vercel preview.

- [ ] **Step 7: Retire Vercel manifest workflow**

  After CloudBase manifest passes:

  - Disable `.github/workflows/preview-manifest.yml`, or replace it with a CloudBase manifest validation workflow.
  - Stop calling `server/scripts/update_preview_manifest.mjs` against Vercel deployments.

- [ ] **Step 8: Run validation**

  Run:

  ```bash
  cd server
  uv run pytest -v tests/test_preview_manifest_endpoint.py
  uv run pytest -v
  curl -fsS https://happyword.cool/api/v1/public/preview-urls.json
  ```

  Expected: endpoint returns valid JSON without Vercel Blob.

- [ ] **Step 9: Commit preview replacement**

  Run:

  ```bash
  git add server/app/services/preview_manifest_service.py server/tests/test_preview_manifest_endpoint.py .github/workflows/server-ci.yml .github/workflows/preview-manifest.yml docs/superpowers/runbooks/dev-menu-runbook.md docs/ci-secrets.md docs/server/cloudbase-run.md
  git commit -m "ci: replace vercel preview qa path"
  ```

## M9: Vercel Retirement

**Goal:** Remove Vercel as an active production dependency only after CloudBase has been stable.

**Files:**

- Delete or archive: `server/vercel.json`
- Keep or annotate: `server/api/index.py`
- Delete or archive: `.github/workflows/vercel-prune.yml`
- Modify: `.github/workflows/server-ci.yml`
- Modify: `.github/workflows/server-cd.yml`
- Modify: `.github/workflows/preview-manifest.yml`
- Modify: `docs/ci-secrets.md`
- Modify: `docs/server/cloudbase-run.md`
- Modify templates if needed: `server/app/templates/public/privacy.html`

- [ ] **Step 1: Confirm stability gate**

  Confirm all are true:

  - CloudBase production has served `happyword.cool` for at least 7 days.
  - CloudBase monitoring shows no sustained 5xx spike.
  - Cron extraction has processed real drafts.
  - New asset uploads no longer depend on Vercel Blob.
  - Preview manifest no longer depends on Vercel deployments or Vercel Blob.
  - GitHub Actions production deployment uses CloudBase CD.
  - Vercel remains only as an inactive rollback/archive path.

- [ ] **Step 2: Remove Vercel cron config**

  Delete `server/vercel.json` only if Vercel deploy is fully disabled. If keeping Vercel as emergency fallback, leave the file and add a comment to the runbook that Vercel cron must stay disabled in the dashboard.

- [ ] **Step 3: Decide fate of `server/api/index.py`**

  If Vercel fallback is no longer needed, either delete the file or leave it with a comment that it is historical. Prefer deletion if tests and import paths do not reference it.

- [ ] **Step 4: Remove Vercel prune workflow**

  Delete `.github/workflows/vercel-prune.yml`.

- [ ] **Step 5: Clean CI docs**

  In `docs/ci-secrets.md`, move these to a retired section:

  ```text
  VERCEL_TOKEN
  VERCEL_ORG_ID
  VERCEL_PROJECT_ID
  VERCEL_AUTOMATION_BYPASS_SECRET
  BLOB_READ_WRITE_TOKEN
  PREVIEW_MANIFEST_BLOB_URL
  ```

- [ ] **Step 6: Update public privacy text**

  If `server/app/templates/public/privacy.html` still says the service may use Vercel hosting/storage, update it to say Tencent Cloud/CloudBase and the selected storage provider.

- [ ] **Step 7: Run full validation**

  Run:

  ```bash
  cd server
  uv run pytest -v
  E2E_BASE_URL=https://happyword.cool uv run pytest -v -m smoke
  ```

  Expected: `0 errors`, `0 warnings`, smoke pass.

- [ ] **Step 8: Commit Vercel retirement**

  Run:

  ```bash
  git add -A server .github/workflows docs
  git commit -m "chore: retire vercel backend deployment"
  ```

## Long-Running Status Template

Copy this into `docs/server/cloudbase-run.md` after each work session:

```markdown
## Migration Status - YYYY-MM-DD

- Current milestone:
- Completed today:
- Blocked by:
- Next action:
- Production traffic owner:
- Rollback target:
- Validation run:
- Notes:
```

## Stop Conditions

Pause the migration and ask for a decision if any of these happens:

- Tencent Cloud console refuses `happyword.cool` binding because filing/domain ownership is not ready.
- CloudBase staging cannot reach MongoDB Atlas from production-like networking.
- CloudBase Run cold start makes login or OAuth callbacks unreliable.
- Request body or timeout limits break a real admin upload/import flow.
- CloudBase storage provider cannot produce stable public URLs usable by current clients.
- GitHub Actions cannot deploy to CloudBase without exposing overly broad Tencent Cloud credentials.
- A production cutover smoke failure affects login, admin, public pack download, or OAuth.

## Final Acceptance

The migration is complete when:

- `https://happyword.cool/api/v1/public/health` is served by CloudBase Run.
- `/family/login`, `/admin/login`, `/privacy`, and `/api/v1/public/packs/latest.json` work on CloudBase.
- Cron extraction is invoked by CloudBase timer or a documented non-Vercel schedule.
- New asset uploads no longer depend on Vercel Blob.
- Preview/QA workflow no longer depends on Vercel deployments.
- GitHub Actions production deploy no longer waits for Vercel.
- Vercel is documented as retired or emergency-only.
- `cd server && uv run pytest -v` and `E2E_BASE_URL=https://happyword.cool uv run pytest -v -m smoke` pass.
