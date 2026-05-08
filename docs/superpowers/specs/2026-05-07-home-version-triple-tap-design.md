# HomePage version label + triple-tap → DevMenu card switcher

**Date:** 2026-05-07
**Owner:** client (HarmonyOS / ArkTS)
**Scope:** debug builds only — release builds render nothing new and have no new code path
**Builds on:** [`2026-05-06-client-backend-env-switcher-design.md`](2026-05-06-client-backend-env-switcher-design.md) (existing `DevMenuPage`, `BackendEnv`, `PreviewManifestService`)

> **Document map (2026-05-08):** §§1–10 retain **v0.6.0** drafting (card layout, triple-tap). **Shipped DevMenu behaviour** is **§11 (v0.6.1 unified grid + tap-to-apply)** and **§12 (v0.6.2 manifest URL / bypass boundary)**. If an earlier section disagrees with §11–12, treat §11–12 as normative.

## 1. Goal

Add a hidden, debug-only entry point on the HarmonyOS home screen that takes a developer / QA tester from "I want to swap the backend to PR #42's preview deployment" to "swapped" in **three taps on the version label** plus **one tap on the target env card** (v0.6.1+ tap-to-apply — §11). The original v0.6.0 draft kept a separate Apply button; that path was superseded. Today this shortcut avoids extra navigation versus Config → Developer → Backend environment.

The change has three user-visible parts:

1. A small grey `v0.6.0(2605072052)` label in the top-left of the home screen.
2. Triple-tap on that label (within **`VersionTripleTap`'s 1500ms** window) navigates to `DevMenuPage`. `HomePage` still passes `presetEnv: 'preview'` for forward compatibility; **`DevMenuPage` may not read it** — see live `DevMenuPage.ets`.
3. The manifest preview list inside `DevMenuPage` is rendered as cards (**unified grid with Local + Staging + previews** in v0.6.1 — §11) showing **title** (max 3 lines), **`#PR(sha)`** centered on preview rows.

Release builds: zero new UI, zero new code path. The label, the tap handler, and the route param are debug-gated (`BuildProfile.BUILD_MODE_NAME === 'debug'`).

## 2. Non-goals

- **Env switching semantics:** The commit pipeline (health probe for Preview when applicable → `resetForEnvSwitch` → `saveBackendEnv` → audit log → `router.replaceUrl`) is unchanged — **v0.6.1 runs it from `onCardTap`** instead of a separate Apply control (§11).
- **No change to the manifest fetcher / cache / TTL** beyond what §12 records (`PREVIEW_MANIFEST_JSON_URL` pinning). The list renderer and `ManifestRow` shape are unchanged.
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

Tap-on-card behaviour (**v0.6.0 draft**): card tap only updated selection; Apply committed.

**Shipped (v0.6.1+):** any card tap runs **`onCardTap`** → full commit pipeline (Preview may prompt for bypass secret, then `probeHealth`, etc.) → toast → `replaceUrl` Home. See **§11**.

The card list lives inside the same `Scroll() { Column { ForEach } }` shell that exists today, with the outer Column gaining `space: 8` between cards. **List height bumped from today's `140 dp` (sized for single-line buttons) to `320 dp`** — each 3-line card is ~90–110 dp tall, so 320 dp shows roughly three cards at a time and the rest scroll. The new height is a lone-line change next to the existing `.height(140)`.

### 3.4 PREVIEW pre-select on entry (**v0.6.0 draft — superseded**)

The following applied **`pendingEnv` after `hydrate()`** when the route carried `presetEnv=preview`. **Current `DevMenuPage`** intentionally does **not** consume this param (comment in source); the unified grid shows every env without a radio pre-select. Kept here as historical context only:

```typescript
async aboutToAppear(): Promise<void> {
  await this.hydrate();
  const params = router.getParams() as Record<string, string> | undefined;
  if (params?.['presetEnv'] === 'preview') {
    this.pendingEnv = BackendEnv.PREVIEW;
  }
}
```

Entering DevMenu via Settings still works; `HomePage` triple-tap still passes `presetEnv` for forward compatibility.

## 4. Architecture

### 4.1 New module: `entry/src/main/ets/services/VersionTripleTap.ets`

A 25-line stateful counter class. No external imports. Pure unit-testable.

```typescript
export class VersionTripleTap {
  private count: number = 0;
  private lastTapMs: number = 0;
  private readonly windowMs: number;

  constructor(windowMs: number = 1500) {
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

### 4.4 `DevMenuPage.ets` — modifications (**v0.6.0 draft**)

Three localized changes in the original proposal:

1. **`aboutToAppear`** — apply the `presetEnv` param after `hydrate()` resolves (see §3.4 — superseded in main).
2. **Replace lines 195–213** — the inner manifest renderer per §3.3 (`previewCard` @Builder pattern).
3. **Card key** — the `ForEach` keyExtractor stays `(row: ManifestRow) => \`${row.pr}-${row.url}\``.

**v0.6.1+ replaces this with** the unified card grid + `onCardTap` — see **§11**. The Apply button, standalone paste row, and env radios described in early drafts are gone in shipped UI.

### 4.5 Shipped layout pointer

Normative structure: **§11.5–11.7** (grid, tap-to-apply, tests).

## 5. Data flow

**v0.6.0 draft** (select + Apply):

```
HomePage.aboutToAppear
  → readVersionInfo() → bundleManager.getBundleInfoForSelf
  → versionLabel = "v0.6.0(2605072052)"

User triple-taps HomeVersionLabel
  → versionTap.onTap(Date.now()) returns true on tap 3
  → router.pushUrl('pages/DevMenuPage', { presetEnv: 'preview' })

DevMenuPage.aboutToAppear
  → hydrate() reads prefs, manifest cache, audit log, history
  → (draft) reads router params; presetEnv → pendingEnv = PREVIEW

User taps a card
  → selection only

User taps Apply
  → probeHealth → resetForEnvSwitch → saveBackendEnv → audit → replaceUrl Home
```

**Shipped v0.6.1+:** card tap runs the commit pipeline immediately (`onCardTap`); no Apply step. Router `presetEnv` may be ignored — **§11.4**. Manifest fetch is pinned — **§12**.

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

Normative case list: **§11.7**. Summary:

`HomeVersionTap.ui.test.ets` — label present; triple-tap navigates (assert **`Developer options`** text — Apply was removed); gap **\> 1500ms** between taps resets counter (`VersionTripleTap` default window).

`DevMenuCardList.ui.test.ets` — Local + Staging cards always visible; preview cards optional (network); **staging card tap** returns to Home after tap-to-apply.

Manifest GET in tests: **`PREVIEW_MANIFEST_JSON_URL`** only — **§12** (not the UI-test mock base URL).

The existing `HomeToolbarLocked.ui.test.ets` is unaffected — it doesn't use `HomeVersionLabel`.

## 8. Risks & mitigations

- **Children tap the version label.** In debug it navigates to DevMenu, which they can't usefully break. In release the label and handler are absent. **Risk: low.**
- **Triple-tap accidental fire.** The 1500ms window plus a 11pt grey label off in the corner means children very rarely hit it. Adults will. Acceptable. (1500ms — not 1000ms — was chosen during D1 verification: each `comp.click()` round-trip on a slow OpenHarmony emulator can drift toward ~400ms, so a 1000ms inter-tap window was occasionally too tight to register three taps as "consecutive". 1500ms is comfortable on real devices and robust against the emulator.)
- **`bundleManager.getBundleInfoForSelf` failing.** Wrapped in try/catch with a `?.?.?` fallback. Label still renders, just without identity.
- **`presetEnv` route param:** Early drafts applied it after `hydrate()` (§3.4). **Shipped `DevMenuPage` does not read it** — no PREVIEW pre-select race; see §3.4 note.
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

---

## 11. v0.6.1 revision — unified card grid, tap-to-apply, no Apply gate

After the original v0.6 design landed, hands-on use with the dev menu produced
a clearer UX. Two concerns drove the revision:

1. The split between **Local / Preview / Staging radio buttons** and the
   **manifest card list** was redundant — both expressed the same idea ("pick
   an environment") in two different visual languages.
2. The separate **Apply** button added a deliberate but ceremonial step to a
   gesture-gated dev affordance. The triple-tap is already the safety gate; a
   second confirmation is not earning its keep.

### 11.1 Goal of the revision

Collapse all three environment choices (Local, Staging, every Preview URL)
into a single uniform **2-column card grid**. Every card is tap-to-apply: the
existing safety pipeline (`probeHealth` for Preview, `resetForEnvSwitch`,
`saveBackendEnv`, `savePreviewUrl`, audit log, toast, `replaceUrl` back to
`HomePage`) fires on the tap itself. Drop the paste-URL field, the recent-URL
history list (and its `loadHistory`/`saveHistory`/`pushHistory` calls), the
Apply button, and the `pendingEnv`/`applying` two-step state machine.

### 11.2 Layout (top-down)

```
┌─────────────────────────────────────────────────┐
│  ← Back     Developer options    [Refresh ▾]    │  ← Header row, refresh moved to right
├─────────────────────────────────────────────────┤
│  Backend environment (debug builds only)         │
│                                                  │
│  ┌─────────────┐  ┌─────────────┐                │
│  │   Local     │  │   Staging   │                │
│  │ http://10…  │  │ https://…   │                │
│  └─────────────┘  └─────────────┘                │
│  ┌─────────────┐  ┌─────────────┐                │
│  │ ci(preview…)│  │ feat: split…│                │
│  │ #42(ca12420)│  │ #41(b9efabc)│                │
│  └─────────────┘  └─────────────┘                │
│  …                                               │
│                                                  │
│  Release builds always use staging: …            │
│  Recent switches                                 │
│  20:52: staging -> preview https://…             │
└─────────────────────────────────────────────────┘
```

- The header row pins **Refresh manifest** to the right with `flexBasis(0)` /
  `layoutWeight(1)` Spacer between title and the button. `Refreshing…` busy
  state stays on the same button.
- Each grid row is a `Row({ space: 12 })` containing two `previewCard` /
  `envCard` children, each `.layoutWeight(1)`. The grid is built by a small
  helper that chunks `[Local, Staging, ...manifest.previews]` into
  consecutive pairs. Trailing odd card pads with an empty layoutWeight(1)
  Column so widths stay symmetric.
- IDs:
  - Local card → `DevMenuLocalCard`
  - Staging card → `DevMenuStagingCard`
  - Preview cards → `DevMenuPreviewCard_<pr>` (unchanged)

### 11.3 Card content & selection

| Card     | Title (bold, max 3 lines) | Footer (centered, fontSize 13, #555) |
|----------|---------------------------|--------------------------------------|
| Local    | `Local`                   | `LOCAL_BASE_URL`                     |
| Staging  | `Staging`                 | `STAGING_BASE_URL`                   |
| Preview  | `row.title`               | `#${row.pr}(${row.head_sha.slice(0,7)})` |

Selection ring: a card is highlighted (`#CDE8FF` fill + `#457B9D` border) iff
it matches the **currently active** env+url:

- Local card highlighted iff `currentEnv === LOCAL`.
- Staging card highlighted iff `currentEnv === STAGING`.
- Preview card highlighted iff `currentEnv === PREVIEW && currentPreviewUrl === row.url`.

There is no "pending" state — taps either fail (toast) or commit and navigate
back. While a tap is in flight, the tapped card uses a `applying` border
treatment (`#9CA3AF` border + dimmed background) and all other cards become
non-interactive (re-entrancy guard).

### 11.4 Tap behaviour

Every card delegates to one private async method:

```typescript
private async onCardTap(env: BackendEnv, previewUrl: string): Promise<void> {
  if (this.applying) return;
  this.applying = true;
  try {
    if (env === BackendEnv.PREVIEW) {
      const ok: boolean = await this.probeHealth(previewUrl);
      if (!ok) {
        this.showToast('Cannot reach /api/v1/health on that URL');
        return;
      }
    }
    const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    await resetForEnvSwitch(ctx);
    await saveBackendEnv(env);
    await savePreviewUrl(env === BackendEnv.PREVIEW ? previewUrl : '');
    const row: AuditRow = {
      ts: Date.now(), from: this.currentEnv, to: env, preview_url: previewUrl,
    };
    await appendAuditLog(row);
    this.currentEnv = env;
    this.showToast('Environment updated. Re-bind parent account if needed.');
    router.replaceUrl({ url: 'pages/HomePage' });
  } finally {
    this.applying = false;
  }
}
```

`previewUrl` is `''` for Local/Staging (their fixed URL is derived inside the
relevant code paths from `metaFor(env).defaultUrl`). The historical
`previewChosenUrl()` helper, the `pasteUrl` field, the `pendingEnv` field,
the `selectedManifestUrl` field, and the `pushHistory`/`loadHistory`/
`saveHistory` calls are all removed.

### 11.5 Removed surface

- `Or paste preview URL` `TextInput` and the `Recent URLs` list and
  associated `pushHistory` write — manifest is the only source of preview
  URLs going forward.
- The dedicated env-pick `Row({ space: 8 })` with three Buttons (Local /
  Preview / Staging) — replaced by Local + Staging cards inside the grid.
- The `Apply` button + the `pendingEnv` / `applying` Apply-button machinery.
- `DevMenuPage` removes its dependency on `loadHistory`, `saveHistory`,
  `pushHistory` from `BackendEnv.ets`. The functions themselves stay
  exported (no UI consumer right now, but cheap to retain — they may be
  reused for a future "URL history" view).

### 11.6 ConfigPage cleanup (companion change)

Two unrelated-but-co-shipped fixes:

1. **Drop `devMenuRow()`**: `ConfigPage.ets` no longer renders the
   `Developer → Backend environment` button. The triple-tap on
   `HomeVersionLabel` is the only entry point. The `devMenuRow()` builder is
   deleted entirely. `DevMenuPage` itself stays routable for tests.
2. **Center-align `cloudSyncRow()`**: change its outer `Column`'s
   `.alignItems(HorizontalAlign.Start)` (currently line 422 in `ConfigPage.ets`)
   to `.alignItems(HorizontalAlign.Center)`. The peer settings rows
   (`adminRow`, `parentPinRow`, `categoryRow`, …) are bare `Row()`s of width
   `120 + 220 = 340 dp`, centered by the parent page Column. `cloudSyncRow`
   is one of two builders wrapped in a full-width `Column` for sub-content
   (status + toast Texts), and its outer Column was set to Start, breaking
   visual alignment. Setting it to Center fixes the row to align with peers.

### 11.7 Tests updated for v0.6.1

`DevMenuCardList.ui.test.ets`:

1. `localAndStagingCardsAlwaysPresent` — `DevMenuLocalCard` and `DevMenuStagingCard` render even when the manifest fetch fails; `Refresh manifest` visible.
2. `previewCardsRenderWhenManifestAvailable` — probes known `DevMenuPreviewCard_<pr>` ids; **never hard-fails** offline (logs only).
3. `stagingCardTapNavigatesBackToHome` — tap-to-apply returns to `HomePage` (assert `HomeVersionLabel`). Replaces the old "highlight without navigating" + Apply smoke.
4. The previous "Apply button works" smoke is removed — Apply is gone.

`HomeVersionTap.ui.test.ets`: triple-tap uses a **cached `HomeVersionLabel` `Component`** for three `.click()` calls; asserts **`Developer options`** on success; gap case uses **2500ms** wait vs **1500ms** window.

### 11.8 Risks new to v0.6.1

- **Tap-to-apply lowers friction below the previous Apply gate.** Mitigated
  by (a) the triple-tap entry already being a deliberate gesture, (b) the
  toast confirmation, and (c) the `replaceUrl` snap back to HomePage which
  visibly proves the switch happened.
- **Health-probe latency bleeds into the tap response.** Up to 2 seconds for
  Preview cards. Mitigated by the in-tap busy border and the `applying`
  re-entrancy guard. Local + Staging taps are sub-50ms.
- **Lost paste-URL escape hatch.** A developer wanting to point at a
  preview URL not yet in the manifest must regenerate the manifest (the
  top-right `Refresh` button now sits a finger-tap away). If the URL is
  not in any open PR, they must open a PR first. Documented in §10.

### 11.9 Acceptance criteria — v0.6.1

- [ ] `DevMenuPage` shows a 2-column grid with cards in order: Local,
      Staging, then one card per manifest preview.
- [ ] No paste-URL `TextInput`, no recent URLs list, no Apply button on
      `DevMenuPage`.
- [ ] `Refresh manifest` button sits at the top-right of the header row.
- [ ] Tapping any card commits the env switch (audit log gains a row,
      toast appears, page replaces back to `HomePage`).
- [ ] Tapping a Preview card whose URL fails the health probe surfaces the
      "Cannot reach /api/v1/health" toast and **does not** change env.
- [ ] `ConfigPage` no longer shows a `Developer` row.
- [ ] `ConfigPage`'s `学习记录` row sits at the same horizontal position as
      its peer rows (Bind parent / Parent PIN / etc.), not pushed to the
      left edge.
- [ ] All updated unit + UI tests pass; existing tests untouched.
- [ ] CodeLinter clean on `DevMenuPage.ets`, `ConfigPage.ets`, and the
      updated UI test files.

## 12. v0.6.2 revision — preview manifest from production only (no bypass)

Companion to [`2026-05-06-client-backend-env-switcher-design.md`](2026-05-06-client-backend-env-switcher-design.md) §10.

### 12.1 Client

- **`PREVIEW_MANIFEST_ORIGIN`** / **`PREVIEW_MANIFEST_JSON_URL`** in `RemoteWordPackConfig.ets` pin DevMenu manifest fetches to **`https://happyword.cool/api/v1/preview-urls.json`**, regardless of the currently selected `BackendEnv` or preview deployment.
- **`PreviewManifestService`** issues a plain GET with **no** `x-vercel-protection-bypass` header — listing PR previews never depends on Vercel Deployment Protection secrets.

### 12.2 Server

- **`GET /api/v1/preview-urls.json`** remains **credential-free** at the FastAPI layer (public router + service docstrings). This aligns with the client’s ability to refresh the manifest without storing a bypass token for that request.

### 12.3 Scope boundary

- Selecting a **Preview** card for app traffic may still require deployment-protection bypass for **`/api/v1/health`** and subsequent API calls — that path is separate from manifest discovery (see env-switcher spec §10).
