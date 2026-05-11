# Android Environment Initialization Plan

## Current Machine Check

Checked on 2026-05-11 from the repo root.

| Check | Result | Meaning |
| --- | --- | --- |
| `java -version` | OpenJDK 23.0.2 from Homebrew | Java exists, but Android Gradle Plugin expects JDK 17. Use Android Studio bundled JBR 17 or install a dedicated JDK 17. |
| `which gradle` | not found | No system Gradle. This is fine once `android/gradlew` exists. |
| `which adb` | not found | Android SDK Platform Tools are not installed or not on `PATH`. |
| `which sdkmanager` | not found | Android SDK Command-Line Tools are not installed. |
| `which avdmanager` | not found | Android virtual device tooling is not installed. |
| `/Applications/Android Studio.app` | not found | Android Studio is not installed. |
| `~/Library/Android` | not found | No local Android SDK directory exists. |

I cannot complete the full Android environment setup from inside this workspace because it requires downloading Android Studio or command-line tools, accepting Android SDK licenses, and writing to user/system tool directories outside the repo. Those are outside the current sandbox and also need GUI/account/license decisions.

## Recommended Installation Path

Use Android Studio first, then make command-line use deterministic.

Official references:

- Android Studio install: <https://developer.android.com/studio/install>
- `sdkmanager`: <https://developer.android.com/tools/sdkmanager>
- Emulator CLI: <https://developer.android.com/studio/run/emulator-commandline>
- Android Gradle Plugin releases and compatibility: <https://developer.android.com/build/releases/gradle-plugin>
- Compose Compiler / Kotlin compatibility: <https://developer.android.com/jetpack/androidx/releases/compose-kotlin>

As of the checked docs, Android Gradle Plugin 9.1 uses JDK 17, Gradle 9.3.1, SDK Build Tools 36.0.0, and supports API level 36.1.

## Step 1: Install Android Studio

Manual action for the developer:

1. Download Android Studio from <https://developer.android.com/studio>.
2. Open the DMG.
3. Drag Android Studio into `/Applications`.
4. Launch Android Studio.
5. Complete the Setup Wizard.
6. Let it install the Android SDK, Platform Tools, Emulator, and a recent API platform/system image.

Recommended SDK path:

```sh
~/Library/Android/sdk
```

Android Studio normally uses that path on macOS.

## Step 2: Export Android Tool Paths

Add this to the shell profile used by Codex and terminal sessions, usually `~/.zshrc`:

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
```

Reload:

```sh
source ~/.zshrc
```

Verify:

```sh
adb version
sdkmanager --version
avdmanager --help
```

Expected:

- `adb version` prints Android Debug Bridge version.
- `sdkmanager --version` prints a version number.
- `avdmanager --help` prints command help.

## Step 3: Ensure JDK 17

Preferred path: use Android Studio's bundled runtime through Gradle:

```properties
org.gradle.java.home=/Applications/Android Studio.app/Contents/jbr/Contents/Home
```

This should live in the local-only file:

```text
android/local.properties
```

Do not commit machine-specific `local.properties`.

Verification:

```sh
"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" -version
```

Expected:

- A Java 17 runtime.

If Android Studio's runtime path differs, inspect:

```sh
ls "/Applications/Android Studio.app/Contents"
```

## Step 4: Install Required SDK Packages

After `sdkmanager` exists:

```sh
sdkmanager --install \
  "platform-tools" \
  "emulator" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "cmdline-tools;latest" \
  "system-images;android-36;google_apis;arm64-v8a"
```

Accept licenses:

```sh
sdkmanager --licenses
```

Expected:

- No pending license prompts after the final run.
- `adb version` works.
- `emulator -list-avds` works, even if it prints no devices yet.

## Step 5: Create AVD

Use Android Studio Device Manager, or command line:

```sh
avdmanager create avd \
  --name WordMagicGame_API36 \
  --package "system-images;android-36;google_apis;arm64-v8a" \
  --device "pixel_8"
```

List:

```sh
emulator -list-avds
```

Start:

```sh
emulator -avd WordMagicGame_API36
```

Verify device:

```sh
adb devices
```

Expected:

- One emulator listed as `device`.

## Step 6: Repo Bootstrap After Tooling Exists

Create the Android project from Android Studio or Gradle templates with these constraints:

| Setting | Value |
| --- | --- |
| Location | `android/` |
| Language | Kotlin |
| UI | Jetpack Compose |
| Package | `cool.happyword.wordmagic` |
| Minimum SDK | 26 unless product support data says otherwise |
| Target/compile SDK | API 36 line initially |
| Build scripts | Kotlin DSL |
| Shared code | none under `shared/`; consume contracts/fixtures only |

The first committed Android slice must include:

- `android/settings.gradle.kts`
- `android/build.gradle.kts`
- `android/gradle/wrapper/*`
- `android/gradlew`
- `android/gradlew.bat`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`
- `android/app/src/test/.../AppMetadataTest.kt`
- `android/app/src/androidTest/.../SmokeTest.kt`
- `android/.gitignore`

## Step 7: First Verification Commands

From repo root:

```sh
cd android
./gradlew --version
./gradlew testDebugUnitTest
./gradlew assembleDebug
./gradlew connectedDebugAndroidTest
```

Expected:

- Gradle reports JDK 17.
- JVM tests pass.
- Debug APK builds.
- Connected Android test passes on the emulator.

## Step 8: Mock Server And Device Automation Parity

Android should mirror the current HarmonyOS UI automation shape:

```sh
cd server
uv run python mock_ui_server.py
```

In another terminal:

```sh
adb reverse tcp:8123 tcp:8123
cd android
./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.serverBaseUrl=http://127.0.0.1:8123
```

Target behavior:

- Instrumentation tests can route the app to the local mock server.
- Android tests use the same conceptual mock-server boundary as HarmonyOS `scripts/run_ui_tests.sh`.

## Agent-Owned Work After You Install Tools

Once Android Studio/SDK exists and the `PATH` exports are active, Codex can do the repo-local work:

1. Generate or normalize the Gradle project inside `android/`.
2. Add `.gitignore`, wrapper, build scripts, app module, and smoke tests.
3. Wire package names and build variants.
4. Add first Compose screen and tests.
5. Run Gradle verification commands.
6. Document any local-only `local.properties` entries without committing them.

## Manual Work Still Required From Developer

- Download/install Android Studio.
- Complete Setup Wizard.
- Accept SDK licenses.
- Choose or create the first emulator device.
- Allow macOS security prompts for emulator/hypervisor/network access.
- Confirm whether the Android app should use the final package id `cool.happyword.wordmagic` before store-facing release work.
