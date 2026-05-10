# iOS Domain Logic Boundary Plan

## Principle

The iOS port should copy the product semantics, not the ArkTS file structure. SwiftUI views should stay thin. Game rules, persistence, pack resolution, network DTOs, and report aggregation must be testable without launching the app.

`shared/` remains contracts and fixtures only. Do not create a shared runtime SDK.

## Phase 1 Core Types

| Swift boundary | HarmonyOS source | Responsibility |
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

Swift implementation rules:

- `BattleEngine` must be pure and covered by XCTest before UI wiring.
- Views never mutate HP, combo, stars, or timer directly. They submit commands to `BattleEngine`.
- `GameConfig` must preserve current defaults: player HP 5, monster HP 3, monsters 5, timer 300, auto speak on.
- Timer presets in UI are `[30, 180, 300, 600]`; custom timer accepts 1...3600 seconds.
- Parent PIN remains local in Phase 1; later cloud account work must not break local offline gating.

## Phase 1 ParentAdmin Types

| Swift boundary | HarmonyOS/server source | Responsibility |
| --- | --- | --- |
| `ParentApiClient` | `services/ParentApiClient.ets`, server OpenAPI | Stats, draft list/detail, import lesson image, approve/reject, publish pack. |
| `ParentAdminDashboard` | `ParentAdminPage.ets` | Read model for overview, import state, draft rows, publish summary. |
| `LessonImagePicker` | `services/LessonImagePicker.ets` | Abstract camera/gallery selection. Use fake adapter in early tests. |
| `PickedLessonImage` | V0.5.8 design | Local image URI/data, filename, MIME type, byte size. |
| `LessonDraftReviewModel` | `LessonDraftReviewPage.ets` | Source image, category, candidate rows, keep/drop/edit state. |
| `LessonDraftReviewStore` | V0.5.8 design | Mutations for keep/drop/edit/approve/reject. |

Phase 1 must preserve these API shapes even if the first implementation uses mocks:

- `GET /api/v1/admin/stats`
- `GET /api/v1/admin/lesson-drafts`
- `GET /api/v1/admin/lesson-drafts/{draft_id}`
- `PATCH /api/v1/admin/lesson-drafts/{draft_id}`
- `POST /api/v1/admin/lesson-drafts/{draft_id}/approve`
- `POST /api/v1/admin/lesson-drafts/{draft_id}/reject`
- `POST /api/v1/admin/lessons/import`
- `POST /api/v1/admin/packs/publish`

The current V0.5.8 security tradeoff is inherited from the HarmonyOS implementation and must be documented in iOS code comments when real networking is added.

## Phase 2 Pack And Local Growth Types

| Swift boundary | HarmonyOS source | Responsibility |
| --- | --- | --- |
| `Pack` / `SceneMetadata` | `models/Pack.ets` | First-class pack object for builtin/global/family. |
| `BuiltinPackLoader` | `services/BuiltinPackLoader.ets` | Load bundled JSON packs. |
| `PackLibrary` | `services/PackLibrary.ets` | Merge family > global > builtin, scene fallback. |
| `PackSelectionStore` | `services/PackSelectionService.ets` | Active max 5, pin state, perfect-run rotation. |
| `CoinAccount` | `services/CoinAccount.ets` | Local magic coin accounting. |
| `WishlistStore` | `services/WishlistStore.ets` | Local default/custom wishes. |
| `RedemptionHistoryStore` | `services/RedemptionHistoryStore.ets` | Local capped history. |
| `LearningRecorder` | `services/LearningRecorder.ets` | Local word stats and snapshot migration. |
| `LearningReportBuilder` | `services/LearningReportBuilder.ets` | Pack-keyed report rows per V0.6.7.8. |

Pack selection semantics to preserve:

- First launch active set is five builtin packs.
- At most five active packs.
- Pin is only meaningful for active packs.
- A perfect adventure is a Today-mode win with no wrong answer.
- Three cumulative perfect adventures on an unpinned active pack trigger rotation when candidates exist.
- Selection is device-local and not cloud-synced.

## Phase 3 Cloud Types

| Swift boundary | Contract source | Responsibility |
| --- | --- | --- |
| `DeviceIdProvider` | `device-binding.md` | Stable device id. On iOS, use Keychain-backed UUID. |
| `DeviceBindingClient` | OpenAPI + `device-binding.md` | Pair redeem with QR token or short code. |
| `CloudCredentialsStore` | `CloudCredentials.ets` | Device token and child/family context. Use Keychain for token. |
| `GlobalPackClient` | `pack-sync.md` | Anonymous ETag global pack fetch. |
| `FamilyPackClient` | `pack-sync.md` | Device-token ETag family pack fetch. |
| `WordStatsSyncClient` | `word-stats-sync.md` | Fire-and-forget local stats sync. |
| `CloudWishlistClient` | `wishlist-redemption.md` | Later cloud wishlist and redemption approval. |

Cloud rules:

- The app remains offline-first. Failed sync must not block battle completion.
- `family_id` is a tenant boundary on the server. The client may display it but never authorizes from local family labels.
- 401/403/410 handling must follow `shared/contracts/protocols/pack-sync.md`.

## Persistence Policy

Recommended iOS stores:

| Data | iOS store |
| --- | --- |
| `GameConfig`, pack selection, local stats, wishlist, coin account | App-group-free app sandbox JSON or UserDefaults, wrapped behind typed stores. |
| Device token and stable device id | Keychain. |
| Cached global/family packs | File-backed JSON with ETag metadata. |
| Cross-page handoff like today plan/active pack | In-memory app state, not persistent storage unless needed for restoration. |

All stores should expose protocol-based fake implementations for XCTest.

## Asset Policy

The first iOS implementation should reuse source assets from HarmonyOS only through an explicit asset migration task. Do not delete or move existing resource files. If an asset is converted for iOS, preserve the source under `assets/` per the repo asset retention policy.
