# iOS Replica Phase 2 — Pack Management And Local Growth Design

> Status: design-for-implementation
> Date: 2026-05-10
> Scope: PackManager, local rewards, wishlist, monster codex, today plan, and learning report.
> Related plan: `docs/ios-replica/04-pack-sync-and-parent-cloud.md`

## 1. Background

Phase 1 gives iOS a playable core and parent lesson-import surface. Phase 2 makes the app feel like the current product by adding the local growth systems and three-layer pack management UI. This phase still remains offline-first and can use local/mock data for cloud layers until Phase 3 adds binding and authenticated sync.

## 2. Goals

- Implement `Pack`, `PackLibrary`, and `PackSelectionStore` semantics equivalent to HarmonyOS V0.6.5+.
- Add PackManager UI with active cap, source tags, pin buttons, toggles, and manual sync surface.
- Add local magic coin, wishlist, redemption history, MonsterCodex, TodayPlan, and pack-keyed LearningReport surfaces.
- Preserve pack-keyed mental model across Home, PackManager, Battle, TodayPlan, and LearningReport.

## 3. Non-Goals

- Do not implement device binding in Phase 2.
- Do not require real family pack sync; family/global clients can be fixture-backed until Phase 3.
- Do not cloud-sync wishlist or learning stats.
- Do not add real payment, Apple IAP, Alipay, or cash redemption.
- Do not implement Cocos2D battle rendering.

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

- `pages/PackManagerPage.ets`
- `pages/WishlistPage.ets`
- `pages/RedemptionHistoryPage.ets`
- `pages/MonsterCodexPage.ets`
- `pages/TodayPlanPage.ets`
- `pages/LearningReportPage.ets`
- `services/PackLibrary.ets`
- `services/PackSelectionService.ets`
- `services/BuiltinPackLoader.ets`
- `services/GlobalPackService.ets`
- `services/FamilyPackService.ets`
- `services/LearningReportBuilder.ets`
- `services/WishlistStore.ets`
- `services/CoinAccount.ets`
- `services/RedemptionHistoryStore.ets`

Historical specs:

- V0.6.5 three-layer pack model.
- V0.6.7 PackManager refinements.
- V0.6.7.8 learning report by pack.
- V0.3.9 wishlist redemption flow.
- V0.3.7 MonsterCodex.
- V0.4.4 TodayPlan.

## 5. Pack Model

Swift types:

```text
PackSource = builtin | global | family
SceneMetadata = bgPrimary, bgAccent, bossName, monsterPlan, bossCandidates, storyZh
Pack = id, name, labelZh, source, version, publishedAt, scene, words
```

Semantics:

- Builtin packs ship with the app and are never deleted.
- Builtin packs are loaded from the same five HarmonyOS rawfile JSON fixtures in canonical order: `fruit-forest`, `school-castle`, `home-cottage`, `animal-safari`, `ocean-realm`.
- Global packs are anonymous remote packs.
- Family packs are parent-uploaded, family-scoped packs.
- Merge priority is family > global > builtin by `pack_id`.
- Scene fallback is own scene -> same-id builtin scene -> deterministic palette.
- Home chip text and card title use English `Pack.name`.
- Battle start uses the selected pack's real `words` through `QuestionGenerator`; the Chinese prompt comes from `meaningZh`, and answer options are shuffled English words from the same repository rather than a fixed correct-first list.

## 6. Pack Selection

Swift service: `PackSelectionStore`.

Persistence shape:

```text
activePackIds: [String]
pinnedPackIds: [String]
perfectScoresByPack: [String: Int]
```

Rules:

- First launch active set is the five builtin ids.
- Max active count is five.
- Duplicate active ids are rejected.
- Pin state is a subset of active ids.
- Pin buttons render only for active packs.
- A perfect adventure is a Today-mode win with zero wrong answers.
- Three cumulative perfect adventures rotate an unpinned active pack if a candidate exists.
- Rotation candidate order is family, global, builtin, then published date/id policy matching HarmonyOS behavior.

## 7. PackManager UI

iPhone adaptation:

- Prefer landscape when launched from Config.
- Use a scrollable list with large touch rows.
- Header includes back, title `我的词包`, active count, and sync button.
- Row includes source tag, English pack name, pin button if active, and toggle.
- Toast/status row explains: switch toggles active, pin prevents perfect-run rotation.

Required identifiers:

- `PackManagerBack`
- `PackManagerTitle`
- `PackManagerSyncButton`
- `PackManagerStatus`
- `PackSourceTag_<packId>`
- `PackLabel_<packId>`
- `PackPin_<packId>`
- `PackToggle_<packId>`
- `PackManagerSyncToast`

Failure handling:

- Selecting sixth active pack shows a toast and preserves state.
- Sync failure keeps current local library.
- Deleted remote family pack is pruned from active/pinned selection.

## 8. Wishlist And Redemption

Swift boundaries:

- `CoinAccount`
- `WishlistStore`
- `RedemptionHistoryStore`
- `ParentPinGate`
- `GiftBoxView`

Rules:

- Today adventure earns coins equal to stars.
- Daily cap stays 20 coins.
- Default wishes exist locally.
- Custom wishes require non-empty name, positive cost, and emoji/icon.
- Add, delete, and apply actions require parent PIN.
- Confirmed redemption deducts coins and appends a history record.
- History keeps newest first and caps at 50.

UI:

- Wishlist shows current magic coins, add button, history button, wish cards.
- Redemption history shows chronological list.
- GiftBox is a modal celebration and blocks interaction while playing.

## 9. MonsterCodex

Swift boundaries:

- `MonsterCatalog`
- `MonsterCodexViewModel`
- `MonsterCodexView`

Rules:

- Render monster image, English name, Chinese kind label, position count, and description.
- Prev/next controls cycle through the catalog.
- Assets must be migrated without deleting source SVG/PNG assets.

## 10. TodayPlan

Swift boundaries:

- `TodayPlanService`
- `TodayPlanViewModel`
- `TodayPlanView`

Rules:

- Read-only view.
- Uses same selected pack and learning recorder semantics as Home/Battle.
- Shows review, learning, and new buckets.
- Does not mutate battle state.
- Report button routes to LearningReport.

## 11. LearningReport

Swift boundary: `LearningReportBuilder`.

Rules from V0.6.7.8:

- Build from `PackLibrary`, active ids, local recorder, and current time.
- Top-level totals dedupe word ids across packs.
- Per-pack rows count each pack independently.
- Active packs render first in selection order.
- Inactive packs with seen words render after active packs, sorted by accuracy ascending.
- Inactive packs with zero seen words are hidden.
- Report rows are pack-keyed, not category-keyed.

Required identifiers:

- `LearningReportPackSection`
- `pack-<packId>` for each row.

## 12. Test Plan

XCTest:

- `PackLibraryTests`: merge priority, scene fallback, source retention.
- `PackSelectionStoreTests`: defaults, cap, duplicate rejection, pin subset, perfect rotation.
- `CoinAccountTests`: star reward, daily cap, transaction reasons.
- `WishlistStoreTests`: add/delete/apply validation and history cap.
- `LearningReportBuilderTests`: pack rows, inactive seen row inclusion, shared-word top-level dedupe.
- `TodayPlanServiceTests`: deterministic plan buckets.

XCUITest:

- Config -> PackManager list smoke.
- Toggle builtin pack off and verify Home chip disappears.
- Pin button label flips.
- Wishlist PIN-gated apply shows GiftBox.
- MonsterCodex prev/next.
- TodayPlan -> LearningReport.

## 13. Acceptance Criteria

- Home/Battle/Report all consume pack identity consistently.
- PackManager can manage the five builtin packs offline.
- Local growth loop works without network.
- LearningReport does not display old category rows.
- All local stores have fake implementations for tests.
