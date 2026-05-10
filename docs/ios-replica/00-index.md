# iOS Replica Design Index

> Status: design-for-implementation
> Target branch: `codex/ios-replica-plan`
> Scope: docs-only plan for native Swift / SwiftUI iOS replication. No iOS project files are created in this pass.

## Goal

Create a staged, component-level plan for replicating the current HarmonyOS WordMagicGame client as a native iOS app. The first implementation target is iPhone landscape for the child learning flow, with ParentAdmin and LessonDraftReview included in Phase 1 as portrait-only parent surfaces.

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

## Current HarmonyOS Route Coverage

`harmonyos/entry/src/main/resources/base/profile/main_pages.json` currently registers 17 pages. iOS implementation planning assigns each page to a phase so the port can proceed in slices instead of as a single rewrite.

| HarmonyOS page | iOS phase | Notes |
| --- | --- | --- |
| `HomePage` | Phase 1 | iPhone landscape, core entry and pack chip row shell. |
| `BattlePage` | Phase 1 | iPhone landscape, first playable combat surface. |
| `ResultPage` | Phase 1 | iPhone landscape, stars and today reward summary. |
| `ConfigPage` | Phase 1 | Landscape settings shell with ParentAdmin entry and Phase 2 PackManager entry placeholder. |
| `ParentAdminPage` | Phase 1 | Portrait parent surface, included in first slice by product decision. |
| `LessonDraftReviewPage` | Phase 1 | Portrait review surface with mock/fake adapter first, real API boundary preserved. |
| `ParentPinSetupPage` | Phase 1 | Minimal PIN setup/edit flow needed to gate ParentAdmin. |
| `PackManagerPage` | Phase 2 | Three-layer pack activation, pin, sync, and rotation UI. |
| `WishlistPage` | Phase 2 | Local magic-wishlist loop after core battle rewards exist. |
| `RedemptionHistoryPage` | Phase 2 | Local history store and list rendering. |
| `MonsterCodexPage` | Phase 2 | Visual codex parity after character asset pipeline lands. |
| `TodayPlanPage` | Phase 2 | Read-only daily plan from iOS TodayAdventureBuilder. |
| `LearningReportPage` | Phase 2 | Pack-keyed report, aligned with V0.6.7.8. |
| `ScanBindingPage` | Phase 3 | QR/short-code binding after local and pack sync surfaces are stable. |
| `BoundDeviceInfoPage` | Phase 3 | Child profile and unbind flow. |
| `DevMenuPage` | Phase 4 | Debug-only environment routing and preview bypass helpers. |
| `BypassSecretPage` | Phase 4 | Debug-only preview deployment bypass token editor. |

## Phase Summary

| Phase | Theme | Deliverable |
| --- | --- | --- |
| Phase 0 | Environment and project setup | Xcode, XcodeGen, lint/format policy, scheme/test plan design. |
| Phase 1 | Core learning plus ParentAdmin | Home -> Battle -> Result and Config -> PIN -> ParentAdmin -> LessonDraftReview. |
| Phase 2 | Local growth and pack management | PackManager, wishlist, codex, today plan, local learning report. |
| Phase 3 | Parent cloud and device binding | Binding, family/global pack sync, word-stats sync, device info. |
| Phase 4 | Debug and preview operations | DevMenu, backend environment switcher, preview bypass, smoke tooling. |
| Phase 5 | Release hardening | Screenshot parity, accessibility identifiers, TestFlight readiness. |

## Non-Goals For This Docs Pass

- Do not create `ios/project.yml`, `.xcodeproj`, Swift files, assets, or tests.
- Do not change HarmonyOS, server, or shared contract runtime code.
- Do not introduce shared client runtime under `shared/`.
- Do not redesign the product away from the existing child-friendly magic-learning experience.

## Default Technical Choices For Later Implementation

- Native Swift / SwiftUI.
- XCTest for pure logic and DTO decoding.
- XCUITest for user operations, with stable `accessibilityIdentifier` coverage.
- XcodeGen is preferred for project reproducibility, but this docs pass only records the choice.
- iPhone landscape is the first child-flow viewport; ParentAdmin remains portrait.
