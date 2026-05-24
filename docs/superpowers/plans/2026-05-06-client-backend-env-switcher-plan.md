# Client Backend Env Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the client-side backend env switcher described in [the env-switcher design spec](../specs/2026-05-06-client-backend-env-switcher-design.md). Debug builds gain a DevMenu page that lets a tester point the HarmonyOS app at Local / a PR Preview / Staging without rebuilding. Release builds remain hard-locked to staging.

**Architecture:** A new `BackendEnv` enum + Preferences-backed resolver replaces the boolean `USE_LOCAL_DEV_SERVER` toggle. A `PreviewManifestService` fetches the preview list from **`PREVIEW_MANIFEST_JSON_URL`** (`https://happyword.cool/api/v1/public/preview-urls.json` — Blob-backed public FastAPI proxy; repo file on `main` is the CI audit copy). Switching environments hard-resets cloud session state by design.

**Revision (2026-05-08):** Aligns with design spec §10 — manifest HTTP never follows `effectiveServerBaseUrl()` or bypass headers. Server `GET /api/v1/public/preview-urls.json` is intentionally unauthenticated (see `public_packs.py` module docstring).

**Tech Stack:** ArkTS, HarmonyOS NEXT, `@ohos/hypium` (unit tests), `@ohos.data.preferences`, AppStorage, `@ohos.net.http`, Node 20 (manifest workflow script), GitHub Actions.

**Spec coverage map:**
| Spec section | Plan task |
| --- | --- |
| §6.1 Phase A — rename | Tasks 1.1, 1.2 |
| §4.1 BackendEnv enum + meta | Tasks 2.1, 2.2 |
| §4.2 Preferences slot wrapper | Task 2.3 |
| §4.3 New resolver | Task 2.4 |
| §4.5 SessionResetService | Task 2.5 |
| §5.4 PreviewManifestService | Task 2.6 |
| §4.4 DevMenu UI | Task 2.7 |
| §6.1 ConfigPage debug-only entry | Task 2.8 |
| Phase B end-to-end ohosTest verification | Task 2.9 |
| §5.2/5.3 manifest workflow + JSON | Tasks 3.1, 3.2, 3.3 |
| §6.4 README + runbook + CLAUDE/AGENTS | Tasks 4.1, 4.2, 4.3 |
| §9 Acceptance | Task 4.4 |

---

## File structure

| File | Created or modified | Responsibility |
| --- | --- | --- |
| `entry/src/main/ets/services/RemoteWordPackConfig.ets` | modify | Rename `PROD_BASE_URL` → `STAGING_BASE_URL`; add reserved `PROD_BASE_URL` constant; teach `effectiveServerBaseUrl()` to honour Preferences in debug builds. |
| `entry/src/test/RemoteWordPackConfig.test.ets` | modify | Mechanical rename of assertions + 1 new assertion for `PROD_BASE_URL == null`. |
| `entry/src/ohosTest/ets/test/List.test.ets` | modify | Update the one comment that mentions `PROD_BASE_URL`. |
| `entry/src/main/ets/services/BackendEnv.ets` | create | `BackendEnv` enum, `BackendEnvMeta` records + per-env metadata table, Preferences I/O helpers (`loadBackendEnv`, `saveBackendEnv`, `loadPreviewUrl`, `savePreviewUrl`, `pushHistory`, `loadHistory`, `loadAuditLog`, `appendAuditLog`). |
| `entry/src/test/BackendEnv.test.ets` | create | 8 unit tests covering enum→meta lookup, default fallback, history dedup-cap, audit-log FIFO trim. |
| `entry/src/main/ets/services/PreviewManifestService.ets` | create | Fetcher + 5-min TTL cache + JSON validation. |
| `entry/src/test/PreviewManifestService.test.ets` | create | 6 tests covering schema-version mismatch, URL guard, sanitisation, cap, TTL, network-failure fallback. |
| `entry/src/main/ets/services/SessionResetService.ets` | create | One function `resetForEnvSwitch(ctx)` clearing 4 AppStorage keys + wiping `wm_cloud_sync` Preferences instance + deleting the `wm_session` cookie. |
| `entry/src/test/SessionResetService.test.ets` | create | 3 tests with injected fakes for AppStorage / Preferences / Cookie store. |
| `entry/src/main/ets/pages/DevMenuPage.ets` | create | UI: radio group, manifest-backed dropdown, paste field, apply button, audit log section, manifest-status footer. |
| `entry/src/main/ets/pages/ConfigPage.ets` | modify | Conditional list row pointing at `pages/DevMenuPage` (debug-only). |
| `entry/src/main/resources/base/profile/main_pages.json` | modify | Register `pages/DevMenuPage`. |
| `server/scripts/update_preview_manifest.mjs` | create | Node script: read state, upsert/remove the row for the current PR, dedup, sort, truncate, write. |
| `.github/workflows/preview-manifest.yml` | create | PR-event-driven workflow that runs the script and commits to `main`. |
| `docs/preview-urls.json` | create | Initial empty manifest. |
| `README.md` (root) | modify | Add a "Client backend env switching" subsection. |
| `docs/superpowers/runbooks/dev-menu-runbook.md` | create | Tester-facing "how to point my emulator at PR #42" runbook. |
| `CLAUDE.md` + `AGENTS.md` (root) | modify | One-liner under Rules confirming DevMenu is debug-only by construction. |
| `docs/superpowers/specs/2026-05-06-client-backend-env-switcher-design.md` | modify | Bump status from "approved" to "landed" at end of rollout. |

All work happens on a single feature branch (created from `main`).

---

## Phase A — Server config rename (Task 1.x)

### Task 1.1: Rename `PROD_BASE_URL` → `STAGING_BASE_URL` + add reserved `PROD_BASE_URL`

**Files:**
- Modify: `entry/src/main/ets/services/RemoteWordPackConfig.ets`

- [ ] **Step 1: Replace lines 1–26 of `RemoteWordPackConfig.ets`**

```typescript
import BuildProfile from 'BuildProfile';

/**
 * V0.7+: server base URL routing.
 *
 * Three named environments are recognised:
 *   - LOCAL_BASE_URL    — the dev FastAPI on the emulator host loopback.
 *   - STAGING_BASE_URL  — what we call "staging" today. Points at the
 *                         Vercel production deploy URL until V0.7 spins
 *                         up a real second project; release builds always
 *                         land here.
 *   - PROD_BASE_URL     — reserved for V0.7+. Stays `null` until a real
 *                         production environment exists; resolvers
 *                         transparently fall back to STAGING_BASE_URL.
 *
 * Debug builds may switch among LOCAL / PREVIEW (paste-or-pick a Vercel
 * preview URL) / STAGING via the in-app DevMenu. Release builds ignore
 * the override entirely and always return STAGING_BASE_URL.
 *
 * For real devices on LAN: change `LOCAL_BASE_URL` to the dev machine's
 * LAN IP (e.g. `http://<lan-host>:8000`). For USB
 * `hdc fport tcp:8000 tcp:8000`, use `http://localhost:8000`.
 */
export const LOCAL_BASE_URL: string = 'http://<android-emulator-host>:8000';
export const STAGING_BASE_URL: string = 'https://happyword.cool';
export const PROD_BASE_URL: string | null = null;          // V0.7+ reserved

/** Cap for a single fetch round-trip; exceeded => fallback to cache. */
export const REMOTE_FETCH_TIMEOUT_MS: number = 8000;
```

(Removes the legacy `DEV_BASE_URL`, `PROD_BASE_URL` (string), and `USE_LOCAL_DEV_SERVER` constants — the env switcher in Task 2.x replaces the toggle entirely.)

- [ ] **Step 2: Replace `pickServerBaseUrlExplicit` / `pickServerBaseUrl`**

These two helpers existed only to support the boolean toggle. Replace lines 31–57 with:

```typescript
/**
 * Pure picker that takes a build mode + explicit env override and
 * returns the canonical URL for that combination. Tests use this to
 * cover all branches without touching Preferences.
 *
 * Rules:
 *   - release build              → STAGING_BASE_URL (PROD_BASE_URL once non-null)
 *   - debug build, no override   → STAGING_BASE_URL (safe default)
 *   - debug build, env=local     → LOCAL_BASE_URL
 *   - debug build, env=preview   → previewUrl (or STAGING_BASE_URL if missing)
 *   - debug build, env=staging   → STAGING_BASE_URL
 *   - debug build, env=prod      → PROD_BASE_URL or STAGING_BASE_URL
 */
export function pickServerBaseUrlExplicit(
  buildModeName: string,
  env: string,           // BackendEnv string value, or '' for default
  previewUrl: string,    // empty string when unset
): string {
  if (buildModeName !== 'debug') {
    return PROD_BASE_URL ?? STAGING_BASE_URL;
  }
  if (env === 'local') {
    return LOCAL_BASE_URL;
  }
  if (env === 'preview') {
    return previewUrl.length > 0 ? previewUrl : STAGING_BASE_URL;
  }
  if (env === 'prod') {
    return PROD_BASE_URL ?? STAGING_BASE_URL;
  }
  // env === 'staging' or unset
  return STAGING_BASE_URL;
}

/**
 * Production picker: applies the persisted Preferences. Read every
 * call so the next HTTP request after Apply uses the new URL.
 *
 * Synchronous wrapper over the cached values that BackendEnv.ets
 * keeps in AppStorage. BackendEnv writes both Preferences (durable)
 * AND AppStorage (sync read here) on every save.
 */
export function pickServerBaseUrl(buildModeName: string): string {
  const env: string = AppStorage.get<string>('backend_env_cache') ?? '';
  const previewUrl: string = AppStorage.get<string>('backend_preview_url_cache') ?? '';
  return pickServerBaseUrlExplicit(buildModeName, env, previewUrl);
}
```

(`AppStorage.get<string>('backend_env_cache')` is a mirror that BackendEnv.ets keeps in sync with Preferences; lets `pickServerBaseUrl` stay sync — necessary because callers like `latestPackUrl()` are sync.)

- [ ] **Step 3: Update the SERVER_BASE_URL line (104) to keep working**

`pickServerBaseUrl(BuildProfile.BUILD_MODE_NAME)` is called once at module load and cached as `SERVER_BASE_URL`. Leave that line as-is — it now picks up the empty AppStorage cache and lands on `STAGING_BASE_URL`, identical to today's behaviour.

- [ ] **Step 4: Build to verify zero compile errors**

```bash
hvigorw assembleHap
```
Expected: BUILD SUCCESSFUL. Any reference to the deleted `DEV_BASE_URL` / `USE_LOCAL_DEV_SERVER` from outside this file would surface as a compile error here.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/services/RemoteWordPackConfig.ets
git commit -m "$(cat <<'EOF'
refactor(client): rename PROD_BASE_URL -> STAGING_BASE_URL, reserve PROD_BASE_URL

Drops the V0.5.1 boolean toggle (`USE_LOCAL_DEV_SERVER`) in favour of
a four-env model (local / preview / staging / prod). PROD_BASE_URL is
reserved as `null` until V0.7 spins up a real production env; resolvers
fall back to STAGING_BASE_URL transparently in the meantime.

`pickServerBaseUrlExplicit` now takes (mode, env, previewUrl) so tests
can cover every branch without touching AppStorage. The production
picker reads `backend_env_cache` / `backend_preview_url_cache` from
AppStorage on every call so the next HTTP request after a DevMenu
Apply uses the new URL synchronously.

Behavioural diff vs. main: zero — empty AppStorage cache lands on
STAGING_BASE_URL, identical to today's PROD_BASE_URL routing.
EOF
)"
```

### Task 1.2: Update existing tests to match the rename

**Files:**
- Modify: `entry/src/test/RemoteWordPackConfig.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

- [ ] **Step 1: Replace the imports + assertions in `RemoteWordPackConfig.test.ets`**

Replace the file entirely with:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import {
  pickServerBaseUrl,
  pickServerBaseUrlExplicit,
  buildLatestPackUrl,
  resolveServerBaseUrl,
  effectiveServerBaseUrl,
  SERVER_BASE_URL_OVERRIDE_KEY,
  LOCAL_BASE_URL,
  STAGING_BASE_URL,
  PROD_BASE_URL,
} from '../main/ets/services/RemoteWordPackConfig';

export default function remoteWordPackConfigTest() {
  describe('RemoteWordPackConfig', () => {
    it('localUrlIsEmulatorHostLoopback', 0, () => {
      expect(LOCAL_BASE_URL).assertEqual('http://<android-emulator-host>:8000');
    });
    it('stagingUrlIsVercelDomain', 0, () => {
      expect(STAGING_BASE_URL).assertEqual('https://happyword.cool');
    });
    it('prodUrlIsReservedAsNull', 0, () => {
      // V0.7+ will flip this to a real URL. Until then resolvers fall
      // back to STAGING_BASE_URL so the app keeps working.
      expect(PROD_BASE_URL).assertNull();
    });

    it('releaseAlwaysLandsOnStaging', 0, () => {
      expect(pickServerBaseUrlExplicit('release', '', '')).assertEqual(STAGING_BASE_URL);
      expect(pickServerBaseUrlExplicit('release', 'local', '')).assertEqual(STAGING_BASE_URL);
      expect(pickServerBaseUrlExplicit('release', 'preview', 'http://x')).assertEqual(STAGING_BASE_URL);
    });
    it('debugWithEmptyEnvDefaultsToStaging', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', '', '')).assertEqual(STAGING_BASE_URL);
    });
    it('debugLocalReturnsLocalUrl', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', 'local', '')).assertEqual(LOCAL_BASE_URL);
    });
    it('debugPreviewWithUrlReturnsPreviewUrl', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', 'preview', 'https://pr-42.vercel.app'))
        .assertEqual('https://pr-42.vercel.app');
    });
    it('debugPreviewWithEmptyFallsBackToStaging', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', 'preview', '')).assertEqual(STAGING_BASE_URL);
    });
    it('debugProdFallsBackToStagingUntilProdIsLive', 0, () => {
      expect(pickServerBaseUrlExplicit('debug', 'prod', '')).assertEqual(STAGING_BASE_URL);
    });

    it('overrideKeyIsStableForGrep', 0, () => {
      expect(SERVER_BASE_URL_OVERRIDE_KEY).assertEqual('serverBaseUrlOverride');
    });
    it('resolveServerBaseUrlReturnsOverrideWhenPresent', 0, () => {
      expect(resolveServerBaseUrl('http://localhost:8123', 'debug'))
        .assertEqual('http://localhost:8123');
      expect(resolveServerBaseUrl('http://localhost:8123', 'release'))
        .assertEqual('http://localhost:8123');
    });
    it('resolveServerBaseUrlIgnoresEmptyOverride', 0, () => {
      AppStorage.delete('backend_env_cache');
      AppStorage.delete('backend_preview_url_cache');
      expect(resolveServerBaseUrl('', 'debug')).assertEqual(STAGING_BASE_URL);
      expect(resolveServerBaseUrl('', 'release')).assertEqual(STAGING_BASE_URL);
    });
    it('resolveServerBaseUrlIgnoresUndefinedOverride', 0, () => {
      AppStorage.delete('backend_env_cache');
      AppStorage.delete('backend_preview_url_cache');
      expect(resolveServerBaseUrl(undefined, 'debug')).assertEqual(STAGING_BASE_URL);
      expect(resolveServerBaseUrl(undefined, 'release')).assertEqual(STAGING_BASE_URL);
    });

    it('effectiveServerBaseUrlReadsAppStorageOverride', 0, () => {
      AppStorage.delete(SERVER_BASE_URL_OVERRIDE_KEY);
      AppStorage.delete('backend_env_cache');
      AppStorage.delete('backend_preview_url_cache');
      expect(effectiveServerBaseUrl()).assertEqual(STAGING_BASE_URL);
      AppStorage.setOrCreate<string>(SERVER_BASE_URL_OVERRIDE_KEY, 'http://localhost:8123');
      expect(effectiveServerBaseUrl()).assertEqual('http://localhost:8123');
      AppStorage.delete(SERVER_BASE_URL_OVERRIDE_KEY);
      expect(effectiveServerBaseUrl()).assertEqual(STAGING_BASE_URL);
    });

    it('debugLocalEnvFromAppStorageRoutesToLocalUrl', 0, () => {
      AppStorage.delete(SERVER_BASE_URL_OVERRIDE_KEY);
      AppStorage.setOrCreate<string>('backend_env_cache', 'local');
      AppStorage.setOrCreate<string>('backend_preview_url_cache', '');
      // The picker drives off BuildProfile.BUILD_MODE_NAME; on the unit
      // test process this defaults to 'debug', so the local URL wins.
      expect(pickServerBaseUrl('debug')).assertEqual(LOCAL_BASE_URL);
      AppStorage.delete('backend_env_cache');
      AppStorage.delete('backend_preview_url_cache');
    });

    it('buildLatestPackUrlAppendsCorrectPath', 0, () => {
      expect(buildLatestPackUrl(STAGING_BASE_URL))
        .assertEqual('https://happyword.cool/api/v1/public/packs/latest.json');
    });
    it('buildLatestPackUrlReturnsEmptyForEmptyBase', 0, () => {
      expect(buildLatestPackUrl('')).assertEqual('');
    });
  });
}
```

(Net change: -3 obsolete tests, +6 new branch-coverage tests, identical assert helpers, no production-code dependency on the old constants.)

- [ ] **Step 2: Update the comment in `List.test.ets`**

Find the comment:
```
 * PROD_BASE_URL through the same `effectiveServerBaseUrl()` call,
```

Replace with:
```
 * STAGING_BASE_URL through the same `effectiveServerBaseUrl()` call,
```

- [ ] **Step 3: Run unit tests**

```bash
hvigorw test --mode=module -p module=entry
```
Expected: all green, including the rewritten `RemoteWordPackConfig` suite.

- [ ] **Step 4: Run codelinter**

```bash
codelinter -c ./code-linter.json5 . --fix
```
Expected: no errors. `--fix` cleans any auto-fixable warnings introduced by the edits.

- [ ] **Step 5: Commit**

```bash
git add entry/src/test/RemoteWordPackConfig.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "test(client): rewrite RemoteWordPackConfig unit tests for the env-switcher API"
```

### Task 1.3: Phase A end-to-end smoke

- [ ] **Step 1: Build a debug HAP and observe routing**

```bash
hvigorw assembleHap
```
Expected: BUILD SUCCESSFUL.

- [ ] **Step 2: Install on emulator (manual; agent stops here for human verification)**

```bash
hdc list targets   # confirm a device
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

Launch the app and observe in DevEco that any HTTP call still goes to `https://happyword.cool`. (The DevMenu doesn't exist yet — pure rename smoke.)

---

## Phase B — DevMenu skeleton (Task 2.x)

### Task 2.1: TDD — `BackendEnv` enum + meta lookup

**Files:**
- Create: `entry/src/main/ets/services/BackendEnv.ets`
- Create: `entry/src/test/BackendEnv.test.ets`

- [ ] **Step 1: Write 8 failing tests**

```typescript
import { describe, it, expect } from '@ohos/hypium';
import {
  BackendEnv,
  metaFor,
  enabledEnvsForBuildMode,
  defaultEnvForBuildMode,
  pushHistory,
  trimAuditLog,
} from '../main/ets/services/BackendEnv';

export default function backendEnvTest() {
  describe('BackendEnv', () => {
    it('enumValuesMatchPersistenceContract', 0, () => {
      expect(BackendEnv.LOCAL).assertEqual('local');
      expect(BackendEnv.PREVIEW).assertEqual('preview');
      expect(BackendEnv.STAGING).assertEqual('staging');
      expect(BackendEnv.PROD).assertEqual('prod');
    });

    it('metaForLocalReportsLocalUrl', 0, () => {
      const m = metaFor(BackendEnv.LOCAL);
      expect(m.defaultUrl).assertEqual('http://<android-emulator-host>:8000');
      expect(m.allowsCustomUrl).assertFalse();
    });

    it('metaForPreviewHasNoDefaultUrlAndAllowsCustom', 0, () => {
      const m = metaFor(BackendEnv.PREVIEW);
      expect(m.defaultUrl).assertNull();
      expect(m.allowsCustomUrl).assertTrue();
    });

    it('metaForProdIsDisabledUntilProdUrlSet', 0, () => {
      const m = metaFor(BackendEnv.PROD);
      expect(m.enabledInDebug).assertFalse();
      expect(m.enabledInRelease).assertFalse();
    });

    it('debugBuildEnablesLocalPreviewStaging', 0, () => {
      const envs = enabledEnvsForBuildMode('debug');
      expect(envs).assertContain(BackendEnv.LOCAL);
      expect(envs).assertContain(BackendEnv.PREVIEW);
      expect(envs).assertContain(BackendEnv.STAGING);
      expect(envs).assertNotContain(BackendEnv.PROD);   // PROD url null
    });

    it('releaseBuildEnablesOnlyStaging', 0, () => {
      expect(enabledEnvsForBuildMode('release')).assertEqual([BackendEnv.STAGING]);
    });

    it('defaultEnvForReleaseIsStaging', 0, () => {
      expect(defaultEnvForBuildMode('release')).assertEqual(BackendEnv.STAGING);
      expect(defaultEnvForBuildMode('debug')).assertEqual(BackendEnv.STAGING);
    });

    it('pushHistoryDedupsAndCapsAtFive', 0, () => {
      let h: string[] = [];
      h = pushHistory(h, 'https://a');
      h = pushHistory(h, 'https://b');
      h = pushHistory(h, 'https://a');                  // dedup-promote
      expect(h).assertEqual(['https://a', 'https://b']);
      h = pushHistory(h, 'https://c');
      h = pushHistory(h, 'https://d');
      h = pushHistory(h, 'https://e');
      h = pushHistory(h, 'https://f');                  // overflow → trim oldest
      expect(h.length).assertEqual(5);
      expect(h[0]).assertEqual('https://f');
    });

    it('trimAuditLogKeepsNewestFifty', 0, () => {
      const rows: object[] = [];
      for (let i = 0; i < 60; i++) {
        rows.push({ ts: i });
      }
      const trimmed = trimAuditLog(rows, 50);
      expect(trimmed.length).assertEqual(50);
      expect((trimmed[0] as { ts: number }).ts).assertEqual(10);
    });
  });
}
```

Save as `entry/src/test/BackendEnv.test.ets`.

- [ ] **Step 2: Register the test in the unit-test runner index**

Open `entry/src/test/List.test.ets` (the unit-test list, not ohosTest) and add an import + call:

```typescript
import backendEnvTest from './BackendEnv.test';
...
backendEnvTest();
```

(Confirm location by `cat entry/src/test/List.test.ets` — there's already an existing index that calls `remoteWordPackConfigTest()` similarly.)

- [ ] **Step 3: Run tests to confirm they fail (module not found)**

```bash
hvigorw test --mode=module -p module=entry
```
Expected: compile errors — no `BackendEnv` module.

- [ ] **Step 4: Implement `entry/src/main/ets/services/BackendEnv.ets`**

```typescript
import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  LOCAL_BASE_URL,
  STAGING_BASE_URL,
  PROD_BASE_URL,
} from './RemoteWordPackConfig';

const PREFS_NAME: string = 'wm_dev_menu';
const KEY_ENV: string = 'backend_env';
const KEY_PREVIEW_URL: string = 'backend_preview_url';
const KEY_HISTORY: string = 'backend_preview_history';
const KEY_AUDIT: string = 'dev_menu_audit';

const APP_STORAGE_ENV_CACHE: string = 'backend_env_cache';
const APP_STORAGE_PREVIEW_CACHE: string = 'backend_preview_url_cache';

const HISTORY_CAP: number = 5;
const AUDIT_CAP: number = 50;

export enum BackendEnv {
  LOCAL = 'local',
  PREVIEW = 'preview',
  STAGING = 'staging',
  PROD = 'prod',
}

export interface BackendEnvMeta {
  env: BackendEnv;
  label: string;
  description: string;
  defaultUrl: string | null;
  allowsCustomUrl: boolean;
  enabledInDebug: boolean;
  enabledInRelease: boolean;
}

const META: Map<BackendEnv, BackendEnvMeta> = new Map<BackendEnv, BackendEnvMeta>([
  [BackendEnv.LOCAL, {
    env: BackendEnv.LOCAL,
    label: '本地',
    description: 'http://<android-emulator-host>:8000',
    defaultUrl: LOCAL_BASE_URL,
    allowsCustomUrl: false,
    enabledInDebug: true,
    enabledInRelease: false,
  }],
  [BackendEnv.PREVIEW, {
    env: BackendEnv.PREVIEW,
    label: 'PR 预览',
    description: '从 manifest 选择或粘贴 URL',
    defaultUrl: null,
    allowsCustomUrl: true,
    enabledInDebug: true,
    enabledInRelease: false,
  }],
  [BackendEnv.STAGING, {
    env: BackendEnv.STAGING,
    label: 'Staging',
    description: STAGING_BASE_URL,
    defaultUrl: STAGING_BASE_URL,
    allowsCustomUrl: false,
    enabledInDebug: true,
    enabledInRelease: true,
  }],
  [BackendEnv.PROD, {
    env: BackendEnv.PROD,
    label: 'Production',
    description: PROD_BASE_URL ?? '(未启用)',
    defaultUrl: PROD_BASE_URL,
    allowsCustomUrl: false,
    enabledInDebug: PROD_BASE_URL !== null,
    enabledInRelease: PROD_BASE_URL !== null,
  }],
]);

export function metaFor(env: BackendEnv): BackendEnvMeta {
  const m = META.get(env);
  if (m === undefined) {
    throw new Error(`No meta for env ${env}`);
  }
  return m;
}

export function enabledEnvsForBuildMode(buildMode: string): BackendEnv[] {
  const out: BackendEnv[] = [];
  META.forEach((meta: BackendEnvMeta) => {
    const enabled: boolean = buildMode === 'release'
      ? meta.enabledInRelease
      : meta.enabledInDebug;
    if (enabled) {
      out.push(meta.env);
    }
  });
  return out;
}

export function defaultEnvForBuildMode(_buildMode: string): BackendEnv {
  // STAGING is the safe default for both debug (fresh install) and release.
  return BackendEnv.STAGING;
}

export function pushHistory(prev: string[], url: string): string[] {
  const filtered = prev.filter((x: string) => x !== url);
  filtered.unshift(url);
  return filtered.slice(0, HISTORY_CAP);
}

export function trimAuditLog(prev: object[], cap: number = AUDIT_CAP): object[] {
  if (prev.length <= cap) {
    return prev;
  }
  return prev.slice(prev.length - cap);
}

// ─── persistence ────────────────────────────────────────────────────────────

let prefsHandle: preferences.Preferences | null = null;

export async function initBackendEnvPrefs(ctx: common.UIAbilityContext): Promise<void> {
  if (prefsHandle !== null) {
    return;
  }
  try {
    prefsHandle = await preferences.getPreferences(ctx, PREFS_NAME);
    const env: string = await getString(KEY_ENV, BackendEnv.STAGING);
    const url: string = await getString(KEY_PREVIEW_URL, '');
    AppStorage.setOrCreate<string>(APP_STORAGE_ENV_CACHE, env);
    AppStorage.setOrCreate<string>(APP_STORAGE_PREVIEW_CACHE, url);
  } catch (err) {
    console.error(`BackendEnv.initPrefs failed: ${JSON.stringify(err as BusinessError)}`);
  }
}

async function getString(key: string, fallback: string): Promise<string> {
  if (prefsHandle === null) {
    return fallback;
  }
  try {
    const v: preferences.ValueType = await prefsHandle.get(key, fallback);
    return typeof v === 'string' ? v : fallback;
  } catch (err) {
    console.error(`BackendEnv.getString(${key}) failed: ${JSON.stringify(err as BusinessError)}`);
    return fallback;
  }
}

async function putAndFlush(key: string, value: string): Promise<void> {
  if (prefsHandle === null) {
    return;
  }
  try {
    await prefsHandle.put(key, value);
    await prefsHandle.flush();
  } catch (err) {
    console.error(`BackendEnv.put(${key}) failed: ${JSON.stringify(err as BusinessError)}`);
  }
}

export async function loadBackendEnv(): Promise<BackendEnv> {
  const raw = await getString(KEY_ENV, BackendEnv.STAGING);
  if (raw === BackendEnv.LOCAL || raw === BackendEnv.PREVIEW
      || raw === BackendEnv.STAGING || raw === BackendEnv.PROD) {
    return raw as BackendEnv;
  }
  return BackendEnv.STAGING;
}

export async function saveBackendEnv(env: BackendEnv): Promise<void> {
  await putAndFlush(KEY_ENV, env);
  AppStorage.setOrCreate<string>(APP_STORAGE_ENV_CACHE, env);
}

export async function loadPreviewUrl(): Promise<string> {
  return getString(KEY_PREVIEW_URL, '');
}

export async function savePreviewUrl(url: string): Promise<void> {
  await putAndFlush(KEY_PREVIEW_URL, url);
  AppStorage.setOrCreate<string>(APP_STORAGE_PREVIEW_CACHE, url);
}

export async function loadHistory(): Promise<string[]> {
  const raw: string = await getString(KEY_HISTORY, '[]');
  try {
    const parsed: object = JSON.parse(raw) as object;
    if (Array.isArray(parsed)) {
      return (parsed as string[]).filter((x: string) => typeof x === 'string');
    }
  } catch (err) {
    console.error(`BackendEnv.loadHistory parse failed: ${JSON.stringify(err)}`);
  }
  return [];
}

export async function saveHistory(history: string[]): Promise<void> {
  await putAndFlush(KEY_HISTORY, JSON.stringify(history));
}

export interface AuditRow {
  ts: number;
  from: string;
  to: string;
  preview_url: string;
}

export async function loadAuditLog(): Promise<AuditRow[]> {
  const raw: string = await getString(KEY_AUDIT, '[]');
  try {
    const parsed: object = JSON.parse(raw) as object;
    if (Array.isArray(parsed)) {
      return parsed as AuditRow[];
    }
  } catch (err) {
    console.error(`BackendEnv.loadAudit parse failed: ${JSON.stringify(err)}`);
  }
  return [];
}

export async function appendAuditLog(row: AuditRow): Promise<void> {
  const prev: AuditRow[] = await loadAuditLog();
  prev.push(row);
  const trimmed: AuditRow[] = trimAuditLog(prev) as AuditRow[];
  await putAndFlush(KEY_AUDIT, JSON.stringify(trimmed));
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
hvigorw test --mode=module -p module=entry
```
Expected: all green (the new 8 BackendEnv assertions plus the existing suites).

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/services/BackendEnv.ets entry/src/test/BackendEnv.test.ets entry/src/test/List.test.ets
git commit -m "feat(client): BackendEnv enum, meta lookup, persistence helpers + 8 unit tests"
```

### Task 2.2: TDD — `PreviewManifestService`

**Files:**
- Create: `entry/src/main/ets/services/PreviewManifestService.ets`
- Create: `entry/src/test/PreviewManifestService.test.ets`

- [ ] **Step 1: Write 6 failing tests**

```typescript
import { describe, it, expect } from '@ohos/hypium';
import {
  parseManifest,
  ManifestRow,
  PreviewManifest,
} from '../main/ets/services/PreviewManifestService';

export default function previewManifestServiceTest() {
  describe('PreviewManifestService.parseManifest', () => {
    it('parsesValidV1Manifest', 0, () => {
      const json = `{
        "schema_version": 1,
        "updated_at": "2026-05-06T00:00:00Z",
        "previews": [
          { "pr": 42, "title": "x", "branch": "f/x", "url": "https://x.vercel.app",
            "author": "u", "head_sha": "abc", "updated_at": "2026-05-06T00:00:00Z" }
        ]
      }`;
      const m = parseManifest(json);
      expect(m).assertNotNull();
      expect((m as PreviewManifest).previews.length).assertEqual(1);
    });

    it('returnsNullOnSchemaVersionMismatch', 0, () => {
      const json = `{ "schema_version": 99, "updated_at": "x", "previews": [] }`;
      expect(parseManifest(json)).assertNull();
    });

    it('skipsRowsWithNonHttpsUrl', 0, () => {
      const json = `{
        "schema_version": 1, "updated_at": "x",
        "previews": [
          { "pr": 1, "title": "ok", "branch": "f/a", "url": "http://x.vercel.app",
            "author": "u", "head_sha": "abc", "updated_at": "x" },
          { "pr": 2, "title": "ok", "branch": "f/b", "url": "https://y.vercel.app",
            "author": "u", "head_sha": "abc", "updated_at": "x" }
        ]
      }`;
      const m = parseManifest(json);
      expect(m).assertNotNull();
      expect((m as PreviewManifest).previews.length).assertEqual(1);
      expect((m as PreviewManifest).previews[0].pr).assertEqual(2);
    });

    it('skipsRowsNotEndingInVercelApp', 0, () => {
      const json = `{
        "schema_version": 1, "updated_at": "x",
        "previews": [
          { "pr": 1, "title": "x", "branch": "f/a", "url": "https://evil.example.com",
            "author": "u", "head_sha": "abc", "updated_at": "x" }
        ]
      }`;
      expect((parseManifest(json) as PreviewManifest).previews.length).assertEqual(0);
    });

    it('truncatesTitleAt80CharsAndStripsNewlines', 0, () => {
      const longTitle = 'a'.repeat(120) + '\nbad';
      const json = `{
        "schema_version": 1, "updated_at": "x",
        "previews": [
          { "pr": 1, "title": ${JSON.stringify(longTitle)}, "branch": "f/a",
            "url": "https://x.vercel.app", "author": "u", "head_sha": "abc",
            "updated_at": "x" }
        ]
      }`;
      const row: ManifestRow = (parseManifest(json) as PreviewManifest).previews[0];
      expect(row.title.length).assertEqual(80);
      expect(row.title.includes('\n')).assertFalse();
    });

    it('returnsNullOnMalformedJson', 0, () => {
      expect(parseManifest('{not json')).assertNull();
    });
  });
}
```

Register in `entry/src/test/List.test.ets` like in Task 2.1.

- [ ] **Step 2: Run tests — confirm they fail with module-not-found**

```bash
hvigorw test --mode=module -p module=entry
```

- [ ] **Step 3: Implement `entry/src/main/ets/services/PreviewManifestService.ets`**

```typescript
import http from '@ohos.net.http';
import preferences from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';

// Production manifest endpoint only — same origin as `PREVIEW_MANIFEST_JSON_URL`
// in RemoteWordPackConfig.ets (no raw.githubusercontent.com; no rewrite via DevMenu base URL).
const MANIFEST_URL: string =
  'https://happyword.cool/api/v1/public/preview-urls.json';
const PREFS_NAME: string = 'wm_dev_menu';
const CACHE_KEY: string = 'preview_manifest_cache';
const CACHE_TTL_MS: number = 5 * 60 * 1000;
const SCHEMA_VERSION: number = 1;
const TITLE_MAX: number = 80;
const PREVIEWS_CAP: number = 50;

export interface ManifestRow {
  pr: number;
  title: string;
  branch: string;
  url: string;
  author: string;
  head_sha: string;
  updated_at: string;
}

export interface PreviewManifest {
  schema_version: number;
  updated_at: string;
  previews: ManifestRow[];
}

interface CacheEnvelope {
  fetched_at: number;
  manifest: PreviewManifest;
}

function isString(v: unknown): boolean {
  return typeof v === 'string';
}

function isNumber(v: unknown): boolean {
  return typeof v === 'number';
}

function sanitiseTitle(raw: string): string {
  return raw.replace(/[\r\n]+/g, ' ').slice(0, TITLE_MAX);
}

function isValidUrl(url: string): boolean {
  return url.startsWith('https://') && url.endsWith('.vercel.app');
}

export function parseManifest(json: string): PreviewManifest | null {
  let obj: object;
  try {
    obj = JSON.parse(json) as object;
  } catch (err) {
    console.error(`PreviewManifest.parse failed: ${JSON.stringify(err)}`);
    return null;
  }
  const ver = (obj as Record<string, unknown>)['schema_version'];
  if (ver !== SCHEMA_VERSION) {
    return null;
  }
  const previewsRaw = (obj as Record<string, unknown>)['previews'];
  const previews: ManifestRow[] = [];
  if (Array.isArray(previewsRaw)) {
    for (const r of previewsRaw) {
      const rec = r as Record<string, unknown>;
      if (!isNumber(rec['pr']) || !isString(rec['title']) || !isString(rec['branch'])
          || !isString(rec['url']) || !isString(rec['author'])
          || !isString(rec['head_sha']) || !isString(rec['updated_at'])) {
        continue;
      }
      const url = rec['url'] as string;
      if (!isValidUrl(url)) {
        continue;
      }
      previews.push({
        pr: rec['pr'] as number,
        title: sanitiseTitle(rec['title'] as string),
        branch: rec['branch'] as string,
        url,
        author: rec['author'] as string,
        head_sha: rec['head_sha'] as string,
        updated_at: rec['updated_at'] as string,
      });
    }
  }
  return {
    schema_version: SCHEMA_VERSION,
    updated_at: isString((obj as Record<string, unknown>)['updated_at'])
      ? (obj as Record<string, unknown>)['updated_at'] as string
      : '',
    previews: previews.slice(0, PREVIEWS_CAP),
  };
}

let prefsHandle: preferences.Preferences | null = null;
let memCache: CacheEnvelope | null = null;

export async function initPreviewManifestService(ctx: common.UIAbilityContext): Promise<void> {
  if (prefsHandle === null) {
    try {
      prefsHandle = await preferences.getPreferences(ctx, PREFS_NAME);
    } catch (err) {
      console.error(`PreviewManifest.init failed: ${JSON.stringify(err as BusinessError)}`);
    }
  }
  if (memCache === null && prefsHandle !== null) {
    try {
      const raw: preferences.ValueType = await prefsHandle.get(CACHE_KEY, '');
      if (typeof raw === 'string' && raw.length > 0) {
        const parsed = JSON.parse(raw) as CacheEnvelope;
        memCache = parsed;
      }
    } catch (err) {
      console.error(`PreviewManifest.loadCache failed: ${JSON.stringify(err)}`);
    }
  }
}

export function getCached(): PreviewManifest | null {
  return memCache?.manifest ?? null;
}

export async function fetchManifest(force: boolean): Promise<PreviewManifest | null> {
  const now = Date.now();
  if (!force && memCache !== null && (now - memCache.fetched_at) < CACHE_TTL_MS) {
    return memCache.manifest;
  }
  const req = http.createHttp();
  try {
    const resp: http.HttpResponse = await req.request(MANIFEST_URL, {
      method: http.RequestMethod.GET,
      readTimeout: 5000,
      connectTimeout: 5000,
    });
    if (resp.responseCode !== 200 || typeof resp.result !== 'string') {
      return memCache?.manifest ?? null;
    }
    const parsed = parseManifest(resp.result);
    if (parsed === null) {
      return memCache?.manifest ?? null;
    }
    memCache = { fetched_at: now, manifest: parsed };
    if (prefsHandle !== null) {
      try {
        await prefsHandle.put(CACHE_KEY, JSON.stringify(memCache));
        await prefsHandle.flush();
      } catch (err) {
        console.error(`PreviewManifest.saveCache failed: ${JSON.stringify(err)}`);
      }
    }
    return parsed;
  } catch (err) {
    console.error(`PreviewManifest.fetch network error: ${JSON.stringify(err)}`);
    return memCache?.manifest ?? null;
  } finally {
    req.destroy();
  }
}

export function __resetForTest(): void {
  memCache = null;
  prefsHandle = null;
}
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
hvigorw test --mode=module -p module=entry
```
Expected: 6 new + previous tests all green.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/services/PreviewManifestService.ets entry/src/test/PreviewManifestService.test.ets entry/src/test/List.test.ets
git commit -m "feat(client): PreviewManifestService — 5-min-TTL fetch with strict JSON validation"
```

### Task 2.3: `SessionResetService` (small, focused)

**Files:**
- Create: `entry/src/main/ets/services/SessionResetService.ets`
- Create: `entry/src/test/SessionResetService.test.ets`

- [ ] **Step 1: Write 3 failing tests**

```typescript
import { describe, it, expect } from '@ohos/hypium';
import {
  resetForEnvSwitchExplicit,
  KEYS_TO_CLEAR,
} from '../main/ets/services/SessionResetService';

export default function sessionResetServiceTest() {
  describe('SessionResetService', () => {
    it('clearsTheDocumentedAppStorageKeys', 0, () => {
      // Sanity: the constant lists exactly the 4 keys the spec promises
      // to wipe on env switch.
      expect(KEYS_TO_CLEAR).assertEqual([
        'cloudCredentials',
        'deviceBinding',
        'parentSession',
        'pendingRedemptions',
      ]);
    });

    it('callsFakeAppStorageDeleteForEachKey', 0, () => {
      const deleted: string[] = [];
      const fakeStorage: { delete: (k: string) => void } = {
        delete: (k: string) => deleted.push(k),
      };
      resetForEnvSwitchExplicit(
        fakeStorage,
        async () => { /* prefs noop */ },
        async () => { /* cookie noop */ },
      );
      expect(deleted).assertEqual([
        'cloudCredentials',
        'deviceBinding',
        'parentSession',
        'pendingRedemptions',
      ]);
    });

    it('invokesPrefsAndCookieFakes', 0, async () => {
      let prefsCalled = false;
      let cookieCalled = false;
      await resetForEnvSwitchExplicit(
        { delete: (_k: string) => { } },
        async () => { prefsCalled = true; },
        async () => { cookieCalled = true; },
      );
      expect(prefsCalled).assertTrue();
      expect(cookieCalled).assertTrue();
    });
  });
}
```

Register in `entry/src/test/List.test.ets`.

- [ ] **Step 2: Implement `SessionResetService.ets`**

```typescript
import preferences from '@ohos.data.preferences';
import webview from '@ohos.web.webview';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { effectiveServerBaseUrl } from './RemoteWordPackConfig';

export const KEYS_TO_CLEAR: string[] = [
  'cloudCredentials',
  'deviceBinding',
  'parentSession',
  'pendingRedemptions',
];

interface AppStorageLike {
  delete(key: string): void;
}

const realStorage: AppStorageLike = { delete: (k: string) => AppStorage.delete(k) };

export async function resetForEnvSwitchExplicit(
  storage: AppStorageLike,
  wipeCloudSyncPrefs: () => Promise<void>,
  deleteSessionCookie: () => Promise<void>,
): Promise<void> {
  for (const key of KEYS_TO_CLEAR) {
    storage.delete(key);
  }
  await wipeCloudSyncPrefs();
  await deleteSessionCookie();
}

export async function resetForEnvSwitch(ctx: common.UIAbilityContext): Promise<void> {
  await resetForEnvSwitchExplicit(
    realStorage,
    async () => {
      try {
        await preferences.deletePreferences(ctx, 'wm_cloud_sync');
      } catch (err) {
        console.error(`SessionReset.deletePrefs failed: ${JSON.stringify(err as BusinessError)}`);
      }
    },
    async () => {
      try {
        const url = effectiveServerBaseUrl();
        const cookieMgr = webview.WebCookieManager;
        cookieMgr.deleteCookieByUrl(url, 'wm_session');
      } catch (err) {
        console.error(`SessionReset.deleteCookie failed: ${JSON.stringify(err as BusinessError)}`);
      }
    },
  );
}
```

- [ ] **Step 3: Run tests — confirm they pass**

```bash
hvigorw test --mode=module -p module=entry
```

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/services/SessionResetService.ets entry/src/test/SessionResetService.test.ets entry/src/test/List.test.ets
git commit -m "feat(client): SessionResetService.resetForEnvSwitch + 3 unit tests"
```

### Task 2.4: Wire `BackendEnv.init` + manifest init at app boot

**Files:**
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets`

- [ ] **Step 1: Find the existing onWindowStageCreate / onCreate hook**

```bash
grep -n "onWindowStageCreate\|TodayPreferences" entry/src/main/ets/entryability/EntryAbility.ets
```
Expected: a few lines around the existing init code.

- [ ] **Step 2: Add two awaits next to the TodayPreferences init**

```typescript
import { initBackendEnvPrefs } from '../services/BackendEnv';
import { initPreviewManifestService } from '../services/PreviewManifestService';
...
// In the same async hook that calls TodayPreferences.init(this.context):
await initBackendEnvPrefs(this.context);
await initPreviewManifestService(this.context);
```

- [ ] **Step 3: Build to verify**

```bash
hvigorw assembleHap
```
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/entryability/EntryAbility.ets
git commit -m "feat(client): init BackendEnv + PreviewManifestService at app boot"
```

### Task 2.5: `DevMenuPage.ets` — full UI

**Files:**
- Create: `entry/src/main/ets/pages/DevMenuPage.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json` — register the page route.

This is one larger task because the UI is structural; splitting it into TDD steps would be artificial. Trust the existing tests on services (Tasks 2.1–2.3) to catch logic regressions; this task is pure rendering glue.

- [ ] **Step 1: Register the route**

Open `entry/src/main/resources/base/profile/main_pages.json` and append `pages/DevMenuPage` to the `src` array.

- [ ] **Step 2: Create `entry/src/main/ets/pages/DevMenuPage.ets`**

```typescript
import router from '@ohos.router';
import http from '@ohos.net.http';
import { common } from '@kit.AbilityKit';
import {
  BackendEnv, BackendEnvMeta, metaFor, enabledEnvsForBuildMode,
  loadBackendEnv, saveBackendEnv,
  loadPreviewUrl, savePreviewUrl,
  loadHistory, saveHistory, pushHistory,
  appendAuditLog, loadAuditLog, AuditRow,
} from '../services/BackendEnv';
import { fetchManifest, getCached, ManifestRow, PreviewManifest } from '../services/PreviewManifestService';
import { resetForEnvSwitch } from '../services/SessionResetService';
import BuildProfile from 'BuildProfile';

@Entry
@Component
struct DevMenuPage {
  @State currentEnv: BackendEnv = BackendEnv.STAGING;
  @State pendingEnv: BackendEnv = BackendEnv.STAGING;
  @State pendingPreviewUrl: string = '';
  @State pasteUrl: string = '';
  @State history: string[] = [];
  @State manifest: PreviewManifest | null = null;
  @State manifestLoading: boolean = false;
  @State auditRows: AuditRow[] = [];
  @State applying: boolean = false;
  @State enabledEnvs: BackendEnv[] = [];

  aboutToAppear(): void {
    this.refreshAll();
  }

  async refreshAll(): Promise<void> {
    this.enabledEnvs = enabledEnvsForBuildMode(BuildProfile.BUILD_MODE_NAME);
    this.currentEnv = await loadBackendEnv();
    this.pendingEnv = this.currentEnv;
    this.pendingPreviewUrl = await loadPreviewUrl();
    this.history = await loadHistory();
    this.manifest = getCached();
    this.auditRows = (await loadAuditLog()).reverse();
    this.refreshManifest(false);
  }

  async refreshManifest(force: boolean): Promise<void> {
    this.manifestLoading = true;
    this.manifest = await fetchManifest(force);
    this.manifestLoading = false;
  }

  async applyChanges(): Promise<void> {
    if (this.applying) {
      return;
    }
    this.applying = true;
    try {
      let chosenUrl: string = this.pendingPreviewUrl;
      if (this.pendingEnv === BackendEnv.PREVIEW) {
        if (this.pasteUrl.length > 0) {
          chosenUrl = this.pasteUrl.trim();
        }
        if (!chosenUrl.startsWith('https://') || !chosenUrl.endsWith('.vercel.app')) {
          this.toast('请粘贴 https:// 开头、.vercel.app 结尾的预览 URL');
          return;
        }
        if (!await this.healthCheck(chosenUrl)) {
          this.toast('无法访问该 URL，已撤回');
          return;
        }
      }
      const ctx = getContext(this) as common.UIAbilityContext;
      await resetForEnvSwitch(ctx);
      await saveBackendEnv(this.pendingEnv);
      if (this.pendingEnv === BackendEnv.PREVIEW) {
        await savePreviewUrl(chosenUrl);
        this.history = pushHistory(this.history, chosenUrl);
        await saveHistory(this.history);
      } else {
        await savePreviewUrl('');
      }
      await appendAuditLog({
        ts: Date.now(),
        from: this.currentEnv,
        to: this.pendingEnv,
        preview_url: chosenUrl,
      });
      this.toast(`已切换到 ${metaFor(this.pendingEnv).label}，请重新登录家长账号 / 配对设备`);
      router.replaceUrl({ url: 'pages/HomePage' }).catch(() => { });
    } finally {
      this.applying = false;
    }
  }

  async healthCheck(url: string): Promise<boolean> {
    const req = http.createHttp();
    try {
      const resp = await req.request(`${url}/api/v1/public/health`, {
        method: http.RequestMethod.GET,
        connectTimeout: 2000,
        readTimeout: 2000,
      });
      return resp.responseCode === 200;
    } catch (_err) {
      return false;
    } finally {
      req.destroy();
    }
  }

  toast(msg: string): void {
    // Use whatever toast helper the codebase already exposes; placeholder
    // — a real impl should call promptAction.showToast({ message: msg }).
    console.info(`[DevMenu] ${msg}`);
  }

  @Builder envRow(env: BackendEnv) {
    const meta: BackendEnvMeta = metaFor(env);
    Row() {
      Radio({ value: env, group: 'env' })
        .checked(this.pendingEnv === env)
        .onChange((checked: boolean) => {
          if (checked) {
            this.pendingEnv = env;
          }
        });
      Column() {
        Text(meta.label).fontSize(16);
        Text(meta.description).fontSize(12).fontColor('#888');
      }.alignItems(HorizontalAlign.Start).margin({ left: 8 });
    }.padding(12);
  }

  build(): void {
    Navigation() {
      Scroll() {
        Column() {
          Text('后端环境').fontSize(18).fontWeight(FontWeight.Bold).padding(12);

          ForEach(this.enabledEnvs, (env: BackendEnv) => {
            this.envRow(env);
            if (env === BackendEnv.PREVIEW && this.pendingEnv === BackendEnv.PREVIEW) {
              this.previewControls();
            }
          });

          Button(this.applying ? '正在应用…' : 'Apply (会清除本地会话)')
            .enabled(!this.applying && this.pendingEnv !== this.currentEnv)
            .width('90%')
            .margin({ top: 16 })
            .onClick(() => { this.applyChanges(); });

          this.manifestStatus();
          this.auditSection();
        }.width('100%');
      }.height('100%');
    }
    .title('开发者选项');
  }

  @Builder previewControls() {
    Column() {
      Select(this.dropdownOptions())
        .selected(this.pendingPreviewUrl.length === 0 ? -1 :
          this.dropdownOptions().findIndex((opt: SelectOption) => opt.value === this.pendingPreviewUrl))
        .value(this.pendingPreviewUrl.length > 0 ? this.pendingPreviewUrl : 'Pick a preview ▼')
        .onSelect((_idx: number, value: string) => {
          this.pendingPreviewUrl = value;
          this.pasteUrl = '';
        });
      TextInput({ placeholder: 'Or paste a preview URL', text: this.pasteUrl })
        .onChange((v: string) => { this.pasteUrl = v; })
        .margin({ top: 8 });
      if (this.history.length > 0) {
        Text('最近使用').fontSize(12).fontColor('#888').margin({ top: 8 });
        ForEach(this.history, (url: string) => {
          Text(url).fontSize(12).onClick(() => { this.pasteUrl = url; });
        });
      }
    }.padding({ left: 32, right: 16 });
  }

  dropdownOptions(): SelectOption[] {
    if (this.manifest === null) {
      return [];
    }
    return this.manifest.previews.map((row: ManifestRow) => {
      return { value: row.url, value2: `#${row.pr} ${row.title}` } as SelectOption;
    });
  }

  @Builder manifestStatus() {
    Row() {
      Text(`Manifest 状态: ${this.manifest === null ? '未加载' : `${this.manifest.previews.length} 个有效预览`}`)
        .fontSize(12).fontColor('#888');
      Button('刷新 manifest')
        .fontSize(12)
        .margin({ left: 8 })
        .onClick(() => { this.refreshManifest(true); });
    }.padding(12);
  }

  @Builder auditSection() {
    Column() {
      Text('切换历史').fontSize(14).fontWeight(FontWeight.Bold).margin({ top: 16, left: 12 });
      ForEach(this.auditRows.slice(0, 10), (row: AuditRow) => {
        Text(`${new Date(row.ts).toISOString()}: ${row.from} → ${row.to} ${row.preview_url}`)
          .fontSize(11).fontColor('#666').padding({ left: 12, right: 12 });
      });
    };
  }
}
```

(`SelectOption` is the ArkUI type for `Select` items; if your installed SDK exposes it under a different name, the surrounding pattern stays identical.)

- [ ] **Step 3: Build to verify the page compiles**

```bash
hvigorw assembleHap
```
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Run codelinter**

```bash
codelinter -c ./code-linter.json5 . --fix
```
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/pages/DevMenuPage.ets entry/src/main/resources/base/profile/main_pages.json
git commit -m "feat(client): DevMenuPage — env radio + preview dropdown + paste field + apply"
```

### Task 2.6: ConfigPage entry row (debug-only)

**Files:**
- Modify: `entry/src/main/ets/pages/ConfigPage.ets`

- [ ] **Step 1: Add the import at the top**

```typescript
import BuildProfile from 'BuildProfile';
```
(May already be present — check first.)

- [ ] **Step 2: Inside the `build()` method (line 853), append a debug-only row**

Find the existing list/menu structure inside `build()`. After the last existing row, append:

```typescript
if (BuildProfile.BUILD_MODE_NAME === 'debug') {
  Row() {
    Text('开发者选项').fontSize(16).flexGrow(1);
    Image($r('app.media.ic_chevron_right')).width(16).height(16);
  }
  .padding(16)
  .onClick(() => {
    router.pushUrl({ url: 'pages/DevMenuPage' }).catch((err: BusinessError): void => {
      console.error(`pushDevMenu failed: ${JSON.stringify(err)}`);
    });
  });
}
```

(Use whatever Image/Text/Row tokens match the surrounding rows in the file — `$r('app.media.ic_chevron_right')` is illustrative; reuse the actual asset id used by neighbouring rows.)

- [ ] **Step 3: Build + lint**

```bash
hvigorw assembleHap
codelinter -c ./code-linter.json5 . --fix
```

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/pages/ConfigPage.ets
git commit -m "feat(client): debug-only DevMenu entry row in ConfigPage"
```

### Task 2.7: Phase B end-to-end smoke (manual)

- [ ] **Step 1: Build + install on emulator**

```bash
hvigorw assembleHap
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

- [ ] **Step 2: Manually verify**

1. Open Settings page → "开发者选项" row visible (debug build only).
2. Pick `本地`, Apply. Confirm next launch routes to `http://<android-emulator-host>:8000` (force-close + reopen + observe in DevEco logs).
3. Pick `PR 预览`, paste a known preview URL (or rely on Phase C dropdown). Apply. Observe routing change.
4. Pick `Staging`. Apply. Observe routing back to `https://happyword.cool`.
5. After each Apply, confirm parent login + device binding ask to re-link.

- [ ] **Step 3: Build a release-mode HAP (Optional)**

```bash
hvigorw assembleHap --mode release
```
Confirm the "开发者选项" row is absent in the resulting Settings page.

---

## Phase C — Manifest workflow + JSON schema (Task 3.x)

### Task 3.1: Empty starter manifest

**Files:**
- Create: `docs/preview-urls.json`

- [ ] **Step 1: Write the file**

```json
{
  "schema_version": 1,
  "updated_at": null,
  "previews": []
}
```

- [ ] **Step 2: Commit**

```bash
git add docs/preview-urls.json
git commit -m "chore: seed empty preview-urls.json (kept fresh by preview-manifest.yml)"
```

### Task 3.2: `update_preview_manifest.mjs` script

**Files:**
- Create: `server/scripts/update_preview_manifest.mjs`

- [ ] **Step 1: Write the script**

```javascript
#!/usr/bin/env node
// Updates docs/preview-urls.json based on a PR-event payload.
// Usage: node server/scripts/update_preview_manifest.mjs <event-json-path> <github-token>

import { readFile, writeFile } from 'node:fs/promises';
import { Octokit } from '@octokit/rest';

const MANIFEST_PATH = 'docs/preview-urls.json';
const SCHEMA_VERSION = 1;
const PREVIEWS_CAP = 50;

async function main() {
  const eventPath = process.argv[2] || process.env.GITHUB_EVENT_PATH;
  const token = process.argv[3] || process.env.GITHUB_TOKEN;
  if (!eventPath || !token) {
    console.error('Usage: update_preview_manifest.mjs <event-json> <token>');
    process.exit(2);
  }

  const event = JSON.parse(await readFile(eventPath, 'utf8'));
  const action = event.action;
  const pr = event.pull_request;
  const owner = event.repository.owner.login;
  const repo = event.repository.name;

  let manifest = await loadManifest();

  if (action === 'closed') {
    manifest.previews = manifest.previews.filter(r => r.pr !== pr.number);
  } else if (['opened', 'synchronize', 'reopened'].includes(action)) {
    const url = await resolveDeployUrl(owner, repo, pr.head.sha, token);
    if (!url) {
      console.warn(`No deploy URL yet for PR #${pr.number}; will retry next event.`);
    } else {
      manifest.previews = manifest.previews.filter(r => r.pr !== pr.number);
      manifest.previews.unshift({
        pr: pr.number,
        title: (pr.title || '').replace(/[\r\n]+/g, ' ').slice(0, 80),
        branch: pr.head.ref,
        url,
        author: pr.user.login,
        head_sha: pr.head.sha.slice(0, 7),
        updated_at: new Date().toISOString(),
      });
    }
  }

  manifest.previews.sort((a, b) => b.pr - a.pr);
  manifest.previews = manifest.previews.slice(0, PREVIEWS_CAP);
  manifest.updated_at = new Date().toISOString();
  manifest.schema_version = SCHEMA_VERSION;

  await writeFile(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n');
  console.log(`Wrote ${MANIFEST_PATH} with ${manifest.previews.length} previews.`);
}

async function loadManifest() {
  try {
    const raw = await readFile(MANIFEST_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed.schema_version === SCHEMA_VERSION && Array.isArray(parsed.previews)) {
      return parsed;
    }
  } catch (_err) { /* fall through */ }
  return { schema_version: SCHEMA_VERSION, updated_at: null, previews: [] };
}

async function resolveDeployUrl(owner, repo, sha, token) {
  const oct = new Octokit({ auth: token });
  const deployments = await oct.paginate(oct.rest.repos.listDeployments, {
    owner, repo, sha, per_page: 100,
  });
  for (const d of deployments.sort((a, b) => b.id - a.id)) {
    const statuses = await oct.paginate(oct.rest.repos.listDeploymentStatuses, {
      owner, repo, deployment_id: d.id, per_page: 100,
    });
    for (const s of statuses) {
      const url = s.environment_url || s.target_url;
      if (s.state === 'success' && url && url.includes('git-')) {
        // Preview deploys carry `git-` in their alias.
        return url;
      }
    }
  }
  return null;
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Add a one-line README note explaining why a `.mjs` lives under `server/scripts/`**

Append to `server/scripts/README.md` (create if missing):

```markdown
## update_preview_manifest.mjs

Node 20 script invoked by `.github/workflows/preview-manifest.yml` to keep
`docs/preview-urls.json` in sync with open PRs. Lives here for proximity to
other CI scripts even though it's JavaScript, not Python.
```

- [ ] **Step 3: Commit**

```bash
git add server/scripts/update_preview_manifest.mjs server/scripts/README.md
git commit -m "feat(ci): script that maintains docs/preview-urls.json from PR events"
```

### Task 3.3: `preview-manifest.yml` workflow

**Files:**
- Create: `.github/workflows/preview-manifest.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: preview-manifest

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]
  workflow_dispatch: {}

permissions:
  contents: write
  pull-requests: read

concurrency:
  group: preview-manifest
  cancel-in-progress: false

jobs:
  update_manifest:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout main
        uses: actions/checkout@v4
        with:
          ref: main
          token: ${{ secrets.GITHUB_TOKEN }}

      - name: Setup Node 20
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install Octokit
        run: npm install --no-save @octokit/rest

      - name: Update manifest
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: node server/scripts/update_preview_manifest.mjs "$GITHUB_EVENT_PATH" "$GITHUB_TOKEN"

      - name: Commit + push if changed
        run: |
          git config user.email "[email protected]"
          git config user.name "github-actions[bot]"
          git add docs/preview-urls.json
          if git diff --staged --quiet; then
            echo "No changes."
            exit 0
          fi
          PR_NUM="${{ github.event.pull_request.number }}"
          git commit -m "chore: refresh preview-urls.json (PR #${PR_NUM})"
          git push origin main
```

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/preview-manifest.yml'))"
```

- [ ] **Step 3: Confirm `server-ci.yml` won't fire on `docs/**` changes**

```bash
grep -n "paths:" .github/workflows/server-ci.yml
```
Expected: a `paths:` section listing `server/**` (or absence of a top-level paths gate that would catch docs). If `docs/**` is currently matched, edit to add `paths-ignore: ['docs/**']`. (Verify by inspection.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/preview-manifest.yml
git commit -m "ci(client): preview-manifest.yml — keep docs/preview-urls.json fresh"
```

### Task 3.4: Phase C smoke (manual after merge)

- [ ] **Step 1: Open one disposable PR**

```bash
git checkout -b chore/preview-manifest-smoke
git commit --allow-empty -m "smoke: trigger preview-manifest workflow"
git push -u origin chore/preview-manifest-smoke
gh pr create --title "smoke: preview manifest" --body "Disposable smoke PR."
```

- [ ] **Step 2: Watch the workflow**

Once Vercel deploys the preview, `preview-manifest.yml` should commit a row to `docs/preview-urls.json` on `main` within ~5 min. Verify by opening the file on the GitHub web UI.

- [ ] **Step 3: Open DevMenu on debug emulator → confirm the new PR row appears in the dropdown**

(Per Task 2.5's Apply flow.)

- [ ] **Step 4: Close the smoke PR**

Confirm the row disappears from `docs/preview-urls.json` within ~30 s.

---

## Phase D — Documentation + lock-in (Task 4.x)

### Task 4.1: Root README — env-switcher subsection

**Files:**
- Modify: `README.md` (project root)

- [ ] **Step 1: Insert a new section right after the existing `## Server` section**

```markdown
## Client backend env switching

Debug builds of the HarmonyOS app expose a "开发者选项" row on the Settings
page that opens a DevMenu allowing the tester to point the app at:
- 本地 (`http://<android-emulator-host>:8000`)
- PR 预览 (any open PR's Vercel preview URL — picked from a dropdown
  populated by `docs/preview-urls.json` or pasted manually)
- Staging (`https://happyword.cool`)

Release builds **never** see this row and are hard-locked to staging.
Switching environments hard-resets cloud session state (re-login + re-pair
required); local progress (battle stats, learned-word state) is preserved.

Spec: [`docs/superpowers/specs/2026-05-06-client-backend-env-switcher-design.md`](docs/superpowers/specs/2026-05-06-client-backend-env-switcher-design.md)
Tester runbook: [`docs/superpowers/runbooks/dev-menu-runbook.md`](docs/superpowers/runbooks/dev-menu-runbook.md)
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: client backend env switching section in root README"
```

### Task 4.2: Tester runbook

**Files:**
- Create: `docs/superpowers/runbooks/dev-menu-runbook.md`

- [ ] **Step 1: Write the runbook**

```markdown
# DevMenu runbook (testers)

This runbook walks a tester through pointing a debug-build emulator at a
specific PR's preview backend.

## Prerequisites

- A debug-mode HAP installed on a HarmonyOS emulator or device.
- The PR you want to test against is open and has a green Vercel preview
  deploy. Verify on github.com/terryma2024/happyword that the PR shows a
  Vercel "Preview" URL.

## Steps

1. Launch the app. From the bottom navigation, tap **Settings**.
2. Scroll to the bottom and tap **开发者选项**.
3. Under **后端环境**, tap the **PR 预览** radio.
4. Either:
   - Pick the PR from the dropdown labelled **Pick a preview ▼** (auto-
     populated from the manifest, refreshed every 5 minutes), OR
   - Paste the full preview URL into the **Or paste a preview URL** field
     (must start with `https://` and end with `.vercel.app`).
5. Tap **Apply (会清除本地会话)**. The app will:
   - validate the URL with a 2-second `/api/v1/public/health` probe,
   - clear your parent login + device binding (you'll need to re-link),
   - persist the choice and return to the Home page.

## Switching back to staging

1. Reopen Settings → 开发者选项.
2. Tap the **Staging** radio.
3. Tap **Apply**. Cloud session clears again; you'll be back on the
   normal staging endpoint after re-login.

## Troubleshooting

- "无法访问该 URL" toast: the preview URL doesn't respond to `/api/v1/public/health`
  within 2 s. Confirm the deploy finished (sometimes takes ~3 min after
  PR push) and try again.
- The dropdown shows "Manifest 状态: 0 个有效预览": tap **刷新 manifest**.
  If still empty, the GitHub workflow may not have run yet — check
  https://github.com/terryma2024/happyword/actions/workflows/preview-manifest.yml
  for the latest run.
- After switching, the app crashes on startup: file an issue and revert
  to Staging via DevMenu (the env switcher itself never crashes the
  next launch — only the chosen backend's responses can).
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/runbooks/dev-menu-runbook.md
git commit -m "docs: tester-facing DevMenu runbook"
```

### Task 4.3: CLAUDE.md + AGENTS.md note

**Files:**
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add one bullet under the existing `## Rules` section in BOTH files**

Append:
```markdown
- The HarmonyOS DevMenu (`pages/DevMenuPage.ets`) and any code that
  switches the backend base URL MUST stay debug-only — gate every entry
  point on `BuildProfile.BUILD_MODE_NAME === 'debug'`. Release builds
  must remain hard-locked to `STAGING_BASE_URL` (or `PROD_BASE_URL` once
  V0.7+ flips it non-null).
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs: lock in the debug-only constraint for the env-switcher"
```

### Task 4.4: Bump spec status

**Files:**
- Modify: `docs/superpowers/specs/2026-05-06-client-backend-env-switcher-design.md`

- [ ] **Step 1: Replace the Status line at the top**

Find:
```markdown
> **Status:** approved 2026-05-06 — implementation pending.
```

Replace with:
```markdown
> **Status:** landed 2026-05-XX (replace XX with the actual merge date).
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-06-client-backend-env-switcher-design.md
git commit -m "docs(spec): mark client-backend-env-switcher design as landed"
```

---

## Final acceptance check (matches spec §9)

- [ ] All four phases (A–D) merged.
- [ ] Release-mode `effectiveServerBaseUrl()` provably hard-locked to `STAGING_BASE_URL` (Task 1.2's `releaseAlwaysLandsOnStaging` test passes; manually flipping the test data to non-staging would fail it).
- [ ] Debug build can switch Local / Preview (paste OR dropdown) / Staging — verified by Task 2.7's manual smoke.
- [ ] `docs/preview-urls.json` updates within 5 min of a PR open and within 30 s of a PR close — verified by Task 3.4's smoke PR.
- [ ] A new tester following `docs/superpowers/runbooks/dev-menu-runbook.md` succeeds without developer help.
- [ ] Root `README.md` has the env-switcher section (Task 4.1).
- [ ] CLAUDE.md / AGENTS.md note added (Task 4.3).

---

## Open execution choice

After the engineer (or subagent) reviews this plan, choose execution mode:

1. **Subagent-Driven (recommended)** — fresh subagent per task with two-stage review.
2. **Inline Execution** — batch tasks in this session with checkpoints.
