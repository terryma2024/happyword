# Android Replica Design Index

> Status: Phase 5 release-hardening gate in progress
> Implementation branch: `codex/android-replica-phase5` merged via PR #66
> Scope: native Kotlin / Jetpack Compose Android replication of the current HarmonyOS client.

## Goal

Create and maintain a staged, testable native Android replica of the current HarmonyOS WordMagicGame client. The Android implementation is phone-first: child learning screens are landscape-first, while parent/admin screens are portrait-first.

This plan is grounded in:

- HarmonyOS screenshots under `assets/screenshots/harmonyos/`.
- Product baseline in `docs/WordMagicGame_overall_spec.md`.
- Current HarmonyOS ArkTS pages, services, models, rawfiles, and route table.
- Existing iOS replica planning under `docs/ios-replica/`.
- Shared contracts and fixtures under `shared/contracts/` and `shared/fixtures/`.
- Android official guidance for Android Studio, SDK command-line tools, Compose testing, UI Automator, and Android Gradle Plugin compatibility.

## Current Repository State

`android/` now contains a native Kotlin / Jetpack Compose project with Gradle wrapper, core battle flow, parent/admin flow, local growth and pack-management screens, cloud binding/debug routing surfaces, copied HarmonyOS art/audio resources, JVM tests, Compose UI tests, screenshot capture tests, and release-hardening gates.

Phase 0-4 feature work has landed in the Android module. Phase 5 is the active gate: keep release/debug policy, offline fallback, screenshot baselines, and Gradle verification current before treating Android as release-ready. `shared/` remains contracts/fixtures only.

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

Future Android work should continue to use focused Superpowers plans for each follow-up slice instead of drifting into a single untracked mega-port.

## Current HarmonyOS Route Coverage

`harmonyos/entry/src/main/resources/base/profile/main_pages.json` currently registers 17 pages. Android assigns each page to a phase so the port can proceed in working slices.

| HarmonyOS page | Android phase | Current Android status |
| --- | --- | --- |
| `HomePage` | Phase 1 | Implemented; covered by smoke/screenshot flows. |
| `BattlePage` | Phase 1 | Implemented with native battle engine, assets, TTS/audio path, and effect screenshots. |
| `ResultPage` | Phase 1 | Implemented with result summary and local reward/progress wiring. |
| `ConfigPage` | Phase 1 / 4 | Implemented with parent PIN, cloud binding entry, and debug-only developer entry. |
| `ParentPinSetupPage` | Phase 1 | Implemented as the local parent gate/edit flow. |
| `ParentAdminPage` | Phase 1 | Implemented as a portrait parent surface with fixture-backed review flow. |
| `LessonDraftReviewPage` | Phase 1 | Implemented as the parent lesson-review surface. |
| `PackManagerPage` | Phase 2 | Implemented with local pack selection, sync action, and pack status UI. |
| `WishlistPage` | Phase 2 | Implemented with local wishes, coin balance, and parent-gated redemption. |
| `RedemptionHistoryPage` | Phase 2 | Implemented with local capped redemption history. |
| `MonsterCodexPage` | Phase 2 | Implemented with native card/gallery flow and copied character assets. |
| `TodayPlanPage` | Phase 2 | Implemented from local pack/library and learning stats. |
| `LearningReportPage` | Phase 2 | Implemented with pack-keyed report semantics. |
| `ScanBindingPage` | Phase 3 | Implemented with manual short-code path and QR/gallery UI placeholders. |
| `BoundDeviceInfoPage` | Phase 3 | Implemented with bound profile, manual sync, and unbind flow. |
| `DevMenuPage` | Phase 4 | Implemented as debug-only backend environment/preview routing surface. |
| `BypassSecretPage` | Phase 4 | Implemented as debug-only preview deployment bypass token editor. |

## Phase Summary

| Phase | Theme | Deliverable |
| --- | --- | --- |
| Phase 0 | Environment and project bootstrap | Landed: Android Gradle project, wrapper, app/test targets, first green build path. |
| Phase 1 | Core learning plus ParentAdmin | Landed: Home -> Battle -> Result and Config -> PIN -> ParentAdmin -> LessonDraftReview. |
| Phase 2 | Local growth and pack management | Landed: PackManager, wishlist, codex, today plan, local learning report. |
| Phase 3 | Parent cloud and device binding | Landed: binding surfaces, fixture-backed family/global pack sync, word-stats sync payload, device info. |
| Phase 4 | Debug and preview operations | Landed: DevMenu, backend switcher, preview bypass, mock/preview routing. |
| Phase 5 | Release hardening | Active gate: screenshot parity, release/debug policy, offline fallback tests, release variant and CI readiness. |

## Non-Goals For This Planning Pass

- Do not change HarmonyOS behavior as part of Android planning.
- Do not introduce shared client runtime under `shared/`.
- Do not make Android a cross-platform wrapper around HarmonyOS or iOS code.
- Do not delete or move existing HarmonyOS assets; Android asset conversion must copy source material and preserve design sources under `assets/`.
- Do not treat Phase 5 as product-feature scope; it is for gates, parity, fallback, release/debug policy, and documentation hygiene.

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
