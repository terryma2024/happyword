# <Feature Name> — iOS Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md). Use `xcodebuild` from `ios/` and the project's stable DerivedData path.

**Goal:** Replicate `<Feature Name>` semantics from HarmonyOS onto iOS native (Swift / SwiftUI) preserving stable IDs, persistence keys, and behavior listed in the design + delta letter.

**Architecture:** SwiftUI views render state; pure Swift services own behavior. New / changed types match the boundaries listed in [`docs/ios-replica/02-domain-logic.md`](../../ios-replica/02-domain-logic.md). `shared/` stays contracts/fixtures only.

**Tech Stack:** Swift, SwiftUI, XCTest, XCUITest. Project generated from `ios/project.yml` via XcodeGen.

---

### Pre-flight: verify the trigger is signed

- [ ] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
- [ ] If missing, stop and ask the human owner. Do not proceed past this point.

### Task 1: Domain types and pure logic

**Files:**
- Create / modify: `ios/WordMagicGame/Models/...`
- Create / modify: `ios/WordMagicGame/Services/...`
- Test: `ios/WordMagicGameTests/...`

- [ ] Translate the design's domain rules (§6) into pure Swift types and services.
- [ ] Mirror persistence keys exactly per `00-design.md` §7 and trigger §2.2.
- [ ] Write XCTest cases that mirror the HarmonyOS unit tests listed in trigger §2.5.
- [ ] Run focused tests: `xcodebuild test -scheme WordMagicGame -only-testing:WordMagicGameTests/<Suite> ...` (see [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md) §3).

### Task 2: SwiftUI views with stable identifiers

**Files:**
- Create / modify: `ios/WordMagicGame/Views/...`
- Modify: `ios/WordMagicGame/App/...` if routing changes.

- [ ] Implement view changes; every UI element listed in `00-design.md` §5 carries `.accessibilityIdentifier("<ID>")` verbatim.
- [ ] Make sure orientation matches HarmonyOS (child-flow landscape, parent-flow portrait).

### Task 3: XCUITest parity for UI flows

**Files:**
- Create / modify: `ios/WordMagicGameUITests/...`

- [ ] For each row in trigger §2.5 with an iOS counterpart, write the matching XCUITest case.
- [ ] Use stable identifiers; do not rely on coordinate taps.
- [ ] Run: `xcodebuild test -scheme WordMagicGame -only-testing:WordMagicGameUITests/...` (see [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md) §4).

### Task 4: Versioning and screenshots

**Files:**
- Modify: `ios/project.yml` (so XcodeGen regenerates `Info.plist` with the new version) or directly bump `CFBundleShortVersionString` / `CFBundleVersion` if XcodeGen is not run for this change.

- [ ] Set `CFBundleShortVersionString` to the HarmonyOS `versionName` recorded in trigger §1.
- [ ] Pick a `CFBundleVersion` (integer) that monotonically increases. Document the chosen mapping rule the first time you do this; reuse it afterwards.
- [ ] Capture iPhone simulator screenshots for every screen this feature changed and place them under `assets/screenshots/ios/`.

### Task 5: Verification

- [ ] All XCTest suites green.
- [ ] All XCUITest suites green for the affected flows.
- [ ] `xcodebuild build ...` succeeds with no new warnings in files you changed.
- [ ] Update [`50-parity-checklist.md`](50-parity-checklist.md) iOS columns; commit when each row is true.
