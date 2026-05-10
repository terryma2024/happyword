# WordMagicGame Android

Native Android client placeholder for V0.7.x and later.

- Target implementation: Kotlin / Jetpack Compose.
- Tests: Gradle unit and instrumentation tests when the app project is created.
- Scope guard: V0.7.0 only reserves this root-level module; it does not implement Android product features.
- Shared code policy: use `../shared/contracts/` and `../shared/fixtures/` for protocol alignment, not shared runtime UI or business logic.
