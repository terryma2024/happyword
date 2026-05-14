# Config page — connectivity + three-platform gap notes

**run-id:** `20260514-084557-pages-config`  
**scope:** `pages:config` (no spec file → `spec-excerpts.md` is placeholder)  
**baseline:** `feat/shared-parity-scout` (used `--allow-dirty-baseline`; not a signed “vs main” run)

---

## 1) Connectivity probe

| Path | Result |
|------|--------|
| **Harmony (`hdc`)** | `127.0.0.1:5555` — target online |
| **iOS (`simctl`)** | Booted: iPhone 17 Pro (iOS 26.4) |
| **Android (`adb`)** | `emulator-5556` device; also `emulator-5554` **offline** → **multiple adb endpoints** |

`scout.py doctor`: hdc / simctl / adb list ✓; Harmony branch row ✗ (non-`main`, expected).

### Tooling issue (Android)

`parity_scout` Android adapter invokes plain `adb` **without `-s <serial>`**. With **>1** line in `adb devices`, `am instrument` failed with **`error: more than one device/emulator`**, leaving **`config-landscape.png` empty (0 bytes)** and `CAPTURE_FAILED.txt`.

**Fix for next run:** `export ANDROID_SERIAL=emulator-5556` (or unplug/stop offline emulators), *and/or* extend the adapter to pass `-s` when `ANDROID_SERIAL` is set.

A **non-empty** `config-landscape.png` was **manually pulled** from app internal storage (`run-as … cat files/screenshots/config-landscape.png`) for analysis below — it may reflect a **previous successful** capture, not necessarily the same frame as today’s failed instrument run.

---

## 2) Harmony (baseline) vs iOS vs Android — behavior / UI gaps

Registry anchors: `HomeConfigButton`, `ConfigParentPinButton`, `ConfigParentAdminButton`; sections Config / 游戏设置.

### A. Page chrome & naming

- **[harmony]** Centered title **「游戏设置」**; no top-left back in this viewport (Harmony nav pattern).
- **[ios]** Title **「游戏设置」** + top-left **「返回」** — closer to baseline naming; extra system-style back affordance.
- **[android]** Title **「设置」** (not **游戏设置**) + **「返回首页」** top-right — **copy / IA gap** vs Harmony baseline.

### B. Numeric rows (玩家血量 / 怪物血量 / 怪物数量)

- **Values align** (5 / 3 / 5) across Harmony and iOS; Android pulled shot matches the same numbers on the visible cards.
- **Visual system gap [harmony vs android]:** Harmony uses **flat rows** + blue circular steppers; Android uses **cream background + white cards** + grey-outline circular steppers — intentional platform styling drift risk.

### C. Countdown (倒计时)

- **[harmony]** Single row of **pills** (30s, 3m, **√5m**, 10m, **自定义**).
- **[ios]** Pills for presets **plus** a separate numeric field showing **「300」** under the row — **extra control surface** not present on Harmony in the same form; possible **behavior / UX gap** (seconds vs presets vs manual entry).

### D. Auto-read (发音播放 / 自动朗读)

- **[harmony]** **Pill** with checkmark: **「√ 自动朗读」** (yellow border / fill).
- **[ios]** **Orange toggle switch** labeled **「自动朗读」** — **control paradigm gap** (toggle vs pill) even if the underlying flag matches.

### E. Word pack entry (我的词包)

- **[harmony]** Dedicated row: **已激活 5 / 5** + **管理 >** in a light blue bar.
- **[ios]** (first viewport) shows **「保存」** bottom-right instead — **layout priority gap**; word-pack row may be off-screen or omitted in this route’s first screenshot.
- **[android]** Pulled frame **does not show** countdown / pronunciation / word-pack block — **vertical coverage gap** vs Harmony’s multi-part `config-part*.png` scroll capture.

### F. Footer actions

- **[ios]** Prominent **「保存」** (red, bottom-right) on first screen.
- **[harmony]** Lower sections (e.g. part3) show **取消 / 保存** pair for parent-related config — **different vertical composition**; compare whether iOS “save” scope matches Harmony’s multi-section save model.

---

## 3) Recommended follow-ups

1. **Stabilize Android capture in CI / multi-device:** teach `AndroidAdapter` to honor `ANDROID_SERIAL` or `-s`.
2. **Retire offline emulators** (`emulator-5554 offline`) so default adb target is unambiguous.
3. **Re-run** `scout.py run` after (1)(2); optionally `plan --spec <feature-design.md>` so `spec-excerpts.md` anchors gaps to spec text.
4. **Android instrument** `captureCoreParentAndDebugScreens` currently **fails** on this device (`performScrollTo` `ConfigDeveloperRow`) — fix or split a **config-only** `@Test` so config parity does not depend on developer-row presence.
