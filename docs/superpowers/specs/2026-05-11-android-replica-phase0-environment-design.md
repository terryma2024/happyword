# Android Replica Phase 0 Environment Design

## Status

Design-for-implementation.

## Goal

Create a reproducible Android development baseline for the native Kotlin / Jetpack Compose client under `android/`, including local setup, Gradle bootstrap, first app shell, and first test gates.

## Current State

The repository has `android/README.md` only. The local machine currently has OpenJDK 23 but no Android Studio, no Android SDK, no `adb`, no `sdkmanager`, no `avdmanager`, and no `~/Library/Android` SDK directory.

## Environment Target

| Component | Target |
| --- | --- |
| IDE | Android Studio latest stable from official installer |
| SDK path | `~/Library/Android/sdk` |
| JDK | 17, preferably Android Studio bundled JBR |
| Android Gradle Plugin | 9.1.x after SDK exists |
| Gradle | Wrapper-managed, compatible with AGP 9.1.x |
| Compile SDK | API 36 line initially |
| Build Tools | 36.0.0 initially |
| Emulator | `WordMagicGame_API36` |
| Language | Kotlin |
| UI | Jetpack Compose |
| Package id | `cool.happyword.wordmagic` until product/store naming changes |

## Repository Deliverable

The first Android implementation slice should create:

```text
android/settings.gradle.kts
android/build.gradle.kts
android/gradle.properties
android/.gitignore
android/gradlew
android/gradlew.bat
android/gradle/wrapper/gradle-wrapper.jar
android/gradle/wrapper/gradle-wrapper.properties
android/app/build.gradle.kts
android/app/src/main/AndroidManifest.xml
android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt
android/app/src/main/java/cool/happyword/wordmagic/app/AppMetadata.kt
android/app/src/test/java/cool/happyword/wordmagic/app/AppMetadataTest.kt
android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt
```

Do not commit `android/local.properties`.

## Build Variants

Start with standard `debug` and `release`.

Rules:

- Debug may expose future DevMenu.
- Release must not expose future DevMenu, preview bypass, or test-only mock routing controls.
- Phase 0 only proves variant creation; Phase 4 implements debug operations.

## First App Shell

The first running app should show a minimal Compose screen:

```text
WordMagicGame Android
Environment ready
```

It is intentionally not the product Home screen. Product UI starts in Phase 1 after build/test infrastructure is green.

## Test Policy

Phase 0 must include:

- One JVM test verifying app metadata/package constants.
- One connected Compose smoke test verifying the minimal shell text exists.

Verification:

```sh
cd android
./gradlew testDebugUnitTest
./gradlew assembleDebug
./gradlew connectedDebugAndroidTest
```

## Handoff Boundary

Codex can implement repo-local files after the developer installs Android Studio/SDK and exports Android tool paths. Codex cannot complete the current machine setup without external downloads, license prompts, and GUI setup.
