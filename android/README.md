# WordMagicGame Android

Native Android client for WordMagicGame.

- Stack: Kotlin / Jetpack Compose.
- Project root: `android/`.
- Package: `cool.happyword.wordmagic`.
- Shared policy: consume `../shared/contracts/` and `../shared/fixtures/`; do not add shared client runtime under `shared/`.
- Planning docs: `../docs/android-replica/`.
- Agent command manifest: `../.cursor/android-dev-commands.md`.

## Local Commands

```sh
./gradlew testDebugUnitTest
./gradlew assembleDebug
./gradlew connectedDebugAndroidTest
./gradlew assembleRelease
```

Use JDK 17. If needed, put this local-only value in `local.properties`:

```properties
org.gradle.java.home=/Applications/Android Studio.app/Contents/jbr/Contents/Home
```
