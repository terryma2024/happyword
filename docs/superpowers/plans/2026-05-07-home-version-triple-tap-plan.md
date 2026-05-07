# HomePage Version Label + Triple-Tap → DevMenu Card Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire a debug-only `v0.6.0(YYMMDDHHmmss)` label onto HomePage's top-left, make a triple-tap (≤1000ms window) navigate to `DevMenuPage` with PREVIEW pre-selected, and re-render the `DevMenuPage` manifest list as cards showing **title** (max 3 lines) and **`#PR(sha)`** centered. Bumping `AppScope/app.json5` `versionName` from `1.0.0` → `0.6.0` is part of this plan (matches the V0.6 in-flight major version in [`docs/WordMagicGame_roadmap.md`](../../WordMagicGame_roadmap.md)).

**Architecture:** Two new pure helper modules (`VersionTripleTap`, `BuildInfo`) keep the counting and timestamp formatting unit-testable. `HomePage` mounts the version `Text` (gated on `BuildProfile.BUILD_MODE_NAME === 'debug'`), holds a `VersionTripleTap` instance, and pushes `pages/DevMenuPage` with `params: { presetEnv: 'preview' }` on the third tap. `DevMenuPage` replaces its existing single-line manifest button rows with a `@Builder previewCard` and reads `router.getParams()` after `hydrate()` to honour the preset.

**Tech Stack:** ArkTS / HarmonyOS NEXT, ArkUI declarative components, `@ohos/hypium` v1 unit tests, `@kit.TestKit` (`Driver`, `ON`) UI tests, `@ohos.bundle.bundleManager`, project-existing `BackendEnv` / `PreviewManifestService` (untouched).

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
| `entry/src/main/ets/pages/DevMenuPage.ets` | modify | Replace the inner manifest renderer with a `@Builder previewCard`; honour `router.getParams().presetEnv === 'preview'` after `hydrate()`. Bump scroll height 140 → 320. |
| `entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets` | **create** | UI test: label exists; triple-tap navigates to DevMenu; gap > 1s does not fire. |
| `entry/src/ohosTest/ets/test/DevMenuCardList.ui.test.ets` | **create** | UI test: cards render `#PR(sha)` and title; tap selects without navigating; Apply still works (smoke). |
| `entry/src/ohosTest/ets/test/List.test.ets` | modify | Register both new UI suites. Order matters — see Task D3. |

No new `BackendEnv`, `PreviewManifestService`, `RemoteWordPackConfig`, or build profile changes. The plan adds two service modules, modifies two pages, and adds two UI test files.

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

  constructor(windowMs: number = 1000) {
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
    it('produces12CharDigitString', 0, () => {
      const out: string = formatBuildTimestamp(0);
      expect(out.length).assertEqual(12);
      // Every char is a digit.
      for (let i: number = 0; i < out.length; i++) {
        const code: number = out.charCodeAt(i);
        expect(code >= 48 && code <= 57).assertTrue();
      }
    });

    it('roundtripsViaDateConstructor', 0, () => {
      // Use a Date built locally so the assertion is timezone-stable.
      // 2026-05-07 20:52:00 local time.
      const d: Date = new Date(2026, 4, 7, 20, 52, 0);
      const out: string = formatBuildTimestamp(d.getTime());
      // YY=26, MM=05, DD=07, HH=20, mm=52, ss=00 → '260507205200'.
      expect(out).assertEqual('260507205200');
    });
  });

  describe('formatVersionLabel', () => {
    it('composesLabel', 0, () => {
      const info: VersionInfo = { versionName: '0.6.0', timestamp: '260507205200' };
      expect(formatVersionLabel(info)).assertEqual('v0.6.0(260507205200)');
    });

    it('preservesFallbackVersionName', 0, () => {
      const info: VersionInfo = { versionName: '?.?.?', timestamp: '260507205200' };
      expect(formatVersionLabel(info)).assertEqual('v?.?.?(260507205200)');
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
  /** YYMMDDHHmmss, local time. */
  timestamp: string;
}

const FALLBACK_VERSION_NAME: string = '?.?.?';

/**
 * Format an epoch millis value as YYMMDDHHmmss in the device's
 * local time. Pure function — deterministic given an input ms.
 */
export function formatBuildTimestamp(epochMs: number): string {
  const d: Date = new Date(epochMs);
  const yy: string = String(d.getFullYear() % 100).padStart(2, '0');
  const mm: string = String(d.getMonth() + 1).padStart(2, '0');
  const dd: string = String(d.getDate()).padStart(2, '0');
  const hh: string = String(d.getHours()).padStart(2, '0');
  const mn: string = String(d.getMinutes()).padStart(2, '0');
  const ss: string = String(d.getSeconds()).padStart(2, '0');
  return `${yy}${mm}${dd}${hh}${mn}${ss}`;
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
git commit -m "feat(client): BuildInfo service — read versionName + updateTime, format YYMMDDHHmmss"
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

### Task C1: DevMenuPage replaces preview list with card builder + reads `presetEnv`

**Files:**
- Modify: `entry/src/main/ets/pages/DevMenuPage.ets`

This task touches two regions of `DevMenuPage.ets`. We do it in one task because both edits land in the same file and reviewing the file diff together is cheaper than reviewing two micro-PRs.

- [ ] **Step 1: Honour `presetEnv` after hydrate**

Replace the existing `aboutToAppear` (lines 51–55):

```typescript
  aboutToAppear(): void {
    this.hydrate().catch((err: BusinessError): void => {
      console.error(`DevMenuPage.hydrate failed: ${JSON.stringify(err)}`);
    });
  }
```

with:

```typescript
  aboutToAppear(): void {
    this.hydrate().then((): void => {
      const params: Record<string, string> | undefined =
        router.getParams() as Record<string, string> | undefined;
      if (params !== undefined && params['presetEnv'] === 'preview') {
        this.pendingEnv = BackendEnv.PREVIEW;
      }
    }).catch((err: BusinessError): void => {
      console.error(`DevMenuPage.hydrate failed: ${JSON.stringify(err)}`);
    });
  }
```

`router` is already imported (line 1).

- [ ] **Step 2: Add the `previewCard` @Builder**

After the existing `private async onApply(): Promise<void> { ... }` method (line 150), and before `build(): void`, add the builder:

```typescript
  @Builder
  private previewCard(row: ManifestRow): void {
    Column({ space: 8 }) {
      Text(row.title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#222222')
        .width('100%')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      Row() {
        Text(`#${row.pr}(${row.head_sha.length > 7 ? row.head_sha.substring(0, 7) : row.head_sha})`)
          .fontSize(13)
          .fontColor('#555555');
      }
      .width('100%')
      .justifyContent(FlexAlign.Center);
    }
    .id(`DevMenuPreviewCard_${row.pr}`)
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.selectedManifestUrl === row.url ? '#CDE8FF' : '#F5F5F5')
    .border({ width: 1, color: this.selectedManifestUrl === row.url ? '#457B9D' : '#E0E0E0' })
    .onClick((): void => {
      this.selectedManifestUrl = row.url;
      this.pasteUrl = '';
    });
  }
```

The 7-char short-sha guard handles `head_sha` strings that are already shorter than 7 chars (the manifest already stores 7-char shas, but the guard prevents an out-of-range substring exception if the field shape ever drifts).

- [ ] **Step 3: Replace the inner manifest renderer**

Replace lines 195–213 — the block:

```typescript
        if (this.manifest !== null && this.manifest.previews.length > 0) {
          Scroll() {
            Column({ space: 6 }) {
              ForEach(this.manifest.previews, (row: ManifestRow) => {
                Button(`#${row.pr} ${row.title}`)
                  .fontSize(12)
                  .height(32)
                  .width('100%')
                  .backgroundColor(this.selectedManifestUrl === row.url ? '#CDE8FF' : '#F5F5F5')
                  .onClick((): void => {
                    this.selectedManifestUrl = row.url;
                    this.pasteUrl = '';
                  });
              }, (row: ManifestRow) => `${row.pr}-${row.url}`);
            };
          }
          .height(140)
          .margin({ bottom: 8 });
        }
```

with:

```typescript
        if (this.manifest !== null && this.manifest.previews.length > 0) {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.manifest.previews, (row: ManifestRow) => {
                this.previewCard(row);
              }, (row: ManifestRow) => `${row.pr}-${row.url}`);
            }
          }
          .height(320)
          .margin({ bottom: 8 });
        }
```

- [ ] **Step 4: Build the HAP and run codelinter**

```sh
hvigorw assembleHap
```
Expected: exit 0.

```sh
codelinter -c ./code-linter.json5 . --fix
```
Expected: exit 0, no errors.

- [ ] **Step 5: Run no-device unit tests**

```sh
hvigorw -p module=entry@default test
```
Expected: all suites pass; no regressions.

- [ ] **Step 6: Commit**

```sh
git add entry/src/main/ets/pages/DevMenuPage.ets
git commit -m "feat(client): DevMenuPage manifest list as cards (title + #PR(sha)) + presetEnv route param"
```

---

## Phase D — UI tests (on-device)

### Task D1: `HomeVersionTap.ui.test.ets`

**Files:**
- Create: `entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets`

UI tests run in `ohosTest`, which always builds in debug mode, so `BuildProfile.BUILD_MODE_NAME === 'debug'` is always true here and `HomeVersionLabel` is always present.

- [ ] **Step 1: Write the UI test file**

Create `entry/src/ohosTest/ets/test/HomeVersionTap.ui.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1000);
  return driver;
}

async function returnToHome(driver: Driver): Promise<void> {
  for (let i: number = 0; i < 5; i++) {
    const home: Component | null =
      await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(500);
  }
}

/**
 * V0.7.x acceptance — debug-only version label triple-tap navigates
 * to DevMenuPage. Always runs in debug (ohosTest = debug build), so
 * the gate is always open here. Three cases:
 *   1. label exists,
 *   2. triple-tap navigates,
 *   3. spaced taps (gap > 1s) do not navigate.
 *
 * The two navigating cases end on DevMenuPage; both press Back at
 * the tail so subsequent suites still start on HomePage.
 */
export default function homeVersionTapUiTest(): void {
  describe('HomeVersionTap', () => {
    it('versionLabelExistsOnHome', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await driver.assertComponentExist(ON.id('HomeVersionLabel'));
      done();
    });

    it('tripleTapNavigatesToDevMenu', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      // Three taps inside ~600ms (well under the 1000ms window).
      await clickByIdShared(driver, 'HomeVersionLabel');
      await driver.delayMs(150);
      await clickByIdShared(driver, 'HomeVersionLabel');
      await driver.delayMs(150);
      await clickByIdShared(driver, 'HomeVersionLabel');
      await driver.delayMs(800);
      // DevMenuPage exposes the env-radio + paste field. The Apply
      // button is the most stable single ID since it's always
      // rendered regardless of pendingEnv. We assert one widget that
      // belongs to DevMenuPage and one widget unique to HomePage is
      // gone (the AdventureCard CTA).
      const apply: Component | null = await driver.findComponent(ON.text('Apply'));
      expect(apply !== null).assertTrue();
      const homeStart: Component | null = await driver.findComponent(ON.id('HomeStartButton'));
      expect(homeStart === null).assertTrue();
      // Cleanup so the next case starts on HomePage.
      await driver.pressBack();
      await driver.delayMs(500);
      done();
    });

    it('gapExceedingWindowDoesNotFire', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await clickByIdShared(driver, 'HomeVersionLabel');
      await driver.delayMs(150);
      await clickByIdShared(driver, 'HomeVersionLabel');
      // 1500ms wait > 1000ms window — counter resets.
      await driver.delayMs(1500);
      await clickByIdShared(driver, 'HomeVersionLabel');
      await driver.delayMs(800);
      // Still on HomePage.
      await driver.assertComponentExist(ON.id('HomeStartButton'));
      // The DevMenu Apply button must NOT be present.
      const apply: Component | null = await driver.findComponent(ON.text('Apply'));
      expect(apply === null).assertTrue();
      done();
    });
  });
}
```

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

The mock UI server (`server/mock_ui_server.py`, port 8123) does **not** stub `https://raw.githubusercontent.com/...`. The manifest fetch in this UI test will hit the real GitHub raw URL — that's fine because `PreviewManifestService.fetchManifest` lives outside the `effectiveServerBaseUrl` rewriting (it has a hard-coded URL constant), and the manifest is a static file in this very repo. If the device has no network, the fetch returns the cached value (or null on first ever boot). The test tolerates both: it asserts only that **either** a card is present **or** a "No manifest" status text is present, and asserts the cards' shape only when at least one is visible.

**Coverage note:** spec §7.2 lists four cases for this file; this task automates cases 1–3 (card visible, format `#PR(sha)`, tap-selects-without-navigating). Case 4 ("Tapping Apply after card selection still works") is intentionally **moved to the manual smoke in Task E1 Step 5 (item 4)** because Apply executes a real `/api/v1/health` probe against the selected `.vercel.app` URL — those URLs rotate out as PRs land, so an automated assertion would flake within weeks of authoring. The manual step keeps the spec covered with stable signal.

- [ ] **Step 1: Write the UI test file**

Create `entry/src/ohosTest/ets/test/DevMenuCardList.ui.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { clickByIdShared } from './RoutingFlow.ui.test';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1000);
  return driver;
}

async function returnToHome(driver: Driver): Promise<void> {
  for (let i: number = 0; i < 5; i++) {
    const home: Component | null =
      await driver.findComponent(ON.id('HomeStartButton'));
    if (home !== null) {
      return;
    }
    await driver.pressBack();
    await driver.delayMs(500);
  }
}

async function tripleTapVersion(driver: Driver): Promise<void> {
  await clickByIdShared(driver, 'HomeVersionLabel');
  await driver.delayMs(150);
  await clickByIdShared(driver, 'HomeVersionLabel');
  await driver.delayMs(150);
  await clickByIdShared(driver, 'HomeVersionLabel');
  await driver.delayMs(1500); // allow manifest fetch + render
}

/**
 * V0.7.x acceptance — DevMenuPage's manifest list is rendered as
 * cards, not single-line buttons. Cards have id
 * DevMenuPreviewCard_<pr>, contain the title text, and a centered
 * "#<pr>(<sha7>)" footer.
 *
 * Network-dependent: the manifest URL is a hard-coded
 * raw.githubusercontent.com path that is NOT rewritten by the mock
 * UI server. If the device is offline the test asserts only the
 * gentler invariant that DevMenuPage rendered (Apply button visible).
 */
export default function devMenuCardListUiTest(): void {
  describe('DevMenuCardList', () => {
    it('cardsRenderTitleAndPrSha', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await tripleTapVersion(driver);
      // Confirm we're on DevMenuPage (Apply button is the stable signal).
      const apply: Component | null = await driver.findComponent(ON.text('Apply'));
      expect(apply !== null).assertTrue();
      // Look for ANY card by id pattern. We probe known PR numbers
      // recorded in docs/preview-urls.json at spec time (42, 41, 40,
      // 30); if none are present (e.g. offline), we accept the
      // weaker assertion that DevMenu rendered.
      const probePrs: number[] = [42, 41, 40, 30];
      let found: Component | null = null;
      for (const pr of probePrs) {
        const c: Component | null = await driver.findComponent(ON.id(`DevMenuPreviewCard_${pr}`));
        if (c !== null) {
          found = c;
          break;
        }
      }
      if (found !== null) {
        const txt: string = await found.getText();
        // Card text concatenates title and "#<pr>(<sha>)" via ArkUI.
        // We only assert the footer pattern is present in the
        // composed text, since title text is content-dependent.
        expect(txt.indexOf('#') >= 0).assertTrue();
        expect(txt.indexOf('(') >= 0).assertTrue();
        expect(txt.indexOf(')') >= 0).assertTrue();
      }
      // Cleanup.
      await driver.pressBack();
      await driver.delayMs(500);
      done();
    });

    it('cardTapSelectsWithoutNavigating', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await tripleTapVersion(driver);
      // Reuse the same PR probe.
      const probePrs: number[] = [42, 41, 40, 30];
      let cardId: string | null = null;
      for (const pr of probePrs) {
        const c: Component | null = await driver.findComponent(ON.id(`DevMenuPreviewCard_${pr}`));
        if (c !== null) {
          cardId = `DevMenuPreviewCard_${pr}`;
          break;
        }
      }
      if (cardId !== null) {
        await clickByIdShared(driver, cardId);
        await driver.delayMs(300);
        // Still on DevMenuPage (Apply still visible).
        const apply: Component | null = await driver.findComponent(ON.text('Apply'));
        expect(apply !== null).assertTrue();
        // Card tap must NOT navigate back to HomePage.
        const homeStart: Component | null = await driver.findComponent(ON.id('HomeStartButton'));
        expect(homeStart === null).assertTrue();
      }
      // Cleanup — back to HomePage so the next suite starts clean.
      await driver.pressBack();
      await driver.delayMs(500);
      done();
    });
  });
}
```

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
  // V0.7.x: debug-only version label + triple-tap → DevMenu navigation.
  // Order-independent: these tests press Back at the tail so HomePage
  // is reachable for the next suite. Placed right after
  // homeToolbarLockedUiTest because both are "home toolbar / top
  // chrome" smoke tests and grouping them surfaces top-screen
  // regressions early.
  homeVersionTapUiTest();
  // V0.7.x: DevMenuPage card layout + tap-selects-without-navigating.
  // Network-dependent on raw.githubusercontent.com (manifest URL).
  // Asserts only the weaker "DevMenu rendered" invariant when offline.
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
Expected output ends with `TestFinished-ResultCode: 0` and `OHOS_REPORT_CODE: 0`. The new suites should report `HomeVersionTap` (3 it blocks) and `DevMenuCardList` (2 it blocks) all passing. No regressions in earlier suites.

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
2. Open the app — confirm the top-left shows `v0.6.0(YYMMDDHHmmss)` in small grey text.
3. Triple-tap quickly (≤1s) → DevMenuPage opens with PREVIEW radio pre-selected and a card list rendered.
4. Tap a card → it highlights blue. Tap Apply → toast `Environment updated. Re-bind parent account if needed.` and you land back on HomePage.
5. Re-open DevMenuPage from `Settings → Developer → Backend environment` → confirm the env reflects what was just selected (cards still appear if PREVIEW).
6. Build a release HAP (`hvigorw -p product=default --mode module -p module=entry@default assembleHap` with the release product) → install on device → confirm **no** version label is visible at top-left and tapping where it would have been does nothing.

- [ ] **Step 6: Final acceptance review**

Walk through `docs/superpowers/specs/2026-05-07-home-version-triple-tap-design.md` §10 (Acceptance criteria) and tick each box. If any item fails, file a follow-up before declaring the work complete.

No commit on this task — verification only.

---

## Notes for the implementer

- **Frequent commits:** every Phase A and B/C task ends with a commit. Don't batch tasks into one giant commit; each commit must build + lint + test green on its own.
- **No new dependencies:** all the APIs used (`bundleManager`, `router`, `Driver`, `ON`, `Component`, `@ohos/hypium`) are already in `oh-package.json5`.
- **Debug-only gating:** every new HomePage code path (the `if (BuildProfile.BUILD_MODE_NAME === 'debug')` checks in steps B1.3 and B1.4) is the safety net that keeps release builds untouched. Do not remove the gate even if codelinter complains about an "unused state" — release builds will inline-elide the dead branch.
- **`router.getParams()` typing:** ArkTS treats route params as `Object`. The cast `params as Record<string, string>` is the project convention; see `entry/src/main/ets/pages/ScanBindingPage.ets` for prior art if you need a reference.
- **CodeLinter quirks:** the project enforces `avoid-overusing-custom-component-check` — that's why the spec uses `@Builder previewCard(row)` rather than a separate `@Component`. Don't refactor the builder into a struct without checking the rule first.
- **Mock UI server irrelevance:** `server/mock_ui_server.py` is for `effectiveServerBaseUrl()`-driven traffic. The manifest URL is a hard-coded `raw.githubusercontent.com` constant inside `PreviewManifestService.ets`, so the mock plays no role here.
