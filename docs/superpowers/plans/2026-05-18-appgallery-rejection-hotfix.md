# AppGallery Rejection Hotfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all non-备案 AppGallery rejection items across HarmonyOS, iOS, and Android, while documenting the still-pending APP备案 gate.

**Architecture:** Add small platform-native compliance surfaces instead of introducing shared client runtime. HarmonyOS gets the production package changes first; iOS and Android mirror visible privacy and report affordances so parity does not drift.

**Tech Stack:** ArkTS / ArkUI, SwiftUI, Kotlin / Jetpack Compose, existing native test suites.

---

### Task 1: Release Todo And Resubmission Notes

**Files:**
- Create: `docs/release/appgallery-v0.7.0-rejection-hotfix-todo.md`
- Modify: `harmonyos/release-pre.md`

- [x] Record the five AppGallery review items, marking APP备案 as externally pending.
- [x] Add the screenshot resubmission requirement: at least three same-size, clear, landscape screenshots with different app scenes.
- [x] Add the resubmission note that the server-location checkbox must match the approved APP备案 information.

### Task 2: HarmonyOS Privacy Consent

**Files:**
- Create: `harmonyos/entry/src/main/ets/services/CompliancePolicy.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/HomePage.ets`
- Test: `harmonyos/entry/src/test/CompliancePolicy.test.ets`

- [x] Write tests for compliance URLs and privacy consent prefs constants.
- [x] Implement constants for terms, privacy, support, report URL, support email, and privacy consent storage.
- [x] Show a first-launch privacy dialog on HomePage when consent is not recorded.
- [x] Include visible links/buttons for privacy policy and user agreement.
- [x] Only dismiss the dialog after the user taps agree.

### Task 3: HarmonyOS Minor Report Channel

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/ConfigPage.ets`
- Test: `harmonyos/entry/src/ohosTest/ets/test/ConfigFlow.ui.test.ets`

- [x] Add a visible `投诉与举报` row in ConfigPage.
- [x] Open the public support/report URL from the row using the existing system browser helper.
- [x] Add UI coverage that the report row is visible from ConfigPage.

### Task 4: HarmonyOS UX Fixes

**Files:**
- Modify: `harmonyos/entry/src/main/ets/pages/ConfigPage.ets`
- Modify: `harmonyos/entry/src/main/ets/pages/BattlePage.ets`
- Test: `harmonyos/entry/src/ohosTest/ets/test/ConfigFlow.ui.test.ets`

- [x] Write UI coverage for player HP, monster HP, and monster count changing immediately.
- [x] Update ConfigPage steppers to assign a fresh `GameConfig` instance per tap.
- [x] Add a small saved-state hint so reviewers can see changes are applied.
- [x] Improve low-contrast labels called out by store checks.

### Task 5: iOS Parity

**Files:**
- Modify: `ios/WordMagicGame/Services/SystemBrowser.swift`
- Modify: `ios/WordMagicGame/App/ContentView.swift`
- Modify: `ios/WordMagicGame/Features/Settings/ConfigView.swift`
- Modify: `ios/WordMagicGame/Features/Settings/CloudBindingViews.swift`
- Test: `ios/WordMagicGameTests/AppMetadataTests.swift`

- [x] Add privacy/terms/support/report constants.
- [x] Show first-launch privacy disclosure with policy links and an agree action.
- [x] Add `投诉与举报` row to ConfigView.
- [x] Add privacy/terms links to the binding/login surface.
- [x] Confirm ConfigView steppers already update immediately; add test coverage for compliance constants.

### Task 6: Android Parity

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/CompliancePolicy.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/navigation/WordMagicGameApp.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/config/ConfigUi.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/DebugRoutingTest.kt`

- [x] Add privacy/terms/support/report constants.
- [x] Show first-launch privacy disclosure with policy links and an agree action.
- [x] Add `投诉与举报` row to ConfigScreen.
- [x] Add privacy/terms links to the binding/login surface.
- [x] Confirm ConfigScreen steppers already update immediately; add test coverage for compliance constants.

### Task 7: Verification

**Commands:**
- HarmonyOS: `cd harmonyos && hvigorw --mode module -p module=entry assembleHap`
- HarmonyOS lint: `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
- iOS: run available XCTest target if local Xcode toolchain is present.
- Android: `cd android && ./gradlew testDebugUnitTest`

- [ ] Run available automated validation.
- [ ] Leave `harmonyos/build-profile.json5` unstaged because it contains local signing material.
- [ ] Summarize residual manual gates: APP备案 approval, screenshots upload, real-device release smoke.
