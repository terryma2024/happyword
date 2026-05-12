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

## Tasks

### Task 1: Make Release Developer Visibility Unit-Testable

- [ ] Create `BuildGate.kt` with a pure `showDeveloperTools(isDebuggable: Boolean)` policy.
- [ ] Add `BuildGateTest` proving debug builds may show developer tools and release builds must hide them.
- [ ] Replace the raw `ApplicationInfo.FLAG_DEBUGGABLE` check in `MainActivity.kt` with `BuildGate.showDeveloperTools(...)`.
- [ ] Run `cd android && ./gradlew testDebugUnitTest`.

### Task 2: Add Offline And Failure Gates

- [ ] Add `OfflineFailureGateTest` proving failed cloud pack sync keeps local builtin packs playable.
- [ ] Add a test that failed word-stat sync returns a non-blocking failure message.
- [ ] Add a test that production backend routing emits no preview bypass headers.
- [ ] Run `cd android && ./gradlew testDebugUnitTest`.

### Task 3: Tighten Phase 5 UI And Documentation

- [ ] Update the stale Config text for `我的词包` so it reflects the implemented PackManager path.
- [ ] Add the Phase 5 plan link to `docs/android-replica/00-index.md`.
- [ ] Add a Phase 5 release-hardening section to `.cursor/android-dev-commands.md`.
- [ ] Run `cd android && ./gradlew testDebugUnitTest`.

### Task 4: Full Verification Gates

- [ ] Run `cd android && ./gradlew assembleDebug`.
- [ ] Run `cd android && ./gradlew connectedDebugAndroidTest`.
- [ ] Run `cd android && ./gradlew assembleRelease`.
- [ ] If `assembleRelease` fails because signing is not configured, document that exact gap in the final report and confirm which release-like gates still passed.

## Acceptance Checklist

- [ ] Release/debug developer visibility is covered by JVM tests.
- [ ] Offline and failed cloud sync behavior is covered by JVM tests.
- [ ] Debug-only DevMenu remains reachable in debug UI tests.
- [ ] Android command manifest lists the Phase 5 verification loop.
- [ ] `assembleDebug`, `testDebugUnitTest`, and `connectedDebugAndroidTest` pass.
- [ ] `assembleRelease` passes, or the signing/configuration gap is explicitly reported.
