import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

val releaseSigningProperties = Properties().apply {
    val localFile = rootProject.file("release-signing.properties")
    if (localFile.isFile) {
        localFile.inputStream().use(::load)
    }
}

fun releaseSigningValue(name: String): String? =
    providers.gradleProperty(name).orNull
        ?: providers.environmentVariable(name).orNull
        ?: releaseSigningProperties.getProperty(name)

val releaseStoreFilePath = releaseSigningValue("WORDMAGIC_ANDROID_STORE_FILE")
val releaseStorePassword = releaseSigningValue("WORDMAGIC_ANDROID_STORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("WORDMAGIC_ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("WORDMAGIC_ANDROID_KEY_PASSWORD")
val hasReleaseUploadSigning = listOf(
    releaseStoreFilePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "cool.happyword.wordmagic"
    compileSdk = 36

    defaultConfig {
        applicationId = "cool.happyword.wordmagic"
        minSdk = 26
        targetSdk = 36
        versionCode = 1_007_000
        versionName = "0.7.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }

    signingConfigs {
        if (hasReleaseUploadSigning) {
            create("releaseUpload") {
                storeFile = file(requireNotNull(releaseStoreFilePath))
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseUploadSigning) {
                signingConfig = signingConfigs.getByName("releaseUpload")
            }
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.04.01"))
    implementation("androidx.activity:activity-compose:1.13.0")
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
