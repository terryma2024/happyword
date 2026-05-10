# Learning Report by Pack — Design

> **Status**: Approved (pending user spec review)
> **Target**: V0.6.7.8 (next minor after V0.6.7.7 ConfigPage timer cleanup)
> **Author**: brainstorming session 2026-05-10
> **Implements**: switch `LearningReportPage` from category-keyed aggregation to pack-keyed aggregation, aligning with the V0.6.5+ three-layer word pack model.

---

## 1. Problem

`LearningReportPage` (V0.4.5 surface) still reports per **category** (`水果 / 地点 / 家庭 / 动物 / 海洋`), inherited from the V0.4-era flat 50-word catalog. Since V0.6.5 introduced the three-layer pack model and V0.6.6 removed the category picker from `ConfigPage`, the category dimension has zero remaining UX surface — the parent + kid only ever interact with **packs** (HomePage chips, PackManagerPage list, BattlePage today-mode pack lookup).

Showing accuracy by an invisible dimension (category) makes the report feel disconnected from the rest of the app. A parent reading `水果 75%` can't act on it: there's no "fruit pack" to study; there's only `Fruit Forest`, `School Castle`, etc., all of which happen to fall under one category each, *but global / family packs ship arbitrary words and break the 1:1 mapping*.

## 2. Goal

`LearningReportPage` aggregates and renders accuracy **by pack** instead of by category. The report stays in sync with what the parent sees on PackManagerPage and HomePage.

Non-goals:

- No new chart types or visualizations. Same row layout, same cards.
- No backend / schema changes. `WordStat` continues to record per-`wordId`, no `packId` event log.
- No "pack source" badge on report rows (parent sees source on PackManagerPage; here the data is the focus).

## 3. User-facing changes

| Section | Before | After |
|---|---|---|
| 总正确率 (Accuracy card) | unchanged | unchanged |
| 单词掌握情况 (State pills) | unchanged | unchanged |
| 今日复习进度 (Review card) | unchanged | unchanged |
| 需要加强的分类 (Weak Categories) | up-to-3 lowest-accuracy categories | **REMOVED** — full breakdown table is the single source of truth |
| 分类详情 → 词包详情 (Breakdown table) | one row per category, Chinese name (`水果 / 地点 / 家庭 / 动物 / 海洋`) | one row per pack, English name (`Fruit Forest / School Castle / ...`) |
| Empty state | unchanged | unchanged |

### Row inclusion rule (Section 4.3)

Rows shown = **active packs ∪ inactive packs with ≥1 seen word**.

Sort order:

1. Active packs first, in `PackSelectionService.getActiveIds()` order (matches HomePage chip order).
2. Inactive-but-seen packs next, sorted by `accuracyPct` ascending (lowest first — surfaces problem packs).

No visual badge for active vs inactive — the sort + clustering is enough signal.

## 4. Architecture

### 4.1 Data model

```typescript
// services/LearningReportBuilder.ets

export class PackReport {
  packId: string = '';       // Pack.id, e.g. 'fruit-forest', 'space-station'
  name: string = '';         // Pack.name (English), e.g. 'Fruit Forest'
  totalSeen: number = 0;     // Σ stat.seenCount over wordIds in this pack
  totalCorrect: number = 0;  // Σ stat.correctCount over wordIds in this pack
  accuracyPct: number = 0;   // 0..100, rounded; 0 when totalSeen === 0
  active: boolean = false;   // mirrors PackSelectionService.getActiveIds().has(packId)
}

export class LearningReport {
  totalWords: number = 0;
  totalSeen: number = 0;
  totalCorrect: number = 0;
  accuracyPct: number = 0;
  newCount: number = 0;
  learningCount: number = 0;
  familiarCount: number = 0;
  masteredCount: number = 0;
  reviewDueCount: number = 0;
  reviewDoneTodayCount: number = 0;
  reviewCompletionPct: number = 0;
  packs: PackReport[] = [];   // ordered: active packs in selection order, then inactive by accuracy asc
}
```

**Removed**: `CategoryReport`, `describeCategory()`, `LearningReport.weakCategories`, `LearningReport.categories`, `pickWeakCategories()` helper.

### 4.2 Builder signature

```typescript
build(
  library: PackLibrary,
  activeIds: string[],
  recorder: LearningRecorder,
  nowMs: number,
): LearningReport;
```

The builder no longer takes a `WordRepository` because the unique-word universe is now defined by `library.allPacks()` (the family-priority union from `PackLibrary`). Top-level `totalWords` reads `dedupedWordIdSetFromLibrary.size`.

`LearningReportPage.populateView` adds one extra cold-start call: after `WordPackBootstrapper.bootstrap()` resolves, it calls `loadHomeIntegration(ctx)` (the same helper HomePage / PackManagerPage already use) to obtain `{ library, selection }` and feeds those to `build()`.

### 4.3 Aggregation rules

**Top-level totals (`totalSeen / totalCorrect / accuracyPct`)** — unique-word-aggregated. Iterate `library.allPacks()` once to build `knownWordIds: Set<string>`. Then sum `stat.seenCount` / `stat.correctCount` by iterating the **stats list once** (`recorder.statsForTest()` returns one `WordStat` per wordId by construction, so dedup is automatic — there's no risk of summing the same answer twice even when multiple packs share a wordId). Stats whose `wordId` is fully orphaned (no pack contains it anymore) are ignored.

**State pills (`new / learning / familiar / mastered`)** + **review counters** — same as today, computed across the library union of words. Top-level cards retain their semantics.

**Per-pack rows** — for each `pack ∈ library.allPacks()`:

```
row.totalSeen    = Σ over (w ∈ pack.words where statByWordId.has(w.id)) of stat.seenCount
row.totalCorrect = Σ over (w ∈ pack.words where statByWordId.has(w.id)) of stat.correctCount
```

A word in N active packs contributes its `stat` to **every** pack row (per-pack independent counting). The top-level total still counts that word once. Therefore `Σ row.totalSeen` may exceed `report.totalSeen` when packs share words — this is intentional and reflects "this pack has been studied" semantics rather than a global tally.

**Row inclusion**: `row` is added to `report.packs` iff `row.active === true OR row.totalSeen > 0`.

**Sort**: `[...activeRowsInSelectionOrder, ...inactiveRowsByAccuracyAsc]`.

### 4.4 Page rendering

```typescript
// pages/LearningReportPage.ets

@State private packs: PackReport[] = [];
// (weakCategories removed)

build() {
  // ... topBar(), accuracyCard(), statesCard(), reviewCard() unchanged
  // weakCard() removed
  this.packBreakdown();   // renamed from categoryBreakdown()
  // emptyState() unchanged
}

@Builder
private packBreakdown() {
  Column({ space: 8 }) {
    Text('词包详情')
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor('#1D3557');
    ForEach(this.packs, (p: PackReport): void => {
      this.packRow(p);
    }, (p: PackReport): string => `pack-${p.packId}`);
  }
  .id('LearningReportPackSection')
  // ... same card chrome as before
}

@Builder
private packRow(p: PackReport) {
  Row() {
    Text(p.name).fontSize(14).fontColor('#1D3557');
    Blank();
    Text(`${p.totalCorrect} / ${p.totalSeen}`).fontSize(13).fontColor('#5A4A35').margin({ right: 12 });
    Text(p.totalSeen > 0 ? `${p.accuracyPct}%` : '—').fontSize(13).fontColor('#5A4A35');
  }
  .width('100%');
}
```

Test ids changed:

- `LearningReportCategorySection` → `LearningReportPackSection`
- `LearningReportWeakSection` → removed
- per-row keys `cat-${cat.category}` → `pack-${p.packId}`

## 5. Test plan

### 5.1 Unit tests — `entry/src/test/LearningReportBuilder.test.ets`

Drop `describe('describeCategory', ...)` block (3 cases — function no longer exists).

Rewrite `describe('LearningReportBuilder.build', ...)` to the new signature. New test fixture builds a small `PackLibrary` with 2 builtins (`fruit-forest` 5 words, `school-castle` 4 words) + 1 inactive seen pack (`space-station` 3 words, simulating a global pack the kid played once before deactivating it):

| Test | Asserts |
|---|---|
| `returnsZeroStateForEmptyRecorder` | totalSeen=0, all active builtins render with 0 stats; inactive packs not in rows |
| `aggregatesAccuracyPerPack` | per-pack totalSeen / totalCorrect attributable to each pack |
| `inactivePackWithSeenWordsStillAppears` | NEW — `space-station` row present even though not in `activeIds` |
| `inactivePackWithNoStatsIsExcluded` | NEW — a 4th never-played, deactivated pack does NOT render |
| `wordSharedBetweenActivePacksCountsTowardBoth` | NEW — fixture with `apple` in both `fruit-forest` and a 2nd active pack; both rows show +1 seen |
| `topLevelTotalsDedupeSharedWordsAcrossPacks` | NEW — same fixture; `report.totalSeen === 1` (one stat record), per-pack rows show `+1` each. Regression guard against future implementations that walk packs instead of stats for top-level. |
| `activePacksSortBeforeInactiveOnes` | first 2 rows = builtins (selection order), 3rd = `space-station` |
| `inactivePacksSortByAccuracyAscending` | with 2 inactive seen packs at 30% and 60% — the 30% one comes first |
| `accuracyRoundsToNearestInteger` | preserved logic check |
| `countsMasteredAndFamiliarViaScheduler` | preserved (top-level state pills) |
| `reviewCompletionTracksTodaysCorrectAnswers` | preserved (top-level review card) |
| `reviewCompletionStays0WhenNothingReviewedToday` | preserved |

Total: 12 unit tests (was 12: 9 builder cases + 3 `describeCategory` cases). `describe('describeCategory')` block removed entirely (function gone); 2 weak-list cases (`orderWeakCategoriesByLowestAccuracyFirst`, `skipsCategoriesWithNoSeenWordsFromWeakList`) removed; 1 case rolled into the new `topLevelTotalsDedupeSharedWordsAcrossPacks` (the old `totalsExcludeUnseenWordsFromAccuracy` is now implicit in the new fixture).

### 5.2 UI test — `entry/src/ohosTest/ets/test/LearningReportFlow.ui.test.ets`

Replace category-id refs with pack-id refs. Add one new smoke case:

| Test | Action |
|---|---|
| `reportRendersAccuracySectionAndAllBuiltinPackRows` | Existing nav assertion + assert all 5 builtin pack rows render: `pack-fruit-forest`, `pack-school-castle`, `pack-home-cottage`, `pack-animal-safari`, `pack-ocean-realm` |

`LearningReportWeakSection` assertions (if any) deleted.

## 6. Edge cases

| Edge case | Behavior |
|---|---|
| Fresh install, no answers | All 5 builtin packs render with `0 / 0` and `—` for accuracy. Top-level shows 0%. |
| User deactivates a previously-played builtin (e.g., `home-cottage`) | Row stays in the report under the inactive cluster, sorted by accuracy. Re-activating moves it back to the active cluster on next report open. |
| Family pack the user played, then unbinds → cache wiped | Words orphaned. Top-level totals drop those answers (no pack contains them anymore); per-pack rows obviously can't show the gone pack. **Trade-off**: the parent's "I remember playing the family pack" mental model loses some history. Mitigation: this is the same behavior the rest of V0.6.5+ has (PackLibrary is the source of truth), and is consistent with the 'pack as canonical word owner' design. Documented in code comment. |
| Word in N active packs (rare today, possible after global pack rollout) | Per-pack rows count it independently. Top-level totals dedupe by wordId. |
| Library returns 0 packs (catastrophic — bootstrap failure) | `report.packs.length === 0`; existing `emptyState()` builder triggers the "go play first" message. |

## 7. Implementation order

1. Update `LearningReportBuilder.ets` (data model + `build()` signature + aggregation logic).
2. Rewrite `entry/src/test/LearningReportBuilder.test.ets` with the new fixture + 12 cases.
3. Run unit tests to verify the builder before touching UI.
4. Update `pages/LearningReportPage.ets` (state fields, builders, populateView).
5. Update `entry/src/ohosTest/ets/test/LearningReportFlow.ui.test.ets`.
6. Run `hvigorw assembleHap` (zero ArkTS:WARN) + `hvigorw -p module=entry@ohosTest assembleHap` + `scripts/run_ui_tests.sh --suite LearningReportFlow`.
7. Update spec/roadmap docs.
8. Bump `AppScope/app.json5` to `0.6.7.8` (versionCode `1006016`).

## 8. Decisions explicitly made (and not made)

**Made**:

- Scope: active packs ∪ inactive-but-seen packs (option B from brainstorming).
- Labels: English only via `pack.name` (matches HomePage / PackManagerPage convention).
- Weak section: removed.
- Shared-word counting: per-pack independent (each pack containing the word counts it).
- Sort: active first (selection order), then inactive by accuracy ascending. No visual badge.

**NOT done in this version (deliberate YAGNI)**:

- No source tag (`builtin / official / family`) on report rows.
- No filter / toggle to hide inactive packs.
- No per-pack state pills (mastered / learning breakdown). Could revisit if parents ask.
- No `packId` field added to `WordStat` schema. Cross-pack attribution stays best-effort via membership lookup.

