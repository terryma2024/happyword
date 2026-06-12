plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "cool.happyword.wordmagic"
    compileSdk = 36

    // Cocos engine native build — Task 0.2 (AND embed).
    // The Cocos template pins r21 (PROP_NDK_VERSION in
    // cocos/build/android/android/proj/gradle.properties) but the engine
    // builds fine with r23; we standardize on the locally installed r23c.
    ndkVersion = "23.2.8568313"

    defaultConfig {
        applicationId = "cool.happyword.wordmagic"
        minSdk = 26
        targetSdk = 36
        versionCode = 1_020_001
        versionName = "1.0.2"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Cocos battle engine — arm64-v8a only (matches our AVD and device target).
        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild {
            cmake {
                // Match the arguments in the Cocos-generated template exactly
                // (cocos/native/engine/android/app/build.gradle, defaultConfig block).
                arguments += listOf(
                    "-DANDROID_STL=c++_static",
                    "-DANDROID_TOOLCHAIN=clang",
                    "-DANDROID_ARM_NEON=TRUE",
                )
            }
        }
    }

    // CMake adapter that bootstraps the engine build from repo paths.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/cocos/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // libcocos.so is already stripped/compressed by the NDK build; double-
    // compressing it bloats the APK and increases install time.  Match the
    // template's PROP_ENABLE_COMPRESS_SO=true setting (useLegacyPackaging).
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // Cocos battle engine Java layer (Task 0.2).
    // game-sdk.jar provides GameActivity (the CocosActivity base class from
    // the Android Games SDK).  The okhttp/okio/zipfile jars are Cocos network
    // and asset-streaming helpers.  Path is pinned to Creator 3.8.8 — update
    // when the Creator version bumps.
    val cocosEngineLibs = "/Applications/Cocos/Creator/3.8.8/CocosCreator.app" +
        "/Contents/Resources/resources/3d/engine/native/cocos/platform/android/java/libs"
    implementation(fileTree(mapOf("dir" to cocosEngineLibs, "include" to listOf("*.jar"))))

    implementation(platform("androidx.compose:compose-bom:2026.04.01"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.browser:browser:1.10.0")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("com.caverock:androidsvg-aar:1.4")
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")

    androidTestImplementation(platform("androidx.compose:compose-bom:2026.04.01"))
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
