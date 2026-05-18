# CloudBase Run Backend Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the `server/` FastAPI backend and HTML admin/parent web shell from Vercel to Tencent CloudBase Run without breaking production traffic, preview QA, cron extraction, OAuth callbacks, or uploaded assets.

**Architecture:** Use a phased migration. Phase 1 containerizes the existing FastAPI app and deploys it to CloudBase Run while keeping MongoDB Atlas and Vercel Blob as compatibility dependencies. Phase 2 cuts production traffic to CloudBase Run. Phase 3 removes Vercel-specific runtime, CI, preview-manifest, cron, and Blob dependencies after the CloudBase route is proven stable.

**Tech Stack:** Python 3.12, FastAPI, Uvicorn, uv, MongoDB/Beanie, CloudBase Run container mode, CloudBase HTTP Access Service, GitHub Actions, CloudBase CLI, CloudBase Cloud Function timer trigger or GitHub scheduled workflow for cron replacement.

---

## Source Snapshot

Checked on 2026-05-17:

- CloudBase Run supports containerized apps in any language/framework, including Python/FastAPI-style web backends; current docs say supported region is Shanghai.
- CloudBase Run deployment options include container image, local code, Git repository, and CLI deployment.
- A CloudBase Run service needs a single listening port; HTTP Access Service routes a domain/path to the Run service.
- A custom production domain on CloudBase HTTP Access requires ICP filing and an SSL certificate; production should not rely on the generated default domain.
- Current CloudBase Run limits that matter here: request timeout 60s, request body 20M, one environment can create 15 services, one environment can run 28 instances by default.
- CloudBase Run version config supports traffic 0% after deploy, traffic 100% after deploy, low-cost min replicas 0, high-availability min replicas >= 1, InitialDelaySeconds, stdout log collection, and environment variables.
- Container image deployment is x86/AMD only. If building from an Apple Silicon Mac, force `linux/amd64` when building externally.

Official docs used:

- CloudBase Run overview: https://docs.cloudbase.net/run/introduction
- Deployment modes: https://docs.cloudbase.net/run/deploy/deploy/introduce
- Git deployment: https://docs.cloudbase.net/run/deploy/deploy/deploying-git
- Image deployment: https://docs.cloudbase.net/run/deploy/deploy/deploying-image
- Version settings: https://docs.cloudbase.net/run/deploy/version-setting
- Service settings: https://docs.cloudbase.net/run/deploy/service-setting
- HTTP access to CloudBase Run: https://docs.cloudbase.net/service/access-cloudrun
- HTTP route matching: https://docs.cloudbase.net/service/routes
- Custom domains: https://docs.cloudbase.net/service/custom-domain
- CloudBase CLI deploy: https://docs.cloudbase.net/cli-v1/cloudrun/deploy
- CloudBase CLI install/login: https://docs.cloudbase.net/en/cli-v1/install
- CloudBase function deploy: https://docs.cloudbase.net/cli-v1/functions/deploy
- Cloud Function timer trigger: https://docs.cloudbase.net/cli-v1/functions/trigger
- CloudBase Run logs/monitoring: https://docs.cloudbase.net/run/maintain/log and https://docs.cloudbase.net/run/maintain/monitoring

## Current Repo State

Runtime:

- `server/app/main.py` defines the real FastAPI app and includes all API, admin, parent, OAuth, public, static, and template routes.
- `server/api/index.py` is Vercel-only. It re-exports `app.main:app` so Vercel's Python preset picks the right ASGI app. CloudBase Run should not use this as the runtime entrypoint.
- `server/pyproject.toml` already includes `uvicorn[standard]`, so a container can start with `uv run uvicorn app.main:app`.
- `server/app/main.py` uses relative runtime paths `app/static` and `app/templates`, so the CloudBase container `WORKDIR` must be the `server/` directory content root.

Vercel-specific platform coupling:

- `server/vercel.json` enables main production deploys and Vercel Cron:

  ```json
  {
    "git": { "deploymentEnabled": { "main": true, "**": false } },
    "crons": [
      {
        "path": "/api/v1/admin/cron/extract-pending",
        "schedule": "* * * * *"
      }
    ]
  }
  ```

- `.github/workflows/server-ci.yml` deploys a Vercel preview for each server PR and uses the preview URL for E2E.
- `.github/workflows/server-cd.yml` waits for a Vercel production deployment before smoke testing.
- `.github/workflows/preview-manifest.yml`, `.github/workflows/vercel-prune.yml`, and `server/scripts/update_preview_manifest.mjs` treat Vercel deployments as the source of truth for preview URLs.
- `server/app/services/blob_service.py` uploads assets to Vercel Blob with `BLOB_READ_WRITE_TOKEN`.
- `server/app/services/preview_manifest_service.py` proxies a public Vercel Blob JSON at `PREVIEW_MANIFEST_BLOB_URL`.
- `server/app/services/oauth_return_origin_service.py` currently recognizes `*.vercel.app` as preview origins.

Critical endpoints to preserve:

- Health: `GET /api/v1/public/health`
- Public pack: `GET /api/v1/public/packs/latest.json`
- Preview manifest: `GET /api/v1/public/preview-urls.json`
- Parent shell: `/family/login`, `/family/*`
- Admin console: `/admin/*`
- Cron extraction: `GET|POST /api/v1/admin/cron/extract-pending` with `Authorization: Bearer $CRON_SECRET`
- OAuth callbacks: `/v1/oauth/{google,apple,wechat,alipay}/callback`
- Static assets: `/static/*`

## Recommendation

Use a two-wave migration:

1. **Wave A: runtime-only move.** Deploy the FastAPI app to CloudBase Run with the same MongoDB Atlas database and the same Vercel Blob asset store. Bind a staging CloudBase default domain first. Then bind and fully validate CloudBase production on `happyword.com.cn`. Only after `happyword.com.cn` health, admin pages, OAuth/cookie behavior, cron, LLM import, and client smoke checks pass, change `happyword.cool` from Vercel DNS/CNAME to the CloudBase target. This proves the CloudBase container, network, env vars, cookies, OAuth, and request limits before removing any storage or CI assumptions.
2. **Wave B: Vercel retirement.** Replace Vercel Blob with CloudBase Storage or Tencent COS, replace Vercel Cron with a CloudBase Cloud Function timer or GitHub scheduled workflow, redesign the preview manifest around CloudBase Run revisions or a maintained QA environment list, and delete Vercel-only workflows after green validation.

Do not attempt a one-shot full migration. The codebase has enough Vercel-specific preview and Blob machinery that moving runtime, storage, preview QA, cron, and production DNS in one release would make rollback noisy.

## Target CloudBase Layout

CloudBase environment:

- Production environment: one CloudBase environment in Shanghai.
- Service name: `happyword-server`.
- Runtime mode: CloudBase Run container mode.
- Port: `8080`.
- Access: public network enabled for production, internal network optional.
- HTTP Access route: first production validation domain `happyword.com.cn` path `/` routes to `happyword-server`; final cutover later moves `happyword.cool` to the same CloudBase target.
- Initial traffic when deploying a new version: `0%` for manual smoke, then promote to `100%`.
- Production replicas: high-availability mode with min `1`, max `3` for first cut. Move to min `0` only after login/OAuth latency is acceptable.
- Suggested first spec: `0.5 CPU / 1 GiB` or `1 CPU / 2 GiB`. Start with `1 CPU / 2 GiB` if LLM vision import and Beanie startup are slow.
- InitialDelaySeconds: `15` to allow Mongo/Beanie initialization before health checks.
- Logs: `stdout,stderr`.

Required production env vars:

```text
MONGODB_URI=use-same-production-mongo-uri-currently-used-by-vercel
MONGO_DB_NAME=use-current-production-db-name
JWT_SECRET=use-same-signing-secret-as-vercel-during-cutover
ADMIN_BOOTSTRAP_USER=use-current-admin-bootstrap-user
ADMIN_BOOTSTRAP_PASS=use-current-admin-bootstrap-password
CRON_SECRET=use-same-value-used-by-scheduled-cron-caller
LLM_PROVIDER=qwen-or-doubao-after-cloudbase-smoke
OPENAI_API_KEY=use-production-key-if-openai-is-enabled
OPENAI_MODEL_TEXT=gpt-4o-mini
OPENAI_MODEL_VISION=gpt-4o
DASHSCOPE_API_KEY=use-if-LLM_PROVIDER-qwen
QWEN_MODEL_VISION=qwen3.6-plus
ARK_API_KEY=use-if-LLM_PROVIDER-doubao
DOUBAO_MODEL_VISION=doubao-seed-2-0-pro-260215
CORS_ALLOW_ORIGINS=*
LOG_LEVEL=info
PARENT_WEB_BASE_URL=https://happyword.cool
OAUTH_CANONICAL_BASE_URL=https://happyword.cool
SESSION_COOKIE_DOMAIN=.happyword.cool
ADMIN_SESSION_COOKIE_NAME=wm_admin_session
PREVIEW_MANIFEST_BLOB_URL=keep-existing-vercel-blob-url-during-wave-a
BLOB_READ_WRITE_TOKEN=keep-existing-vercel-blob-token-during-wave-a-only
GOOGLE_OAUTH_CLIENT_ID=set-if-google-oauth-is-enabled
GOOGLE_OAUTH_CLIENT_SECRET=set-if-google-oauth-is-enabled
APPLE_OAUTH_CLIENT_ID=set-if-apple-oauth-is-enabled
APPLE_OAUTH_TEAM_ID=set-if-apple-oauth-is-enabled
APPLE_OAUTH_KEY_ID=set-if-apple-oauth-is-enabled
APPLE_OAUTH_PRIVATE_KEY=set-if-apple-oauth-is-enabled
WECHAT_OAUTH_APP_ID=set-if-wechat-oauth-is-enabled
WECHAT_OAUTH_APP_SECRET=set-if-wechat-oauth-is-enabled
ALIPAY_OAUTH_APP_ID=set-if-alipay-oauth-is-enabled
ALIPAY_OAUTH_APP_PRIVATE_KEY=set-if-alipay-oauth-is-enabled
ALIPAY_OAUTH_PUBLIC_KEY=set-if-alipay-oauth-is-enabled
```

OAuth provider consoles:

- Keep the existing production callback paths, only confirm the host:
  - `https://happyword.cool/v1/oauth/google/callback`
  - `https://happyword.cool/v1/oauth/apple/callback`
  - `https://happyword.cool/v1/oauth/wechat/callback`
  - `https://happyword.cool/v1/oauth/alipay/callback`
- For staging, use the CloudBase generated domain only if provider consoles allow it and the route is stable enough. Production OAuth/cookie validation happens on `happyword.com.cn` before `happyword.cool` DNS changes.

## Task 1: Containerize `server/` for CloudBase Run

**Files:**

- Create: `server/Dockerfile`
- Create: `server/.dockerignore`
- Modify: `server/app/main.py` only if the local container cannot resolve `app/static` or `app/templates` from `WORKDIR /app`.

- [ ] **Step 1: Add Dockerfile**

  Create `server/Dockerfile`:

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

  CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers"]
  ```

- [ ] **Step 2: Add Docker ignore**

  Create `server/.dockerignore`:

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

- [ ] **Step 3: Build locally**

  On Apple Silicon, force AMD64 to match CloudBase image constraints:

  ```bash
  cd server
  docker buildx build --platform linux/amd64 -t happyword-server:cloudbase .
  ```

  Expected: image builds successfully and `uv sync --frozen --no-dev` installs only runtime dependencies.

- [ ] **Step 4: Run locally against local Mongo**

  ```bash
  cd server
  docker run --rm -p 8080:8080 \
    --env-file .env.local \
    happyword-server:cloudbase
  ```

  Expected:

  ```bash
  curl -fsS http://127.0.0.1:8080/api/v1/public/health
  ```

  returns JSON like `{"ok":true,"ts":...}`.

- [ ] **Step 5: Validate existing tests**

  ```bash
  cd server
  uv run pytest -v
  ```

  Expected: `0 errors`, `0 warnings`.

## Task 2: Create CloudBase Run Staging Service

**Files:**

- No code changes required.
- Update docs after actual values are known: `docs/ci-secrets.md` and a new `docs/server/cloudbase-run.md`.

- [x] **Step 1: Read-only console check**

  In Tencent Cloud console, confirm:

  - CloudBase environment exists in Shanghai.
  - CloudBase Run is enabled.
  - Over-limit pay-as-you-go is enabled for CloudBase Run.
  - `happyword.cool` ICP filing state is valid for Tencent Cloud access filing.
  - SSL certificate for `happyword.cool` is available or uploadable.

- [x] **Step 2: Deploy by console or CLI**

  Preferred first deploy is console/Git repository deploy so the UI-created service settings are visible. Use:

  - Source path: `server/`
  - Dockerfile: `Dockerfile`
  - Service name: `happyword-server-staging`
  - Port: `8080`
  - Traffic after deploy: `0%`
  - InitialDelaySeconds: `15`
  - Logs: `stdout,stderr`

  If using CLI:

  ```bash
  cd server
  tcb cloudrun deploy -e "$TCB_ENV_ID" -s happyword-server --port 8080 --source . --force
  ```

  Expected: CloudBase Run creates a new version and shows normal status after health checks.

- [x] **Step 3: Configure staging env vars**

  Use a staging Mongo DB name first:

  ```text
  MONGO_DB_NAME=happyword_cloudbase_staging
  OAUTH_CANONICAL_BASE_URL=https://cloudbase-default-domain-recorded-in-runbook
  SESSION_COOKIE_DOMAIN=
  PREVIEW_MANIFEST_BLOB_URL=use-existing-public-blob-url
  ```

  Expected: staging can boot without touching the production DB.

- [ ] **Step 4: Smoke staging default domain**

  ```bash
  export CBR_URL=https://cloudbase-default-domain-recorded-in-runbook
  curl -fsS "$CBR_URL/api/v1/public/health"
  curl -fsS "$CBR_URL/api/v1/public/packs/latest.json" -I
  curl -fsS "$CBR_URL/privacy" -I
  curl -fsS "$CBR_URL/admin/login" -I
  ```

  Expected:

  - Health is 200 JSON.
  - Public pack is 200 or 304 with `ETag`.
  - Privacy/admin login pages return HTML.
  - CloudBase Run logs show app startup, resolved Mongo DB name, and no uncaught exception.

  2026-05-18 execution note:

  - `happyword-server-staging` version `002` is normal on the CloudBase default
    domain.
  - `GET /api/v1/public/health`, `GET /api/v1/public/packs/latest.json`,
    `GET /api/v1/public/preview-urls.json`, `GET /privacy`, and
    `GET /admin/login` passed.
  - Blob write + staging Mongo insert passed via
    `POST /api/v1/family/cloudbase-smoke/lessons/import`.
  - OpenAI server-to-server smoke failed from CloudBase with
    `httpx.ConnectTimeout` / `openai.APITimeoutError`.
  - Server now supports `LLM_PROVIDER=openai|qwen|doubao`; keep Step 4 open
    until the selected CloudBase provider is smoke-tested from CloudBase.
  - `LLM_PROVIDER=qwen` was configured on CloudBase staging and the service was
    redeployed on 2026-05-18 14:11. `/api/v1/admin/llm/scan-words` with
    `assets/lessons/1.jpg` returned `200` from `qwen3.6-plus` with 15 extracted
    clothing words.
  - Full async lesson import smoke passed after a second cron tick:
    `POST /api/v1/family/cloudbase-qwen-smoke/lessons/import` created an
    `extracting` draft, `POST /api/v1/admin/cron/extract-pending` returned
    `{"claimed":1,"succeeded":1,"failed":0}`, and the draft became `pending`
    with `model=qwen3.6-plus`.

## Task 3: Replace Vercel Cron

**Files:**

- Create: `cloudbase/functions/cron-extract-pending/index.js` or a GitHub scheduled workflow.
- Modify: `docs/ci-secrets.md`

Recommended first implementation: CloudBase Cloud Function timer trigger that POSTs the CloudBase Run cron endpoint. This keeps the scheduled call inside Tencent Cloud and mirrors the existing Vercel Cron contract.

- [ ] **Step 1: Create tiny timer function**

  Function behavior:

  ```js
  exports.main = async () => {
    const url = process.env.CRON_TARGET_URL;
    const secret = process.env.CRON_SECRET;
    if (!url || !secret) throw new Error("CRON_TARGET_URL/CRON_SECRET missing");

    const res = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${secret}` },
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`cron target ${res.status}: ${text}`);
    return { status: res.status, body: text };
  };
  ```

- [ ] **Step 2: Add timer trigger**

  Use CloudBase function trigger config:

  ```json
  {
    "version": "2.0",
    "envId": "cloudbase-env-id-recorded-in-runbook",
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

  Note: CloudBase function cron has a seconds field. `0 * * * * * *` means once per minute at second 0.

- [ ] **Step 3: Configure function env vars**

  ```text
  CRON_TARGET_URL=https://cloudbase-domain-recorded-in-runbook/api/v1/admin/cron/extract-pending
  CRON_SECRET=use-same-secret-as-cloudbase-run-cron-secret
  ```

- [ ] **Step 4: Deploy function and trigger**

  Use the CloudBase CLI command family:

  ```bash
  tcb fn deploy cron-extract-pending --dir cloudbase/functions/cron-extract-pending -e "$TCB_ENV_ID" --force --yes
  tcb fn trigger create cron-extract-pending -e "$TCB_ENV_ID" --yes
  ```

  Expected: function deploy succeeds, and the trigger list shows `extractPendingEveryMinute`.

- [ ] **Step 5: Validate cron call**

  Manually invoke once and inspect CloudBase Run logs.

  Expected target response:

  ```json
  {"claimed":0,"succeeded":0,"failed":0}
  ```

  or one claimed draft summary when test data exists.

Fallback implementation: GitHub Actions schedule with `curl -X POST`. Use it only if CloudBase function timers are blocked by account policy.

2026-05-18 execution note:

- Added `cloudbase/functions/cron-extract-pending/`.
- Deployed CloudBase function `cron-extract-pending` with runtime `Nodejs20.19`,
  `128 MB` memory, and `60s` timeout.
- Configured function env vars in CloudBase:
  `CRON_TARGET_URL` points at the CloudBase staging
  `/api/v1/admin/cron/extract-pending` endpoint, and `CRON_SECRET` matches the
  staging Run service.
- Created timer trigger `extractPendingEveryMinute` with cron
  `0 * * * * * *`.
- First manual invocation saw a transient CloudBase Run gateway `503`, so the
  function implementation was hardened with short retries for `502` / `503` /
  `504`.
- Manual invocation after redeploy returned `status=200`, body
  `{"claimed":0,"succeeded":0,"failed":0}`, `attempt=1`.

## Task 4: Production Domain Cutover

**Files:**

- No runtime code changes expected.
- Update docs: `docs/server/cloudbase-run.md`, `docs/ci-secrets.md`, and any release status doc if present.

- [ ] **Step 1: Pre-cutover checks**

  Verify:

  ```bash
  curl -fsS "$CLOUDBASE_BASE_URL/api/v1/public/health"
  curl -fsS "$CLOUDBASE_BASE_URL/api/v1/public/packs/latest.json" -I
  ```

  Verify manually in browser:

  - `/family/login`
  - `/admin/login`
  - admin login using bootstrap user
  - a public legal page: `/privacy`

- [ ] **Step 2: Bind first production custom domain in CloudBase HTTP Access Service**

  In CloudBase HTTP Access Service:

  - Add domain `happyword.com.cn`.
  - Attach SSL certificate.
  - Create route: domain `happyword.com.cn`, path `/`, resource type `CloudBase Run`, service `happyword-server`.
  - Use no CDN first unless latency measurements need it.
  - Copy CNAME value.

- [ ] **Step 3: DNS cutover for `happyword.com.cn`**

  Lower DNS TTL before cutover if DNS provider allows it. Update CNAME for `happyword.com.cn` to CloudBase's provided target. Keep `happyword.cool` on Vercel until all `happyword.com.cn` smoke checks pass.

- [ ] **Step 4: Production smoke**

  ```bash
  curl -fsS https://happyword.com.cn/api/v1/public/health
  curl -fsS https://happyword.com.cn/api/v1/public/packs/latest.json -I
  curl -fsS https://happyword.com.cn/privacy -I
  curl -fsS https://happyword.com.cn/admin/login -I
  ```

  Then run:

  ```bash
  cd server
  E2E_BASE_URL=https://happyword.com.cn \
  E2E_MONGODB_URI=use-production-observation-uri-or-staging-uri \
  E2E_MONGO_DB_NAME=use-production-db-name \
  uv run pytest -v -m smoke
  ```

  Expected: smoke subset passes. If using production DB, only run smoke cases that do not mutate destructive data.

- [ ] **Step 5: Final `happyword.cool` CNAME cutover**

  Only after `happyword.com.cn` is fully green, bind/route `happyword.cool` to
  the same CloudBase production service and update `happyword.cool` DNS/CNAME
  from Vercel to CloudBase. Keep the Vercel project and env vars intact until
  post-cutover smoke on `happyword.cool` passes.

- [ ] **Step 5: Rollback rule**

  If health, admin login, pack download, or OAuth callback fails after DNS cutover:

  - Repoint `happyword.cool` CNAME back to Vercel.
  - Set CloudBase Run traffic to 0 for the bad version.
  - Keep Mongo and Blob unchanged.
  - Diagnose CloudBase logs before attempting the next cutover.

## Task 5: Rewire CI/CD

**Files:**

- Modify: `.github/workflows/server-ci.yml`
- Modify: `.github/workflows/server-cd.yml`
- Modify or delete after CloudBase preview strategy is live: `.github/workflows/preview-manifest.yml`
- Delete after Vercel preview deployments are retired: `.github/workflows/vercel-prune.yml`
- Modify: `docs/ci-secrets.md`

- [ ] **Step 1: Keep offline pytest unchanged**

  Preserve `server_pytest` in `.github/workflows/server-ci.yml`.

- [ ] **Step 2: Add CloudBase deployment workflow**

  Production CD on `main` should:

  ```yaml
  name: server-cloudbase-cd

  on:
    push:
      branches: [main]
      paths:
        - "server/**"
        - ".github/workflows/server-cloudbase-cd.yml"

  jobs:
    deploy:
      runs-on: ubuntu-latest
      defaults:
        run:
          working-directory: server
      steps:
        - uses: actions/checkout@v5
        - uses: actions/setup-node@v5
          with:
            node-version: "24"
        - uses: actions/setup-python@v6
          with:
            python-version: "3.12"
        - uses: astral-sh/setup-uv@v8.1.0
        - run: uv sync --dev
        - run: uv run pytest -v
        - run: npm i -g @cloudbase/cli
        - run: tcb login --apiKeyId "$TCB_SECRET_ID" --apiKey "$TCB_SECRET_KEY"
          env:
            TCB_SECRET_ID: ${{ secrets.TCB_SECRET_ID }}
            TCB_SECRET_KEY: ${{ secrets.TCB_SECRET_KEY }}
        - run: tcb cloudrun deploy -e "$TCB_ENV_ID" -s happyword-server --port 8080 --source . --force
          env:
            TCB_ENV_ID: ${{ secrets.TCB_ENV_ID }}
        - run: curl -fsS "$E2E_BASE_URL/api/v1/public/health"
          env:
            E2E_BASE_URL: ${{ secrets.CLOUDBASE_PROD_BASE_URL }}
        - run: uv run pytest -v -m smoke
          env:
            E2E_BASE_URL: ${{ secrets.CLOUDBASE_PROD_BASE_URL }}
            E2E_MONGODB_URI: ${{ secrets.E2E_MONGODB_URI }}
            E2E_MONGO_DB_NAME: ${{ secrets.E2E_STAGING_DB_NAME }}
  ```

  Use this as the first working shape, then tighten permissions and add Slack alert parity with the current Vercel CD workflow.

- [ ] **Step 3: Decide preview strategy**

  Recommended first preview strategy:

  - Keep PR CI offline tests green.
  - Do not create one CloudBase service per PR at first, because the default environment service limit is 15.
  - Use one shared staging service `happyword-server-staging` for manual/branch validation.
  - Keep Vercel preview E2E temporarily until CloudBase staging E2E is reliable, then retire Vercel preview.

  Later preview strategy:

  - Create CloudBase revisions with traffic 0 for selected PRs.
  - Maintain a preview manifest from GitHub PR metadata plus CloudBase revision/domain data.
  - Remove Vercel deployment source from `server/scripts/update_preview_manifest.mjs`.

- [ ] **Step 4: Update secrets doc**

  Add:

  ```text
  TCB_SECRET_ID
  TCB_SECRET_KEY
  TCB_ENV_ID
  CLOUDBASE_PROD_BASE_URL
  CLOUDBASE_STAGING_BASE_URL
  ```

  Mark these Vercel secrets as retired only after Wave B:

  ```text
  VERCEL_TOKEN
  VERCEL_ORG_ID
  VERCEL_PROJECT_ID
  VERCEL_AUTOMATION_BYPASS_SECRET
  BLOB_READ_WRITE_TOKEN
  PREVIEW_MANIFEST_BLOB_URL
  ```

## Task 6: Remove Vercel Blob Dependency

**Files:**

- Modify: `server/app/services/blob_service.py`
- Modify: `server/app/services/preview_manifest_service.py`
- Modify: `server/scripts/update_preview_manifest.mjs` or replace it
- Add tests under `server/tests/`
- Modify: `docs/ci-secrets.md`

Wave A keeps Vercel Blob. Wave B replaces it.

- [ ] **Step 1: Introduce storage provider abstraction**

  Keep router calls stable:

  ```python
  async def upload_object(path: str, payload: bytes, mime: str) -> str:
      provider = os.environ.get("ASSET_STORAGE_PROVIDER", "vercel_blob")
      if provider == "vercel_blob":
          return await _upload_vercel_blob(path, payload, mime)
      if provider == "cloudbase_storage":
          return await _upload_cloudbase_storage(path, payload, mime)
      raise RuntimeError(f"Unsupported ASSET_STORAGE_PROVIDER={provider}")
  ```

- [ ] **Step 2: Backfill tests**

  Add tests that monkeypatch each provider and assert:

  - no token means configured check is false;
  - uploaded illustration/audio/lesson paths stay deterministic;
  - provider returns a public URL;
  - delete tolerates upstream failures.

- [ ] **Step 3: Migrate existing asset URLs**

  Do not rewrite existing Mongo rows in the first CloudBase runtime release. Existing Vercel Blob URLs can remain readable. New uploads move after provider switch.

- [ ] **Step 4: Replace preview manifest storage**

  Options:

  - CloudBase Storage public JSON file plus FastAPI proxy.
  - Store manifest JSON in Mongo and serve directly.
  - Keep Vercel Blob only for preview manifest until CloudBase preview strategy exists.

  Recommended: Mongo-backed manifest after Vercel previews are retired, because the manifest becomes operational metadata rather than static asset storage.

## Task 7: Remove Vercel Runtime Config

**Files:**

- Keep during Wave A: `server/vercel.json`, `server/api/index.py`
- Delete only after CloudBase production has run stable for at least 7 days:
  - `server/vercel.json`
  - Vercel-only workflow files
  - Vercel-only docs sections

- [ ] **Step 1: Keep Vercel rollback alive**

  For the first production cutover, do not delete Vercel project, env vars, or workflows. Vercel is the rollback target.

- [ ] **Step 2: Declare CloudBase stable**

  Stability criteria:

  - 7 days production traffic on CloudBase.
  - No CloudBase Run abnormal instance spikes.
  - Cron extraction processed real pending drafts.
  - Admin upload/import path works.
  - Parent OAuth login works.
  - Mobile clients can download `latest.json`.
  - Server smoke passes from GitHub Actions against `https://happyword.cool`.

- [ ] **Step 3: Retire Vercel**

  Delete or disable:

  - Vercel Git integration and production auto deploy.
  - Vercel Cron.
  - Vercel preview E2E deploy path.
  - Vercel deployment prune workflow.
  - Vercel Blob tokens after storage migration.

## Validation Matrix

Before DNS cutover:

- `cd server && uv run pytest -v`
- `docker buildx build --platform linux/amd64 -t happyword-server:cloudbase server`
- Local container health check.
- CloudBase default domain health check.
- CloudBase logs show no startup exceptions.

During DNS cutover:

- `GET /api/v1/public/health`
- `GET /api/v1/public/packs/latest.json`
- `GET /privacy`
- `GET /admin/login`
- Admin login in browser.
- Parent login in browser.
- OAuth start/callback if provider is configured.

After cutover:

- `cd server && E2E_BASE_URL=https://happyword.cool uv run pytest -v -m smoke`
- Manual cron trigger returns 200.
- One real lesson import reaches `pending` or controlled `extract_failed`.
- Upload one admin illustration or audio asset and verify public URL renders.
- Check CloudBase monitoring: calls, latency, HTTP errors, CPU, memory, instances, abnormal instances.

## Open Decisions

These are the only decisions that should be confirmed before implementation:

1. **Scope of "migrate from Vercel":** runtime-only first, or runtime plus storage in the same project. Recommendation: runtime-only first.
2. **Production domain readiness:** whether `happyword.cool` has ICP filing and Tencent Cloud access filing ready. If not, CloudBase can only be staging until filing is done.
3. **Preview replacement target:** one shared CloudBase staging service first, or per-PR CloudBase revisions. Recommendation: shared staging first.
4. **Storage replacement target:** CloudBase Storage or Tencent COS direct. Recommendation: CloudBase Storage first if it provides the public URL and CDN behavior needed by clients; COS direct if CloudBase Storage SDK/API is awkward from FastAPI.

## Rollback Plan

CloudBase deploy rollback:

- In CloudBase Run version list, shift 100% traffic back to the previous known-good version.
- If the whole CloudBase route is broken, set CloudBase traffic to 0 and repoint DNS CNAME to Vercel.

Data rollback:

- Do not change Mongo production DB schema during Wave A.
- Do not migrate existing asset URLs during Wave A.
- Reuse the same `JWT_SECRET` during cutover so existing sessions remain valid.

CI rollback:

- Keep Vercel workflows until CloudBase CD is stable.
- If CloudBase CD fails repeatedly, disable the new CloudBase workflow and keep Vercel production deploy on `main`.

## Console Browser Use Policy

When executing this plan, use the logged-in Tencent Cloud browser only for:

- reading CloudBase environment ID, region, service list, domain binding state, and current service settings;
- creating/updating CloudBase Run service versions after an explicit execution request;
- binding custom domain only after the user confirms DNS and ICP readiness;
- checking logs and monitoring after deploy.

Do not delete environments, services, versions, domains, certificates, or Vercel resources from the console without a separate explicit confirmation.
