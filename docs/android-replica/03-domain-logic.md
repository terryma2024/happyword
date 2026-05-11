# Android Domain Logic Boundary Plan

## Principle

The Android port should copy product semantics, not ArkTS file structure. Compose UI should stay thin. Game rules, persistence, pack resolution, network DTOs, and report aggregation must be testable with local JVM tests before UI wiring.

`shared/` remains contracts, schemas, fixtures, and protocol docs only. Do not create a shared runtime SDK.

## Proposed Android Package Structure

```text
android/app/src/main/java/cool/happyword/wordmagic/
  app/
  core/
    battle/
    question/
    config/
    packs/
    progress/
    rewards/
  data/
    local/
    network/
    fixtures/
  ui/
    home/
    battle/
    result/
    config/
    parent/
    packs/
    growth/
    debug/
  testing/
```

Rules:

- `core/` must not import Compose or Android UI types.
- `data/` adapts persistence, assets, HTTP, and fixtures to core interfaces.
- `ui/` owns Compose state holders and screen rendering.
- `testing/` contains fake repositories and deterministic sample data used by tests and debug builds.

## Phase 1 Core Types

| Kotlin boundary | HarmonyOS source | Responsibility |
| --- | --- | --- |
| `WordEntry` | `models/WordEntry.ets` | Word id, English word, Chinese meaning, category, difficulty, optional media/LLM fields. |
| `Question` / `QuestionKind` | `models/Question.ets` | Choice, FillLetter, FillLetterMedium, Spell question state. |
| `GameConfig` | `models/GameConfig.ets` | Player HP, monster HP, monster count, timer, auto speak, mode, parent PIN. |
| `BattleState` | `models/BattleState.ets` | HP, monster index, countdown, combo, current question, status. |
| `SessionResult` | `models/SessionResult.ets` | Battle summary, stars, today metadata, coin reward fields. |
| `BattleEngine` | `services/BattleEngine.ets` | Pure battle state transitions and star computation. |
| `QuestionGenerator` | `services/QuestionGenerator.ets` | MCQ and fallback generation. |
| `FillLetterGenerator` | `services/FillLetterGenerator.ets` | Fill-letter question generation. |
| `SpellGenerator` | `services/SpellGenerator.ets` | Full spelling question generation. |
| `TodayAdventureBuilder` | `services/TodayAdventureBuilder.ets` | Build a daily plan from a selected pack and learning recorder. |

Kotlin implementation rules:

- `BattleEngine` is a pure class covered by JVM tests.
- Compose screens never mutate HP, combo, stars, or timer directly. They submit commands to a state holder that delegates to `BattleEngine`.
- `GameConfig` defaults match HarmonyOS: player HP 5, monster HP 3, monsters 5, timer 300, auto speak on.
- Timer presets are `[30, 180, 300, 600]`.
- Custom timer accepts `1..3600` seconds.
- Parent PIN remains local in Phase 1.

## Phase 1 ParentAdmin Types

| Kotlin boundary | HarmonyOS/server source | Responsibility |
| --- | --- | --- |
| `ParentApiClient` | `services/ParentApiClient.ets`, server OpenAPI | Stats, draft list/detail, import lesson image, approve/reject, publish pack. |
| `ParentAdminDashboard` | `ParentAdminPage.ets` | Overview, import state, draft rows, publish summary. |
| `LessonImagePicker` | `services/LessonImagePicker.ets` | Abstract camera/gallery selection. |
| `PickedLessonImage` | V0.5.8 design | Local image URI/data, filename, MIME type, byte size. |
| `LessonDraftReviewModel` | `LessonDraftReviewPage.ets` | Source image, category, candidate rows, keep/drop/edit state. |
| `LessonDraftReviewStore` | V0.5.8 design | Mutations for keep/drop/edit/approve/reject. |

Preserve these API shapes:

- `GET /api/v1/admin/stats`
- `GET /api/v1/admin/lesson-drafts`
- `GET /api/v1/admin/lesson-drafts/{draft_id}`
- `PATCH /api/v1/admin/lesson-drafts/{draft_id}`
- `POST /api/v1/admin/lesson-drafts/{draft_id}/approve`
- `POST /api/v1/admin/lesson-drafts/{draft_id}/reject`
- `POST /api/v1/admin/lessons/import`
- `POST /api/v1/admin/packs/publish`

## Phase 2 Pack And Local Growth Types

| Kotlin boundary | HarmonyOS source | Responsibility |
| --- | --- | --- |
| `Pack` / `SceneMetadata` | `models/Pack.ets` | First-class pack object for builtin/global/family. |
| `BuiltinPackLoader` | `services/BuiltinPackLoader.ets` | Load bundled JSON packs from Android assets or raw resources. |
| `PackLibrary` | `services/PackLibrary.ets` | Merge family > global > builtin, scene fallback. |
| `PackSelectionStore` | `services/PackSelectionService.ets` | Active max 5, pin state, perfect-run rotation. |
| `CoinAccount` | `services/CoinAccount.ets` | Local magic coin accounting. |
| `WishlistStore` | `services/WishlistStore.ets` | Local default/custom wishes. |
| `RedemptionHistoryStore` | `services/RedemptionHistoryStore.ets` | Local capped history. |
| `LearningRecorder` | `services/LearningRecorder.ets` | Local word stats and snapshot migration. |
| `LearningReportBuilder` | `services/LearningReportBuilder.ets` | Pack-keyed report rows per V0.6.7.8. |

Pack rules:

- First launch active set is five builtin packs.
- At most five active packs.
- Pin only applies to active packs.
- A perfect adventure is a Today-mode win with no wrong answer.
- Three cumulative perfect adventures on an unpinned active pack trigger rotation when candidates exist.
- Selection is device-local and not cloud-synced.

## Phase 3 Cloud Types

| Kotlin boundary | Contract source | Responsibility |
| --- | --- | --- |
| `DeviceIdProvider` | `device-binding.md` | Stable device id. Use Android Keystore or app-private encrypted storage for the id source. |
| `DeviceBindingClient` | OpenAPI + `device-binding.md` | Pair redeem with QR token or short code. |
| `CloudCredentialsStore` | `CloudCredentials.ets` | Device token and child/family context. |
| `GlobalPackClient` | `pack-sync.md` | Anonymous ETag global pack fetch. |
| `FamilyPackClient` | `pack-sync.md` | Device-token ETag family pack fetch. |
| `WordStatsSyncClient` | `word-stats-sync.md` | Fire-and-forget local stats sync. |
| `CloudWishlistClient` | `wishlist-redemption.md` | Later cloud wishlist and redemption approval. |

Cloud rules:

- The app remains offline-first.
- Failed sync must not block battle completion.
- `family_id` is a server-side tenant boundary.
- 401/403/410 handling must follow `shared/contracts/protocols/pack-sync.md`.

## Persistence Policy

| Data | Android store |
| --- | --- |
| `GameConfig`, pack selection, local stats, wishlist, coin account | DataStore or app-private JSON wrapped behind typed stores. |
| Device token and stable device id | EncryptedSharedPreferences or Keystore-backed store. |
| Cached global/family packs | App-private JSON files with ETag metadata. |
| Today plan / active battle state | In-memory state, persisted only if restoration becomes necessary. |

All stores must expose fake implementations for JVM tests.

## Asset Policy

Android asset migration must copy from existing sources and preserve design files:

- Source SVGs remain under `assets/` or current HarmonyOS rawfile/design-source locations.
- Android raster/vector conversions live under `android/app/src/main/res/`.
- Retired or converted design-source files must not be deleted.
