# Android Later Phases: Pack, Cloud, Debug, Release

## Phase 2: Local Growth And Pack Management

Goal:

```text
PackManager + Wishlist + RedemptionHistory + MonsterCodex + TodayPlan + LearningReport
```

### PackManager

Responsibilities:

- Load builtin packs from Android assets/raw resources.
- Load cached global/family packs from app-private storage.
- Merge `family > global > builtin`.
- Render source tags: `内置`, `官方`, `家庭`.
- Enforce max five active packs.
- Support active toggle.
- Support pin only on active packs.
- Support perfect-run rotation.

Acceptance:

- JVM tests cover merge precedence and active max.
- Compose UI test toggles one builtin pack off and verifies Home chip row updates.
- Compose UI test pins an active pack and verifies perfect-run rotation skips it.

### Wishlist And Redemption History

Responsibilities:

- Local coin account.
- Default wishes and custom wishes.
- PIN-gated custom wish add/remove.
- Redemption request writes local capped history.

Acceptance:

- JVM tests cover coin debit, insufficient balance, and capped history.
- UI test can add a custom wish behind PIN and request redemption.

### MonsterCodex

Responsibilities:

- Display existing character/monster roster.
- Reuse converted assets without deleting source assets.
- Preserve child-friendly magic/fairy-tale style.

Acceptance:

- Visual smoke test opens the codex and verifies at least Slime, Zombie, Dragon, and later boss entries.

### TodayPlan

Responsibilities:

- Build read-only daily plan from selected pack and learning recorder.
- Preserve Review/Learning/New grouping.

Acceptance:

- JVM tests cover deterministic day seed and grouping.
- UI test opens TodayPlan from Home and returns.

### LearningReport

Responsibilities:

- Match V0.6.7.8 pack-keyed report semantics.
- Top-level totals dedupe shared words.
- Per-pack rows count each pack independently.
- Active packs sort first by selection order.
- Inactive seen packs sort by accuracy ascending.

Acceptance:

- Port the HarmonyOS `LearningReportBuilder` cases into Kotlin JVM tests.
- UI test verifies `LearningReportPackSection` equivalent and one builtin pack row.

## Phase 3: Parent Cloud And Device Binding

Goal:

```text
ScanBinding + BoundDeviceInfo + family/global pack sync + word stats sync
```

### Binding

Responsibilities:

- QR scan where Android camera permission and device support allow it.
- Manual short-code entry.
- Stable device id.
- Token storage.
- Unbind flow behind parent PIN.

Acceptance:

- JVM tests cover pair response decoding and credential persistence.
- Instrumentation test uses fake/mocked API to bind by short code.

### Pack Sync

Responsibilities:

- Anonymous global pack fetch with ETag.
- Device-token family pack fetch with ETag.
- 304 handling.
- 401/403/410 handling per `shared/contracts/protocols/pack-sync.md`.

Acceptance:

- JVM tests use fixtures under `shared/fixtures/`.
- Mock server instrumentation test uses `adb reverse tcp:8123 tcp:8123`.

### Word Stats Sync

Responsibilities:

- Fire-and-forget sync after battle/session changes.
- Offline failures do not block learning flow.
- Retry/backoff can remain simple initially.

Acceptance:

- JVM tests verify request payload.
- UI test completes battle while mock sync endpoint returns an error and still reaches Result.

## Phase 4: Debug And Preview Operations

Goal:

```text
DevMenu + backend environment switcher + preview manifest + bypass secret
```

Rules:

- Debug build only.
- Release builds must not expose DevMenu, version-label triple-tap, or bypass secret UI.
- Behavior should align with HarmonyOS DevMenu intent.

Components:

- Backend environment switcher: staging/local/preview.
- Preview manifest fetch from `GET /api/v1/public/preview-urls.json`.
- Bypass secret editor.
- Mock-server instrumentation override.

Acceptance:

- Debug variant exposes DevMenu.
- Release variant test verifies DevMenu route is unavailable.
- Instrumentation can inject `serverBaseUrl=http://localhost:8123`.

## Phase 5: Release Hardening

Goal:

```text
Parity, accessibility, performance, CI, release gates
```

Release gates:

- `./gradlew testDebugUnitTest`
- `./gradlew assembleDebug`
- `./gradlew connectedDebugAndroidTest`
- Screenshot smoke on at least one phone emulator.
- Release variant confirms debug routes are unavailable.
- Accessibility labels/content descriptions for all icon-only controls.
- Contract fixture drift checks where Android consumes shared fixtures.

CI recommendation:

- Start with JVM tests only in CI.
- Add connected emulator tests after the local suite is stable.
- Keep Android CI independent from HarmonyOS DevEco tooling.

Residual risks:

- Android Studio/SDK version drift can break Gradle bootstrap if wrapper and AGP versions are not pinned.
- Camera/gallery permissions differ from HarmonyOS; isolate behind `LessonImagePicker`.
- Emulator performance can make UI tests flaky; favor deterministic fake repositories and direct route setup for most tests.
