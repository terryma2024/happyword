# iOS Replica Design Index

> Status: **bootstrap parity shipped (V0.7.1)** — native app under `ios/WordMagicGame/`; TestFlight gate documented in [`ios/release-pre.md`](../../ios/release-pre.md) (v0.7.0 build 1007004 verified 2026-05-16).
> Historical planning branch: `codex/ios-replica-plan`
> Scope: this folder remains the **design + phase map** for the iOS port; implementation lives in `ios/`, not in these markdown files alone.

## Goal

Replicate the HarmonyOS WordMagicGame client as a native iOS app (Swift / SwiftUI). **Phases 0–5 are landed** for the bootstrap 17-page matrix aligned with HarmonyOS V0.6.7.8 semantics (pack-keyed learning report, three-layer packs, binding, wishlist, local growth surfaces). Child learning flow is iPhone landscape-first; parent/admin surfaces are portrait-first.

**After V0.7.1**, new product capabilities follow [`docs/sop/00-three-platform-feature-sop.md`](../sop/00-three-platform-feature-sop.md) (`docs/features/<feature-id>/`), not open-ended edits to this replica index.

The plan is grounded in:

- HarmonyOS screenshots under `assets/screenshots/harmonyos/`.
- Product baseline in `docs/WordMagicGame_overall_spec.md`.
- Current HarmonyOS ArkTS pages, models, services, rawfiles, and route table.
- Historical specs and plans for V0.5.8 ParentAdmin, V0.6 parent account, V0.6.5 three-layer packs, and V0.6.7.8 learning report by pack.
- Shared contracts and fixtures under `shared/contracts/` and `shared/fixtures/`.

## Document Map

| File | Purpose |
| --- | --- |
| `01-screenshot-parity.md` | Visual source audit and iPhone adaptation rules by screen group. |
| `02-domain-logic.md` | Swift model/service boundaries mapped from current ArkTS logic. |
| `03-phase1-core-and-parent-admin.md` | Phase 1 design: Home, Battle, Result, Config entry, ParentAdmin, LessonDraftReview. |
| `04-pack-sync-and-parent-cloud.md` | Later phases for PackManager, binding, cloud sync, wishlist cloud, and report parity. |
| `05-validation-plan.md` | Verification matrix for docs, XCTest, XCUITest, screenshots, and contract fixtures. |
| `06-release-readiness-checklist.md` | Phase 5 release gates for debug routing, fixture parity, accessibility IDs, and TestFlight readiness. |
| `07-configpage-color-style-spec.md` | Current iOS ConfigPage color/style rules for future `ConfigView` edits. |

## Superpowers Phase Specs

The detailed phase implementation specs live under `docs/superpowers/specs/` so they match the existing Superpowers design-doc convention.

| Phase | Spec |
| --- | --- |
| Phase 0 | `docs/superpowers/specs/2026-05-10-ios-replica-phase0-environment-design.md` |
| Phase 1 | `docs/superpowers/specs/2026-05-10-ios-replica-phase1-core-parent-admin-design.md` |
| Phase 2 | `docs/superpowers/specs/2026-05-10-ios-replica-phase2-local-growth-pack-design.md` |
| Phase 3 | `docs/superpowers/specs/2026-05-10-ios-replica-phase3-parent-cloud-design.md` |
| Phase 4 | `docs/superpowers/specs/2026-05-10-ios-replica-phase4-debug-preview-design.md` |
| Phase 5 | `docs/superpowers/specs/2026-05-10-ios-replica-phase5-release-hardening-design.md` |

## Superpowers Implementation Plans

| Phase | Plan |
| --- | --- |
| Phase 3 | `docs/superpowers/plans/2026-05-11-ios-replica-phase3-parent-cloud.md` |

## Current Repository State

`ios/` contains a native Swift / SwiftUI project (`ios/project.yml` → `WordMagicGame.xcodeproj`), JVM-equivalent XCTest coverage for domain logic, XCUITest smoke flows, copied HarmonyOS art/audio under `ios/WordMagicGame/Resources/`, and release metadata in `ios/release-pre.md`. Parity scope matches the 17 HarmonyOS routes below; **V0.9 / V1.0.0 / V1.1.0** roadmap items (AI sentences, battle BGM, Cocos) are **out of bootstrap parity**.

## Current HarmonyOS Route Coverage

`harmonyos/entry/src/main/resources/base/profile/main_pages.json` registers **17 pages**. iOS maps each page to a phase; **all rows are implemented** for V0.7.1 bootstrap.

| HarmonyOS page | iOS phase | Bootstrap status |
| --- | --- | --- |
| `HomePage` | Phase 1 | Shipped — landscape entry + pack chip row. |
| `BattlePage` | Phase 1 | Shipped — playable combat surface. |
| `ResultPage` | Phase 1 | Shipped — stars and today reward summary. |
| `ConfigPage` | Phase 1 | Shipped — settings + ParentAdmin + PackManager entry. |
| `ParentAdminPage` | Phase 1 | Shipped — portrait parent surface. |
| `LessonDraftReviewPage` | Phase 1 | Shipped — portrait lesson review. |
| `ParentPinSetupPage` | Phase 1 | Shipped — PIN setup/edit gate. |
| `PackManagerPage` | Phase 2 | Shipped — three-layer pack activation, pin, sync. |
| `WishlistPage` | Phase 2 | Shipped — local wishlist + parent PIN redemption. |
| `RedemptionHistoryPage` | Phase 2 | Shipped — capped local history. |
| `MonsterCodexPage` | Phase 2 | Shipped — codex gallery. |
| `TodayPlanPage` | Phase 2 | Shipped — read-only daily plan. |
| `LearningReportPage` | Phase 2 | Shipped — pack-keyed report (V0.6.7.8). |
| `ScanBindingPage` | Phase 3 | Shipped — QR / short-code binding. |
| `BoundDeviceInfoPage` | Phase 3 | Shipped — profile + server unbind. |
| `DevMenuPage` | Phase 4 | Shipped — debug-only backend routing. |
| `BypassSecretPage` | Phase 4 | Shipped — debug-only preview bypass editor. |

## Phase Summary

| Phase | Theme | Deliverable |
| --- | --- | --- |
| Phase 0 | Environment and project setup | **Landed** — XcodeGen, schemes, lint/format policy. |
| Phase 1 | Core learning plus ParentAdmin | **Landed** — Home → Battle → Result; Config → PIN → ParentAdmin → LessonDraftReview. |
| Phase 2 | Local growth and pack management | **Landed** — PackManager, wishlist, codex, today plan, learning report. |
| Phase 3 | Parent cloud and device binding | **Landed** — binding, family/global pack sync, word-stats, device info. |
| Phase 4 | Debug and preview operations | **Landed** — DevMenu, backend switcher, preview bypass. |
| Phase 5 | Release hardening | **Landed** — screenshot parity, accessibility IDs, TestFlight upload (see `ios/release-pre.md`). |

## Non-Goals For This Index (ongoing)

- Do not treat this folder as the only spec for **post–V0.7.1 features** — use `docs/features/` + Harmony-first SOP.
- Do not change HarmonyOS behavior when doing iOS-only follow-ups unless parity checklist requires it.
- Do not introduce shared client runtime under `shared/`.
- Do not redesign the product away from the existing child-friendly magic-learning experience.

## Default Technical Choices For Later Implementation

- Native Swift / SwiftUI.
- XCTest for pure logic and DTO decoding.
- XCUITest for user operations, with stable `accessibilityIdentifier` coverage.
- XcodeGen generates `ios/WordMagicGame.xcodeproj` from `ios/project.yml`.
- iPhone landscape is the first child-flow viewport; ParentAdmin remains portrait.
