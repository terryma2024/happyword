# Android Replica Environment And Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a reproducible native Android baseline under `android/` with Gradle, Kotlin, Compose, one minimal screen, and first unit/instrumentation tests.

**Architecture:** Android starts as a peer native client, not a shared-runtime wrapper. Phase 0 creates only the app shell and verification gates; product UI begins in the next plan after the Android SDK and Gradle project are healthy.

**Tech Stack:** Kotlin, Jetpack Compose, Gradle Kotlin DSL, Android Gradle Plugin 9.1.x, JDK 17, Android SDK API 36, Compose UI tests.

---

## File Structure

Create or modify these files only:

```text
android/README.md
android/.gitignore
android/settings.gradle.kts
android/build.gradle.kts
android/gradle.properties
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

Do not edit HarmonyOS, iOS, server, or shared runtime files in this plan.

## Prerequisite: Developer Installs Android Tooling

- [ ] **Step 1: Install Android Studio manually**

Download Android Studio from:

```text
https://developer.android.com/studio
```

Install it into:

```text
/Applications/Android Studio.app
```

Expected:

```sh
test -d "/Applications/Android Studio.app"
```

returns success.

- [ ] **Step 2: Complete Android Studio Setup Wizard**

Install at least:

```text
Android SDK Platform 36
Android SDK Build-Tools 36.0.0
Android SDK Platform-Tools
Android Emulator
Android SDK Command-line Tools latest
Google APIs ARM64 system image for API 36
```

Expected:

```sh
test -d "$HOME/Library/Android/sdk"
```

returns success.

- [ ] **Step 3: Export Android paths**

Add to `~/.zshrc`:

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

```text
adb version prints a version
sdkmanager prints a version
avdmanager prints help
```

- [ ] **Step 4: Create emulator**

Run:

```sh
avdmanager create avd \
  --name WordMagicGame_API36 \
  --package "system-images;android-36;google_apis;arm64-v8a" \
  --device "pixel_8"
```

Verify:

```sh
emulator -list-avds
```

Expected includes:

```text
WordMagicGame_API36
```

## Task 1: Create Gradle Project Shell

**Files:**
- Create: `android/settings.gradle.kts`
- Create: `android/build.gradle.kts`
- Create: `android/gradle.properties`
- Create: `android/.gitignore`
- Modify: `android/README.md`

- [ ] **Step 1: Create settings**

Create `android/settings.gradle.kts`:

```kotlin
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "WordMagicGameAndroid"
include(":app")
```

- [ ] **Step 2: Create root build file**

Create `android/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.21" apply false
}
```

- [ ] **Step 3: Create Gradle properties**

Create `android/gradle.properties`:

```properties
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
```

- [ ] **Step 4: Create Android ignore rules**

Create `android/.gitignore`:

```gitignore
.gradle/
build/
*/build/
local.properties
.idea/
captures/
*.iml
*.apk
*.aab
*.ap_
```

- [ ] **Step 5: Update README**

Replace `android/README.md` with:

````markdown
# WordMagicGame Android

Native Android client for WordMagicGame.

- Stack: Kotlin / Jetpack Compose.
- Project root: `android/`.
- Package: `cool.happyword.wordmagic`.
- Shared policy: consume `../shared/contracts/` and `../shared/fixtures/`; do not add shared client runtime under `shared/`.
- Planning docs: `../docs/android-replica/`.

## Local Commands

```sh
./gradlew testDebugUnitTest
./gradlew assembleDebug
./gradlew connectedDebugAndroidTest
```

Use JDK 17. If needed, put this local-only value in `local.properties`:

```properties
org.gradle.java.home=/Applications/Android Studio.app/Contents/jbr/Contents/Home
```
````

- [ ] **Step 6: Verify no wrapper yet**

Run:

```sh
cd android
test ! -f gradlew
```

Expected:

```text
command exits 0 before Task 2
```

## Task 2: Add Gradle Wrapper

**Files:**
- Create: `android/gradlew`
- Create: `android/gradlew.bat`
- Create: `android/gradle/wrapper/gradle-wrapper.jar`
- Create: `android/gradle/wrapper/gradle-wrapper.properties`

- [ ] **Step 1: Generate wrapper**

Use Android Studio project creation or a local Gradle install to generate:

```sh
cd android
gradle wrapper --gradle-version 9.3.1
```

If no local Gradle exists, create the project through Android Studio and let it generate the wrapper.

Expected:

```text
gradlew, gradlew.bat, gradle/wrapper/gradle-wrapper.jar, and gradle-wrapper.properties exist
```

- [ ] **Step 2: Verify wrapper metadata**

Open `android/gradle/wrapper/gradle-wrapper.properties` and ensure it contains:

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-9.3.1-bin.zip
```

- [ ] **Step 3: Verify wrapper executes**

Run:

```sh
cd android
./gradlew --version
```

Expected:

```text
Gradle 9.3.1
JVM: 17...
```

If JVM is not 17, add local-only `android/local.properties`:

```properties
org.gradle.java.home=/Applications/Android Studio.app/Contents/jbr/Contents/Home
```

Then rerun `./gradlew --version`.

## Task 3: Create App Module

**Files:**
- Create: `android/app/build.gradle.kts`
- Create: `android/app/src/main/AndroidManifest.xml`
- Create: `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`
- Create: `android/app/src/main/java/cool/happyword/wordmagic/app/AppMetadata.kt`

- [ ] **Step 1: Create app build file**

Create `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "cool.happyword.wordmagic"
    compileSdk = 36

    defaultConfig {
        applicationId = "cool.happyword.wordmagic"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.04.01"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")

    androidTestImplementation(platform("androidx.compose:compose-bom:2026.04.01"))
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
```

- [ ] **Step 2: Create manifest**

Create `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:label="WordMagicGame"
        android:supportsRtl="true"
        android:theme="@style/Theme.WordMagicGame">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

- [ ] **Step 3: If the template requires theme resources, create them**

Create `android/app/src/main/res/values/styles.xml`:

```xml
<resources>
    <style name="Theme.WordMagicGame" parent="android:style/Theme.Material.Light.NoActionBar" />
</resources>
```

- [ ] **Step 4: Create app metadata**

Create `android/app/src/main/java/cool/happyword/wordmagic/app/AppMetadata.kt`:

```kotlin
package cool.happyword.wordmagic.app

object AppMetadata {
    const val appName = "WordMagicGame Android"
    const val packageName = "cool.happyword.wordmagic"
}
```

- [ ] **Step 5: Create main activity**

Create `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`:

```kotlin
package cool.happyword.wordmagic

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import cool.happyword.wordmagic.app.AppMetadata

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            AndroidBootstrapApp()
        }
    }
}

@Composable
fun AndroidBootstrapApp() {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier.testTag("AndroidBootstrapScreen"),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(AppMetadata.appName)
                Text("Environment ready")
            }
        }
    }
}
```

## Task 4: Add First Tests

**Files:**
- Create: `android/app/src/test/java/cool/happyword/wordmagic/app/AppMetadataTest.kt`
- Create: `android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt`

- [ ] **Step 1: Add JVM test**

Create `android/app/src/test/java/cool/happyword/wordmagic/app/AppMetadataTest.kt`:

```kotlin
package cool.happyword.wordmagic.app

import org.junit.Assert.assertEquals
import org.junit.Test

class AppMetadataTest {
    @Test
    fun metadataMatchesAndroidPackage() {
        assertEquals("WordMagicGame Android", AppMetadata.appName)
        assertEquals("cool.happyword.wordmagic", AppMetadata.packageName)
    }
}
```

- [ ] **Step 2: Add Compose smoke test**

Create `android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt`:

```kotlin
package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import org.junit.Rule
import org.junit.Test

class SmokeTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun bootstrapScreenRenders() {
        composeRule.onNodeWithTag("AndroidBootstrapScreen").assertIsDisplayed()
        composeRule.onNodeWithText("WordMagicGame Android").assertIsDisplayed()
        composeRule.onNodeWithText("Environment ready").assertIsDisplayed()
    }
}
```

- [ ] **Step 3: Run JVM tests**

Run:

```sh
cd android
./gradlew testDebugUnitTest
```

Expected:

```text
BUILD SUCCESSFUL
```

- [ ] **Step 4: Build debug APK**

Run:

```sh
cd android
./gradlew assembleDebug
```

Expected:

```text
BUILD SUCCESSFUL
```

- [ ] **Step 5: Run connected smoke test**

Start emulator:

```sh
emulator -avd WordMagicGame_API36
```

Run:

```sh
cd android
./gradlew connectedDebugAndroidTest
```

Expected:

```text
BUILD SUCCESSFUL
```

## Task 5: Final Review

**Files:**
- Review all Android files changed in this plan.

- [ ] **Step 1: Check formatting and generated noise**

Run:

```sh
git status --short
git diff --check
```

Expected:

```text
No whitespace errors
Only Android bootstrap files and Android planning docs are modified
```

- [ ] **Step 2: Confirm local-only files are ignored**

Run:

```sh
cd android
test -f local.properties && git check-ignore -v local.properties || true
```

Expected if `local.properties` exists:

```text
android/.gitignore:...:local.properties local.properties
```

- [ ] **Step 3: Record verification result**

Update the implementation PR/commit message with the exact commands that passed:

```text
cd android && ./gradlew testDebugUnitTest
cd android && ./gradlew assembleDebug
cd android && ./gradlew connectedDebugAndroidTest
```

If connected tests cannot run because emulator setup is missing, explicitly state:

```text
Not run: connectedDebugAndroidTest, Android emulator is not installed/configured on this machine.
```
