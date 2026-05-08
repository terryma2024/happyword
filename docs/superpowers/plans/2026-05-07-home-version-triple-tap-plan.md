# HomePage Version Label + Triple-Tap → DevMenu Card Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire a debug-only `v0.6.0(YYMMDDHHmm)` label onto HomePage's top-left (minute precision — seconds dropped), make a triple-tap (**1500ms** `VersionTripleTap` window) navigate to `DevMenuPage`, and render backend picks as **cards** (**v0.6.1+ unified grid** — Local, Staging, manifest previews — tap-to-apply per spec §11). Bumping `AppScope/app.json5` `versionName` from `1.0.0` → `0.6.0` is part of this plan (matches the V0.6 in-flight major version in [`docs/WordMagicGame_roadmap.md`](../../WordMagicGame_roadmap.md)).

**Architecture:** Two new pure helper modules (`VersionTripleTap`, `BuildInfo`) keep the counting and timestamp formatting unit-testable. `HomePage` mounts the version `Text` (gated on `BuildProfile.BUILD_MODE_NAME === 'debug'`), holds a `VersionTripleTap` instance, and pushes `pages/DevMenuPage` with `params: { presetEnv: 'preview' }` on the third tap (param kept for compatibility). **`DevMenuPage`** implements the **unified card grid + tap-to-apply** flow — see spec **§11** and live `DevMenuPage.ets` (Phase C in this plan is archival).

**Tech Stack:** ArkTS / HarmonyOS NEXT, ArkUI declarative components, `@ohos/hypium` v1 unit tests, `@kit.TestKit` (`Driver`, `ON`) UI tests, `@ohos.bundle.bundleManager`, project-existing `BackendEnv` / `PreviewManifestService` / **`PREVIEW_MANIFEST_JSON_URL`** (manifest origin pinned to production — §12 of this spec).

**Spec:** [`docs/superpowers/specs/2026-05-07-home-version-triple-tap-design.md`](../specs/2026-05-07-home-version-triple-tap-design.md)

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `AppScope/app.json5` | modify | Bump `versionName: "1.0.0"` → `"0.6.0"` to match the V0.6 in-flight major version on the roadmap. |
| `entry/src/main/ets/services/VersionTripleTap.ets` | **create** | Pure stateful counter — `onTap(nowMs)` returns true on the third tap inside the configured window. |
| `entry/src/test/VersionTripleTap.test.ets` | **create** | Hypium unit tests for the counter (5 cases). |
| `entry/src/main/ets/services/BuildInfo.ets` | **create** | `formatBuildTimestamp(epochMs)`, `readVersionInfo()` (async via `bundleManager`), `formatVersionLabel(info)`. |
| `entry/src/test/BuildInfo.test.ets` | **create** | Unit tests for `formatBuildTimestamp` (2 cases). |
| `entry/src/test/List.test.ets` | modify | Register the two new test suites. |
| `entry/src/main/ets/pages/HomePage.ets` | modify | Add top-left version `Text`, hold `VersionTripleTap` instance, push `DevMenuPage` on triple-tap. Debug-only. |
| `entry/src/main/ets/pages/DevMenuPage.ets` | modify | Unified card grid (Local, Staging, manifest previews); tap-to-apply via `onCardTap`; Preview probes may use bypass-secret dialog. See live `DevMenuPage.ets` — `presetEnv` from HomePage triple-tap is kept on the route for compatibility but not read in `aboutToAppear`. |
| `entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets` | **create** | UI test: label exists; triple-tap navigates to DevMenu (assert **`Developer options`** header — Apply removed in v0.6.1); gap exceeding **1500ms** window does not fire. |
| `entry/src/ohosTest/ets/test/DevMenuCardList.ui.test.ets` | **create** | UI test: Local + Staging cards always present; optional preview cards when manifest loads; **staging card tap** runs apply pipeline and returns to Home (`replaceUrl`). Manifest GET uses **`PREVIEW_MANIFEST_JSON_URL`** only. |
| `entry/src/ohosTest/ets/test/List.test.ets` | modify | Register both new UI suites. Order matters — see Task D3. |

No new `BackendEnv`, `PreviewManifestService`, `RemoteWordPackConfig`, or build profile changes beyond what the backend-env-switcher spec records (**`PREVIEW_MANIFEST_JSON_URL`** pinning). The plan adds two service modules, modifies two pages, and adds two UI test files.

---

## Phase A — Pure helpers (no device, no UI)

### Task A0: Bump `versionName` to track the roadmap

**Files:**
- Modify: `AppScope/app.json5`

This is a config bump only. Doing it first means every later phase sees the correct value when it reads `bundleManager.getBundleInfoForSelf().versionName`.

- [ ] **Step 1: Edit `AppScope/app.json5`**

Change line 6:

```diff
-    "versionName": "1.0.0",
+    "versionName": "0.6.0",
```

`versionCode` stays at `1000000` — bumping it is a separate concern (publish-time, not source-of-truth). The 7-digit code already encodes a minor channel, and we don't need to renumber until we cut a real release.

- [ ] **Step 2: Sanity-check the build still compiles**

```sh
hvigorw assembleHap
```
Expected: exit 0. The change is a JSON value swap; if it breaks, something else is wrong.

- [ ] **Step 3: Commit**

```sh
git add AppScope/app.json5
git commit -m "chore(client): bump versionName to 0.6.0 to track V0.6 in-flight roadmap milestone"
```

---

### Task A1: `VersionTripleTap` service + tests

**Files:**
- Create: `entry/src/main/ets/services/VersionTripleTap.ets`
- Create: `entry/src/test/VersionTripleTap.test.ets`

- [ ] **Step 1: Write the failing tests**

Create `entry/src/test/VersionTripleTap.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { VersionTripleTap } from '../main/ets/services/VersionTripleTap';

export default function versionTripleTapTest(): void {
  describe('VersionTripleTap', () => {
    it('firesOnThirdTapInsideWindow', 0, () => {
      const t: VersionTripleTap = new VersionTripleTap(1000);
      expect(t.onTap(0)).assertEqual(false);
      expect(t.onTap(200)).assertEqual(false);
      expect(t.onTap(400)).assertEqual(true);
    });

    it('doesNotReFireOnFourthTap', 0, () => {
      const t: VersionTripleTap = new VersionTripleTap(1000);
      t.onTap(0);
      t.onTap(100);
      expect(t.onTap(200)).assertEqual(true);
      // Tap 4 inside window must NOT fire — counter resets after firing.
      expect(t.onTap(205)).assertEqual(false);
      expect(t.onTap(210)).assertEqual(false);
      expect(t.onTap(215)).assertEqual(true);
    });

    it('resetsWhenGapExceedsWindow', 0, () => {
      const t: VersionTripleTap = new VersionTripleTap(1000);
      expect(t.onTap(0)).assertEqual(false);
      expect(t.onTap(500)).assertEqual(false);
      // 1500ms gap exceeds the 1000ms window → counter resets.
      expect(t.onTap(2001)).assertEqual(false);
      expect(t.pendingCount()).assertEqual(1);
    });

    it('honoursCustomWindow', 0, () => {
      const fast: VersionTripleTap = new VersionTripleTap(500);
      expect(fast.onTap(0)).assertEqual(false);
      expect(fast.onTap(200)).assertEqual(false);
      expect(fast.onTap(400)).assertEqual(true);

      const slow: VersionTripleTap = new VersionTripleTap(500);
      expect(slow.onTap(0)).assertEqual(false);
      expect(slow.onTap(300)).assertEqual(false);
      // 700 - 300 = 400 ≤ 500, this DOES fire. Use a larger gap to
      // assert reset behaviour at the custom window boundary.
      expect(slow.onTap(900)).assertEqual(false);
      expect(slow.pendingCount()).assertEqual(1);
    });

    it('pendingCountReflectsInternalCounter', 0, () => {
      const t: VersionTripleTap = new VersionTripleTap(1000);
      expect(t.pendingCount()).assertEqual(0);
      t.onTap(0);
      expect(t.pendingCount()).assertEqual(1);
      t.onTap(100);
      expect(t.pendingCount()).assertEqual(2);
      t.onTap(200);
      // Counter zeroed after firing on tap 3.
      expect(t.pendingCount()).assertEqual(0);
    });
  });
}
```

- [ ] **Step 2: Run tests, confirm they fail**

Run from project root:
```sh
hvigorw -p module=entry@default test
```
Expected: compile failure on `Cannot find module '../main/ets/services/VersionTripleTap'`. (We have not registered the suite yet, so the compile failure is the only signal at this stage — that's fine.)

- [ ] **Step 3: Write the minimal implementation**

Create `entry/src/main/ets/services/VersionTripleTap.ets`:

```typescript
/**
 * Stateful triple-tap detector. UI-agnostic so it can be unit-tested
 * with a fake clock (`onTap(fakeNowMs)`).
 *
 * Lifecycle:
 *  - First tap (or any tap with `now - lastTapMs > windowMs`): reset count to 1.
 *  - Subsequent taps inside the window: increment.
 *  - On the 3rd tap: return true and zero the counter so a 4th tap
 *    does not re-fire.
 */
export class VersionTripleTap {
  private count: number = 0;
  private lastTapMs: number = 0;
  private readonly windowMs: number;

  constructor(windowMs: number = 1500) {
    this.windowMs = windowMs;
  }

  /** Returns true exactly when this tap completes a triple-tap. */
  onTap(nowMs: number): boolean {
    if (nowMs - this.lastTapMs > this.windowMs) {
      this.count = 1;
    } else {
      this.count += 1;
    }
    this.lastTapMs = nowMs;
    if (this.count >= 3) {
      this.count = 0;
      this.lastTapMs = 0;
      return true;
    }
    return false;
  }

  /** For tests: peek the internal counter without advancing it. */
  pendingCount(): number {
    return this.count;
  }
}
```

- [ ] **Step 4: Wire the suite into the test list**

Edit `entry/src/test/List.test.ets`. Add the import near the other imports:

```typescript
import versionTripleTapTest from './VersionTripleTap.test';
```

And the call inside `testsuite()`, after `barcodeImageDecoderTest();`:

```typescript
  versionTripleTapTest();
```

- [ ] **Step 5: Run tests, confirm they pass**

Run:
```sh
hvigorw -p module=entry@default test
```
Expected: build succeeds; the hypium report shows `VersionTripleTap` describe with 5 passing `it` blocks. No new failures elsewhere.

- [ ] **Step 6: Commit**

```sh
git add entry/src/main/ets/services/VersionTripleTap.ets \
        entry/src/test/VersionTripleTap.test.ets \
        entry/src/test/List.test.ets
git commit -m "feat(client): VersionTripleTap pure stateful tap-counter helper"
```

---

### Task A2: `BuildInfo` service + tests

**Files:**
- Create: `entry/src/main/ets/services/BuildInfo.ets`
- Create: `entry/src/test/BuildInfo.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: Write the failing tests**

Create `entry/src/test/BuildInfo.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { formatBuildTimestamp, formatVersionLabel, VersionInfo } from '../main/ets/services/BuildInfo';

export default function buildInfoTest(): void {
  describe('formatBuildTimestamp', () => {
    it('produces10CharDigitString', 0, () => {
      const out: string = formatBuildTimestamp(0);
      expect(out.length).assertEqual(10);
      // Every char is a digit.
      for (let i: number = 0; i < out.length; i++) {
        const code: number = out.charCodeAt(i);
        expect(code >= 48 && code <= 57).assertTrue();
      }
    });

    it('roundtripsViaDateConstructor', 0, () => {
      // Use a Date built locally so the assertion is timezone-stable.
      // 2026-05-07 20:52:34 local time — seconds intentionally non-zero
      // so the assertion proves they're dropped, not coincidentally :00.
      const d: Date = new Date(2026, 4, 7, 20, 52, 34);
      const out: string = formatBuildTimestamp(d.getTime());
      // YY=26, MM=05, DD=07, HH=20, mm=52 → '2605072052'.
      // Seconds (34) are intentionally absent.
      expect(out).assertEqual('2605072052');
    });
  });

  describe('formatVersionLabel', () => {
    it('composesLabel', 0, () => {
      const info: VersionInfo = { versionName: '0.6.0', timestamp: '2605072052' };
      expect(formatVersionLabel(info)).assertEqual('v0.6.0(2605072052)');
    });

    it('preservesFallbackVersionName', 0, () => {
      const info: VersionInfo = { versionName: '?.?.?', timestamp: '2605072052' };
      expect(formatVersionLabel(info)).assertEqual('v?.?.?(2605072052)');
    });
  });
}
```

- [ ] **Step 2: Run tests, confirm they fail**

```sh
hvigorw -p module=entry@default test
```
Expected: compile failure on `Cannot find module '../main/ets/services/BuildInfo'`.

- [ ] **Step 3: Write the minimal implementation**

Create `entry/src/main/ets/services/BuildInfo.ets`:

```typescript
import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@ohos.base';

export interface VersionInfo {
  versionName: string;
  /** YYMMDDHHmm, local time, minute precision. */
  timestamp: string;
}

const FALLBACK_VERSION_NAME: string = '?.?.?';

/**
 * Format an epoch millis value as YYMMDDHHmm in the device's local
 * time. Pure function — deterministic given an input ms. Seconds are
 * intentionally dropped: minute precision is enough to identify which
 * install corresponds to which build, and avoids visual churn from
 * re-installs within the same minute.
 */
export function formatBuildTimestamp(epochMs: number): string {
  const d: Date = new Date(epochMs);
  const yy: string = String(d.getFullYear() % 100).padStart(2, '0');
  const mm: string = String(d.getMonth() + 1).padStart(2, '0');
  const dd: string = String(d.getDate()).padStart(2, '0');
  const hh: string = String(d.getHours()).padStart(2, '0');
  const mn: string = String(d.getMinutes()).padStart(2, '0');
  return `${yy}${mm}${dd}${hh}${mn}`;
}

/**
 * Read versionName + bundle update time from the OHOS bundle manager
 * and return a {versionName, timestamp} pair. On any failure returns
 * the fallback `?.?.?` versionName and `formatBuildTimestamp(now)`.
 *
 * `updateTime` corresponds to when the HAP was last installed/updated
 * on this device — close enough to "build identity" for dev/QA loops
 * without requiring a custom hvigor plugin (see spec §6).
 */
export async function readVersionInfo(): Promise<VersionInfo> {
  try {
    const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    );
    const name: string = (info.versionName !== undefined && info.versionName.length > 0)
      ? info.versionName
      : FALLBACK_VERSION_NAME;
    const ms: number = (info.updateTime !== undefined && info.updateTime > 0)
      ? info.updateTime
      : Date.now();
    return { versionName: name, timestamp: formatBuildTimestamp(ms) };
  } catch (err) {
    console.error(`BuildInfo.readVersionInfo failed: ${JSON.stringify(err as BusinessError)}`);
    return { versionName: FALLBACK_VERSION_NAME, timestamp: formatBuildTimestamp(Date.now()) };
  }
}

/** Convenience composer: `v{name}({timestamp})`. */
export function formatVersionLabel(info: VersionInfo): string {
  return `v${info.versionName}(${info.timestamp})`;
}
```

- [ ] **Step 4: Wire the suite into the test list**

Edit `entry/src/test/List.test.ets`. Add the import:

```typescript
import buildInfoTest from './BuildInfo.test';
```

And the call inside `testsuite()`, after `versionTripleTapTest();`:

```typescript
  buildInfoTest();
```

- [ ] **Step 5: Run tests, confirm they pass**

```sh
hvigorw -p module=entry@default test
```
Expected: hypium report shows `formatBuildTimestamp` (2 it blocks) and `formatVersionLabel` (2 it blocks) all pass. No regressions in earlier suites.

- [ ] **Step 6: Commit**

```sh
git add entry/src/main/ets/services/BuildInfo.ets \
        entry/src/test/BuildInfo.test.ets \
        entry/src/test/List.test.ets
git commit -m "feat(client): BuildInfo service — read versionName + updateTime, format YYMMDDHHmm"
```

---

## Phase B — HomePage version label

### Task B1: HomePage adds version label + triple-tap handler

**Files:**
- Modify: `entry/src/main/ets/pages/HomePage.ets`

This task does not get its own unit test — the helper logic is covered by Task A1 / A2, and the on-device behaviour is asserted by the UI tests in Phase D. We're left with the wiring inside HomePage's `build()`.

- [ ] **Step 1: Add imports**

Edit `entry/src/main/ets/pages/HomePage.ets`. Add the new imports immediately after the existing `CloudCredentials` import (line 25 area):

```typescript
import BuildProfile from 'BuildProfile';
import { VersionTripleTap } from '../services/VersionTripleTap';
import { formatVersionLabel, readVersionInfo, VersionInfo } from '../services/BuildInfo';
```

- [ ] **Step 2: Add @State + private fields**

Inside `struct HomePage`, near the other `@State` declarations (around line 73), add:

```typescript
  @State private versionLabel: string = '';
  private versionTap: VersionTripleTap = new VersionTripleTap();
```

- [ ] **Step 3: Hydrate `versionLabel` in `aboutToAppear`**

Inside `aboutToAppear()`, after `this.refreshWrongCount();` (around line 103), append:

```typescript
    if (BuildProfile.BUILD_MODE_NAME === 'debug') {
      readVersionInfo().then((v: VersionInfo): void => {
        this.versionLabel = formatVersionLabel(v);
      }).catch((err: BusinessError): void => {
        console.error(`HomePage.readVersionInfo failed: ${JSON.stringify(err)}`);
      });
    }
```

The debug gate avoids the bundleManager round-trip in release builds where the label is never rendered.

- [ ] **Step 4: Render the label inside the outer `Stack`**

Inside `build()`'s outer `Stack` (the one that ends with `.alignContent(Alignment.TopEnd)` near line 443), add a new top-level child *after* the existing icon `Row({ space: 12 })...margin({ top: 16, right: 16 });` block. The new child:

```typescript
      if (BuildProfile.BUILD_MODE_NAME === 'debug') {
        Column() {
          Text(this.versionLabel)
            .id('HomeVersionLabel')
            .fontSize(11)
            .fontColor('#999999')
            .padding({ left: 16, top: 16, right: 16, bottom: 8 })
            .onClick((): void => {
              if (this.versionTap.onTap(Date.now())) {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/DevMenuPage',
                  params: { presetEnv: 'preview' } as Record<string, string>,
                }).catch((err: BusinessError): void => {
                  console.error(`HomePage: pushUrl DevMenuPage (triple-tap) failed: ${JSON.stringify(err)}`);
                });
              }
            });
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%');
      }
```

The Stack's `Alignment.TopEnd` aligns Stack-level children, but each child can be wrapped in a `Column().alignItems(HorizontalAlign.Start)` to anchor its inner content left, so the version label sits at the top-left without disturbing the right-side icon row's layout.

- [ ] **Step 5: Build the HAP and run codelinter**

```sh
hvigorw assembleHap
```
Expected: exit 0, `.hap` produced.

```sh
codelinter -c ./code-linter.json5 . --fix
```
Expected: exit 0, no errors. Re-run with `--fix` until clean.

- [ ] **Step 6: Run no-device unit tests**

```sh
hvigorw -p module=entry@default test
```
Expected: all existing + Task A1/A2 suites pass.

- [ ] **Step 7: Commit**

```sh
git add entry/src/main/ets/pages/HomePage.ets
git commit -m "feat(client): HomePage version label + triple-tap → DevMenuPage (debug-only)"
```

---

## Phase C — DevMenuPage card refactor

> **Revision 2026-05-08:** The collapsible section below records the **v0.6.0** “preview-only cards + `presetEnv` + Apply” migration. **Shipped main** is **v0.6.1+**: unified Local / Staging / Preview card grid, **tap-to-apply** (`onCardTap`), optional **bypass-secret** dialog for Preview probes, manifest fetch **only** via **`PREVIEW_MANIFEST_JSON_URL`**, and **`presetEnv` not consumed** in `aboutToAppear`. Canonical implementation: `entry/src/main/ets/pages/DevMenuPage.ets`; boundary notes: design spec §12.

### Task C1: DevMenuPage — align with live `DevMenuPage.ets`

**Files:**

- Canonical: `entry/src/main/ets/pages/DevMenuPage.ets`

- [ ] **Step 1: Confirm behaviour matches spec §12**

Unified card grid; Preview rows use `DevMenuPreviewCard_<pr>`; card tap runs env switch / probe / audit / toast; no separate Apply control.

- [ ] **Step 2: Build the HAP and run codelinter**

```sh
hvigorw assembleHap
```

```sh
codelinter -c ./code-linter.json5 . --fix
```

- [ ] **Step 3: Run no-device unit tests**

```sh
hvigorw -p module=entry@default test
```

- [ ] **Step 4: Commit** (when changing DevMenu in this branch)

```sh
git add entry/src/main/ets/pages/DevMenuPage.ets
git commit -m "feat(client): DevMenuPage unified env cards + tap-to-apply"
```

<details>
<summary>Archived steps (v0.6.0 preview-only list — superseded)</summary>

### Task C1 (archived): preview list → `previewCard` + `presetEnv`

**Files:**
- Modify: `entry/src/main/ets/pages/DevMenuPage.ets`

- [ ] **Step 1: Honour `presetEnv` after hydrate** … **Step 3: Replace inner manifest renderer** — see git history / pre-v0.6.1 plan revisions for full snippets (`previewCard` @Builder, scroll height 320).

</details>

---

## Phase D — UI tests (on-device)

### Task D1: `HomeVersionTap.ui.test.ets`

**Files:**
- Create: `entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets`

UI tests run in `ohosTest`, which always builds in debug mode, so `BuildProfile.BUILD_MODE_NAME === 'debug'` is always true here and `HomeVersionLabel` is always present.

- [ ] **Step 1: Write the UI test file**

Create `entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets`. **Do not paste stale snippets here** — the canonical source is checked in at [`entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets`](../../../entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets).

**Invariants to preserve when editing:**

- Triple-tap uses **one cached `Component`** for three `.click()` calls so slow emulators stay inside **`VersionTripleTap`'s 1500ms** window.
- After navigation, assert **`Developer options`** (v0.6.1 removed **Apply**).
- Gap case: **2500ms** wait between taps 2 and 3 so the counter resets (`> 1500ms` window).

- [ ] **Step 2: Build and install the test HAP**

```sh
hvigorw assembleHap
```
Locate the `entry-ohosTest-*.hap` under `entry/build/` and `hdc install` it (or rely on `scripts/run_ui_tests.sh` which installs both HAPs).

- [ ] **Step 3: Wire the suite into the UI test list (Task D3) before running**

Wait until Task D3 to run on device — both new UI tests will be wired together so we run them in one device pass.

---

### Task D2: `DevMenuCardList.ui.test.ets`

**Files:**
- Create: `entry/src/ohosTest/ets/test/DevMenuCardList.ui.test.ets`

Manifest GET for DevMenu uses **`PREVIEW_MANIFEST_JSON_URL`** only (production); UI tests still inject the mock base URL for **`effectiveServerBaseUrl()`** traffic — see `List.test.ets` header.

- [ ] **Step 1: Write the UI test file**

Create `entry/src/ohosTest/ets/test/DevMenuCardList.ui.test.ets`. **Canonical source:** [`entry/src/ohosTest/ets/test/DevMenuCardList.ui.test.ets`](../../../entry/src/ohosTest/ets/test/DevMenuCardList.ui.test.ets).

**Suites (3 `it` blocks):**

1. `localAndStagingCardsAlwaysPresent` — `DevMenuLocalCard` / `DevMenuStagingCard`; `Refresh manifest`.
2. `previewCardsRenderWhenManifestAvailable` — optional `DevMenuPreviewCard_<pr>` probe; never hard-fails when offline.
3. `stagingCardTapNavigatesBackToHome` — tap-to-apply returns to `HomeVersionLabel`; DevMenu header absent after `replaceUrl`.

**Triple-open helper:** cache `HomeVersionLabel` `Component` + three `.click()` (same rationale as `HomeVersionTap`).

- [ ] **Step 2: Build the test HAP**

```sh
hvigorw assembleHap
```

Move on to D3 to wire and run.

---

### Task D3: Wire both UI suites into `entry/src/ohosTest/ets/test/List.test.ets` and run the device pass

**Files:**
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

- [ ] **Step 1: Add imports and registration**

Edit `entry/src/ohosTest/ets/test/List.test.ets`. After `import homeToolbarLockedUiTest from './HomeToolbarLocked.ui.test';` (line 8), add:

```typescript
import homeVersionTapUiTest from './HomeVersionTap.ui.test';
import devMenuCardListUiTest from './DevMenuCardList.ui.test';
```

Inside `testsuite()`, **after** `homeToolbarLockedUiTest();` (line 65) and **before** `monsterCodexFlowUiTest();` (line 70), add:

```typescript
  // V0.6: debug-only version label + triple-tap → DevMenu navigation.
  // Order-independent: these tests press Back at the tail so HomePage
  // is reachable for the next suite. Placed right after
  // homeToolbarLockedUiTest because both are "home toolbar / top
  // chrome" smoke tests and grouping them surfaces top-screen
  // regressions early.
  homeVersionTapUiTest();
  // V0.6: DevMenuPage unified card grid (Local / Staging / previews).
  // Tap-to-apply; manifest GET uses PREVIEW_MANIFEST_JSON_URL only (not the mock base URL).
  devMenuCardListUiTest();
```

- [ ] **Step 2: Verify the device is up**

```sh
hdc list targets
```
Expected: at least one device line. If empty, start the emulator from DevEco or attach a USB device.

- [ ] **Step 3: Run the full UI suite**

```sh
scripts/run_ui_tests.sh
```
Expected output ends with `TestFinished-ResultCode: 0` and `OHOS_REPORT_CODE: 0`. The new suites should report `HomeVersionTap` (3 `it` blocks) and `DevMenuCardList` (3 `it` blocks) all passing. No regressions in earlier suites.

If the run fails with `execute timeout 5000ms`, check that `scripts/run_ui_tests.sh` invokes `aa test` with `-s timeout 30000` (it does today — see [`.cursor/dev-commands.md`](../../../.cursor/dev-commands.md) §4).

- [ ] **Step 4: Commit**

```sh
git add entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets \
        entry/src/ohosTest/ets/test/DevMenuCardList.ui.test.ets \
        entry/src/ohosTest/ets/test/List.test.ets
git commit -m "test(client): UI coverage for HomePage version triple-tap + DevMenu card list"
```

---

## Phase E — Final verification

### Task E1: Full pipeline green

**Files:** none (verification only)

- [ ] **Step 1: Build**

```sh
hvigorw assembleHap
```
Expected: exit 0.

- [ ] **Step 2: CodeLinter**

```sh
codelinter -c ./code-linter.json5 . --fix
```
Expected: exit 0, no errors.

- [ ] **Step 3: No-device unit tests**

```sh
hvigorw -p module=entry@default test
```
Expected: every existing suite + `VersionTripleTap` + `formatBuildTimestamp` + `formatVersionLabel` pass. No new warnings.

- [ ] **Step 4: On-device UI tests**

```sh
hdc list targets    # confirm device
scripts/run_ui_tests.sh
```
Expected: `TestFinished-ResultCode: 0`, `OHOS_REPORT_CODE: 0`. All earlier suites still pass; the two new suites pass.

- [ ] **Step 5: Manual smoke (optional but recommended)**

1. `hdc install` the latest debug HAP.
2. Open the app — confirm the top-left shows `v0.6.0(YYMMDDHHmm)` in small grey text (10-char timestamp, minute precision).
3. Triple-tap quickly (within **`VersionTripleTap`'s 1500ms** window) → DevMenuPage opens with the unified card grid (Local, Staging, manifest previews).
4. Tap **Staging** (or Local) — env applies immediately (**tap-to-apply**; there is no **Apply** button). Expect toast `Environment updated. Re-bind parent account if needed.` and navigation back to HomePage. Preview cards may prompt for the Vercel bypass secret on first use, then probe `/api/v1/health` on the selected `.vercel.app` URL.
5. Re-open DevMenuPage from `Settings → Developer → Backend environment` → confirm the env reflects what was just selected.
6. Build a release HAP (`hvigorw -p product=default --mode module -p module=entry@default assembleHap` with the release product) → install on device → confirm **no** version label is visible at top-left and tapping where it would have been does nothing.

- [ ] **Step 6: Final acceptance review**

Walk through `docs/superpowers/specs/2026-05-07-home-version-triple-tap-design.md` §10 where still applicable, plus **§11.9** (v0.6.1 acceptance) and **§12** (manifest URL). Tick each box. If any item fails, file a follow-up before declaring the work complete.

No commit on this task — verification only.

---

## Notes for the implementer

- **Frequent commits:** every Phase A and B/C task ends with a commit. Don't batch tasks into one giant commit; each commit must build + lint + test green on its own.
- **No new dependencies:** all the APIs used (`bundleManager`, `router`, `Driver`, `ON`, `Component`, `@ohos/hypium`) are already in `oh-package.json5`.
- **Debug-only gating:** every new HomePage code path (the `if (BuildProfile.BUILD_MODE_NAME === 'debug')` checks in steps B1.3 and B1.4) is the safety net that keeps release builds untouched. Do not remove the gate even if codelinter complains about an "unused state" — release builds will inline-elide the dead branch.
- **`router.getParams()` typing:** ArkTS treats route params as `Object`. The cast `params as Record<string, string>` is the project convention; see `entry/src/main/ets/pages/ScanBindingPage.ets` for prior art if you need a reference.
- **CodeLinter quirks:** the project enforces `avoid-overusing-custom-component-check` — prefer `@Builder` helpers over extra `@Component` structs when adding DevMenu UI. See live `DevMenuPage.ets`.
- **Mock UI server irrelevance:** `server/mock_ui_server.py` is for `effectiveServerBaseUrl()`-driven traffic. The manifest URL is **`PREVIEW_MANIFEST_JSON_URL`** inside `PreviewManifestService.ets`, so the mock plays no role here.
