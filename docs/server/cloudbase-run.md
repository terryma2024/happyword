# CloudBase Run Operations Runbook

## Current State

- Runtime owner: CloudBase Run
- Current production and rollback domain: happyword.cool
- First CloudBase production validation domain: happyword.com.cn
- Production service name: happyword-server
- Staging service name: happyword-server-staging
- MongoDB provider during Wave A: MongoDB Atlas
- MongoDB provider after Wave C: CloudBase FlexDB first, TencentDB fallback
- Asset storage provider during Wave A: Vercel Blob
- Asset storage provider during Wave B: Tencent COS for new uploads; CloudBase Storage remains an alternate only if server-side public URL behavior proves simpler

## CloudBase Environment

- Environment name: happyword
- Environment tier: Standard, continuous monthly subscription
- Environment ID: happyword-d5g66zmq8ef2430b8
- Region: ap-shanghai
- HTTP Access Service: enabled
- Production Cloud Run default domain:
  https://happyword-server-255236-5-1429584068.sh.run.tcloudbase.com
- HTTP Access default domain:
  happyword-d5g66zmq8ef2430b8-1429584068.ap-shanghai.app.tcloudbase.com
- Staging default domain:
  https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com
- Custom domains: none
- Routes: none

## Domain and DNS Management

### Domain Strategy

- Current production and rollback domain: `happyword.cool`
- First CloudBase production validation domain: `happyword.com.cn`
- Additional Tencent-registered reserve domain: `happyword.cloud`
- Production-domain sequence: bind and fully validate CloudBase production on
  `happyword.com.cn` first. Only after health, admin pages, OAuth/cookie
  behavior, cron, LLM import, and client smoke checks pass on
  `happyword.com.cn`, change `happyword.cool` from Vercel DNS/CNAME to the
  CloudBase target.
- Cutover rule: do not change `happyword.cool` DNS while `happyword.com.cn`
  validation is incomplete. Keep `happyword.cool` on Vercel as the rollback
  domain until the final CNAME cutover.

### Tencent Cloud Domain Console Findings

Snapshot date: 2026-05-17.

| Domain | Service status | DNS status | Owner | Registrar | Registered at | Expires at | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `happyword.com.cn` | 正常 | DNSPod | 马天一 | 腾讯云 | 2026-05-17 18:07:10 | 2027-05-17 18:07:10 | New Tencent candidate production domain. Apex DNS has no answer yet. |
| `happyword.cloud` | 正常 | DNSPod | 马天一 | 帝思普 | 2026-05-17 18:07:12 | 2027-05-17 18:07:12 | Reserve or secondary domain. |
| `happyword.cool` | Existing production | Vercel DNS | Not checked in Tencent console | Vercel | Not checked | Not checked | Current production and rollback domain. |

Tencent Cloud real-name template:

- Owner template: 马天一
- Status: 已实名审核
- Progress: 100%
- Submitted at: 2026-05-17 17:36:27

### DNS Lookup Snapshot

Snapshot date: 2026-05-17.

| Domain | Query | Result |
| --- | --- | --- |
| `happyword.cool` | `NS` | `ns1.vercel-dns.com`, `ns2.vercel-dns.com` |
| `happyword.cool` | apex A | `216.150.1.193`, `216.150.1.129` |
| `happyword.com.cn` | `NS` | `cob.dnspod.net`, `user.dnspod.net` |
| `happyword.com.cn` | apex A/CNAME | no answer yet |

### CloudBase Console Findings

Snapshot date: 2026-05-17.

- Environment name: `happyword`
- Environment tier: `体验版`
- Environment ID: `happyword-d5g66zmq8ef2430b8`
- Region: `ap-shanghai`
- HTTP Access Service: enabled
- Default HTTP Access domain:
  `happyword-d5g66zmq8ef2430b8-1429584068.ap-shanghai.app.tcloudbase.com`
- Custom domain table: empty
- Route table: empty
- Cloud functions: none
- Web security domains currently include the CloudBase default domains and
  Tencent console defaults.

Snapshot date: 2026-05-18.

- CloudBase CLI version checked through `npx --package @cloudbase/cli tcb`:
  `3.3.3`.
- CLI device authorization completed from the logged-in Tencent Cloud console.
- Cloud Run service `happyword-server-staging` exists as a container service.
  Version `002` is normal and serves the staging traffic.
- Cloud Run deploy options visible in console: Git repository, container image,
  public Git repository, and local code upload.
- Cloud Run fixed public IP: disabled.
- Image repository: personal image repository selected.
- Package: CloudBase Standard, continuous monthly subscription, purchased on
  2026-05-18. Current package period ends on 2026-06-18.
- Package resource points consumed: 0.07 / 330,000.
- Auto-renewal: enabled. A Google Calendar reminder named
  `停止 CloudBase 连续包月提醒` was created for 2026-06-15 09:00
  Asia/Shanghai, three days before the first renewal date.
- Pay-as-you-go toggle: on; enabled on 2026-05-18 after upgrading to Standard.
- Cloud Run current usage: 0 CPU seconds, 0 GBs memory, 0 Byte outbound traffic.
- Earlier attempt to enable pay-as-you-go on the free trial tier was blocked by
  Tencent CloudBase. Upgrading to Standard removed the blocker.
- Production Cloud Run service `happyword-server` exists as a container service.
  Version `happyword-server-002` is online with 100% traffic on the Cloud Run
  default domain. The first deploy attempt, version `001`, failed because it was
  submitted before required environment variables were configured; version
  `002` was redeployed after configuration and started successfully.

M2 staging is now unblocked for CloudBase Run service creation. Do not create
`happyword-server-staging` with dummy or production values.

Staging service:

- Service name: `happyword-server-staging`
- Default domain:
  `https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com`
- Runtime port: `8080`
- Deploy method: CloudBase CLI local code upload, archive rooted at `server/`
- Active version: `happyword-server-staging-009`, redeployed/configured
  2026-05-21 after staging COS env validation
- Staging Mongo database override: `MONGO_DB_NAME=happyword_cloudbase_staging`
- Logs: enabled after initial OpenAI smoke returned `500`
- Current staging LLM provider: `LLM_PROVIDER=qwen`,
  `QWEN_MODEL_VISION=qwen3.6-plus`

Production service:

- Service name: `happyword-server`
- Default domain:
  `https://happyword-server-255236-5-1429584068.sh.run.tcloudbase.com`
- Runtime port: `8080`
- Deploy method: CloudBase CLI local code upload, archive rooted at `server/`
- Active version: `happyword-server-008`, updated 2026-05-22 after clearing
  `SESSION_COOKIE_DOMAIN` for CloudBase default-domain admin login validation
- Traffic: 100% on the Cloud Run default domain only. `happyword.com.cn` and
  `happyword.cool` DNS were not changed.
- Production Mongo database: `MONGO_DB_NAME=happyword`
- Current production LLM provider: `LLM_PROVIDER=qwen`,
  `QWEN_MODEL_VISION=qwen3.6-plus`
- Production canonical URLs staged for first validation domain:
  `PARENT_WEB_BASE_URL=https://happyword.com.cn`,
  `OAUTH_CANONICAL_BASE_URL=https://happyword.com.cn`, and an empty
  `SESSION_COOKIE_DOMAIN` while validating on the CloudBase default domain.

Required staging secrets:

- `MONGODB_URI` - present in local `~/.env.tcb` on 2026-05-18
- `MONGO_DB_NAME` - present in local `~/.env.tcb` on 2026-05-18
- `JWT_SECRET` - present in local `~/.env.tcb` on 2026-05-18
- `ADMIN_BOOTSTRAP_USER` - present in local `~/.env.tcb` on 2026-05-18
- `ADMIN_BOOTSTRAP_PASS` - present in local `~/.env.tcb` on 2026-05-18
- `CRON_SECRET` - present in local `~/.env.tcb` on 2026-05-18
- `LLM_PROVIDER` - recommended for CloudBase; use `qwen`, `doubao`, or `kimi`
  after provider smoke passes
- `OPENAI_API_KEY` - present in local `~/.env.tcb` on 2026-05-18; useful for
  non-mainland deployments or local comparison
- `DASHSCOPE_API_KEY` - required when `LLM_PROVIDER=qwen`
- `ARK_API_KEY` - required when `LLM_PROVIDER=doubao`
- `MOONSHOT_API_KEY` - required when `LLM_PROVIDER=kimi`; `KIMI_API_KEY` is
  accepted as a local compatibility alias
- `PREVIEW_MANIFEST_BLOB_URL` - present in local `~/.env.tcb` on 2026-05-18;
  required only if staging must validate `/api/v1/public/preview-urls.json`
- `BLOB_READ_WRITE_TOKEN` - present in local `~/.env.tcb` on 2026-05-18;
  required only if upload paths must be tested during staging

Required operator decisions:

- OpenAI connectivity from CloudBase Shanghai is currently blocked by
  `httpx.ConnectTimeout` / `openai.APITimeoutError`. The server can now switch
  lesson image parsing through `LLM_PROVIDER`; validate `qwen`, `doubao`, and
  `kimi` from CloudBase before production cutover.

## Replacement Strategy

### MongoDB Atlas Replacement

Target: CloudBase FlexDB shared document database first; keep TencentDB for
MongoDB as the scale-up/fallback option.

Current M7A status, 2026-05-23:

- The built-in CloudBase document database instance is
  `tnt-jw1cesl68` in environment `happyword-d5g66zmq8ef2430b8`.
- Console observation: `连接管理` creates a MongoDB connector to an external
  TencentDB instance; it did not expose a copyable MongoDB URI for the built-in
  shared FlexDB instance during the console spike.
- Official docs describe CloudBase document database as MongoDB-based and
  compatible with MongoDB protocol, but the validated automation surface today
  is CloudBase/Tencent Cloud API, not a Python `motor` URI.
- Live API spike created `m7a_flexdb_probe`, inserted/query/updated a document
  through `RunCommands`, created a unique `word_1` index through `UpdateTable`,
  confirmed duplicate insert failed with `E11000 duplicate key`, then deleted
  the probe table with `DeleteTable`.
- Cost stance: shared FlexDB is acceptable while user volume is low. Revisit an
  isolated FlexDB instance or TencentDB when production traffic or contention
  makes it necessary.

Rationale:

- The current FastAPI backend uses Motor + Beanie across the app, so a direct
  URI-compatible target is still the lowest-risk cutover shape.
- FlexDB is much cheaper to start than TencentDB. If a standard URI can be
  obtained or officially confirmed for CloudBase Run, it becomes the preferred
  target with minimal application change.
- If no driver URI exists, FlexDB is still feasible but becomes an adapter
  project: replace Beanie/Motor persistence with a repository layer backed by
  CloudBase document database APIs. That is larger than the original env-var
  switch, but may still be cheaper than TencentDB at the current scale.

Decision gates:

1. Ask Tencent Cloud support or use API Explorer/console to confirm whether
   built-in FlexDB exposes a MongoDB driver URI usable from CloudBase Run.
2. If yes, perform the original URI-switch migration against FlexDB.
3. If no, run a focused FlexDB adapter spike before changing production data.
4. Keep TencentDB for MongoDB as the fallback if the adapter spike is too broad,
   too slow, or exposes missing query semantics.

Validated FlexDB API surface:

| Operation | Result |
| --- | --- |
| `ListTables` | Returned an empty built-in FlexDB table list before/after cleanup. |
| `CreateTable` | Created `m7a_flexdb_probe`. |
| `RunCommands` `INSERT` | Inserted `_id=probe-1`, scalar fields, and nested JSON. |
| `RunCommands` `QUERY` | Returned the inserted document with MongoDB extended JSON numeric fields. |
| `RunCommands` `UPDATE` | `$set` update worked and modified one document. |
| `UpdateTable` `CreateIndexes` | Created unique index `word_1`. |
| `RunCommands` `listIndexes` | Returned `_id_`, `_openid_1`, and unique `word_1`. |
| Duplicate insert | Failed with `E11000 duplicate key`, proving unique enforcement. |
| `DeleteTable` | Deleted the temporary probe table; final `ListTables` total was `0`. |

Operator references checked on 2026-05-23:

- CloudBase document database overview states the product is MongoDB-based,
  supports Shanghai, and offers shared vs isolated instance specs:
  <https://cloud.tencent.com/document/product/876/46897>
- `RunCommands` executes document database commands:
  <https://cloud.tencent.com/document/product/876/129012>
- `ListTables` lists document database tables:
  <https://cloud.tencent.com/document/product/876/127965>
- `DescribeTable` returns table index metadata:
  <https://cloud.tencent.com/document/product/876/127966>
- `DeleteTable` deletes document database tables:
  <https://cloud.tencent.com/document/product/876/127967>

Planned sequence:

1. Inventory Atlas collections, document counts, index definitions, TTL indexes,
   unique indexes, and backup status. Done on 2026-05-23.
2. Complete FlexDB URI confirmation. If a URI exists, smoke it with the existing
   Motor/Beanie app before any data migration.
3. If there is no URI path, build a small local FlexDB adapter proof against the
   highest-risk query shapes: unique indexes, upserts, sorted/limited queries,
   regex/search filters, and aggregation-like paths used by pack publishing.
4. Choose one migration path:
   - URI path: export/import Atlas data, create indexes, set
     `MONGODB_URI`/`MONGO_DB_NAME`, restart CloudBase, run smoke.
   - Adapter path: introduce repository boundaries, run dual-backed tests,
     migrate staging data through CloudBase APIs, then switch staging.
5. Keep Atlas and its old URI as rollback for at least one full release cycle or
   7 clean production days, whichever is longer.
6. Revisit TencentDB if shared FlexDB capacity, missing semantics, or rewrite
   scope makes FlexDB worse than the managed MongoDB cost.

Cutover acceptance:

- `GET /api/v1/public/health` returns `200`.
- `GET /api/v1/public/packs/latest.json` returns `200` from FlexDB-backed
  CloudBase production.
- Admin login, parent login, one safe write path, and cron extraction pass.
- Collection counts and critical indexes match the recorded Atlas inventory.

Recorded Atlas inventory, generated 2026-05-23:

```text
Source provider: MongoDB Atlas
Atlas SRV host: atlas-lime-garden.qwoxcy5.mongodb.net
Production database: happyword
MongoDB server version: 8.0.23
Collections: 25
Total documents: 275
TTL indexes: none reported
Unique index collections: 15
Stats mode: skipped collStats because the remote command timed out during the
first live inventory attempt; counts and index metadata were collected.
Atlas backup/restore status: pending manual Atlas console confirmation.
```

Collection counts and index shape:

| Collection | Documents | Indexes | TTL | Unique |
| --- | ---: | ---: | ---: | ---: |
| audit_log | 13 | 4 | 0 | 0 |
| categories | 5 | 1 | 0 | 0 |
| child_profiles | 9 | 5 | 0 | 1 |
| cloud_wishlist_items | 0 | 5 | 0 | 1 |
| device_bindings | 14 | 7 | 0 | 1 |
| email_verifications | 8 | 3 | 0 | 0 |
| families | 6 | 4 | 0 | 3 |
| family_pack_definitions | 5 | 4 | 0 | 1 |
| family_pack_drafts | 5 | 3 | 0 | 1 |
| family_pack_pointers | 5 | 3 | 0 | 1 |
| family_word_packs | 7 | 4 | 0 | 0 |
| lesson_import_drafts | 2 | 3 | 0 | 0 |
| llm_drafts | 0 | 3 | 0 | 0 |
| oauth_handoff_tickets | 0 | 2 | 0 | 1 |
| oauth_identities | 5 | 3 | 0 | 0 |
| oauth_pending_identities | 2 | 4 | 0 | 0 |
| pack_pointer | 1 | 2 | 0 | 1 |
| pair_tokens | 21 | 5 | 0 | 2 |
| parent_inbox_msgs | 0 | 4 | 0 | 1 |
| redemption_requests | 0 | 5 | 0 | 1 |
| synced_word_stats | 108 | 4 | 0 | 0 |
| user_feedback | 0 | 6 | 0 | 1 |
| users | 7 | 4 | 0 | 1 |
| word_packs | 2 | 2 | 0 | 1 |
| words | 50 | 2 | 0 | 0 |

Collections with unique indexes:

```text
child_profiles: profile_id_1
cloud_wishlist_items: item_id_1
device_bindings: binding_id_1
families: family_id_1, owner_user_id_1, primary_email_1
family_pack_definitions: pack_id_1
family_pack_drafts: pack_definition_id_1
family_pack_pointers: pack_definition_id_1
oauth_handoff_tickets: ticket_id_1
pack_pointer: singleton_key_1
pair_tokens: token_1, short_code_1
parent_inbox_msgs: msg_id_1
redemption_requests: request_id_1
user_feedback: feedback_id_1
users: username_1
word_packs: version_1
```

Live inventory command, using secret values from the CloudBase service env and
writing only redacted metadata:

```bash
cd server
MONGODB_URI=... MONGO_DB_NAME=happyword \
  uv run python -m scripts.db_inventory \
  --format json \
  --skip-stats \
  --count-timeout-ms 5000
```

Next M7A-FlexDB steps:

1. Confirm the FlexDB connection model with Tencent Cloud support/API Explorer:
   built-in instance driver URI vs CloudBase API only.
2. Create `server/scripts/flexdb_api_smoke.py` using direct signed Cloud API
   calls, not the CLI, so the CloudBase Run runtime path is testable. Done
   locally on 2026-05-23; CloudBase Run execution is still pending.
3. Generate an Atlas collection/index manifest that can be replayed into
   FlexDB tables via `CreateTable`/`UpdateTable`/`RunCommands`.
4. If URI-compatible, reuse the existing direct connectivity smoke before
   changing CloudBase runtime env:

```bash
cd server
MONGODB_URI=... MONGO_DB_NAME=happyword \
  uv run python -m scripts.db_connectivity_smoke \
  --write-probe
```

Expected: JSON with `ok: true`, redacted `connection_hosts`, server version,
collection list, and `write_probe.deleted_count: 1`.

FlexDB API smoke, after setting runtime API credentials:

```bash
cd server
FLEXDB_ENV_ID=happyword-d5g66zmq8ef2430b8 \
FLEXDB_TAG=tnt-jw1cesl68 \
FLEXDB_API_SECRET_ID=... \
FLEXDB_API_SECRET_KEY=... \
  uv run python -m scripts.flexdb_api_smoke
```

FlexDB adapter spike risks:

- Beanie initialization currently owns the ODM model registry in
  `server/app/main.py`; removing it is not a local edit.
- The codebase uses Beanie/Motor query builders directly in many routes and
  services, including `find`, `find_one`, `update_one`, upserts, sorting,
  regex filters, and direct Motor collection access. A full adapter means
  repository extraction, not just a config change.
- CloudBase API credentials would become runtime database credentials. Define a
  narrow CAM policy before production instead of using broad
  `QcloudTCBFullAccess`.
- CloudBase API rate limits and latency must be measured from CloudBase Run;
  the CLI spike proves semantics, not production throughput.

TencentDB fallback branch:

If FlexDB cannot be used through a driver URI and the adapter spike is too large
for M7A, return to TencentDB for MongoDB. The earlier TencentDB plan remains
valid technically: provision `ap-shanghai`, use a compatible MongoDB version,
enable backup, validate `MONGODB_URI` with `scripts.db_connectivity_smoke`, then
choose DTS or a short write-freeze dump/import for the tiny current dataset.

### Vercel Blob Replacement

Target: Tencent COS for new backend-owned uploads.

Rationale:

- The server already performs server-side uploads and stores absolute HTTPS URLs
  in MongoDB documents.
- COS provides object storage with SDK/REST access, lifecycle management,
  public URL/custom-domain patterns, and CDN integration.
- Existing Vercel Blob URLs can remain readable; the first migration only needs
  to route new uploads to COS.

CloudBase Storage remains an alternate if a later console/API validation proves
that its Python server-side upload and public URL behavior is simpler than COS.

Planned env vars:

| Variable | Required for | Notes |
| --- | --- | --- |
| `ASSET_STORAGE_PROVIDER` | Wave B storage switch | `vercel_blob` by default; set `tencent_cos` after staging validation. |
| `COS_SECRET_ID` | Tencent COS uploads | Secret store only. |
| `COS_SECRET_KEY` | Tencent COS uploads | Secret store only. |
| `COS_REGION` | Tencent COS uploads | Region selected for the bucket. |
| `COS_BUCKET` | Tencent COS uploads | Separate staging and production buckets. |
| `COS_PUBLIC_BASE_URL` | Tencent COS public URLs | Default COS domain, CDN domain, or custom asset domain. |

Planned sequence:

1. Create staging and production COS buckets. Done on 2026-05-21:
   `happyword-assets-staging-1429584068` and
   `happyword-assets-prod-1429584068` in `ap-shanghai`.
2. Decide public URL policy: default COS domain, CDN domain, or custom asset
   domain.
3. Add a storage-provider abstraction while keeping existing
   `blob_service.py` call sites stable. Done on 2026-05-20.
4. Keep `vercel_blob` as the default provider until staging passes.
5. Upload new staging assets to COS and verify image/audio URLs load publicly.
   Use `cd server && uv run python -m scripts.cos_storage_smoke` with
   `ASSET_STORAGE_PROVIDER=tencent_cos` and the staging COS env vars before
   flipping the CloudBase staging service. Done on 2026-05-21:
   `happyword-server-staging` deploy record `009` returns new lesson-import
   COS URLs under `happyword-assets-staging-1429584068`.
6. Switch production `ASSET_STORAGE_PROVIDER=tencent_cos`. Done on 2026-05-21:
   `happyword-server` deploy record `007` uses `ap-shanghai` and
   `happyword-assets-prod-1429584068`; read-only production smoke passed, and
   `scripts.cos_storage_smoke` uploaded, publicly read, and deleted production
   COS smoke objects without writing to production MongoDB.
7. Do not rewrite existing Vercel Blob URLs during the first rollout.
8. Decide later whether old Vercel Blob objects should be copied to COS and DB
   URLs rewritten. If approved, that backfill must be a separate reversible
   migration with a rollback map.

Cutover acceptance:

- New admin-uploaded illustration/audio assets return COS URLs.
- New lesson-import image uploads return COS URLs.
- Existing Vercel Blob URLs stored in MongoDB remain readable.
- Delete logic only deletes objects owned by the URL provider.

### Vercel Preview Replacement

First target: shared CloudBase staging preview.

Current Vercel Preview responsibilities:

- Per-PR preview URL for server E2E.
- Preview manifest publishing to Vercel Blob.
- Mobile DevMenu target discovery through `/api/v1/public/preview-urls.json`.
- Cleanup on PR close and Vercel deployment pruning.

Replacement sequence:

1. **M8A shared staging.** Use existing CloudBase staging service
   `happyword-server-staging` as the default QA/DevMenu target.
2. **M8A manifest source.** Keep the public endpoint
   `/api/v1/public/preview-urls.json`, but serve a CloudBase staging row from a
   non-Vercel source such as `PREVIEW_MANIFEST_INLINE_JSON`.
3. **M8A CI behavior.** Keep normal PR CI offline by default. Run CloudBase
   staging smoke only on `workflow_dispatch`, a maintainer-approved label, or a
   scheduled validation window.
4. **M8B on-demand PR previews.** Later, selected PRs may deploy a temporary
   CloudBase Run version or service only after service quota, route URL,
   database isolation, and cleanup are implemented.
5. **M8C retirement.** Remove Vercel preview deployment detection and Vercel
   Blob manifest publishing only after DevMenu and CI can use CloudBase staging.

Planned environment variables:

| Variable | Required for | Notes |
| --- | --- | --- |
| `CLOUDBASE_STAGING_BASE_URL` | M8A shared staging smoke | CloudBase staging URL used by CI and DevMenu manifest. |
| `PREVIEW_MANIFEST_INLINE_JSON` | M8A manifest replacement | JSON payload served by `/api/v1/public/preview-urls.json` before a Mongo-backed manifest exists. |
| `CLOUDBASE_PREVIEW_MODE` | Future M8B | Suggested values: `shared_staging`, `on_demand_version`, `on_demand_service`. |

Implementation status, 2026-05-20:

- `server/app/services/preview_manifest_service.py` now checks
  `PREVIEW_MANIFEST_INLINE_JSON` first and falls back to
  `PREVIEW_MANIFEST_BLOB_URL` for legacy Vercel Preview compatibility.
- Inline JSON can use the `items` shape below; the server normalizes it to the
  existing `schema_version: 1` / `previews` response expected by current
  clients.
- HarmonyOS `PreviewManifestService` now accepts CloudBase default domains
  ending in `.tcloudbase.com` as well as legacy `*.vercel.app` preview rows.
- `.github/workflows/server-ci.yml` is in a dual-track transition state: PRs
  still run the legacy Vercel Preview deploy/E2E/Blob manifest refresh, while
  CloudBase staging smoke runs only through `workflow_dispatch` or when a PR
  has the `cloudbase-smoke` label.
- `.github/workflows/server-cloudbase-cd.yml` deploys `main` to CloudBase Run
  in parallel with the existing Vercel `server-cd.yml` workflow. Keep both
  active until CloudBase has passed the stability window and rollback no longer
  depends on Vercel.
- PR-specific CloudBase preview deployment is still disabled until quota,
  routing, database isolation, and cleanup are implemented.

Post-merge CD status, 2026-05-21:

- PR #118 merged the dual-track CI/CD and M8A manifest changes to `main`.
- GitHub Actions run `server-cloudbase-cd` `26199672079` succeeded on `main`
  after the merge. The workflow ran offline pytest, deployed `server/` to
  CloudBase Run, checked `/api/v1/public/health`, and ran the smoke subset
  against `CLOUDBASE_PROD_BASE_URL`.
- The legacy Vercel `server-cd` workflow also stays active and green on `main`.
  During the transition, every `main` server deploy should keep deploying both
  Vercel production and CloudBase production until CloudBase has passed the
  stability window and the final `happyword.cool` cutover is complete.
- `tcb login --apiKeyId "$TCB_SECRET_ID" --apiKey "$TCB_SECRET_KEY"` failed
  when the API key only had `QcloudTCBRFullAccess`. Adding
  `QcloudTCBFullAccess` allowed GitHub Actions and the local CLI to authenticate.
  Treat this as a temporary broad permission; tighten to the minimum CloudBase
  Run, HTTP access, and function permissions after the migration path is stable.

Default-domain smoke tooling, 2026-05-21:

- `tools/cloudbase/smoke-default-domains.sh` runs no-secret public smoke checks
  against staging and production CloudBase Run default domains.
- The default checks cover `/api/v1/public/health`,
  `/api/v1/public/packs/latest.json`, `/privacy`, `/admin/login`,
  `/family/login`, and `/api/v1/public/preview-urls.json`.
- Running the script without an expected preview title passed for both default
  domains on 2026-05-21.
- Running with `CLOUDBASE_EXPECT_PREVIEW_TITLE="CloudBase Staging"` passed for
  both default domains after `PREVIEW_MANIFEST_INLINE_JSON` was added to the
  CloudBase Run staging and production services and both services were
  redeployed.
- Staging was redeployed to `happyword-server-staging-005`; production was
  redeployed to `happyword-server-004`. Both versions received 100% traffic and
  returned the inline `CloudBase Staging` preview row.
- CloudBase service settings support environment variables through either
  Key-Value entries or JSON. Use the console to add this value so existing
  secret environment variables are not copied through shell command arguments.

Initial inline manifest shape:

```json
{
  "items": [
    {
      "name": "CloudBase Staging",
      "url": "https://happyword-server-staging-255236-5-1429584068.sh.run.tcloudbase.com",
      "branch": "shared-staging",
      "provider": "cloudbase",
      "source": "inline"
    }
  ]
}
```

Do not enable automatic CloudBase service-per-PR preview creation until cleanup
exists for PR close, TTL expiry, manifest row removal, and optional PR database
cleanup.

M8B on-demand PR preview design, not implemented yet:

| Decision | M8B default |
| --- | --- |
| Trigger | `workflow_dispatch` or a maintainer-applied `cloudbase-preview` label. Never every PR by default. |
| Preferred target | A temporary CloudBase Run version under `happyword-server-staging`, if CloudBase exposes a stable version URL that can be smoke-tested and added to the manifest. |
| Fallback target | A temporary service named `happyword-server-pr-<number>` only if service quota, naming limits, and cleanup automation are proven. |
| Traffic | 0% of production and shared staging traffic unless a maintainer explicitly promotes it. |
| Manifest row | Add a row with `provider: cloudbase`, `source: github-actions`, PR number, branch, commit SHA, URL, and TTL expiry. |
| Cleanup trigger | PR close, `cloudbase-preview` label removal, manual cleanup dispatch, or TTL expiry. |

Preview data isolation rules:

- Shared staging uses `MONGO_DB_NAME=happyword_cloudbase_staging`.
- PR-specific previews use `MONGO_DB_NAME=happyword_pr_<number>`; fall back to
  a branch hash only when no PR number exists.
- PR-specific previews must use staging-only COS config. They must not write to
  production buckets or reuse production asset domains.
- Cron is disabled for PR-specific previews by default. Enable it only in a
  dedicated smoke scenario with a short-lived database.
- OAuth uses stable staging callback domains only. Do not register every PR URL
  with Google, Apple, Alipay, or WeChat provider consoles.

M8B cleanup requirements before implementation:

- Delete or disable the temporary CloudBase Run version/service on PR close.
- Remove the preview row from the manifest source on PR close, label removal,
  manual cleanup, and TTL expiry.
- Drop or archive the PR-specific Mongo database after the retention window.
- Delete only PR-owned COS objects if the PR preview used a dedicated prefix;
  never sweep shared staging or production asset prefixes.
- Cleanup must be idempotent and safe to run repeatedly.

Storage implementation status, 2026-05-21:

- `ASSET_STORAGE_PROVIDER` defaults to `vercel_blob`, preserving current
  behavior.
- `ASSET_STORAGE_PROVIDER=tencent_cos` routes new uploads through the Tencent
  COS XML API using `COS_SECRET_ID`, `COS_SECRET_KEY`, `COS_REGION`,
  `COS_BUCKET`, and `COS_PUBLIC_BASE_URL`.
- Delete routing is URL-owned: Vercel Blob URLs are sent only to Vercel delete,
  COS URLs under `COS_PUBLIC_BASE_URL` are sent only to COS delete, and unknown
  URLs are ignored.
- Staging and production COS buckets are provisioned in `ap-shanghai`.
- CloudBase staging and production services are configured for Tencent COS new
  uploads. Existing Vercel Blob URLs remain stored as-is and readable through
  their original public URLs.
- `scripts.cos_storage_smoke` verifies illustration, audio, and lesson-image
  uploads, checks the public URLs, and deletes the smoke objects unless
  `COS_SMOKE_KEEP_OBJECTS=1`.

### Filing and Certificate Readiness

CloudBase filing page says mainland China servers used for websites or apps
must complete ICP filing and obtain an ICP filing number before opening access.

Current CloudBase custom-domain state as of 2026-05-18:

- CloudBase HTTP Access has only the default domain. No custom domains or
  routes are bound.
- Tencent Cloud SSL certificate `XjNs7qFU` for `happyword.com.cn` was issued on
  2026-05-18. It covers `happyword.com.cn` and `www.happyword.com.cn`, and is
  valid until 2026-08-16 07:59:59.
- `tcb domains add` requires a valid Tencent Cloud SSL certificate ID and
  explicitly states that the domain must have completed ICP filing.
- Attempting to bind `happyword.com.cn` to CloudBase HTTP Access with
  certificate `XjNs7qFU` failed with `CreateHTTPServiceRoute: 域名未备案`.
- DNS for `happyword.com.cn` is hosted by DNSPod and has no apex A or CNAME
  record yet.
- Tencent Lighthouse instance `lhins-nxph0u6i` was purchased on 2026-05-18 as
  the ICP filing resource. The ICP `验证备案` form now recognizes it as a
  `轻量应用服务器` resource and reports that the current server IP has 0 bound
  websites and 5 remaining available website filing slots.
- ICP order `30177909141643864` was submitted on 2026-05-18 as a first filing
  (`首次备案`) and is now in Tencent Cloud review (`腾讯云审核`). The console says
  Tencent Cloud will perform phone verification within 1-2 business days; if
  the calls are missed, the order can be rejected.
- The current CloudBase Standard monthly package is not shown as an eligible
  备案云资源.
- Tencent Cloud ICP documentation says CloudBase resources used for filing must
  have more than 6 months remaining during filing and fixed public IP enabled.
  The current CloudBase package period ends on 2026-06-18 and fixed public IP is
  disabled, so it is not eligible for this filing path.
- DNS for `happyword.cool` is still hosted by Vercel DNS and remains the
  production and rollback path.

Required before production custom-domain binding:

- Pass Tencent Cloud review, MIIT SMS verification, and communications
  administration review for `happyword.com.cn`.
- Bind `happyword.com.cn` in CloudBase HTTP Access after both prerequisites are
  satisfied, then create the route to CloudBase Run service `happyword-server`.

CloudBase CD status as of 2026-05-21:

- `server-cloudbase-cd` is live on `main` and succeeded in GitHub Actions run
  `26199672079`. This validates the CloudBase default-domain deploy and smoke
  path, not the custom-domain route.
- `CLOUDBASE_PROD_BASE_URL` currently points at the CloudBase production HTTP
  access URL used by CI smoke. Do not assume it is `https://happyword.com.cn`
  until the ICP filing and HTTP Access custom-domain binding are complete.
- `CLOUDBASE_STAGING_BASE_URL` remains the shared staging CloudBase URL used by
  M8A smoke and the DevMenu manifest. It is not `happyword.com.cn`.

## Deployment Commands

```bash
cd server
tcb cloudrun deploy -e "$TCB_ENV_ID" -s happyword-server --port 8080 --source . --force
```

## Health Checks

```bash
curl -fsS "$CLOUDBASE_BASE_URL/api/v1/public/health"
curl -fsS "$CLOUDBASE_BASE_URL/api/v1/public/packs/latest.json"
curl -fsS "$CLOUDBASE_BASE_URL/privacy"
curl -fsS "$CLOUDBASE_BASE_URL/admin/login"
```

M2 smoke results on 2026-05-18 against version `002`:

- `GET /api/v1/public/health`: `200`
- `GET /api/v1/public/packs/latest.json`: `200`, proving CloudBase Run can
  reach MongoDB Atlas with the current staging allowlist strategy.
- `GET /api/v1/public/preview-urls.json`: `200`, proving CloudBase Run can
  read the Wave A Vercel Blob preview manifest.
- `GET /privacy`: `200`
- `GET /admin/login`: `200`
- `POST /api/v1/family/cloudbase-smoke/lessons/import`: `201`, proving
  CloudBase Run can write to Vercel Blob and insert the draft into the staging
  MongoDB database.
- `POST /api/v1/admin/llm/scan-words`: `500`; CloudBase logs show
  `httpx.ConnectTimeout` followed by `openai.APITimeoutError: Request timed
  out`. The same local `OPENAI_API_KEY` validates against OpenAI with `200`, so
  the remaining blocker is CloudBase-to-OpenAI network reachability rather than
  key configuration.
- After switching staging to `LLM_PROVIDER=qwen`, `POST
  /api/v1/admin/llm/scan-words` with `assets/lessons/1.jpg` returned `200` from
  `qwen3.6-plus` and extracted 15 clothing vocabulary words.
- Full async lesson import smoke also passed:
  `POST /api/v1/family/cloudbase-qwen-smoke/lessons/import` created an
  `extracting` draft, then `POST /api/v1/admin/cron/extract-pending` returned
  `{"claimed":1,"succeeded":1,"failed":0}`. The draft became `pending` with
  `model=qwen3.6-plus`, `category_id=clothing`, `label_en=Clothing`, and 15
  extracted words.

M4 production default-domain smoke results on 2026-05-18 against
`happyword-server-002`:

- `GET /api/v1/public/health`: `200`
- `GET /api/v1/public/packs/latest.json`: `200`, proving the production
  CloudBase service can read MongoDB Atlas using `MONGO_DB_NAME=happyword`.
- `GET /privacy`: `200`
- `GET /admin/login`: `200`
- No `happyword.com.cn` or `happyword.cool` DNS change was made during this
  smoke. The only public production traffic path still in use is
  `happyword.cool` on Vercel.

### LLM Provider Switching

Lesson image extraction is controlled by `LLM_PROVIDER`:

| Provider | `LLM_PROVIDER` | Required key | Default vision model | Runtime notes |
| --- | --- | --- | --- | --- |
| OpenAI | `openai` | `OPENAI_API_KEY` | `gpt-4o` | Existing baseline; currently times out from CloudBase Shanghai. |
| Qwen | `qwen` | `DASHSCOPE_API_KEY` | `qwen3.6-plus` | Uses DashScope OpenAI-compatible Responses API with thinking enabled. |
| Doubao | `doubao` | `ARK_API_KEY` | `doubao-seed-2-0-pro-260215` | Uses Volcengine Ark OpenAI-compatible Responses API. |
| Kimi | `kimi` | `MOONSHOT_API_KEY` | `kimi-k2.6` | Uses Moonshot OpenAI-compatible Chat Completions API with image input and thinking disabled for JSON extraction. `KIMI_API_KEY` is accepted as a compatibility alias. |

When adding another provider, compare it on these dimensions before enabling it
in staging: CloudBase network reachability, JSON validity without manual repair,
lesson word recall/precision on `assets/lessons/1.jpg`, example sentence
quality, latency, timeout rate, cost per image, data residency, and SDK/API
compatibility with the existing provider registry.

## Environment Variable Inventory

Record names only in this file. Store actual values in Vercel, CloudBase, GitHub
Actions secrets, Tencent Cloud Secret Manager, or the local operator password
manager.

### Core Runtime

| Variable | Required for | Notes |
| --- | --- | --- |
| `MONGODB_URI` | Staging, production | MongoDB connection string. Keep production and staging values separate. |
| `MONGO_DB_NAME` | Staging, production | Database name. Staging should use a non-production DB. |
| `JWT_SECRET` | Staging, production | Must match the old production value during cutover so existing sessions remain valid. |
| `ADMIN_BOOTSTRAP_USER` | Staging, production | Seeds or updates the bootstrap admin row at startup. |
| `ADMIN_BOOTSTRAP_PASS` | Staging, production | Seeds or updates the bootstrap admin password at startup. |
| `LLM_PROVIDER` | Staging, production | Lesson image extraction provider: `openai`, `qwen`, `doubao`, or `kimi`. |
| `OPENAI_API_KEY` | Production, optional staging | Required when `LLM_PROVIDER=openai`; still used by older OpenAI-only admin flows. |
| `OPENAI_MODEL_TEXT` | Optional | Defaults to `gpt-4o-mini` for older word-level OpenAI helpers. |
| `OPENAI_MODEL_VISION` | Optional | Defaults to `gpt-4o` for OpenAI lesson image parsing. |
| `DASHSCOPE_API_KEY` | Optional | Required when `LLM_PROVIDER=qwen`. |
| `QWEN_MODEL_VISION` | Optional | Defaults to `qwen3.6-plus`. |
| `ARK_API_KEY` | Optional | Required when `LLM_PROVIDER=doubao`. |
| `DOUBAO_MODEL_VISION` | Optional | Defaults to `doubao-seed-2-0-pro-260215`. |
| `MOONSHOT_API_KEY` | Optional | Required when `LLM_PROVIDER=kimi`; `KIMI_API_KEY` is accepted as a compatibility alias. |
| `KIMI_MODEL_VISION` | Optional | Defaults to `kimi-k2.6`. |
| `CORS_ALLOW_ORIGINS` | Staging, production | Current default can remain `*` unless tightened later. |
| `LOG_LEVEL` | Staging, production | Use `info` for normal deployment. |
| `PARENT_WEB_BASE_URL` | Staging, production | Canonical parent web shell base URL for the deployed environment. CloudBase production validation uses `https://happyword.com.cn` before final `happyword.cool` cutover. |
| `OAUTH_CANONICAL_BASE_URL` | Staging, production | Canonical OAuth host. CloudBase production validation uses `https://happyword.com.cn` before final `happyword.cool` cutover. |
| `SESSION_COOKIE_DOMAIN` | Production | Leave empty while validating on CloudBase default domains so browser sessions use a host-only cookie. An exact `happyword.com.cn` host also works with the empty value after binding. Set `.happyword.com.cn` or `.happyword.cool` only if cross-subdomain cookie sharing becomes necessary after custom-domain cutover. |
| `ADMIN_SESSION_COOKIE_NAME` | Staging, production | Current value is `wm_admin_session`. |

### Cron

| Variable | Required for | Notes |
| --- | --- | --- |
| `CRON_SECRET` | Staging, production, cron caller | Shared bearer secret between CloudBase Run and the timer caller. |

M3 CloudBase cron replacement status:

- Function name: `cron-extract-pending`
- Runtime: `Nodejs20.19`
- Memory: `128 MB`
- Timeout: `60s`
- Trigger: `extractPendingEveryMinute`
- Trigger cron: `0 * * * * * *` (CloudBase timer syntax includes seconds;
  this fires once per minute at second 0)
- Function env vars:
  - `CRON_TARGET_URL`: CloudBase staging
    `/api/v1/admin/cron/extract-pending`
  - `CRON_SECRET`: same value as CloudBase Run staging `CRON_SECRET`
- Source path: `cloudbase/functions/cron-extract-pending/`
- `cloudbaserc.json` is not committed. The environment-specific deployment
  config was generated under `/tmp` for the deployment command.
- Manual validation on 2026-05-18:
  `tcb fn invoke cron-extract-pending -e happyword-d5g66zmq8ef2430b8 --json`
  returned `status=200`, body
  `{"claimed":0,"succeeded":0,"failed":0}`, `attempt=1`.
- The function includes short retries for transient CloudBase Run gateway
  `502` / `503` / `504` responses because the first manual invocation saw a
  temporary gateway `503` before the backend cron endpoint was confirmed
  healthy.

### Wave A Vercel Blob Compatibility

| Variable | Required for | Notes |
| --- | --- | --- |
| `PREVIEW_MANIFEST_BLOB_URL` | Wave A staging, Wave A production | Keeps `/api/v1/public/preview-urls.json` working while Vercel Blob remains the manifest source. |
| `BLOB_READ_WRITE_TOKEN` | Wave A upload paths | Keeps existing asset upload code working until storage moves to Tencent COS. |

### OAuth Providers

| Variable | Required for | Notes |
| --- | --- | --- |
| `GOOGLE_OAUTH_CLIENT_ID` | Google OAuth | Set only if Google OAuth remains enabled in the target environment. |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Google OAuth | Set only if Google OAuth remains enabled in the target environment. |
| `APPLE_OAUTH_CLIENT_ID` | Sign in with Apple | Set only if Apple OAuth remains enabled in the target environment. |
| `APPLE_OAUTH_TEAM_ID` | Sign in with Apple | Set only if Apple OAuth remains enabled in the target environment. |
| `APPLE_OAUTH_KEY_ID` | Sign in with Apple | Set only if Apple OAuth remains enabled in the target environment. |
| `APPLE_OAUTH_PRIVATE_KEY` | Sign in with Apple | Keep escaped/newline formatting compatible with `server/app/config.py`. |
| `WECHAT_OAUTH_APP_ID` | WeChat OAuth | Set only if WeChat OAuth remains enabled in the target environment. |
| `WECHAT_OAUTH_APP_SECRET` | WeChat OAuth | Set only if WeChat OAuth remains enabled in the target environment. |
| `ALIPAY_OAUTH_APP_ID` | Alipay OAuth | Set only if Alipay OAuth remains enabled in the target environment. |
| `ALIPAY_OAUTH_APP_PRIVATE_KEY` | Alipay OAuth | Keep escaped/newline formatting compatible with `server/app/config.py`. |
| `ALIPAY_OAUTH_PUBLIC_KEY` | Alipay OAuth | Keep escaped/newline formatting compatible with `server/app/config.py`. |

## Rollback

- CloudBase version rollback:
- DNS rollback to Vercel: keep or restore `happyword.cool` nameservers to
  `ns1.vercel-dns.com` and `ns2.vercel-dns.com`.
- Known-good Vercel production URL: `https://happyword.cool`
