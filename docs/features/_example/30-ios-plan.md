# Example Stable-ID Toggle — iOS Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md). Use `xcodebuild` from `ios/` and the project's stable DerivedData path.

**Goal:** Replicate the wrong-answer-cue toggle from HarmonyOS onto iOS, preserving the four stable IDs and the one-frame skip marker semantics.

**Architecture:** Add `playWrongCue` to the Swift `GameConfig`; sanitize on decode; branch in `AudioService.playWrongCue`; mount a transient `EmptyView().accessibilityIdentifier("BattleWrongCueSkippedMarker")` on Battle for one render frame on skip; add the Config row in SwiftUI.

**Tech Stack:** Swift, SwiftUI, XCTest, XCUITest.

---

### Pre-flight: verify the trigger is signed

- [x] Opened [`20-replication-trigger.md`](20-replication-trigger.md). `replication_approved: true`, signed by `SOP authors` on `2026-05-12`. Proceeding.

### Task 1: Domain types and pure logic

**Files:**
- Modify: `ios/WordMagicGame/Models/GameConfig.swift`
- Modify: `ios/WordMagicGame/Services/AudioService.swift`
- Test: `ios/WordMagicGameTests/GameConfigTests.swift`
- Test: `ios/WordMagicGameTests/AudioServiceTests.swift`

- [x] Add `playWrongCue: Bool = true` to `GameConfig`.
- [x] Decoder sanitization: missing or non-bool → `true`.
- [x] `AudioService.playWrongCue` reads `cfg.playWrongCue` lazily (per trigger §2.6).
- [x] XCTest cases mirror trigger §2.5 rows 1, 2, 5.

### Task 2: SwiftUI views with stable identifiers

**Files:**
- Modify: `ios/WordMagicGame/Views/ConfigView.swift`
- Modify: `ios/WordMagicGame/Views/BattleView.swift`

- [x] Add a Toggle row using `accessibilityIdentifier("ConfigWrongCueRow")` on the row, `"ConfigWrongCueLabel"` on the Text, `"ConfigWrongCueSwitch"` on the Toggle.
- [x] Mount transient `EmptyView().accessibilityIdentifier("BattleWrongCueSkippedMarker")` on Battle for one frame on skip; remove via `.task { try? await Task.sleep(...); state.skipMarker = false }` or equivalent.

### Task 3: XCUITest parity for UI flows

**Files:**
- Create: `ios/WordMagicGameUITests/WrongCueUITests.swift`

- [x] `testTogglesSkipMarker` — flips toggle off, drives a wrong answer, asserts the marker exists.
- [x] `testNoMarkerWhenOn` — leaves toggle on, drives a wrong answer, asserts the marker does not exist.

### Task 4: Versioning and screenshots

**Files:**
- Modify: `ios/project.yml` (regenerated `Info.plist`).

- [x] `CFBundleShortVersionString` → `0.6.7.9` (matches HarmonyOS).
- [x] `CFBundleVersion` → next monotonic integer per the existing iOS rule.
- [x] Captured `assets/screenshots/ios/config.png` at the new row.

### Task 5: Verification

- [x] All XCTest suites green.
- [x] `WrongCueUITests` green.
- [x] `xcodebuild build ...` clean for changed files.
- [x] Updated [`50-parity-checklist.md`](50-parity-checklist.md) iOS columns.
