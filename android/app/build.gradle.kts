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
        versionCode = 1_009_003
        versionName = "0.9.3"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
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
