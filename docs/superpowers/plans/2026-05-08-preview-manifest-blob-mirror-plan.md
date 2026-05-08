# Preview Manifest Blob Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Revision 2026-05-08:** Document **credential-free** access for `GET /api/v1/preview-urls.json` (module docstrings on `public_packs.py` + `preview_manifest_service.py`). Client uses **`PREVIEW_MANIFEST_JSON_URL`** — fixed production origin, **no** `x-vercel-protection-bypass` on manifest GET (see env-switcher design §10).

**Goal:** Publish `docs/preview-urls.json` to Vercel Blob and expose it through a public FastAPI endpoint.

**Architecture:** `server/scripts/update_preview_manifest.mjs` remains the manifest builder and optionally uploads the same JSON payload to a deterministic public Blob path. The backend exposes **`GET /api/v1/preview-urls.json`** (**unauthenticated** — no JWT / cookies / API keys), which proxies a configured `PREVIEW_MANIFEST_BLOB_URL` with short cache headers and clear upstream error handling.

**Tech Stack:** FastAPI, httpx, pytest, Node 24 native `fetch`, Vercel Blob HTTP API, GitHub Actions.

---

### Task 1: Public Manifest Proxy

**Files:**
- Create: `server/app/services/preview_manifest_service.py`
- Modify: `server/app/routers/public_packs.py`
- Test: `server/tests/test_preview_manifest_endpoint.py`

- [ ] **Step 1: Write failing pytest coverage**

Cover three endpoint states: missing `PREVIEW_MANIFEST_BLOB_URL` returns `503`; a Blob `200` returns raw JSON plus `ETag` and short cache headers; a Blob non-2xx returns `502`.

- [ ] **Step 2: Run focused tests to verify red**

Run: `cd server && uv run pytest tests/test_preview_manifest_endpoint.py -q`

Expected: collection fails or tests fail because the endpoint/service does not exist yet.

- [ ] **Step 3: Implement service and router**

Add a service that fetches the configured Blob URL, forwards `If-None-Match`, validates JSON for `200`, and maps upstream errors to `502`. Add `GET /api/v1/preview-urls.json` to the existing **public** router — **no `Depends` auth**; record in module docstrings (`public_packs.py`, `preview_manifest_service.py`) that this path stays credential-free so HarmonyOS can refresh the manifest without a deployment-protection bypass token on this GET.

- [ ] **Step 4: Run focused tests to verify green**

Run: `cd server && uv run pytest tests/test_preview_manifest_endpoint.py -q`

Expected: all new tests pass with zero warnings.

### Task 2: Blob Upload Hook

**Files:**
- Modify: `server/scripts/update_preview_manifest.mjs`
- Modify: `.github/workflows/server-ci.yml`
- Modify: `.github/workflows/preview-manifest.yml`

- [ ] **Step 1: Add optional upload support**

After writing `docs/preview-urls.json`, if `BLOB_READ_WRITE_TOKEN` is present, upload the same payload to `PREVIEW_MANIFEST_BLOB_PATH` (default `preview/preview-urls.json`) using deterministic path, JSON content type, overwrite enabled, and `cacheControlMaxAge` 60 seconds.

- [ ] **Step 2: Wire Actions env**

Pass `BLOB_READ_WRITE_TOKEN` from repository secrets into both manifest rebuild workflows. The script skips upload locally or in forks when the token is absent.

- [ ] **Step 3: Verify syntax**

Run: `node --check server/scripts/update_preview_manifest.mjs`

Expected: syntax check exits 0.

### Task 3: Docs

**Files:**
- Modify: `server/scripts/README.md`
- Modify: `docs/superpowers/runbooks/dev-menu-runbook.md`

- [ ] **Step 1: Document the two-layer publication path**

Record that GitHub keeps the audit copy, Vercel Blob is the runtime mirror, and `/api/v1/preview-urls.json` is the client-facing endpoint — **credential-free** at the FastAPI layer.

- [ ] **Step 2: Record required Vercel env**

Document `BLOB_READ_WRITE_TOKEN`, `PREVIEW_MANIFEST_BLOB_URL`, and optional `PREVIEW_MANIFEST_BLOB_PATH`.

### Task 4: Client Manifest Source

**Files:**
- Modify: `entry/src/main/ets/services/PreviewManifestService.ets`
- Modify: `entry/src/main/ets/services/RemoteWordPackConfig.ets` (manifest URL constants)

- [ ] **Step 1: Pin manifest fetch to production origin**

Use **`PREVIEW_MANIFEST_JSON_URL`** from `RemoteWordPackConfig.ets` (today `https://happyword.cool/api/v1/preview-urls.json`). Do **not** derive the URL from `effectiveServerBaseUrl()`, `STAGING_BASE_URL` alone, or `BackendHeaders` / bypass — DevMenu must load the PR list even when the device is pointed at a Preview deployment. Rows inside the JSON still carry per-PR `*.vercel.app` URLs for actual API traffic after the user picks a card.

### Task 5: Verification

- [ ] **Step 1: Focused server tests**

Run: `cd server && uv run pytest tests/test_preview_manifest_endpoint.py -q`

- [ ] **Step 2: Full server suite**

Run: `cd server && uv run pytest`

- [ ] **Step 3: JS syntax check**

Run: `node --check server/scripts/update_preview_manifest.mjs`
