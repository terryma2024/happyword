# Monster Codex Progress v1.0.2 — iOS Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md). Use `xcodebuild` from `ios/` and the project's stable DerivedData path.

**Goal:** Replicate Monster Codex progress v1.0.2 semantics from HarmonyOS onto iOS native Swift / SwiftUI preserving stable IDs, persistence keys, and behavior listed in the signed trigger.

**Architecture:** SwiftUI renders codex progress state; pure Swift services own persistence, masking, reward eligibility, and cap-free coin claims. `shared/` stays contracts/fixtures only.

**Tech Stack:** Swift, SwiftUI, XCTest, XCUITest. Project generated from `ios/project.yml` via XcodeGen.

---

### Pre-flight: verify the trigger is signed

- [x] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
- [x] If missing, stop and ask the human owner. Do not proceed past this point.

### Task 1: Domain types and pure logic

- [x] Translate the design's domain rules (§6) into pure Swift types and services.
- [x] Mirror persistence key `monster_progress/snapshot_v1` exactly.
- [x] Write XCTest cases that mirror the HarmonyOS tests listed in trigger §2.5.
- [x] Run focused XCTest cases per [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md).

### Task 2: SwiftUI codex states

- [x] Implement locked, encountered-disabled, claimable, and claimed codex states.
- [x] Every UI element listed in `00-design.md` §5 carries `.accessibilityIdentifier("<ID>")` verbatim.
- [x] Preserve Monster Codex landscape orientation.

### Task 3: XCUITest parity

- [x] Add XCUITest coverage for locked, disabled, claimable, and claimed reward states.
- [x] Use stable identifiers; do not rely on coordinate taps.

### Task 4: Versioning and screenshots

- [x] Set `CFBundleShortVersionString` to `1.0.2`.
- [x] Pick a monotonically increasing `CFBundleVersion`.
- [x] Human-review affected codex screenshots / simulator states.

### Task 5: Verification

- [x] All affected XCTest suites green.
- [x] All affected XCUITest suites green.
- [x] `xcodebuild build ...` succeeds with no new warnings in files changed.
- [x] Update [`50-parity-checklist.md`](50-parity-checklist.md) iOS columns.
