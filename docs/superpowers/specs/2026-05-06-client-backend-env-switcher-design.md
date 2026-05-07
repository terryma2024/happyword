# Client Backend Env Switcher Design

> **Status:** landed 2026-05-06 — implementation in `entry/` + `docs/preview-urls.json` + `preview-manifest.yml`. Confirm GitHub Actions secrets and Vercel preview deployments if the manifest stays empty for new PRs.
> **Companion spec:** [server QA pipeline design](2026-05-06-server-qa-pipeline-design.md) (defines the three logical environments — preview / staging / prod — that this client switcher targets).
> **Successor (after this spec is approved):** an implementation plan at `docs/superpowers/plans/2026-05-06-client-backend-env-switcher-plan.md`.

## 1. Goal

Let HarmonyOS debug builds switch their backend at runtime among **Local**, **PR Preview**, **Staging**, and (future) **Production**, while release builds remain hard-locked to a single fixed environment. The picker must be ergonomic enough that a non-developer tester can point an emulator at PR #42 within five minutes, but invisible — and unreachable — in any release artifact.

## 2. Non-goals

- A user-facing env switcher in release builds. The picker exists only when `BuildProfile.BUILD_MODE_NAME === 'debug'`.
- Per-environment session namespacing. Switching environments hard-resets cloud session state on purpose; namespacing was rejected as too risky for a feature that any future release accidentally exposing would leak data.
- A real production environment in V0.6. The `PROD` enum entry is reserved and disabled until V0.7 launches it.
- A server-side `/admin/preview-urls.json` endpoint. The manifest is a repo file maintained by GitHub Actions.
- Switching environments mid-flight inside a single network request. Switches are atomic at the prefs-write boundary; in-flight requests finish against the old URL and the very next request uses the new one.

## 3. Architecture overview

```
                                       ┌───── HarmonyOS device ─────┐
                                       │                             │
                                       │   release build             │
                                       │     hard-locked → STAGING   │
                                       │                             │
                                       │   debug build               │
                                       │     ┌─ DevMenu page ─────┐  │
                                       │     │ ○ Local            │  │
                                       │     │ ○ Preview ▼        │  │   ◄── dropdown reads
                                       │     │   [happyword-pr-42]│  │       cached manifest
                                       │     │   [happyword-pr-43]│  │
                                       │     │ ● Staging          │  │
                                       │     └─ "Apply" → reset ──┘  │
                                       │                             │
                                       └─────────┬───────────────────┘
                                                 │ on launch (debug only)
                                                 ▼
                                  https://raw.githubusercontent.com/
                                       terryma2024/happyword/main/
                                       docs/preview-urls.json
                                                 ▲
                                                 │ updated by NEW
                                                 │ .github/workflows/preview-manifest.yml
                                                 │ on PR opened/synchronize/closed
```

### 3.1 Key invariants

- **Release builds cannot switch.** The DevMenu entry point and every option enum are gated by `BuildProfile.BUILD_MODE_NAME === 'debug'`. A release APK has no reachable DevMenu page; ohosTest covers the resolver branches that simulate release mode.
- **Switching environments hard-resets cloud session state.** Cleared: `wm_session` cookie, `device_token`, parent session, cloud-sync watermark. Preserved: local-only data — battle stats, learned-word state, monster codex.
- **Manifest fetch is best-effort.** On failure (offline, 404, parse error) the dropdown falls back to a free-text URL field plus a local-history list of the last 5 manually-pasted preview URLs.
- **Today's `PROD_BASE_URL`** (`https://happyword.vercel.app`) is renamed to `STAGING_BASE_URL` (it points at what the QA pipeline spec calls staging). A new `PROD_BASE_URL` constant is reserved as `null` for V0.7+.

## 4. Env model + DevMenu UX

### 4.1 Env enum + URL constants

`entry/src/main/ets/services/RemoteWordPackConfig.ets` evolves from a 2-URL boolean toggle to a typed enum:

```typescript
// Static URL constants (no runtime substitution).
export const LOCAL_BASE_URL: string  = 'http://10.0.2.2:8000';
export const STAGING_BASE_URL: string = 'https://happyword.vercel.app';        // today's "PROD_BASE_URL", renamed
export const PROD_BASE_URL: string | null = null;                              // reserved, V0.7+

export enum BackendEnv {
  LOCAL   = 'local',
  PREVIEW = 'preview',
  STAGING = 'staging',
  PROD    = 'prod',
}

export interface BackendEnvMeta {
  env: BackendEnv;
  label: string;                  // shown in DevMenu radio
  description: string;            // sub-label
  defaultUrl: string | null;      // null for PREVIEW (must come from manifest or paste)
  allowsCustomUrl: boolean;       // true only for PREVIEW
  enabledInDebug: boolean;        // true except for PROD-when-null
  enabledInRelease: boolean;      // false for everything except STAGING (until PROD ships)
}
```

`BackendEnvMeta` table for V0.6:

| env | label | defaultUrl | enabledInDebug | enabledInRelease |
| --- | --- | --- | --- | --- |
| LOCAL | "本地 (10.0.2.2:8000)" | `LOCAL_BASE_URL` | ✓ | ✗ |
| PREVIEW | "PR 预览" | null (dropdown/paste) | ✓ | ✗ |
| STAGING | "Staging" | `STAGING_BASE_URL` | ✓ | ✓ (release-locked) |
| PROD | "Production" | `PROD_BASE_URL` | ✗ (until non-null) | ✗ (until non-null) |

### 4.2 Persistence — what's stored where

Two slots in `Preferences` (HarmonyOS distributed prefs, instance: `wm_dev_menu`):

| Key | Value | Set by |
| --- | --- | --- |
| `backend_env` | one of `local | preview | staging | prod` | DevMenu Apply button |
| `backend_preview_url` | the chosen preview URL string when `backend_env == 'preview'` | DevMenu Apply button |
| `backend_preview_history` | JSON array of last 5 manually-pasted URLs (most-recent first, dedup) | DevMenu Apply button |

The existing `serverBaseUrlOverride` AppStorage key (test-only) **stays as-is** so ohosTest harnesses keep working — the new resolver respects it as the highest-priority override.

### 4.3 New resolver

`effectiveServerBaseUrl()` in `RemoteWordPackConfig.ets` becomes:

```
1. ohosTest override key set?         → return that.
2. Build mode == release?             → return STAGING_BASE_URL (or PROD_BASE_URL once non-null).
3. Build mode == debug:
    a. Read backend_env from prefs.
    b. switch (env):
       LOCAL   → return LOCAL_BASE_URL.
       PREVIEW → return backend_preview_url or fallback to STAGING_BASE_URL with a logged warning.
       STAGING → return STAGING_BASE_URL.
       PROD    → if PROD_BASE_URL != null return it; else fallback to STAGING with a warning.
4. Anything unset on first launch → default to STAGING.
```

Signature stays unchanged so the 6+ services already calling `effectiveServerBaseUrl()` (CloudSyncService, FamilyPackService, ParentApiClient, etc.) need zero edits.

### 4.4 DevMenu page — entry + render

**Entry point**: a new page `entry/src/main/ets/pages/DevMenuPage.ets`, linked from a small "开发者选项" row at the bottom of `ConfigPage.ets`. The row is conditionally visible via `if (BuildProfile.BUILD_MODE_NAME === 'debug')`; release builds ship `ConfigPage` without that row. The DevMenu page file itself remains in the bundle (small) but is unreachable in release.

**Layout** (top-to-bottom):

```
┌──────────────────────────────────────────────┐
│ ← 开发者选项                                  │
├──────────────────────────────────────────────┤
│ 后端环境                                      │
│                                              │
│  ○ 本地  http://10.0.2.2:8000                 │
│                                              │
│  ● PR 预览                                    │
│     ┌────────────────────────────────────┐   │
│     │ Pick a preview ▼                   │   │   ← dropdown, manifest-backed
│     │   #42 feat(server): foo            │   │
│     │   #43 feat(client): bar            │   │
│     └────────────────────────────────────┘   │
│     [ Or paste a URL ]                       │
│     ┌────────────────────────────────────┐   │
│     │ https://happyword-git-...vercel.app│   │
│     └────────────────────────────────────┘   │
│                                              │
│  ○ Staging  https://happyword.vercel.app     │
│                                              │
│  ○ Production  (未启用)                      │
│                                              │
│ ┌────────────────────────────┐               │
│ │  Apply (会清除本地会话)     │               │
│ └────────────────────────────┘               │
│                                              │
│ Manifest 状态: 上次同步 21:30, 2 个有效预览    │
│ [刷新 manifest]                               │
└──────────────────────────────────────────────┘
```

### 4.5 Apply-button flow (hard reset)

Pressing Apply when the selection differs from the persisted env executes, in order:

1. Validate the URL the user picked: `https://...` shape check + 2 s timeout HEAD against `/api/v1/health`. On failure → toast "无法访问，已撤回" and abort, no state changes.
2. Hard-reset device-side session/binding:
   - Delete the Cookie store entry for `wm_session`.
   - Clear AppStorage keys: `cloudCredentials`, `deviceBinding`, `parentSession`, `pendingRedemptions`.
   - Wipe Preferences instance `wm_cloud_sync` (cloud-sync watermark) so the next launch re-pulls from scratch.
   - Local progress (battle stats, learned-word state, monster codex) is **kept** — it's not session-bound.
3. Persist the new selection to Preferences (`backend_env`, `backend_preview_url`, history dedup-update).
4. Toast "已切换到 <label>，请重新登录家长账号 / 配对设备".
5. Navigate back to `HomePage`. The next launch path naturally re-prompts for parent login + device pairing if needed.

No automatic app restart — `effectiveServerBaseUrl()` reads Preferences on every call so existing service constructors pick up the new URL on their next request.

### 4.6 Auditability

Every env switch writes one row to a new `dev_menu_audit` Preferences instance:

```
{ ts: <epoch_ms>, from: 'staging', to: 'preview', preview_url: '...', who: 'debug-build' }
```

Capped at 50 rows (FIFO trim). Visible at the bottom of DevMenu under "切换历史". Exists for "wait, when did I switch to preview and forget?" debugging. Release builds never write here.

## 5. Manifest workflow + JSON schema

### 5.1 What the manifest is

A **single JSON file at `docs/preview-urls.json` on the `main` branch**, kept current by a new GitHub Actions workflow that listens to PR lifecycle events. The HarmonyOS app fetches it on every DevMenu open from `https://raw.githubusercontent.com/terryma2024/happyword/main/docs/preview-urls.json` (no auth — public repo). The file is the single source of truth for "what preview URLs are alive right now".

### 5.2 JSON schema (v1)

```json
{
  "schema_version": 1,
  "updated_at": "2026-05-06T22:30:00Z",
  "previews": [
    {
      "pr": 42,
      "title": "feat(server): admin words pagination",
      "branch": "feat/admin-words-pagination",
      "url": "https://happyword-git-feat-admin-words-pagination-terryma2024.vercel.app",
      "author": "terryma2024",
      "head_sha": "abc1234",
      "updated_at": "2026-05-06T22:25:00Z"
    }
  ]
}
```

Field invariants (validated client-side; bad rows skipped, not fatal):
- `schema_version` is the only thing the client matches against; mismatched version → fall back to manual-paste-only mode and log a warning (forward-compat hatch).
- `pr` is unique (used as React-style key in the dropdown).
- `title` is sanitised — first 80 chars, no newlines, used purely as a UX hint.
- `url` MUST be `https://` and end in `.vercel.app` (cheap SSRF guard for the client).
- `updated_at` is the manifest-write time, NOT the deploy time. The client's "last refreshed" footer uses this.
- The `previews` array length is capped at 50; older entries are pruned by the workflow.

### 5.3 The manifest-refresh workflows

The manifest is rebuilt by `server/scripts/update_preview_manifest.mjs`, which sources truth from the **Vercel deployments API** (NOT GitHub PR webhook payloads). On every run it:

1. Lists every Vercel deployment for the project.
2. Groups by `meta.githubCommitRef` and picks the newest READY non-production deployment per non-protected branch.
3. Looks up the matching PR via `GET /repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=all`, sorted by `created_at desc`.
4. Emits `{pr, title, branch, url (the canonical Vercel hash URL), author, head_sha, updated_at}` per branch with a PR; sorts `pr desc`; truncates to 50; writes file.

Two workflows call it, sharing the `concurrency: preview-manifest` group so writes to `docs/preview-urls.json` serialise:

- **`.github/workflows/server-ci.yml` → `update_manifest` job** — runs on every PR open/synchronize/reopen, gated on `server_e2e` success. Restricted to in-repo PRs (forks can't push back to `main`). The "happy path" that picks up new previews after a green E2E.
- **`.github/workflows/preview-manifest.yml`** — runs on PR `closed` and on `workflow_dispatch`. No e2e gate (the PR is closed; e2e won't run again, but the merged-PR's preview may still be alive on Vercel and should stay in the manifest until pruned).

Key choices:
- All mutations land on `main` in their own commit. Path-filtered CI workflows ignore `docs/**` so this doesn't trigger `server-ci.yml` or `server-cd.yml`.
- The script is fully **idempotent** — every invocation rebuilds the manifest from current Vercel + GitHub state. There is no per-event upsert/remove bookkeeping. This makes the manifest self-healing: if a workflow run is missed, the next one reconciles automatically.
- A merged PR whose Vercel preview is still alive remains in the manifest until the weekly `vercel-prune.yml` cron deletes the deployment. No separate cleanup-on-merge step is needed.
- Script is **node-based** (not Python) because GitHub Actions ships node natively and the Vercel API helper already lives in `server/scripts/vercel_prune_branch_deployments.mjs`.
- `workflow_dispatch` is a real manual repair button — running it without any PR payload triggers a full rebuild, useful when the file drifts (e.g. failed workflow run, hand-edited commit).

### 5.4 Client-side fetch + cache

`entry/src/main/ets/services/PreviewManifestService.ets` (new):

```typescript
class PreviewManifestService {
  private static readonly URL = 'https://raw.githubusercontent.com/'
    + 'terryma2024/happyword/main/docs/preview-urls.json';
  private static readonly CACHE_KEY = 'preview_manifest_cache';
  private static readonly CACHE_TTL_MS = 5 * 60 * 1000;   // 5 minutes

  async fetch(force: boolean): Promise<PreviewManifest> { ... }   // with TTL + ETag
  getCached(): PreviewManifest | null { ... }
  history(): string[] { ... }                                     // last 5 manually-pasted URLs
  pushHistory(url: string): void { ... }
}
```

Behaviour:
- First DevMenu open: synchronous read of cached manifest (if any) → render dropdown immediately; kick off async refresh in background; re-render when fresh data lands.
- TTL = 5 min. Manual "刷新 manifest" button bypasses TTL and forces a network call.
- Cache stored in Preferences instance `wm_dev_menu` under `preview_manifest_cache`. Capped at 16 KB (the JSON is small); older cache evicted on TTL expire.
- All network errors are non-fatal — falls back to whatever is cached, then to manual-paste-only.

### 5.5 What changes server-side?

**Nothing.** Purely a GitHub-Actions + repo-file + client-fetch design. No new server endpoint. The server has no knowledge of which previews are live; that's GitHub's job.

## 6. Rollout plan (4 phases)

### 6.1 Phase A — Server config rename (PR-sized, ~30 min)
**Owner: agent.**

`PROD_BASE_URL` is referenced in only 3 files — all callers downstream go through `effectiveServerBaseUrl()` so they're unaffected by the rename:
- `entry/src/main/ets/services/RemoteWordPackConfig.ets` (definition + internal uses + docstring)
- `entry/src/test/RemoteWordPackConfig.test.ets` (≈20 assertion lines)
- `entry/src/ohosTest/ets/test/List.test.ets` (one comment line)

Steps:
1. Rename `PROD_BASE_URL` → `STAGING_BASE_URL` in `RemoteWordPackConfig.ets`. Add a (deliberately null) `PROD_BASE_URL: string | null = null` constant on the same file as a forward-compat hook.
2. Update the file-level docstring (lines that talk about "PROD_BASE_URL routing") to reflect the staging meaning + the future-prod constant.
3. Update `RemoteWordPackConfig.test.ets` — every assertion that compared against `PROD_BASE_URL` now compares against `STAGING_BASE_URL`. Add one new assertion: `PROD_BASE_URL` is `null` until V0.7.
4. Update the comment in `List.test.ets`.
5. Run `hvigorw assembleHap` + `codelinter -c ./code-linter.json5 . --fix` + the existing ohosTest harness as a pure-rename safety net.

**Checkpoint:** App still routes to `https://happyword.vercel.app` exactly as it does today. Zero behavioural change. ohosTest still green.

### 6.2 Phase B — DevMenu skeleton (PR-sized, ~2 hours)
**Owner: agent.**
1. New `entry/src/main/ets/services/BackendEnv.ets` — enum + meta table + Preferences I/O.
2. New `entry/src/main/ets/services/PreviewManifestService.ets` — fetcher + cache + history.
3. New `entry/src/main/ets/pages/DevMenuPage.ets` — UI with radio + dropdown + paste field + apply button + audit log.
4. New `entry/src/main/ets/services/SessionResetService.ets` — single function `resetForEnvSwitch()` that wipes the AppStorage / Preferences keys listed in §4.5.
5. Conditional row in `ConfigPage.ets` — visible only when `BuildProfile.BUILD_MODE_NAME === 'debug'`.
6. Update `effectiveServerBaseUrl()` to consult Preferences in debug builds (per §4.3 algorithm).
7. ohosTest cases:
   - Resolver returns staging when prefs unset (debug fresh install).
   - Resolver returns local when env=local and build=debug.
   - Resolver returns paste-URL when env=preview + paste-URL set.
   - Resolver still returns staging on release-mode-simulator (override the `BuildProfile.BUILD_MODE_NAME` constant per the existing pattern).
   - Apply-button flow clears the documented session keys.

**Checkpoint:** Debug build can switch among Local / Preview-with-pasted-URL / Staging without restarting the app. Release build never shows the row. Network requests after a switch use the new URL.

### 6.3 Phase C — Manifest workflow (PR-sized, ~1 hour)
**Owner: agent.**
1. Create `server/scripts/update_preview_manifest.mjs` (node 20). Lives under `server/scripts/` because that's where our existing CI scripts live, even though it's node-not-python; one-line README note explains.
2. Create `.github/workflows/preview-manifest.yml` per §5.3.
3. Create the initial `docs/preview-urls.json` with `{"schema_version": 1, "updated_at": null, "previews": []}` so the client's first fetch always succeeds.
4. Hook the dropdown in `DevMenuPage.ets` to `PreviewManifestService.fetch()` (was a stub in Phase B).
5. Smoke test by opening one disposable PR and watching the JSON refresh on `main`.

**Checkpoint:** Open a PR → `docs/preview-urls.json` gains a row → DevMenu dropdown on a debug device shows the new PR's URL within 5 minutes (or immediately after manual refresh).

### 6.4 Phase D — Documentation + lock-in (PR-sized, ~30 min)
**Owner: agent.**
1. README section in the root `README.md` describing the four envs and the DevMenu UX (debug-only).
2. New `docs/superpowers/runbooks/dev-menu-runbook.md` for testers — "how to point my emulator at PR #42".
3. CLAUDE.md / AGENTS.md additions: a one-liner under "Rules" stating "Never expose backend env switching in release builds; the DevMenu is debug-only by construction."
4. Promote this design spec from "approved-pending-implementation" to "landed".

**Checkpoint:** A new tester following the runbook can switch to a PR preview and back to staging within 5 minutes, with no developer help.

## 7. Risk register

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| DevMenu accidentally compiled into release build | low | Single `if (BuildProfile.BUILD_MODE_NAME === 'debug')` gate — covered by ohosTest using the existing build-mode override pattern. CI would also catch any ConfigPage UI snapshot drift in release-mode tests. |
| Manifest JSON becomes stale (workflow fails silently) | medium | Workflow failure posts to `#happyword-ci`; client shows "上次同步" timestamp prominently so testers notice >24h staleness. |
| Vercel preview deploy still pending when manifest workflow runs | high | Self-reschedule pattern in §5.3 (60 s retry, 5 attempts, 15 min total). |
| Client routes traffic to a stale (Vercel-pruned) URL still in cache | low | Cache TTL = 5 min. Manifest rows are recomputed from the Vercel deployments API on every refresh, so a row vanishes within one PR-event cycle of the deployment being pruned. Worst case: user picks a row whose deployment was just pruned → 404 → DevMenu's pre-apply HEAD validation refuses to switch. |
| Manifest URL list grows unbounded | low | Workflow caps at 50 newest, prunes older. |
| Debug-build APK leaked externally has DevMenu enabled | low | Same risk profile as today's debug builds. Acceptable for V0.6. |
| Release build mistakenly built with `BUILD_MODE_NAME` not set to `release` | low | Existing `pickServerBaseUrlExplicit` test pattern covers unknown modes by defaulting to staging — extended to cover the new resolver. |
| `docs/preview-urls.json` triggers `server-ci.yml` on every PR sync | impossible | Path-filter `server/**` in `server-ci.yml` excludes `docs/**` already. Verified during Phase C smoke. |

## 8. Open questions (none blocking)

- **Slack channel name** — `#happyword-ci` matches the QA pipeline spec; reused here for manifest-workflow failure alerts. If you ever rename the channel, this spec inherits the rename via the QA pipeline spec.
- **Audit-log retention beyond 50 rows** — sufficient for V0.6 single-tester use. If multi-tester usage grows, revisit (low priority).

## 9. Acceptance criteria

The env-switcher is "live" when ALL hold:

- [ ] Phases A–D all merged.
- [ ] Release build's `effectiveServerBaseUrl()` is provably hard-locked to `STAGING_BASE_URL` (ohosTest passes; manual confirmation by stripping debug guard temporarily fails the test, then reinstated).
- [ ] Debug build can switch to Local / Preview / Staging via DevMenu, with hard-reset working (verified by inspecting Preferences after Apply).
- [ ] `docs/preview-urls.json` reflects current Vercel deployments after every green E2E (open/sync/reopen) and after every PR close. A merged PR whose Vercel preview is still alive STAYS in the manifest; it disappears only after `vercel-prune.yml` deletes the deployment. (Measured during Phase C smoke.)
- [ ] Tester following `docs/superpowers/runbooks/dev-menu-runbook.md` succeeds without developer assistance.
- [ ] Root `README.md` has the env-switcher section.
- [ ] CLAUDE.md / AGENTS.md note added.
