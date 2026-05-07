# HomePage version label + triple-tap → DevMenu card switcher

**Date:** 2026-05-07
**Owner:** client (HarmonyOS / ArkTS)
**Scope:** debug builds only — release builds render nothing new and have no new code path
**Builds on:** [`2026-05-06-client-backend-env-switcher-design.md`](2026-05-06-client-backend-env-switcher-design.md) (existing `DevMenuPage`, `BackendEnv`, `PreviewManifestService`)

## 1. Goal

Add a hidden, debug-only entry point on the HarmonyOS home screen that takes a developer / QA tester from "I want to swap the backend to PR #42's preview deployment" to "swapped" in three taps + one Apply tap. Today this requires four screen transitions (Home → Config scroll → "Backend environment" → DevMenu → pick → Apply); the change collapses the first three into a triple-tap on a small version label that already needs to exist for build identification.

The change has three user-visible parts:

1. A small grey `v0.6.0(2605072052)` label in the top-left of the home screen.
2. Triple-tap on that label (within 1000 ms) navigates to `DevMenuPage` with PREVIEW pre-selected.
3. The manifest preview list inside `DevMenuPage` is re-rendered as cards showing **title** (max 3 lines), **`#PR(sha)`** centered.

Release builds: zero new UI, zero new code path. The label, the tap handler, and the param-driven pre-select are all gated on `BuildProfile.BUILD_MODE_NAME === 'debug'`.

## 2. Non-goals

- **No change to env switching semantics.** The existing Apply pipeline (health probe → `resetForEnvSwitch` → `saveBackendEnv` → audit log → `router.replaceUrl`) stays. Card tap = select; Apply = commit. We're not building a tap-and-go switcher — too easy to misclick.
- **No change to the manifest fetcher / cache / TTL.** `PreviewManifestService` is untouched.
- **No new manifest fields.** We render `pr`, `title`, `head_sha` from the existing `ManifestRow`. `branch`, `author`, `updated_at` stay in the JSON for future use but are not shown on the card.
- **No build-time timestamp injection.** We use the bundle's install/update time at runtime (`bundleManager.getBundleInfoForSelf().updateTime`). See §6 for the rationale and the alternative we rejected.

## 3. UX

### 3.1 Home screen — version label

Top-left of the screen, padded `{ left: 16, top: 16 }`. The existing `HomePage`'s outer Stack uses `Alignment.TopEnd` to anchor the icon row at top-right; we add a parallel `Column { Text }` that overrides alignment to `HorizontalAlign.Start` so the version label sits on the opposite side of the same horizontal band.

- Style: `fontSize(11)`, `fontColor('#999999')` — small, easy to ignore, but readable.
- Content: `v{versionName}({timestamp})` e.g. `v0.6.0(2605072052)`. Timestamp is `YYMMDDHHmm` (10 chars) — minute precision is enough to identify which install corresponds to which build, and dropping seconds avoids visually noisy churn from re-installs within the same minute.
- ID: `HomeVersionLabel` (used by UI tests and the tap detector).
- Visibility: `if (BuildProfile.BUILD_MODE_NAME === 'debug')`. Release builds render no widget at all (no transparent invisible widget — the entire `if` block is omitted).

`versionName` comes from `AppScope/app.json5` (`0.6.0` today, tracking the V0.6 in-flight major version per [`docs/WordMagicGame_roadmap.md`](../../WordMagicGame_roadmap.md)). It is read once at `aboutToAppear` via `bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)` (see §4.2 for the exact call) and cached in a `@State` field. If the call fails the label falls back to `v?.?.?(<timestamp>)` so the layout doesn't shift.

### 3.2 Triple-tap behaviour

The `Text` widget's `.onClick` handler delegates to a `VersionTripleTap` instance:

- Window: 1000 ms between consecutive taps.
- 3 taps within window → fire (return `true`).
- A 4th tap before the counter resets does **not** re-fire; the counter is zeroed by the firing tap, so the user must lift, wait, and start a fresh sequence.
- Gap > 1000 ms between any two taps → counter resets to 1 (current tap counts as "the first" of a new attempt).

When fired:

```
router.pushUrl({
  url: 'pages/DevMenuPage',
  params: { presetEnv: 'preview' } as Record<string, string>,
});
```

There is no haptic, no animation, no audio cue. The tap target stays small and easily missed by children, which is intentional — this is a developer affordance hidden inside a kids' app.

Children tapping the version (which is inevitable — kids tap text) will not navigate anywhere in release builds (the label and handler are not present), and in debug builds they will navigate to a screen that is, well, the dev menu. Acceptable.

### 3.3 DevMenuPage card layout

Replace the current inner list (`DevMenuPage.ets` lines 195–213, the `Scroll > Column { ForEach { Button } }` rendering `#${pr} ${title}` as a single-line button) with a new `@Builder` that renders each row as:

```
┌──────────────────────────────────────────────────┐
│ ci(preview-manifest): rebuild from Vercel        │
│ deployments instead of PR webhook, this is a     │  ← title, bold, fontSize 14, max 3 lines, ellipsis
│ long-enough title to wrap into three lines.      │
│                                                  │
│                  #42(ca12420)                    │  ← Centered single line, fontSize 13, fontColor #555555
└──────────────────────────────────────────────────┘
```

Card styling:

- Wrapping `Column({ space: 8 })` with `width('100%')`, `padding(12)`, `borderRadius(12)`, `margin({ bottom: 8 })`.
- Selected: `backgroundColor('#CDE8FF')` + `border({ width: 1, color: '#457B9D' })`.
- Unselected: `backgroundColor('#F5F5F5')` + `border({ width: 1, color: '#E0E0E0' })`.
- Title: `Text(row.title)` with `.maxLines(3)` and `.textOverflow({ overflow: TextOverflow.Ellipsis })`. Bold, `fontSize(14)`, `fontColor('#222222')`, `width('100%')`.
- Footer (`#PR(sha)`): `Text(\`#${row.pr}(${row.head_sha.slice(0, 7)})\`)` inside a `Row().width('100%').justifyContent(FlexAlign.Center)`. `fontSize(13)`, `fontColor('#555555')`. The 7-char short-sha matches the conventional git short-SHA length and is sliced from the full `head_sha` already stored in the manifest.
- ID: each card gets `id(\`DevMenuPreviewCard_${row.pr}\`)` so UI tests can target by PR number.

Tap-on-card behaviour: identical to today — sets `selectedManifestUrl = row.url` and clears `pasteUrl`. **No** auto-Apply. The Apply button at the bottom of the page is the commit point.

The card list lives inside the same `Scroll() { Column { ForEach } }` shell that exists today, with the outer Column gaining `space: 8` between cards. **List height bumped from today's `140 dp` (sized for single-line buttons) to `320 dp`** — each 3-line card is ~90–110 dp tall, so 320 dp shows roughly three cards at a time and the rest scroll. The new height is a lone-line change next to the existing `.height(140)`.

### 3.4 PREVIEW pre-select on entry

`DevMenuPage.hydrate()` reads `loadBackendEnv()` from preferences and assigns it to `pendingEnv`. To honour a `?presetEnv=preview` route param without racing the hydrate write, we apply the param **after** `hydrate()` resolves:

```typescript
async aboutToAppear(): Promise<void> {
  await this.hydrate();
  const params = router.getParams() as Record<string, string> | undefined;
  if (params?.['presetEnv'] === 'preview') {
    this.pendingEnv = BackendEnv.PREVIEW;
  }
}
```

Entering DevMenu via the existing ConfigPage button passes no params → `pendingEnv` stays at the persisted value, behaviour unchanged.

## 4. Architecture

### 4.1 New module: `entry/src/main/ets/services/VersionTripleTap.ets`

A 25-line stateful counter class. No external imports. Pure unit-testable.

```typescript
export class VersionTripleTap {
  private count: number = 0;
  private lastTapMs: number = 0;
  private readonly windowMs: number;

  constructor(windowMs: number = 1000) {
    this.windowMs = windowMs;
  }

  /** Returns true exactly when the current tap completes a triple-tap inside the window. */
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

`HomePage` holds a single instance as `private versionTap = new VersionTripleTap();` — no `@State`, the counter is internal, no UI re-render needed on tap-1 / tap-2.

### 4.2 New module: `entry/src/main/ets/services/BuildInfo.ets`

Two pure functions plus one async lookup. Kept separate from `VersionTripleTap` because the responsibility (read bundle info, format timestamp) is unrelated.

```typescript
import bundleManager from '@ohos.bundle.bundleManager';
import { BusinessError } from '@ohos.base';

export interface VersionInfo {
  versionName: string;     // e.g. '0.6.0' or '?.?.?' on lookup failure
  timestamp: string;       // YYMMDDHHmm (minute precision)
}

const FALLBACK_VERSION_NAME = '?.?.?';

export function formatBuildTimestamp(epochMs: number): string {
  const d = new Date(epochMs);
  const yy = String(d.getFullYear() % 100).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const mn = String(d.getMinutes()).padStart(2, '0');
  return `${yy}${mm}${dd}${hh}${mn}`;
}

export async function readVersionInfo(): Promise<VersionInfo> {
  try {
    const info = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    );
    return {
      versionName: info.versionName ?? FALLBACK_VERSION_NAME,
      timestamp: formatBuildTimestamp(info.updateTime ?? Date.now()),
    };
  } catch (err) {
    console.error(`BuildInfo.readVersionInfo failed: ${JSON.stringify(err as BusinessError)}`);
    return { versionName: FALLBACK_VERSION_NAME, timestamp: formatBuildTimestamp(Date.now()) };
  }
}

/** Convenience composer used by the UI. */
export function formatVersionLabel(info: VersionInfo): string {
  return `v${info.versionName}(${info.timestamp})`;
}
```

`formatBuildTimestamp` is pure (deterministic given input ms) and is the unit-test target. `readVersionInfo` does the bundleManager call and wraps errors. `formatVersionLabel` is the UI composer.

### 4.3 `HomePage.ets` — modifications

Outer Stack already uses `Alignment.TopEnd` for the right-side icon row (`Row({ space: 12 }) { ... }.margin({ top: 16, right: 16 })`). We add a *parallel* child anchored to the top-left.

A new `@State` field:

```typescript
@State private versionLabel: string = '';
private versionTap: VersionTripleTap = new VersionTripleTap();
```

In `aboutToAppear`:

```typescript
readVersionInfo().then((v: VersionInfo): void => {
  this.versionLabel = formatVersionLabel(v);
}).catch((err: BusinessError): void => {
  console.error(`HomePage.readVersionInfo failed: ${JSON.stringify(err)}`);
});
```

In `build()`, inside the outer `Stack`, add (only in debug builds):

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

Stack alignment: the outer Stack's `.alignContent(Alignment.TopEnd)` is already set; this new Column has `width('100%')` so it spans the row, and the inner `Text` is anchored left by the Column's `HorizontalAlign.Start`. The right-side icon Row is unaffected — Stack layers all its children, so the version label sits behind/beside the icon row without overlap (the icon row uses `margin({ top: 16, right: 16 })` and starts at the right edge; the version label is at the left edge with `padding({ left: 16 })`).

### 4.4 `DevMenuPage.ets` — modifications

Three localized changes:

1. **`aboutToAppear`** — apply the `presetEnv` param after `hydrate()` resolves (see §3.4).
2. **Replace lines 195–213** — the inner manifest renderer:
   - Today: a `Button(\`#${row.pr} ${row.title}\`)` per row, inside a `Scroll().height(140)`.
   - New: a `@Builder` private method `previewCard(row: ManifestRow)` containing the Column-based card layout from §3.3, plus the wrapping `Scroll().height(320)` (raised from 140 to fit 3-line cards). `margin({ bottom: 8 })` on the Scroll stays the same.
3. **Card key** — the `ForEach` keyExtractor stays `(row: ManifestRow) => \`${row.pr}-${row.url}\``.

The Apply button, audit log, paste field, env radio, and history list are unchanged.

## 5. Data flow

```
HomePage.aboutToAppear
  → readVersionInfo() → bundleManager.getBundleInfoForSelf
  → versionLabel = "v0.6.0(2605072052)"

User triple-taps HomeVersionLabel
  → versionTap.onTap(Date.now()) returns true on tap 3
  → router.pushUrl('pages/DevMenuPage', { presetEnv: 'preview' })

DevMenuPage.aboutToAppear
  → hydrate() reads prefs, manifest cache, audit log, history
  → reads router params; sees presetEnv='preview' → pendingEnv = PREVIEW
  → render: preview env selected, cards visible, manifest list scrollable

User taps a card (DevMenuPreviewCard_42)
  → selectedManifestUrl = row.url
  → pasteUrl = ''
  → re-render highlights the tapped card

User taps Apply
  → onApply() (unchanged): probeHealth → resetForEnvSwitch → saveBackendEnv → audit → replaceUrl('pages/HomePage')
```

## 6. Build timestamp: rationale

We use `bundleManager.getBundleInfoForSelf().updateTime` rather than a compile-injected literal. Trade-off:

|  | Bundle install time (chosen) | Compile-time literal |
|---|---|---|
| Implementation | 1 API call, no build infra | Custom `hvigorfile.ts` plugin that writes a generated `BuildInfo.ets` before `compileArkTS` |
| Same value across all installs of the same HAP | No — each install resets it | Yes |
| Useful for "is this build the one I just installed" | Yes | Yes |
| Useful for "are these two devices running the same HAP" | No | Yes |
| Drift from actual build time | Up to days (developer might install yesterday's HAP today) | None |
| Files touched | 1 new service module | 1 new service module + 1 generated file + 1 hvigor plugin |

For the dev/QA loop this is targeted at — "did my last `hdc install` actually deploy?" and "which preview did this device end up on?" — install time is the right answer. Cross-device build-fingerprinting is a future concern; if it ever becomes one, swap in the hvigor plugin and the consumer side (`readVersionInfo`) doesn't change.

## 7. Tests

### 7.1 No-device unit (`entry/src/test/`)

`VersionTripleTap.test.ets` — 5 cases, all using fixed fake `nowMs` arguments:

1. Three taps inside the 1500ms window all return `[false, false, true]`.
2. After firing on tap 3, tap 4 (5ms later) returns `false` — the counter resets after firing.
3. Two fast taps then a 1500ms gap then one more tap returns `[false, false, false]` — gap reset.
4. Custom window (`new VersionTripleTap(500)`) — three taps at 0/200/400 fire; three taps at 0/300/700 don't (700-300 > 500).
5. `pendingCount()` reflects the internal counter without firing — useful for ohosTest assertions.

`BuildInfo.test.ets` — 2 cases:

1. `formatBuildTimestamp(0)` produces a 12-char string of digits with the expected components for epoch 0 in local time.
2. `formatBuildTimestamp(specificMs)` produces the expected `YYMMDDHHmm` string for a known timestamp (e.g. 2026-05-07T20:52:34 → `2605072052` in local time — seconds are intentionally dropped).

### 7.2 On-device UI (`entry/src/ohosTest/ets/test/`)

`HomeVersionTap.ui.test.ets`:

1. `HomeVersionLabel` is present in debug builds (always true under ohosTest, which builds in debug).
2. Triple-tap on `HomeVersionLabel` (3 taps with ≤500ms between) navigates to `DevMenuPage` (assert by checking for `ConfigDevMenuButton`'s absence and a known DevMenu widget's presence).
3. Two taps then a 1.5s wait then one tap does **not** navigate (HomePage still visible).

`DevMenuCardList.ui.test.ets`:

1. After entry, at least one `DevMenuPreviewCard_*` is visible (uses the seeded manifest cache or the live fetch with a generous timeout).
2. The card text contains `#${pr}(${head_sha.slice(0,7)})` exactly — guards against future regressions on the format.
3. Tapping a card highlights it (assert backgroundColor change) and does **not** navigate.
4. Tapping Apply after card selection still works (smoke).

The existing `HomeToolbarLocked.ui.test.ets` is unaffected — it doesn't use `HomeVersionLabel`.

## 8. Risks & mitigations

- **Children tap the version label.** In debug it navigates to DevMenu, which they can't usefully break. In release the label and handler are absent. **Risk: low.**
- **Triple-tap accidental fire.** The 1500ms window plus a 11pt grey label off in the corner means children very rarely hit it. Adults will. Acceptable. (1500ms — not 1000ms — was chosen during D1 verification: each `comp.click()` round-trip on a slow OpenHarmony emulator can drift toward ~400ms, so a 1000ms inter-tap window was occasionally too tight to register three taps as "consecutive". 1500ms is comfortable on real devices and robust against the emulator.)
- **`bundleManager.getBundleInfoForSelf` failing.** Wrapped in try/catch with a `?.?.?` fallback. Label still renders, just without identity.
- **Param-based PREVIEW pre-select racing with hydrate.** Avoided by applying the param **after** `hydrate()` resolves (see §3.4 code).
- **Stack overlap on narrow screens.** The version label is `padding({ left: 16, right: 16 })` and the icon row is `margin({ right: 16 })` from the right edge. Even on the narrowest supported phone, the icon row's leftmost icon is well to the right of the label's rightmost glyph. No overlap.

## 9. Out of scope (deferred)

- Showing `branch` and `author` on the card (room is there if we drop to 2-line title later — easy follow-up).
- Compile-time build-stamp injection (see §6).
- Sorting cards by `updated_at` (today's manifest order is "fetch order", which is fine for a small list).
- A "Filter manifest by branch / author" search box.
- Surfacing the version label in release builds (would require a separate UX decision — kids' apps don't usually show build identity).

## 10. Acceptance criteria

- [ ] Open a debug build → home screen shows `v0.6.0(YYMMDDHHmm)` in the top-left, grey, 11pt.
- [ ] Open a release build → no version label, no new behaviour anywhere.
- [ ] Triple-tap (≤1500ms gaps between taps) the label in debug → land on `DevMenuPage` with PREVIEW selected and the card list visible.
- [ ] Each card shows the title (up to 3 lines, ellipsised), then `#PR(sha)` centered.
- [ ] Tapping a card highlights it; tapping Apply commits and replaces the route to HomePage with the new env active.
- [ ] All new unit + UI tests pass; existing tests untouched.
- [ ] CodeLinter clean on all changed files.
