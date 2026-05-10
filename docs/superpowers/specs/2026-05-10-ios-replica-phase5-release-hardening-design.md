# iOS Replica Phase 5 — Release Hardening And Parity Gates Design

> Status: design-for-implementation
> Date: 2026-05-10
> Scope: screenshot parity, accessibility identifiers, contract validation, performance, and TestFlight readiness.

## 1. Background

After the iOS feature phases are implemented, the app needs a release-hardening pass before TestFlight or broader family use. This phase turns the design and implementation into a verifiable native client that can evolve alongside HarmonyOS without drifting.

## 2. Goals

- Establish screenshot parity baselines under `assets/screenshots/ios/`.
- Require stable accessibility identifiers for every scripted path.
- Verify server contract fixtures decode in Swift.
- Ensure debug-only tools are absent from release builds.
- Confirm offline-first behavior across child flows.
- Prepare a TestFlight readiness checklist.

## 3. Non-Goals

- Do not add new product features in the hardening phase.
- Do not redesign the visual system.
- Do not replace server contracts.
- Do not clean up unrelated HarmonyOS or server code.

## 4. Source Evidence

Inputs:

- `assets/screenshots/harmonyos/*.png`
- `docs/WordMagicGame_overall_spec.md`
- `docs/WordMagicGame_roadmap.md`
- `docs/ios-replica/01-screenshot-parity.md`
- `shared/contracts/openapi/happyword-api.openapi.json`
- `shared/fixtures/**`
- HarmonyOS ohosTest identifiers from pages/components.

## 5. Screenshot Parity Gates

Required iOS screenshot set:

| iOS screenshot | Comparison source |
| --- | --- |
| `assets/screenshots/ios/home-iphone-landscape.png` | `assets/screenshots/harmonyos/home.png` |
| `assets/screenshots/ios/battle-iphone-landscape.png` | `assets/screenshots/harmonyos/battle.png` |
| `assets/screenshots/ios/result-iphone-landscape.png` | `assets/screenshots/harmonyos/result.png` |
| `assets/screenshots/ios/config-iphone-landscape.png` | `config-part*.png` |
| `assets/screenshots/ios/pack-manager-iphone-landscape.png` | `pack-manager.png` |
| `assets/screenshots/ios/wishlist-iphone-landscape.png` | `wishlist.png` |
| `assets/screenshots/ios/learning-report-iphone-landscape.png` | `learning-report-part*.png` |
| `assets/screenshots/ios/parent-admin-iphone-portrait.png` | `parent-admin-part*.png` |
| `assets/screenshots/ios/lesson-review-iphone-portrait.png` | V0.5.8 spec baseline |

Rules:

- Add iOS screenshots only after user approval.
- Keep source HarmonyOS screenshots unchanged.
- iPhone screenshots are judged by hierarchy, readable text, and interaction parity, not pixel coordinates.
- No text overlap or clipped primary controls is allowed.

## 6. Accessibility Identifier Policy

Rules:

- Every XCUITest target must use identifiers, not visible-text-only queries.
- Identifiers should mirror existing HarmonyOS ids when the semantic element is the same.
- Dynamic ids use the same suffix style where practical: `RegionChip_<packId>`, `PackToggle_<packId>`, `pack-<packId>`.
- Debug-only identifiers must be absent or unreachable in release UI traversal.

Minimum required groups:

- Home: title, coin, toolbar buttons, chip row, start button.
- Battle: combo, timer, prompt, speaker, answer buttons, player/monster areas.
- Result: title, stars, stats, coin rows, navigation buttons.
- Config: steppers, timer chips, custom timer, PIN, ParentAdmin, PackManager row.
- ParentAdmin: refresh, import buttons, draft rows, publish.
- LessonReview: rows, edit dialog, approve/reject.
- PackManager: sync, rows, source tags, pin, toggles.
- Cloud: ScanBinding, BoundDeviceInfo, unbind.

## 7. Contract And Fixture Gates

Swift tests must decode these fixtures:

- `shared/fixtures/packs/global-packs-latest.sample.json`
- `shared/fixtures/packs/family-packs-latest.sample.json`
- `shared/fixtures/pairing/pair-redeem.sample.json`
- `shared/fixtures/child/word-stats-sync.sample.json`
- `shared/fixtures/public/preview-urls.sample.json`

OpenAPI gate:

- The iOS DTO names may be native Swift names, but every API shape must map to `shared/contracts/openapi/happyword-api.openapi.json`.
- API drift is not accepted without updating `shared/contracts/**`.

## 8. Offline And Failure Gates

Must pass:

- Airplane mode launch reaches Home.
- Airplane mode starts a builtin battle.
- Airplane mode finishes battle and writes local result.
- Failed pack sync preserves cached/builtin packs.
- Failed word-stats sync does not block Result.
- Missing ParentAdmin network shows retry state, not app crash.
- Unbound device still has local playable flow.

## 9. Performance And UX Gates

Targets:

- Home first meaningful render from bundled data without network.
- Battle answer feedback has stable button layout; no jumpy answer row.
- ParentAdmin import progress shows immediately after image selection.
- Large local pack cache does not block the main thread during Home render.
- iPhone landscape touch targets remain comfortable for child use.

## 10. Release Build Gates

Before TestFlight:

- Release build hides DevMenu and BypassSecret.
- No preview bypass token is bundled.
- No mock server URL is bundled.
- ParentAdmin security caveat is still server-side and documented; iOS does not add a false auth layer.
- Privacy strings for camera/photo access exist if real image picking is enabled.
- App icon and launch assets are present and sourced from retained assets.

## 11. Final Verification Commands

Future implementation should provide exact commands similar to:

```sh
cd ios
xcodegen generate
xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=<iPhone target>'
swiftlint
swiftformat --lint .
```

If Xcode is unavailable on the machine, the branch cannot be called implementation-complete; it can only be docs-complete.

## 12. Acceptance Criteria

- iOS has screenshot baselines for all implemented phases.
- XCTest covers core rules, DTOs, stores, and fixture decoding.
- XCUITest covers child flow, ParentAdmin, pack management, and cloud binding.
- Release build hides debug tools.
- Offline-first behavior is explicitly verified.
- No runtime code exists under `shared/`.
