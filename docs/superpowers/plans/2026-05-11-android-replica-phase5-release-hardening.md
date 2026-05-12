# Android Replica Phase 5 Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lock the Android replica behind repeatable release-hardening gates for screenshot parity, offline fallback, debug-only developer tooling, and release-style build readiness.

**Architecture:** Keep Phase 5 as a hardening pass, not a feature phase. Add small pure helpers around release/debug visibility so the policy is unit-testable, tighten stale UI text, and document the verification commands that prove Android remains aligned with HarmonyOS behavior.

**Tech Stack:** Native Android, Kotlin, Jetpack Compose, JUnit4, Android instrumentation tests, Gradle Android plugin.

---

## Source Spec

`docs/superpowers/specs/2026-05-11-android-replica-phase5-release-hardening-design.md`

## Files

- Create: `android/app/src/main/java/cool/happyword/wordmagic/app/BuildGate.kt`
- Create: `android/app/src/test/java/cool/happyword/wordmagic/app/BuildGateTest.kt`
- Create: `android/app/src/test/java/cool/happyword/wordmagic/app/OfflineFailureGateTest.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`
- Modify: `.cursor/android-dev-commands.md`
- Modify: `docs/android-replica/00-index.md`
- Modify: `docs/android-replica/07-release-readiness-checklist.md`

## Tasks

> Execution status: completed on 2026-05-12 from
> `codex/phase-5-release-hardening`. The implementation files were already
> present in the Android baseline; this pass verified the gates and refreshed
> the tracking state.

### Task 1: Make Release Developer Visibility Unit-Testable

- [x] Create `BuildGate.kt` with a pure `showDeveloperTools(isDebuggable: Boolean)` policy.
- [x] Add `BuildGateTest` proving debug builds may show developer tools and release builds must hide them.
- [x] Replace the raw `ApplicationInfo.FLAG_DEBUGGABLE` check in `MainActivity.kt` with `BuildGate.showDeveloperTools(...)`.
- [x] Run `cd android && ./gradlew testDebugUnitTest`.

### Task 2: Add Offline And Failure Gates

- [x] Add `OfflineFailureGateTest` proving failed cloud pack sync keeps local builtin packs playable.
- [x] Add a test that failed word-stat sync returns a non-blocking failure message.
- [x] Add a test that production backend routing emits no preview bypass headers.
- [x] Run `cd android && ./gradlew testDebugUnitTest`.

### Task 3: Tighten Phase 5 UI And Documentation

- [x] Update the stale Config text for `我的词包` so it reflects the implemented PackManager path.
- [x] Add the Phase 5 plan link to `docs/android-replica/00-index.md`.
- [x] Add a Phase 5 release-hardening section to `.cursor/android-dev-commands.md`.
- [x] Run `cd android && ./gradlew testDebugUnitTest`.

### Task 4: Full Verification Gates

- [x] Run `cd android && ./gradlew assembleDebug`.
- [x] Run `cd android && ./gradlew connectedDebugAndroidTest`.
- [x] Run `cd android && ./gradlew assembleRelease`.
- [x] `assembleRelease` passed; no signing/configuration gap needed to be documented.

### Task 5: Harden Release Routing Against Persisted Debug State

- [x] Add `BuildGate.coerceBackendRouteForBuild(...)` so release builds coerce persisted Local/Preview routing back to Staging while preserving explicit Prod.
- [x] Add `BuildGateTest` cases for Preview, Local, Prod, and debug-preserved route states.
- [x] Apply the gate when `WordMagicGameApp` loads persisted backend route state.

## Acceptance Checklist

- [x] Release/debug developer visibility is covered by JVM tests.
- [x] Offline and failed cloud sync behavior is covered by JVM tests.
- [x] Debug-only DevMenu remains reachable in debug UI tests.
- [x] Android command manifest lists the Phase 5 verification loop.
- [x] Release builds cannot inherit persisted Local/Preview routing from a prior debug install.
- [x] `assembleDebug`, `testDebugUnitTest`, and `connectedDebugAndroidTest` pass.
- [x] `assembleRelease` passes, or the signing/configuration gap is explicitly reported.
