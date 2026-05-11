# Android Replica Phase 3 Parent Cloud And Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Android child-device binding, cloud credential state, fixture-compatible pack/stat sync, BoundDeviceInfo, and parent-PIN-gated unbind without weakening offline play.

**Architecture:** Mirror HarmonyOS cloud services with pure Kotlin interfaces first: device id, binding client, credential store, pack sync clients, word-stats payload builder, and sync coordinator. Android UI uses those interfaces through a local repository and fixture-backed clients now; Phase 4 can replace the fixture transport with debug-selectable backend routing without rewriting screens or domain tests.

**Tech Stack:** Kotlin, Jetpack Compose Material3, `SharedPreferences` for non-secret labels, app-private file storage for the device token, JUnit4, Compose UI tests.

---

## Scope Boundary

This plan implements the Android Phase 3 cloud skeleton and offline-safe local sync behavior. It does not require a real server to pass tests. It does not cloud-sync active pack selection or pins. It does not expose debug backend switching; Phase 4 owns runtime environment selection.

## File Structure

| File | Action | Responsibility |
| --- | --- | --- |
| `android/app/src/main/java/cool/happyword/wordmagic/core/CloudModels.kt` | Create | Device id, credentials, binding result, sync result, fixture clients, coordinator |
| `android/app/src/main/java/cool/happyword/wordmagic/data/AndroidCloudRepositories.kt` | Create | Android storage for device id, token file, cloud labels, cached global/family pack layers |
| `android/app/src/main/java/cool/happyword/wordmagic/ui/Phase3Screens.kt` | Create | ScanBinding and BoundDeviceInfo Compose screens |
| `android/app/src/main/java/cool/happyword/wordmagic/ui/Phase2Screens.kt` | Modify | Add PackManager manual sync callback |
| `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt` | Modify | Add ScanBinding/BoundDeviceInfo routes, cloud state, manual sync, unbind |
| `android/app/src/test/java/cool/happyword/wordmagic/core/CloudModelsTest.kt` | Create | Device id stability, credential save/clear, binding, sync coordinator, stats payload |
| `android/app/src/androidTest/java/cool/happyword/wordmagic/Phase3FlowTest.kt` | Create | Config -> ScanBinding -> BoundDeviceInfo -> unbind UI flow |
| `docs/android-replica/00-index.md` | Modify | Link Phase 3 implementation plan |
| `.cursor/android-dev-commands.md` | Modify | Add Phase 3 verification commands |

## Task 1: Cloud Core Models And Fixture Clients

- [ ] Create `CloudModels.kt` with stable `DeviceIdProvider`, `CloudCredentialsStore`, fixture binding, fixture pack sync, word-stats payload builder, and offline-safe coordinator.
- [ ] Add JVM tests proving device id stability, token not stored in normal prefs, binding save/clear, fixture global/family sync, and coordinator failure isolation.
- [ ] Run `cd android && ./gradlew testDebugUnitTest`.

## Task 2: Android Cloud Repository

- [ ] Create `AndroidCloudRepositories.kt` using `SharedPreferences` for non-secret labels and an app-private `cloud_device_token.secure` file for token storage.
- [ ] Expose load/save for credentials, cached global packs, cached family packs, and sync status.
- [ ] Run `cd android && ./gradlew testDebugUnitTest`.

## Task 3: ScanBinding And BoundDeviceInfo UI

- [ ] Create `Phase3Screens.kt` with `ScanBindingScreen` and `BoundDeviceInfoScreen`.
- [ ] Required tags: `ScanBindingScreen`, `ScanBindingManualCodeInput`, `ScanBindingRedeemButton`, `ScanBindingError`, `BoundDeviceInfoScreen`, `BoundDeviceInfoNickname`, `BoundDeviceInfoSyncStatus`, `BoundDeviceInfoManualSync`, `BoundDeviceInfoUnbind`.
- [ ] Add routes in `MainActivity`: `ScanBinding`, `BoundDeviceInfo`.
- [ ] Add a Config card showing bound/unbound state and opening the correct route.
- [ ] Run `cd android && ./gradlew assembleDebug`.

## Task 4: Pack Sync And Word Stats Integration

- [ ] Make `PackManagerScreen` sync button call `CloudSyncCoordinator.syncPacks`.
- [ ] Keep Home/Battle/Result playable when sync throws.
- [ ] Merge cached global/family packs with builtin packs through `PackLibrary.merge`.
- [ ] Trigger non-blocking stats payload build after battle result and store the successful checkpoint only after coordinator success.
- [ ] Run `cd android && ./gradlew testDebugUnitTest`.

## Task 5: Compose UI Tests And Screenshots

- [ ] Add `Phase3FlowTest` for manual-code bind, BoundDeviceInfo display, manual sync, and parent-PIN-gated unbind.
- [ ] Add screenshot capture for `phase3-scan-binding.png` and `phase3-bound-device-info.png`.
- [ ] Run:

```bash
cd android && ./gradlew testDebugUnitTest
cd android && ./gradlew assembleDebug
cd android && ./gradlew connectedDebugAndroidTest
```

## Acceptance Checklist

- [ ] Manual short-code binding changes the Android app from unbound to bound.
- [ ] BoundDeviceInfo shows nickname, family label, shortened device id, and sync status.
- [ ] Unbind requires parent PIN and clears cloud credentials without deleting local progress.
- [ ] Pack sync can add fixture global/family layers and preserves offline builtin packs on failure.
- [ ] Word-stats sync builds a contract-shaped payload without blocking Result.
- [ ] Device token is not stored in normal SharedPreferences.
- [ ] Android tests cover core cloud rules and UI bound/unbound transitions.
