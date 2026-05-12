# Android Release Readiness Checklist

> Status: Phase 5 gate verified
> Updated: 2026-05-12

This checklist captures the Android release-hardening gate for the native
WordMagicGame replica. It complements `.cursor/android-dev-commands.md` and
the Phase 5 Superpowers plan.

## Required Automated Gates

- `cd android && ./gradlew testDebugUnitTest`
- `cd android && ./gradlew assembleDebug`
- `cd android && ./gradlew connectedDebugAndroidTest`
- `cd android && ./gradlew assembleRelease`

Latest verification on 2026-05-12:

- `testDebugUnitTest`: passed.
- `assembleDebug`: passed.
- `connectedDebugAndroidTest`: passed, 15/15 on `emulator-5556`.
- `assembleRelease`: passed. Gradle reported `libandroidx.graphics.path.so`
  could not be stripped and was packaged as-is; this did not fail the release
  build.

## Required Screenshot Baselines

All screenshots live under `assets/screenshots/android/`.

- `home.png`
- `battle.png`
- `battle-effects.png`
- `battle-effects-mid.png`
- `battle-effects-crit.png`
- `result.png`
- `config-landscape.png`
- `parent-pin-portrait.png`
- `parent-admin.png`
- `lesson-review-portrait.png`
- `pack-manager.png`
- `wishlist.png`
- `redemption-history.png`
- `monster-codex.png`
- `today-plan.png`
- `learning-report.png`
- `scan-binding.png`
- `bound-device-info.png`
- `dev-menu-debug.png`
- `bypass-secret-debug.png`

## Policy Gates

- Release builds do not expose Config developer entry points.
- Release builds coerce any persisted Local/Preview debug routing state back to
  release-safe Staging/Prod routing on launch.
- Production routing does not attach preview bypass headers.
- Failed pack sync keeps bundled/local packs playable.
- Failed word-stats sync does not block local Result or learning progress.
- Shared fixtures under `shared/fixtures/` are decoded by Android JVM tests.
- Android code consumes shared contracts and fixtures only; no shared client
  runtime code is added under `shared/`.
- Debug screenshots may include DevMenu and BypassSecret; release traversal must
  not expose those paths.

## Manual Review Notes

- Compare Android screenshots against HarmonyOS references by hierarchy,
  spacing, legibility, and touch-target comfort.
- Child-facing Home/Battle/Result screens stay landscape.
- Parent/admin screens stay portrait where the HarmonyOS flow is parent-facing.
- Keep `android/local.properties`, emulator state, and machine-specific SDK
  paths out of product configuration.
