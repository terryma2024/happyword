# Monster Codex Progress v1.0.2 — Android Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/android-dev-commands.md`](../../../.cursor/android-dev-commands.md). Use `./gradlew` from `android/`.

**Goal:** Replicate Monster Codex progress v1.0.2 semantics from HarmonyOS onto Android native Kotlin / Jetpack Compose preserving stable IDs, persistence keys, and behavior listed in the signed trigger.

**Architecture:** Compose renders codex progress state; pure Kotlin services own persistence, masking, reward eligibility, and cap-free coin claims. `shared/` stays contracts/fixtures only.

**Tech Stack:** Kotlin, Jetpack Compose, JUnit, Compose UI tests, UI Automator where needed.

---

### Pre-flight: verify the trigger is signed

- [x] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
- [x] If missing, stop and ask the human owner. Do not proceed past this point.

### Task 1: Domain types and pure logic

- [x] Translate the design's domain rules (§6) into pure Kotlin types and services.
- [x] Mirror persistence key `monster_progress/snapshot_v1` exactly.
- [x] Write JUnit cases that mirror the HarmonyOS tests listed in trigger §2.5.
- [x] Run `cd android && ./gradlew testDebugUnitTest`.

### Task 2: Compose codex states

- [x] Implement locked, encountered-disabled, claimable, and claimed codex states.
- [x] Every UI element listed in `00-design.md` §5 carries `Modifier.testTag("<ID>")` verbatim.
- [x] Preserve Monster Codex landscape orientation.

### Task 3: Compose UI parity

- [x] Add UI coverage for locked, disabled, claimable, and claimed reward states.
- [x] Use stable tags; avoid coordinate taps.

### Task 4: Versioning and screenshots

- [x] Set `versionName` to `1.0.2`.
- [x] Pick a monotonically increasing `versionCode`.
- [x] Human-review affected codex screenshots / emulator states.
  - Owner reviewed Android landscape screenshots in-thread after compact layout fixes.

### Task 5: Verification

- [x] All affected JVM tests green.
- [x] All affected Compose UI / UI Automator tests green.
- [x] `cd android && ./gradlew assembleDebug` succeeds with no new warnings in files changed.
- [x] Update [`50-parity-checklist.md`](50-parity-checklist.md) Android columns.
