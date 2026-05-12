# Android Replica Design Index

> Status: design-for-implementation
> Target branch: to be chosen when implementation starts
> Scope: native Kotlin / Jetpack Compose Android replication of the current HarmonyOS client.

## Goal

Create a staged, testable plan for replicating the current HarmonyOS WordMagicGame client as a native Android app. The first implementation target is a phone-first Android experience: child learning screens are landscape-first, while parent/admin screens are portrait-first.

This plan is grounded in:

- HarmonyOS screenshots under `assets/screenshots/harmonyos/`.
- Product baseline in `docs/WordMagicGame_overall_spec.md`.
- Current HarmonyOS ArkTS pages, services, models, rawfiles, and route table.
- Existing iOS replica planning under `docs/ios-replica/`.
- Shared contracts and fixtures under `shared/contracts/` and `shared/fixtures/`.
- Android official guidance for Android Studio, SDK command-line tools, Compose testing, UI Automator, and Android Gradle Plugin compatibility.

## Current Repository State

`android/` now contains a native Kotlin / Jetpack Compose project with Gradle wrapper, a debug app shell, core battle logic, copied HarmonyOS art/audio resources, JVM tests, and Compose UI smoke tests. The remaining phase specs below should be read as the roadmap for filling out the Android client beyond the current Phase 1-style playable slice.

This is good for planning: Android has enough local structure to anchor future work, while `shared/` still remains contracts/fixtures only.

## Document Map

| File | Purpose |
| --- | --- |
| `01-environment-init.md` | Local Android development environment setup, current machine gap analysis, and install/verification commands. |
| `02-screenshot-parity.md` | Visual source audit and Android phone adaptation rules by screen group. |
| `03-domain-logic.md` | Kotlin model/service boundaries mapped from ArkTS without creating shared runtime code. |
| `04-phase1-core-and-parent-admin.md` | Phase 1 design: Home, Battle, Result, Config, Parent PIN, ParentAdmin, LessonDraftReview. |
| `05-later-phases-pack-cloud-debug.md` | Phase 2-5 plan: local growth, pack sync, parent cloud, debug preview, release hardening. |
| `06-validation-plan.md` | Verification matrix for Gradle, JVM tests, Compose UI tests, UI Automator, screenshots, and contracts. |
| `07-release-readiness-checklist.md` | Phase 5 release-hardening gate checklist, screenshot set, and policy checks. |

## Superpowers Specs And Plans

| Purpose | File |
| --- | --- |
| Phase 0 environment design | `docs/superpowers/specs/2026-05-11-android-replica-phase0-environment-design.md` |
| Phase 1 core design | `docs/superpowers/specs/2026-05-11-android-replica-phase1-core-parent-admin-design.md` |
| Phase 2 local growth and pack design | `docs/superpowers/specs/2026-05-11-android-replica-phase2-local-growth-pack-design.md` |
| Phase 3 parent cloud and sync design | `docs/superpowers/specs/2026-05-11-android-replica-phase3-parent-cloud-design.md` |
| Phase 4 debug and preview routing design | `docs/superpowers/specs/2026-05-11-android-replica-phase4-debug-preview-design.md` |
| Phase 5 release hardening design | `docs/superpowers/specs/2026-05-11-android-replica-phase5-release-hardening-design.md` |
| Phase 0 executable implementation plan | `docs/superpowers/plans/2026-05-11-android-replica-environment-and-bootstrap.md` |
| Phase 2 local growth implementation plan | `docs/superpowers/plans/2026-05-11-android-replica-phase2-local-growth-pack.md` |
| Phase 3 parent cloud implementation plan | `docs/superpowers/plans/2026-05-11-android-replica-phase3-parent-cloud-sync.md` |
| Phase 4 debug preview routing implementation plan | `docs/superpowers/plans/2026-05-11-android-replica-phase4-debug-preview-routing.md` |
| Phase 5 release hardening implementation plan | `docs/superpowers/plans/2026-05-11-android-replica-phase5-release-hardening.md` |

Later Android implementation should create one additional Superpowers plan per phase instead of attempting a single mega-port.

## Current HarmonyOS Route Coverage

`harmonyos/entry/src/main/resources/base/profile/main_pages.json` currently registers 17 pages. Android assigns each page to a phase so the port can proceed in working slices.

| HarmonyOS page | Android phase | Notes |
| --- | --- | --- |
| `HomePage` | Phase 1 | Phone landscape, core entry and pack chip row shell. |
| `BattlePage` | Phase 1 | Phone landscape, playable combat with deterministic test fixture first. |
| `ResultPage` | Phase 1 | Phone landscape summary, stars, coin delta, back-home path. |
| `ConfigPage` | Phase 1 | Landscape settings shell with parent PIN and ParentAdmin entry. |
| `ParentPinSetupPage` | Phase 1 | Local six-digit PIN setup/edit flow. |
| `ParentAdminPage` | Phase 1 | Portrait parent surface, mockable API boundary first. |
| `LessonDraftReviewPage` | Phase 1 | Portrait draft review with mock client first. |
| `PackManagerPage` | Phase 2 | Three-layer pack activation, pin, sync, and rotation UI. |
| `WishlistPage` | Phase 2 | Local magic-wishlist loop after battle rewards exist. |
| `RedemptionHistoryPage` | Phase 2 | Local capped redemption history. |
| `MonsterCodexPage` | Phase 2 | Character/monster card parity and asset pipeline. |
| `TodayPlanPage` | Phase 2 | Read-only daily plan. |
| `LearningReportPage` | Phase 2 | Pack-keyed report, matching V0.6.7.8 semantics. |
| `ScanBindingPage` | Phase 3 | QR/short-code binding after local pack flows are stable. |
| `BoundDeviceInfoPage` | Phase 3 | Child profile and unbind flow. |
| `DevMenuPage` | Phase 4 | Debug-only backend environment switcher. |
| `BypassSecretPage` | Phase 4 | Debug-only preview deployment bypass token editor. |

## Phase Summary

| Phase | Theme | Deliverable |
| --- | --- | --- |
| Phase 0 | Environment and project bootstrap | Android Studio/SDK, JDK 17, Gradle wrapper, app/test targets, first green build. |
| Phase 1 | Core learning plus ParentAdmin | Home -> Battle -> Result and Config -> PIN -> ParentAdmin -> LessonDraftReview. |
| Phase 2 | Local growth and pack management | PackManager, wishlist, codex, today plan, local learning report. |
| Phase 3 | Parent cloud and device binding | Binding, family/global pack sync, word-stats sync, device info. |
| Phase 4 | Debug and preview operations | DevMenu, backend switcher, preview bypass, mock server routing. |
| Phase 5 | Release hardening | Screenshot parity, accessibility, release variant gates, CI readiness. |

## Non-Goals For This Planning Pass

- Do not create Android app code before the local Android SDK exists.
- Do not change HarmonyOS behavior as part of Android planning.
- Do not introduce shared client runtime under `shared/`.
- Do not make Android a cross-platform wrapper around HarmonyOS or iOS code.
- Do not delete or move existing HarmonyOS assets; Android asset conversion must copy source material and preserve design sources under `assets/`.

## Default Technical Choices

- Native Kotlin.
- Jetpack Compose for UI.
- Gradle Kotlin DSL.
- Android Gradle Plugin 9.1.x once the local environment supports it.
- JDK 17 for Android builds.
- Kotlin 2.x with the Compose Compiler Gradle plugin.
- JVM unit tests for pure domain logic.
- Compose UI tests for in-app UI semantics.
- UI Automator and `adb` scripting for HarmonyOS-like device automation parity.
- `adb reverse tcp:8123 tcp:8123` to mirror the HarmonyOS mock-server workflow where possible.
