# Android Replica Phase 5 - Release Hardening And Parity Gates Design

> Status: design-for-implementation
> Date: 2026-05-11
> Scope: screenshot parity, accessibility/test tags, contract gates, offline and failure gates, performance, release variant checks, and distribution readiness.

## 1. Background

After Android implements the feature phases, it needs a hardening pass before broader family testing or store-style distribution. Phase 5 turns the Android app from a feature-complete replica into a verified native client that can evolve alongside HarmonyOS without visual, contract, or operational drift.

This phase should not add new product functionality. It verifies and tightens what already exists.

## 2. Goals

- Establish Android screenshot baselines under `assets/screenshots/android/`.
- Compare implemented Android screens against HarmonyOS screenshots.
- Require stable test tags for every scripted path.
- Decode shared fixtures and validate API DTO mappings.
- Prove offline-first behavior for child flows.
- Prove release builds hide debug-only DevMenu and preview bypass tools.
- Check performance-sensitive flows for visible jank or blocking work.
- Prepare an Android release readiness checklist.

## 3. Non-Goals

- Do not add new product screens.
- Do not redesign the visual language.
- Do not replace server contracts.
- Do not clean up unrelated HarmonyOS, iOS, or server code.
- Do not introduce cross-platform runtime code.
- Do not publish to Play Store as part of this spec.

## 4. Source Evidence

Inputs:

- `assets/screenshots/harmonyos/*.png`
- `assets/screenshots/android/*.png`
- `docs/WordMagicGame_overall_spec.md`
- `docs/WordMagicGame_roadmap.md`
- `docs/android-replica/02-screenshot-parity.md`
- `docs/android-replica/06-validation-plan.md`
- `.cursor/android-dev-commands.md`
- `shared/contracts/openapi/happyword-api.openapi.json`
- `shared/contracts/protocols/*.md`
- `shared/fixtures/**`

## 5. Screenshot Parity Gates

Required Android screenshot set:

| Android screenshot | Comparison source |
| --- | --- |
| `assets/screenshots/android/home.png` | `assets/screenshots/harmonyos/home.png` |
| `assets/screenshots/android/battle.png` | `assets/screenshots/harmonyos/battle.png` |
| `assets/screenshots/android/result.png` | `assets/screenshots/harmonyos/result.png` |
| `assets/screenshots/android/config-landscape.png` | `assets/screenshots/harmonyos/config-part*.png` |
| `assets/screenshots/android/parent-pin-portrait.png` | `assets/screenshots/harmonyos/parent-pin-setup.png` |
| `assets/screenshots/android/parent-admin.png` | `assets/screenshots/harmonyos/parent-admin-part*.png` |
| `assets/screenshots/android/lesson-review-portrait.png` | V0.5.8 parent-admin baseline |
| `assets/screenshots/android/pack-manager.png` | `assets/screenshots/harmonyos/pack-manager.png` |
| `assets/screenshots/android/wishlist.png` | `assets/screenshots/harmonyos/wishlist.png` |
| `assets/screenshots/android/redemption-history.png` | `assets/screenshots/harmonyos/redemption-history.png` |
| `assets/screenshots/android/monster-codex.png` | `assets/screenshots/harmonyos/monster-codex-part*.png` |
| `assets/screenshots/android/today-plan.png` | `assets/screenshots/harmonyos/today-plan.png` |
| `assets/screenshots/android/learning-report.png` | `assets/screenshots/harmonyos/learning-report-part*.png` |
| `assets/screenshots/android/bound-device-info.png` | `assets/screenshots/harmonyos/bound-device-info.png` |
| `assets/screenshots/android/dev-menu-debug.png` | `assets/screenshots/harmonyos/dev-menu.png` |
| `assets/screenshots/android/bypass-secret-debug.png` | `assets/screenshots/harmonyos/bypass-secret.png` |

Rules:

- Add or replace Android screenshots only after the relevant screen is implemented.
- Keep HarmonyOS source screenshots unchanged.
- Judge by hierarchy, spacing, text readability, touch target size, and interaction parity.
- No clipped primary labels, overlapping controls, or unreadable button text.
- Battle screenshots should include at least one normal hit and one combo/crit frame.

## 6. Test Tag Policy

Rules:

- Every Compose UI test target must use stable `testTag` values where possible.
- Tests can query visible text for dynamic answer options, but stable container tags must still exist.
- Dynamic ids use suffix style: `RegionChip_<packId>`, `PackToggle_<packId>`, `LearningReportPackRow_<packId>`.
- Debug-only tags must be absent or unreachable in release traversal.

Minimum required groups:

- Home: `HomeScreen`, title, version label, coin/profile badges, toolbar buttons, chip row, start button.
- Battle: `BattleScreen`, combo, timer, prompt, speaker, answer buttons, player panel, monster panel.
- Result: result title, stars, stat rows, home button.
- Config: timer presets, custom timer, auto speak, ParentAdmin, PackManager, Developer row.
- ParentAdmin: refresh/import/publish controls and draft rows.
- LessonReview: word rows, edit dialog, approve/reject.
- PackManager: sync, row labels, source tags, pin, toggles.
- Growth: Wishlist, RedemptionHistory, MonsterCodex, TodayPlan, LearningReport.
- Cloud: ScanBinding, BoundDeviceInfo, unbind.
- Debug: DevMenu and BypassSecret debug-only tags.

## 7. Contract And Fixture Gates

JVM tests must decode or encode these fixtures:

- `shared/fixtures/packs/global-packs-latest.sample.json`
- `shared/fixtures/packs/family-packs-latest.sample.json`
- `shared/fixtures/pairing/pair-redeem.sample.json`
- `shared/fixtures/child/word-stats-sync.sample.json`
- `shared/fixtures/public/preview-urls.sample.json`

OpenAPI gate:

- Android DTO names can be idiomatic Kotlin names.
- Every request/response shape must map to `shared/contracts/openapi/happyword-api.openapi.json` or documented protocol markdown.
- API drift requires updating `shared/contracts/**` in the same change.
- Client code must not use server-only models directly.

## 8. Offline And Failure Gates

Must pass:

- Airplane mode launch reaches Home.
- Airplane mode starts a builtin battle.
- Airplane mode finishes battle and writes local result.
- Failed pack sync preserves cached and builtin packs.
- Failed word-stats sync does not block Result.
- Missing ParentAdmin network shows retry or local empty state, not app crash.
- Unbound device still has local playable flow.
- Bound credentials rejected by 401/410 show rebind guidance and do not erase local progress without user-visible explanation.

## 9. Performance And UX Gates

Targets:

- Home first render uses bundled/cached data without network.
- Battle answer feedback keeps answer row stable during 650 ms feedback window.
- TTS and SFX do not block the main thread.
- Pack cache decode does not block Home render for large cached packs.
- ParentAdmin image-import progress appears immediately after selection.
- Landscape child screens keep comfortable touch targets.
- Portrait parent screens are readable on phone-width devices.

Suggested verification:

- Use Android Studio profiler or `adb logcat` plus manual timing for obvious hangs.
- Add small benchmark-style JVM tests only where pure parsing/building work can be measured deterministically.
- Use screenshots to catch overlap and clipping.

## 10. Release Build Gates

Before release-style distribution:

- Release build hides DevMenu and BypassSecret.
- Release build has no preview bypass token bundled.
- Release build has no mock server URL as default.
- Debug-only Config Developer row is absent.
- App icon matches HarmonyOS/source asset direction.
- Privacy strings/permissions are present only for features actually enabled.
- Camera/photo permission prompts are understandable if QR scan or lesson import is enabled.
- ParentAdmin security caveat remains server-side; Android does not add a false local-auth guarantee for server operations.
- `android/local.properties`, emulator config, and machine paths are not committed as product configuration.

## 11. Verification Commands

Required commands before claiming Phase 5 complete:

```sh
cd android
./gradlew testDebugUnitTest
./gradlew connectedDebugAndroidTest
./gradlew assembleDebug
```

Release or release-like gate:

```sh
cd android
./gradlew assembleRelease
```

Manual install and screenshot loop:

```sh
cd android
./gradlew installDebug
adb -s <serial> shell am start -n cool.happyword.wordmagic/.MainActivity
adb -s <serial> exec-out screencap -p > ../assets/screenshots/android/home.png
```

If release signing is not configured, `assembleRelease` may produce an unsigned release artifact or fail at signing. In that case, Phase 5 can only be considered release-hardening-complete after the signing gap is documented and a release-like variant still proves debug UI is absent.

## 12. CI Readiness

Minimum CI goals:

- JVM tests on every Android change.
- Debug assemble on every Android change.
- Instrumented tests on a known emulator image when CI capacity exists.
- Artifact upload for unit test reports and instrumented test reports.
- Optional screenshot artifact upload for parity review.

CI must not require a developer's local Android Studio GUI.

## 13. Acceptance Criteria

- Android screenshots exist for every implemented phase and are stored under `assets/screenshots/android/`.
- JVM tests cover core rules, local stores, DTO decoding, and fixture compatibility.
- Compose UI tests cover child flow, ParentAdmin, pack management, cloud binding, and debug gating.
- Release build hides debug tools and contains no preview/mock defaults.
- Offline-first behavior is explicitly verified.
- No runtime code exists under `shared/`.
- The Android command manifest remains current with the commands used to verify the release-hardening pass.
