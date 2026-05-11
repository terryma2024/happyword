# Android Replica Phase 2 - Local Growth And Pack Management Design

> Status: design-for-implementation
> Date: 2026-05-11
> Scope: PackManager, local rewards, wishlist, redemption history, MonsterCodex, TodayPlan, and pack-keyed LearningReport.

## 1. Background

Phase 1 gives Android a playable local core: Home, Battle, Result, Config, Parent PIN, ParentAdmin, and LessonDraftReview. Phase 2 makes the Android client feel like the current HarmonyOS product by adding the local growth loop and the three-layer pack-management model. This phase stays offline-first. Global and family pack layers can be fixture-backed or locally cached; authenticated cloud sync starts in Phase 3.

The Android implementation must remain native Kotlin and Jetpack Compose. `shared/` remains contracts, schemas, and fixtures only; do not create a shared Android runtime from it.

## 2. Goals

- Implement Android-native pack domain models equivalent to HarmonyOS V0.6.5+.
- Add PackManager UI with source tags, active toggles, active max five, pin controls, and manual sync affordance.
- Add local coin account, wishlist, redemption history, MonsterCodex, TodayPlan, and pack-keyed LearningReport.
- Make Home, Battle, TodayPlan, and LearningReport consume the same selected pack identity.
- Preserve offline play when no network, no binding, or no synced pack cache exists.
- Add JVM and Compose UI tests for local pack/growth rules.

## 3. Non-Goals

- Do not implement parent cloud binding or authenticated pack sync in Phase 2.
- Do not require a real server for Phase 2 acceptance.
- Do not cloud-sync wishlist, redemption history, or learning stats.
- Do not implement real money, in-app purchase, Alipay, cash payout, or compliance-sensitive redemption.
- Do not replace the Compose battle scene with Cocos.
- Do not introduce a shared client runtime under `shared/`.

## 4. Source Evidence

Screenshots:

- `assets/screenshots/harmonyos/pack-manager.png`
- `assets/screenshots/harmonyos/wishlist.png`
- `assets/screenshots/harmonyos/redemption-history.png`
- `assets/screenshots/harmonyos/monster-codex-part1.png`
- `assets/screenshots/harmonyos/monster-codex-part2.png`
- `assets/screenshots/harmonyos/today-plan.png`
- `assets/screenshots/harmonyos/learning-report-part1.png`
- `assets/screenshots/harmonyos/learning-report-part2.png`

HarmonyOS code:

- `harmonyos/entry/src/main/ets/pages/PackManagerPage.ets`
- `harmonyos/entry/src/main/ets/pages/WishlistPage.ets`
- `harmonyos/entry/src/main/ets/pages/RedemptionHistoryPage.ets`
- `harmonyos/entry/src/main/ets/pages/MonsterCodexPage.ets`
- `harmonyos/entry/src/main/ets/pages/TodayPlanPage.ets`
- `harmonyos/entry/src/main/ets/pages/LearningReportPage.ets`
- `harmonyos/entry/src/main/ets/services/PackLibrary.ets`
- `harmonyos/entry/src/main/ets/services/PackSelectionService.ets`
- `harmonyos/entry/src/main/ets/services/BuiltinPackLoader.ets`
- `harmonyos/entry/src/main/ets/services/GlobalPackService.ets`
- `harmonyos/entry/src/main/ets/services/FamilyPackService.ets`
- `harmonyos/entry/src/main/ets/services/LearningRecorder.ets`
- `harmonyos/entry/src/main/ets/services/LearningReportBuilder.ets`
- `harmonyos/entry/src/main/ets/services/WishlistStore.ets`
- `harmonyos/entry/src/main/ets/services/CoinAccount.ets`
- `harmonyos/entry/src/main/ets/services/RedemptionHistoryStore.ets`

Planning docs:

- `docs/android-replica/03-domain-logic.md`
- `docs/android-replica/05-later-phases-pack-cloud-debug.md`
- `docs/android-replica/06-validation-plan.md`
- `docs/superpowers/specs/2026-05-09-v0.6.5-three-layer-pack-model-design.md`
- `docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md`

## 5. Android Architecture

Use three layers:

| Layer | Suggested package | Responsibility |
| --- | --- | --- |
| Domain | `cool.happyword.wordmagic.core` | Pure Kotlin models and rules: packs, selection, rewards, reports. |
| Data | `cool.happyword.wordmagic.data` | App-private JSON/SharedPreferences or DataStore persistence, raw asset loaders, fixture-backed sync stubs. |
| UI | `cool.happyword.wordmagic.ui` or current Compose file until split | Compose screens, view models/state holders, navigation events. |

Phase 2 may keep the current single `MainActivity.kt` UI shell only if the implementation plan explicitly splits it later. Domain and persistence should be separated early because the pack and learning rules need focused JVM tests.

Recommended persistence:

- `SharedPreferences` or Jetpack DataStore for small selection/wishlist/coin state.
- App-private JSON files for pack caches and learning stats snapshots.
- Raw Android resources or assets for builtin pack JSON and SVG/PNG media.

## 6. Pack Model

Kotlin domain types:

```text
enum class PackSource { Builtin, Global, Family }

data class SceneMetadata(
    bgPrimary: String,
    bgAccent: String,
    bossName: String,
    monsterPlan: List<String>,
    bossCandidates: List<String>,
    storyZh: String
)

data class WordPack(
    id: String,
    name: String,
    labelZh: String,
    source: PackSource,
    version: Int,
    publishedAtMs: Long?,
    scene: SceneMetadata?,
    words: List<WordEntry>
)
```

Rules:

- Builtin packs ship with Android and are never deleted by sync.
- Global packs are anonymous official remote packs.
- Family packs are parent-uploaded and family-scoped, but Phase 2 can load them from local fixtures.
- Merge priority is `family > global > builtin` by pack id.
- If an overriding pack lacks scene metadata, fallback to same-id builtin scene.
- If no same-id builtin scene exists, use deterministic fallback colors derived from pack id.
- Home chip text and adventure title use English pack names.
- Battle still uses Chinese prompt meanings and English answer options.

## 7. Pack Selection

Kotlin boundary: `PackSelectionStore`.

Persisted shape:

```text
activePackIds: List<String>
pinnedPackIds: Set<String>
perfectScoresByPack: Map<String, Int>
lastSelectionUpdatedAtMs: Long
```

Rules:

- First launch active set is the five builtin pack ids.
- At most five active packs.
- Duplicate active ids are ignored during load and rejected during mutation.
- Active ids that no longer exist are pruned.
- Pin state is always a subset of active ids.
- Pin controls are only shown for active packs.
- A perfect adventure is a Today-mode win with zero wrong answers.
- Three cumulative perfect adventures on one unpinned active pack trigger rotation if a candidate exists.
- Rotation candidate order: family packs first, then global packs, then inactive builtin packs; within a source, prefer newest `publishedAtMs`, then stable id sort.
- Pinned active packs are skipped during rotation.

## 8. PackManager UI

Orientation: landscape is preferred for child-facing consistency; portrait is acceptable only if a later implementation plan chooses a compact phone list and screenshot review approves it.

Screen requirements:

- Header with back button, title `我的词包`, active count, and sync button.
- Scrollable rows grouped or tagged by source: `内置`, `官方`, `家庭`.
- Each row shows English pack name, Chinese subtitle/story when available, source tag, active toggle, and pin button if active.
- Sync row shows last sync status. In Phase 2 this can be local/fixture-backed.
- Selecting a sixth active pack shows a visible message and preserves state.
- Deactivating a pinned pack clears the pin.
- Home chip row updates from active packs.

Suggested test tags:

- `PackManagerScreen`
- `PackManagerBack`
- `PackManagerTitle`
- `PackManagerActiveCount`
- `PackManagerSyncButton`
- `PackManagerStatus`
- `PackSourceTag_<packId>`
- `PackLabel_<packId>`
- `PackPin_<packId>`
- `PackToggle_<packId>`
- `PackManagerLimitMessage`

## 9. Wishlist And Redemption History

Kotlin boundaries:

- `CoinAccount`
- `WishlistStore`
- `RedemptionHistoryStore`
- `ParentPinGate`

Rules:

- Battle result awards coins equal to stars.
- Local daily coin cap is 20.
- Default wish catalog ships locally.
- Custom wishes require parent PIN.
- Custom wish input requires non-empty title, positive coin cost, and icon/emoji.
- Applying a wish requires enough coins and parent PIN.
- Successful redemption deducts coins and appends history.
- Redemption history is newest-first and capped at 50 records.
- Failed or cancelled PIN does not mutate coins or history.

UI:

- Wishlist shows magic coin balance, default/custom wish cards, add button, and history entry.
- RedemptionHistory shows timestamp, wish name, cost, and status.
- Gift/celebration modal may be simple in Phase 2, but it must block double redemption while visible.

## 10. MonsterCodex

Kotlin boundaries:

- `MonsterCatalog`
- `MonsterCodexViewModel`
- `MonsterCodexScreen`

Rules:

- Reuse HarmonyOS character assets copied into Android resources.
- Render image, English name, Chinese kind label, position count, and child-friendly description.
- Prev/next controls cycle through catalog entries.
- Codex starts with Slime, Zombie, Dragon, and any already-copied boss/region assets available in Android resources.
- Do not delete source SVG/PNG/audio assets when changing runtime usage.

Suggested test tags:

- `MonsterCodexScreen`
- `MonsterCodexImage`
- `MonsterCodexName`
- `MonsterCodexPrevious`
- `MonsterCodexNext`

## 11. TodayPlan

Kotlin boundaries:

- `TodayPlanService`
- `TodayPlanViewModel`
- `TodayPlanScreen`

Rules:

- Read-only.
- Uses active pack ids and local learning recorder.
- Shows review, learning, and new buckets.
- Does not start or mutate a battle.
- Start buttons route to Battle only through the existing battle-start path.
- Report action routes to LearningReport.

Suggested test tags:

- `TodayPlanScreen`
- `TodayPlanReviewBucket`
- `TodayPlanLearningBucket`
- `TodayPlanNewBucket`
- `TodayPlanReportButton`

## 12. LearningReport

Kotlin boundary: `LearningReportBuilder`.

Rules matching HarmonyOS V0.6.7.8:

- Build from pack library, active ids, local learning stats, and current time.
- Top-level totals dedupe word ids across packs.
- Per-pack rows count each pack independently.
- Active packs render first in selection order.
- Inactive packs with seen words render after active packs, sorted by accuracy ascending.
- Inactive packs with zero seen words are hidden.
- Report rows are pack-keyed, not category-keyed.

Suggested test tags:

- `LearningReportScreen`
- `LearningReportPackSection`
- `LearningReportPackRow_<packId>`
- `LearningReportTotalWords`
- `LearningReportAccuracy`

## 13. Test Plan

JVM tests:

- `PackLibraryTest`: merge priority, source retention, scene fallback.
- `PackSelectionStoreTest`: defaults, active max five, duplicate rejection, pin subset, pruned missing packs, perfect-run rotation.
- `CoinAccountTest`: star rewards, daily cap, transaction reasons.
- `WishlistStoreTest`: default/custom wishes, validation, PIN-gated mutation.
- `RedemptionHistoryStoreTest`: debit, insufficient balance, newest-first cap.
- `LearningRecorderTest`: answer recording, local stats snapshot migration.
- `LearningReportBuilderTest`: pack-keyed rows, inactive seen rows, shared-word top-level dedupe.
- `TodayPlanServiceTest`: deterministic buckets for fixed local stats.

Compose UI tests:

- Open PackManager from Config and return.
- Toggle one builtin pack off and verify Home chip row updates.
- Pin an active pack and verify the pin label/state flips.
- Open Wishlist, attempt redemption behind PIN, and see coin/history mutation after valid PIN.
- Open MonsterCodex and use prev/next.
- Open TodayPlan and navigate to LearningReport.
- Open LearningReport and find one builtin pack row.

Manual visual verification:

- Screenshot PackManager, Wishlist, MonsterCodex, TodayPlan, and LearningReport under `assets/screenshots/android/`.
- Compare against HarmonyOS screenshots listed in section 4.

## 14. Acceptance Criteria

- Home, Battle, TodayPlan, and LearningReport all use the same active pack identity.
- PackManager manages the five builtin packs offline.
- Local coin/wishlist/redemption loop works without network.
- MonsterCodex renders copied character assets without deleting source assets.
- LearningReport is pack-keyed and does not show old category-keyed rows.
- JVM and Compose UI tests cover the rules listed above.
- No runtime code is added under `shared/`.
