# Learning Report by Pack — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch `LearningReportPage` from category-keyed aggregation to pack-keyed aggregation so the report aligns with the V0.6.5+ three-layer word pack model that the rest of the app already uses.

**Architecture:** Replace `CategoryReport` with a new `PackReport` DTO. Change `LearningReportBuilder.build()` signature from `(repo, recorder, nowMs)` to `(library, activeIds, recorder, nowMs)`. Top-level totals iterate `recorder.statsForTest()` once (already deduped by `wordId`); per-pack rows iterate each pack's `words[]` and look up stats by id (per-pack independent counting — a shared word counts toward every pack containing it). Drop the "Weak Categories" card; the "Pack Breakdown" table is the single per-pack surface.

**Tech Stack:** ArkTS strict mode, HarmonyOS NEXT, `@ohos/hypium` for unit + UI tests, `hvigorw assembleHap` / `assembleOhosTest` for builds. Spec: [`docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md`](../specs/2026-05-10-learning-report-by-pack-design.md).

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `entry/src/main/ets/services/LearningReportBuilder.ets` | Modify | Replace `CategoryReport` → `PackReport`, drop `describeCategory`/`pickWeakCategories`, change `build()` signature, swap aggregation logic |
| `entry/src/test/LearningReportBuilder.test.ets` | Rewrite | New fixture builds `PackLibrary` + `PackSelectionService` substitute; 12 cases covering active / inactive / shared-word / sort behaviors |
| `entry/src/main/ets/pages/LearningReportPage.ets` | Modify | Replace `categories` / `weakCategories` state with `packs`; rename `categoryBreakdown()` → `packBreakdown()`; drop `weakCard()` + `weakRow()`; add `loadHomeIntegration(ctx)` to `populateView` cold-start |
| `entry/src/ohosTest/ets/test/LearningReportFlow.ui.test.ets` | Modify | Swap `LearningReportCategorySection` for `LearningReportPackSection`; add 1 new case asserting all 5 builtin pack rows render |
| `AppScope/app.json5` | Modify | Bump `versionCode` to `1006016`, `versionName` to `"0.6.7.8"` |
| `docs/WordMagicGame_overall_spec.md` | Modify | Update §1 version table + §15.2 ohosTest index entry |
| `docs/WordMagicGame_roadmap.md` | Modify | Add V0.6.7.8 entry to "最近更新" |

---

## Task 1: Atomic shape change — builder types + builder stub + page rewrite

**Files:**
- Modify: `entry/src/main/ets/services/LearningReportBuilder.ets`
- Modify: `entry/src/main/ets/pages/LearningReportPage.ets`

**Why atomic:** ArkTS compiles `entry/src/main/` and `entry/src/test/` together; a half-refactored builder leaves the page failing to compile, which blocks Task 2's unit tests from running. Both files change in one commit. The builder's `build()` body is a stub that returns an empty `LearningReport` — tests in Task 2 will fail against this stub, then Task 3 fills in the logic. The page renders correctly (no crash) because every state field has a sane default.

**Critical step ordering:** the old `build()` body still references `CategoryReport`, `describeCategory`, and `pickWeakCategories`. We MUST replace `build()` with the stub first, otherwise deleting those helpers leaves the old body referencing deleted code.

- [ ] **Step 1: Replace the entire `LearningReportBuilder.ets` file in one shot**

Replace the contents of `entry/src/main/ets/services/LearningReportBuilder.ets` with:

```typescript
import { WordEntry } from '../models/WordEntry';
import { Pack } from '../models/Pack';
import { PackLibrary } from './PackLibrary';
import { LearningRecorder } from './LearningRecorder';
import { MemoryScheduler, MemoryState } from './MemoryScheduler';
import { WordStat } from './WrongAnswerStore';
import { localStartOfDay } from './TodayPlanService';

/**
 * One pack row in the learning report. The page renders these
 * verbatim into the pack-breakdown table. Replaces V0.4.5's
 * CategoryReport (the category dimension has zero remaining UX
 * surface since V0.6.6 removed the category picker from
 * ConfigPage; HomePage chips, PackManagerPage, and BattlePage
 * today-mode all key on packs).
 */
export class PackReport {
  packId: string = '';
  name: string = '';
  totalSeen: number = 0;
  totalCorrect: number = 0;
  /** 0..100, rounded to integer. 0 when totalSeen === 0. */
  accuracyPct: number = 0;
  /** Mirrors PackSelectionService.getActiveIds().has(packId). */
  active: boolean = false;
}

/**
 * Aggregate snapshot of learning progress so far. Pure data, no
 * methods that mutate. The page reads each field directly into
 * ArkUI components.
 */
export class LearningReport {
  totalWords: number = 0;
  totalSeen: number = 0;
  totalCorrect: number = 0;
  /** 0..100, rounded to integer. 0 when totalSeen === 0. */
  accuracyPct: number = 0;
  newCount: number = 0;
  learningCount: number = 0;
  familiarCount: number = 0;
  masteredCount: number = 0;
  reviewDueCount: number = 0;
  reviewDoneTodayCount: number = 0;
  /** 0..100. `done / max(due, done)` so it never exceeds 100. */
  reviewCompletionPct: number = 0;
  /**
   * One row per pack. Order: active packs first (in selection
   * order), then inactive-but-seen packs sorted by accuracyPct
   * ascending. See LearningReportBuilder.build for the rules.
   */
  packs: PackReport[] = [];
}

/**
 * Pure builder for the V0.6.7.8 learning report. No persistence,
 * no I/O — feed it the in-memory PackLibrary, the active-id list,
 * and the initialised recorder; receive a `LearningReport`.
 *
 * V0.4.5 keyed reports by category; the V0.6.7.8 rewrite keys by
 * pack to align with the V0.6.5 three-layer pack model. See
 * docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md
 * for the rules around per-pack independent counting and top-level
 * dedup-by-stat-iteration.
 */
export class LearningReportBuilder {
  private scheduler: MemoryScheduler;

  constructor(scheduler?: MemoryScheduler) {
    this.scheduler = scheduler !== undefined ? scheduler : new MemoryScheduler();
  }

  build(
    library: PackLibrary,
    activeIds: string[],
    recorder: LearningRecorder,
    nowMs: number,
  ): LearningReport {
    // V0.6.7.8 stub — Task 3 will replace this with the real
    // aggregation logic. Leaving it as an empty report keeps the
    // module buildable so the unit-test refactor in Task 2 can land.
    const report: LearningReport = new LearningReport();
    return report;
  }
}
```

This single replacement deletes `CategoryReport` / `describeCategory` / `pickWeakCategories` and replaces `build()` body atomically — there is no intermediate state where any reference dangles.

- [ ] **Step 2: Update `LearningReportPage.ets` imports + state**

In `entry/src/main/ets/pages/LearningReportPage.ets`, replace the existing imports block (lines 1-12) with:

```typescript
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import display from '@ohos.display';
import { WordPackBootstrapper, BootstrapDeps } from '../services/WordPackBootstrapper';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import {
  LearningReportBuilder,
  LearningReport,
  PackReport,
} from '../services/LearningReportBuilder';
import {
  HomeIntegrationBundle,
  loadHomeIntegration,
} from '../services/PackHomeIntegration';
```

(Removed: `WordRepository` import — no longer needed; `CategoryReport` import — replaced.)

In the `LearningReportPage` struct, replace:

```typescript
  @State private categories: CategoryReport[] = [];
  @State private weakCategories: CategoryReport[] = [];
```

with:

```typescript
  @State private packs: PackReport[] = [];
```

- [ ] **Step 3: Rewrite `aboutToAppear` + `populateView` to load library + selection**

Replace the existing `aboutToAppear()` (lines ~57-82) with:

```typescript
  aboutToAppear(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const widthVp: number = this.getUIContext().px2vp(d.width);
      const heightVp: number = this.getUIContext().px2vp(d.height);
      this.shortEdgeVp = Math.min(widthVp, heightVp);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      console.error(`LearningReportPage: display query failed: ${JSON.stringify(e)}`);
    }
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // V0.6.7.8: report aggregates per-pack, so we need the same
    // (PackLibrary + PackSelectionService) bundle that HomePage
    // and PackManagerPage already build via loadHomeIntegration.
    // Run bootstrap (recorder hydration deps) and loadHomeIntegration
    // (library + selection) in parallel; both are idempotent.
    Promise.all([
      WordPackBootstrapper.forContext(ctx),
      loadHomeIntegration(ctx),
    ]).then((results: [BootstrapDeps, HomeIntegrationBundle]): void => {
      const bundle: HomeIntegrationBundle = results[1];
      const recorder: LearningRecorder = getLearningRecorder();
      recorder.init(ctx).then((): void => {
        this.populateView(bundle, recorder);
      }).catch((err: BusinessError): void => {
        console.error(`LearningReportPage: recorder.init failed: ${JSON.stringify(err)}`);
        this.populateView(bundle, recorder);
      });
    }).catch((err: BusinessError): void => {
      console.error(`LearningReportPage: bootstrap or loadHomeIntegration failed: ${JSON.stringify(err)}`);
      this.loaded = true;
    });
  }
```

Replace `populateView(repo, recorder)` (lines ~95-111) with:

```typescript
  private populateView(bundle: HomeIntegrationBundle, recorder: LearningRecorder): void {
    const report: LearningReport = new LearningReportBuilder().build(
      bundle.library,
      bundle.selection.getActiveIds(),
      recorder,
      Date.now(),
    );
    this.accuracyPct = report.accuracyPct;
    this.totalSeen = report.totalSeen;
    this.totalCorrect = report.totalCorrect;
    this.masteredCount = report.masteredCount;
    this.familiarCount = report.familiarCount;
    this.learningCount = report.learningCount;
    this.newCount = report.newCount;
    this.reviewDoneTodayCount = report.reviewDoneTodayCount;
    this.reviewDueCount = report.reviewDueCount;
    this.reviewCompletionPct = report.reviewCompletionPct;
    this.packs = report.packs;
    this.loaded = true;
  }
```

- [ ] **Step 4: Drop `weakCard` call + rename categoryBreakdown to packBreakdown in `build()`**

Replace the inner `Column({ space: 12 })` block (lines ~122-134) with:

```typescript
          Column({ space: 12 }) {
            this.accuracyCard();
            this.statesCard();
            this.reviewCard();
            this.packBreakdown();
            if (this.loaded && this.totalSeen === 0) {
              this.emptyState();
            }
          }
```

- [ ] **Step 5: Remove `weakCard()` + `weakRow()` builders**

Delete the entire `@Builder private weakCard()` (lines ~295-313) and `@Builder private weakRow(cat)` (lines ~315-327) methods.

- [ ] **Step 6: Replace `categoryBreakdown()` + `categoryRow()` with `packBreakdown()` + `packRow()`**

Delete the existing `@Builder private categoryBreakdown()` (lines ~329-347) and `@Builder private categoryRow(cat)` (lines ~349-365). Replace with:

```typescript
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
    .width('100%')
    .padding(16)
    .id('LearningReportPackSection')
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: '#E0E0E0' });
  }

  @Builder
  private packRow(p: PackReport) {
    Row() {
      Text(p.name)
        .fontSize(14)
        .fontColor('#1D3557');
      Blank();
      Text(`${p.totalCorrect} / ${p.totalSeen}`)
        .fontSize(13)
        .fontColor('#5A4A35')
        .margin({ right: 12 });
      Text(p.totalSeen > 0 ? `${p.accuracyPct}%` : '—')
        .fontSize(13)
        .fontColor('#5A4A35');
    }
    .id(`pack-${p.packId}`)
    .width('100%');
  }
```

The `.id(\`pack-${p.packId}\`)` line is required for Task 4's UI test that looks up rows like `pack-fruit-forest` by id. (`ForEach`'s 3rd arg is React-style reconciliation only and doesn't surface as a UI test id.)

- [ ] **Step 7: Verify clean build with zero ArkTS warnings**

Run: `hvigorw clean assembleHap --no-daemon 2>&1 | tail -10`
Expected: `BUILD SUCCESSFUL`.

Then: `hvigorw assembleHap --no-daemon 2>&1 | grep -i 'arkts:warn' ; echo done`
Expected: only `done` printed.

The page now renders correctly with empty `packs[]` (the breakdown card shows the `词包详情` heading + zero rows). State pills + accuracy will all read 0. This is the expected intermediate state until Task 3 fills in the builder logic.

- [ ] **Step 8: Commit**

```bash
git add entry/src/main/ets/services/LearningReportBuilder.ets entry/src/main/ets/pages/LearningReportPage.ets
git commit -m "$(cat <<'EOF'
refactor(learning-report): replace CategoryReport with PackReport DTO

Atomic shape change: replace CategoryReport with PackReport in
LearningReportBuilder, drop describeCategory + pickWeakCategories,
change build() signature from (repo, recorder, nowMs) to
(library, activeIds, recorder, nowMs). LearningReportPage updated
in the same commit to consume the new DTO, drop weakCard, and
load PackLibrary + PackSelectionService via loadHomeIntegration.

The build() body is stubbed to return an empty LearningReport;
the next commit adds the per-pack aggregation logic.

Refs: docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md
EOF
)"
```

---

## Task 2: Rewrite unit tests (TDD — tests will fail until Task 3)

**Files:**
- Modify: `entry/src/test/LearningReportBuilder.test.ets`

**Why before logic:** TDD. Each behavior in the spec gets a failing test before the implementation lands.

- [ ] **Step 1: Replace the entire test file**

Replace the contents of `entry/src/test/LearningReportBuilder.test.ets` with:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { WordEntry } from '../main/ets/models/WordEntry';
import { Pack, SceneMetadata } from '../main/ets/models/Pack';
import { PackLibrary } from '../main/ets/services/PackLibrary';
import { LearningRecorder } from '../main/ets/services/LearningRecorder';
import {
  LearningSnapshot,
  StringPreferencesLike,
  WordStat,
  WrongAnswerStore,
} from '../main/ets/services/WrongAnswerStore';
import {
  LearningReportBuilder,
  LearningReport,
  PackReport,
} from '../main/ets/services/LearningReportBuilder';

class FakePreferences implements StringPreferencesLike {
  private readonly map: Map<string, string> = new Map<string, string>();
  getString(key: string): Promise<string> {
    return Promise.resolve(this.map.has(key) ? (this.map.get(key) as string) : '');
  }
  putString(key: string, value: string): Promise<void> {
    this.map.set(key, value);
    return Promise.resolve();
  }
  flush(): Promise<void> {
    return Promise.resolve();
  }
}

function makeWord(id: string, category: string): WordEntry {
  const w: WordEntry = new WordEntry();
  w.id = id;
  w.word = id;
  w.meaningZh = '_';
  w.category = category;
  w.difficulty = 1;
  return w;
}

function makePack(id: string, name: string, source: 'builtin' | 'global' | 'family',
                  wordIds: string[], category: string): Pack {
  const p: Pack = new Pack();
  p.id = id;
  p.name = name;
  p.labelZh = '';
  p.source = source;
  p.version = 1;
  p.publishedAtMs = 0;
  p.scene = new SceneMetadata();
  p.words = wordIds.map((wid: string): WordEntry => makeWord(wid, category));
  return p;
}

/**
 * Standard 3-pack fixture used by most cases:
 *   - fruit-forest (builtin, 5 words: f-apple, f-banana, f-orange, f-grape, f-pear)
 *   - school-castle (builtin, 4 words: s-school, s-park, s-zoo, s-bank)
 *   - space-station (global, 3 words: ss-rocket, ss-moon, ss-earth)
 *
 * activeIds defaults to the 2 builtins; tests that need
 * inactive-but-seen behavior pass space-station's words into the
 * recorder while leaving it out of activeIds.
 */
function makeLibrary(): PackLibrary {
  const lib: PackLibrary = new PackLibrary();
  lib.setBuiltins([
    makePack('fruit-forest', 'Fruit Forest', 'builtin',
      ['f-apple', 'f-banana', 'f-orange', 'f-grape', 'f-pear'], 'fruit'),
    makePack('school-castle', 'School Castle', 'builtin',
      ['s-school', 's-park', 's-zoo', 's-bank'], 'place'),
  ]);
  lib.setGlobals([
    makePack('space-station', 'Space Station', 'global',
      ['ss-rocket', 'ss-moon', 'ss-earth'], 'place'),
  ]);
  return lib;
}

const ACTIVE_BUILTINS: string[] = ['fruit-forest', 'school-castle'];

function makeRecorder(stats: WordStat[]): LearningRecorder {
  const snap: LearningSnapshot = new LearningSnapshot();
  for (let i = 0; i < stats.length; i++) {
    snap.stats.push(stats[i]);
  }
  const store: WrongAnswerStore = new WrongAnswerStore();
  store.injectPreferences(new FakePreferences());
  const rec: LearningRecorder = new LearningRecorder(store);
  rec.attachStore(store, snap);
  return rec;
}

function makeStat(
  wordId: string,
  seenCount: number,
  correctCount: number,
  consecutiveCorrect: number,
  lastAnsweredMs: number,
  memoryState: string,
): WordStat {
  const s: WordStat = new WordStat();
  s.wordId = wordId;
  s.seenCount = seenCount;
  s.correctCount = correctCount;
  s.wrongCount = seenCount - correctCount;
  s.consecutiveCorrect = consecutiveCorrect;
  s.consecutiveWrong = consecutiveCorrect > 0 ? 0 : (seenCount - correctCount);
  s.lastAnsweredMs = lastAnsweredMs;
  s.lastCorrectMs = correctCount > 0 ? lastAnsweredMs : -1;
  s.nextReviewMs = lastAnsweredMs + 60 * 60 * 1000;
  s.memoryState = memoryState;
  s.mastery = correctCount / Math.max(1, seenCount);
  return s;
}

function findPack(report: LearningReport, packId: string): PackReport {
  for (let i = 0; i < report.packs.length; i++) {
    if (report.packs[i].packId === packId) return report.packs[i];
  }
  return new PackReport();
}

const NOW: number = 17_000_000_000_000;
const YESTERDAY: number = NOW - 26 * 60 * 60 * 1000;

export default function learningReportBuilderTest() {
  describe('LearningReportBuilder.build', () => {
    it('returnsZeroStateForEmptyRecorder', 0, () => {
      const lib: PackLibrary = makeLibrary();
      const rec: LearningRecorder = makeRecorder([]);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      expect(report.totalSeen).assertEqual(0);
      expect(report.totalCorrect).assertEqual(0);
      expect(report.accuracyPct).assertEqual(0);
      // 5 + 4 + 3 = 12 unique wordIds in the library union
      expect(report.totalWords).assertEqual(12);
      // Active builtins both render with 0 stats; inactive global pack
      // (no stats) does NOT render.
      expect(report.packs.length).assertEqual(2);
      expect(report.packs[0].packId).assertEqual('fruit-forest');
      expect(report.packs[1].packId).assertEqual('school-castle');
      expect(report.packs[0].active).assertTrue();
      expect(report.packs[0].totalSeen).assertEqual(0);
      expect(report.packs[0].accuracyPct).assertEqual(0);
    });

    it('aggregatesAccuracyPerPack', 0, () => {
      const lib: PackLibrary = makeLibrary();
      const stats: WordStat[] = [
        makeStat('f-apple', 4, 4, 4, NOW, 'familiar'),
        makeStat('f-banana', 4, 2, 0, NOW, 'review'),
        makeStat('s-school', 4, 1, 0, NOW, 'review'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      expect(report.totalSeen).assertEqual(12);
      expect(report.totalCorrect).assertEqual(7);
      // 7 / 12 = 58.33 -> 58
      expect(report.accuracyPct).assertEqual(58);
      // fruit-forest: 4+2 / 4+4 = 6 / 8 = 75
      const fruit: PackReport = findPack(report, 'fruit-forest');
      expect(fruit.totalSeen).assertEqual(8);
      expect(fruit.totalCorrect).assertEqual(6);
      expect(fruit.accuracyPct).assertEqual(75);
      // school-castle: 1 / 4 = 25
      const school: PackReport = findPack(report, 'school-castle');
      expect(school.totalSeen).assertEqual(4);
      expect(school.accuracyPct).assertEqual(25);
    });

    it('inactivePackWithSeenWordsStillAppears', 0, () => {
      const lib: PackLibrary = makeLibrary();
      const stats: WordStat[] = [
        // The kid played space-station at some point — it has stats —
        // but it's not in activeIds today.
        makeStat('ss-rocket', 3, 2, 0, NOW, 'learning'),
        makeStat('ss-moon', 2, 1, 0, NOW, 'review'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      // Both active builtins (no stats, but active) + space-station
      // (inactive, has stats) → 3 rows.
      expect(report.packs.length).assertEqual(3);
      // Active first.
      expect(report.packs[0].packId).assertEqual('fruit-forest');
      expect(report.packs[1].packId).assertEqual('school-castle');
      expect(report.packs[2].packId).assertEqual('space-station');
      expect(report.packs[2].active).assertFalse();
      expect(report.packs[2].totalSeen).assertEqual(5);
      expect(report.packs[2].totalCorrect).assertEqual(3);
      expect(report.packs[2].accuracyPct).assertEqual(60);
    });

    it('inactivePackWithNoStatsIsExcluded', 0, () => {
      const lib: PackLibrary = makeLibrary();
      // space-station is inactive AND has zero stats — it must NOT
      // render. activeIds excludes it as well.
      const rec: LearningRecorder = makeRecorder([]);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      expect(report.packs.length).assertEqual(2);
      for (let i = 0; i < report.packs.length; i++) {
        expect(report.packs[i].packId !== 'space-station').assertTrue();
      }
    });

    it('wordSharedBetweenActivePacksCountsTowardBoth', 0, () => {
      // Build a library where 'shared-word' appears in BOTH packs.
      const lib: PackLibrary = new PackLibrary();
      lib.setBuiltins([
        makePack('p1', 'P1', 'builtin', ['shared-word', 'p1-only'], 'fruit'),
        makePack('p2', 'P2', 'builtin', ['shared-word', 'p2-only'], 'fruit'),
      ]);
      const stats: WordStat[] = [makeStat('shared-word', 1, 1, 1, NOW, 'learning')];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ['p1', 'p2'], rec, NOW);
      const p1: PackReport = findPack(report, 'p1');
      const p2: PackReport = findPack(report, 'p2');
      // Per-pack independent: each row counts the shared word.
      expect(p1.totalSeen).assertEqual(1);
      expect(p1.totalCorrect).assertEqual(1);
      expect(p2.totalSeen).assertEqual(1);
      expect(p2.totalCorrect).assertEqual(1);
    });

    it('topLevelTotalsDedupeSharedWordsAcrossPacks', 0, () => {
      // Same fixture as the previous case — but assert top-level
      // totals do NOT double-count.
      const lib: PackLibrary = new PackLibrary();
      lib.setBuiltins([
        makePack('p1', 'P1', 'builtin', ['shared-word', 'p1-only'], 'fruit'),
        makePack('p2', 'P2', 'builtin', ['shared-word', 'p2-only'], 'fruit'),
      ]);
      const stats: WordStat[] = [makeStat('shared-word', 1, 1, 1, NOW, 'learning')];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ['p1', 'p2'], rec, NOW);
      // Top-level: one stat record contributes once.
      expect(report.totalSeen).assertEqual(1);
      expect(report.totalCorrect).assertEqual(1);
      expect(report.accuracyPct).assertEqual(100);
    });

    it('activePacksSortBeforeInactiveOnes', 0, () => {
      const lib: PackLibrary = makeLibrary();
      const stats: WordStat[] = [
        makeStat('ss-rocket', 1, 1, 1, NOW, 'learning'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      // Pass ACTIVE_BUILTINS in reverse to confirm selection order
      // (not alphabetical) is honored.
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ['school-castle', 'fruit-forest'], rec, NOW);
      expect(report.packs[0].packId).assertEqual('school-castle');
      expect(report.packs[1].packId).assertEqual('fruit-forest');
      expect(report.packs[2].packId).assertEqual('space-station');
    });

    it('inactivePacksSortByAccuracyAscending', 0, () => {
      const lib: PackLibrary = new PackLibrary();
      lib.setBuiltins([
        makePack('a', 'A', 'builtin', ['a1', 'a2'], 'fruit'),
      ]);
      lib.setGlobals([
        // High-accuracy inactive pack
        makePack('high', 'High', 'global', ['h1', 'h2'], 'place'),
        // Low-accuracy inactive pack
        makePack('low', 'Low', 'global', ['l1', 'l2'], 'place'),
      ]);
      const stats: WordStat[] = [
        makeStat('h1', 5, 4, 0, NOW, 'familiar'),  // 80%
        makeStat('h2', 5, 4, 0, NOW, 'familiar'),
        makeStat('l1', 5, 1, 0, NOW, 'review'),    // 20%
        makeStat('l2', 5, 1, 0, NOW, 'review'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ['a'], rec, NOW);
      // Active 'a' first (no stats), then inactive sorted by accuracy
      // ascending: low (20%) before high (80%).
      expect(report.packs[0].packId).assertEqual('a');
      expect(report.packs[1].packId).assertEqual('low');
      expect(report.packs[2].packId).assertEqual('high');
      expect(report.packs[1].accuracyPct).assertEqual(20);
      expect(report.packs[2].accuracyPct).assertEqual(80);
    });

    it('accuracyRoundsToNearestInteger', 0, () => {
      const lib: PackLibrary = makeLibrary();
      const stats: WordStat[] = [
        makeStat('f-apple', 3, 2, 2, NOW, 'learning'), // 2/3 = 66.67
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      expect(report.accuracyPct).assertEqual(67);
    });

    it('countsMasteredAndFamiliarViaScheduler', 0, () => {
      const lib: PackLibrary = makeLibrary();
      const stats: WordStat[] = [
        makeStat('f-apple', 6, 6, 6, NOW, 'mastered'),
        makeStat('f-banana', 3, 3, 3, NOW, 'familiar'),
        makeStat('f-orange', 1, 1, 1, NOW, 'learning'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      expect(report.masteredCount).assertEqual(1);
      expect(report.familiarCount).assertEqual(1);
      expect(report.learningCount).assertEqual(1);
      // 12 unique words - 3 seen = 9 untouched still count as new
      expect(report.newCount).assertEqual(9);
    });

    it('reviewCompletionTracksTodaysCorrectAnswers', 0, () => {
      const lib: PackLibrary = makeLibrary();
      const apple: WordStat = makeStat('f-apple', 3, 3, 1, NOW, 'learning');
      const stats: WordStat[] = [
        apple,
        makeStat('f-banana', 2, 1, 0, YESTERDAY, 'review'),
        makeStat('s-school', 2, 1, 0, YESTERDAY, 'review'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      expect(report.reviewDoneTodayCount).assertEqual(1);
      expect(report.reviewDueCount > 0).assertTrue();
      expect(report.reviewCompletionPct > 0).assertTrue();
      expect(report.reviewCompletionPct <= 100).assertTrue();
    });

    it('reviewCompletionStays0WhenNothingReviewedToday', 0, () => {
      const lib: PackLibrary = makeLibrary();
      const stats: WordStat[] = [
        makeStat('f-apple', 2, 1, 0, YESTERDAY, 'review'),
      ];
      const rec: LearningRecorder = makeRecorder(stats);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      expect(report.reviewDoneTodayCount).assertEqual(0);
      expect(report.reviewCompletionPct).assertEqual(0);
    });
  });
}
```

- [ ] **Step 2: Run unit tests — they should fail**

Run: `hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -40`
Expected: All 12 cases under `LearningReportBuilder.build` fail because `build()` returns an empty report (Task 1's stub).

- [ ] **Step 3: Commit**

```bash
git add entry/src/test/LearningReportBuilder.test.ets
git commit -m "$(cat <<'EOF'
test(learning-report): rewrite unit tests for pack-keyed aggregation

Replace category-based fixture with PackLibrary-based fixture.
12 cases cover active-only, inactive-but-seen, shared-word
counting, top-level dedup, and sort order. All tests fail
against Task 1's stub build() — Task 3 will make them pass.

Refs: docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md
EOF
)"
```

---

## Task 3: Implement `build()` aggregation logic

**Files:**
- Modify: `entry/src/main/ets/services/LearningReportBuilder.ets`

- [ ] **Step 1: Replace the stub `build()` with the real implementation**

Replace the stub from Task 1 (currently `return new LearningReport()`) with:

```typescript
build(
  library: PackLibrary,
  activeIds: string[],
  recorder: LearningRecorder,
  nowMs: number,
): LearningReport {
  const stats: WordStat[] = recorder.statsForTest();
  const statByWordId: Map<string, WordStat> = new Map<string, WordStat>();
  for (let i = 0; i < stats.length; i++) {
    statByWordId.set(stats[i].wordId, stats[i]);
  }

  const startOfDay: number = localStartOfDay(nowMs);
  const allPacks: Pack[] = library.allPacks();
  const activeSet: Set<string> = new Set<string>();
  for (let i = 0; i < activeIds.length; i++) activeSet.add(activeIds[i]);

  // Collect every wordId that is reachable from the library union.
  // Stats whose wordId is not in this set are orphaned (the pack
  // that owned them was removed) and are ignored at the top level.
  const knownWordIds: Set<string> = new Set<string>();
  for (let i = 0; i < allPacks.length; i++) {
    const ws: WordEntry[] = allPacks[i].words;
    for (let j = 0; j < ws.length; j++) knownWordIds.add(ws[j].id);
  }

  const report: LearningReport = new LearningReport();
  report.totalWords = knownWordIds.size;

  // ----- Top-level totals: iterate STATS once. Each stat record is
  // unique-per-wordId by construction (LearningRecorder guarantees
  // this), so summing here naturally dedupes across packs that share
  // a word. Stats whose wordId is orphaned are skipped.
  let totalSeen: number = 0;
  let totalCorrect: number = 0;
  let newCount: number = 0;
  let learningCount: number = 0;
  let familiarCount: number = 0;
  let masteredCount: number = 0;
  let reviewDue: number = 0;
  let reviewDoneToday: number = 0;
  for (let i = 0; i < stats.length; i++) {
    const stat: WordStat = stats[i];
    if (!knownWordIds.has(stat.wordId)) continue;
    totalSeen += stat.seenCount;
    totalCorrect += stat.correctCount;
    const state: MemoryState = this.scheduler.classify(stat, nowMs);
    if (state === MemoryState.New) {
      newCount += 1;
    } else if (state === MemoryState.Mastered) {
      masteredCount += 1;
    } else if (state === MemoryState.Familiar) {
      familiarCount += 1;
    } else if (state === MemoryState.Review) {
      reviewDue += 1;
      learningCount += 1;
    } else {
      learningCount += 1;
    }
    const isReviewable: boolean =
      stat.seenCount > 0 && stat.lastAnsweredMs < startOfDay;
    if (isReviewable && stat.lastAnsweredMs >= 0 && state !== MemoryState.New) {
      if (state !== MemoryState.Review) {
        reviewDue += 1;
      }
    }
    const doneToday: boolean =
      stat.lastAnsweredMs >= startOfDay && stat.consecutiveCorrect > 0;
    if (doneToday) {
      reviewDoneToday += 1;
    }
  }
  // Words in the library union that have no stat record are "new".
  newCount += knownWordIds.size - statByWordId.size;
  // (knownWordIds may include words whose stat is orphaned-from-library,
  // but those are the same set: any wordId in statByWordId AND in
  // knownWordIds was counted as one of the 4 states above. The
  // remaining (knownWordIds.size - countedInStats) words are unseen.
  // Recompute below to be precise.)
  // Recompute newCount precisely: iterate knownWordIds, count those
  // without a stat, plus the MemoryState.New stat-bearing entries.
  let unseenInLibrary: number = 0;
  knownWordIds.forEach((id: string): void => {
    if (!statByWordId.has(id)) unseenInLibrary += 1;
  });
  // newCount currently includes MemoryState.New from stats; re-derive
  // to avoid double-counting the unseen-in-library set.
  let newFromStats: number = 0;
  for (let i = 0; i < stats.length; i++) {
    const stat: WordStat = stats[i];
    if (!knownWordIds.has(stat.wordId)) continue;
    const state: MemoryState = this.scheduler.classify(stat, nowMs);
    if (state === MemoryState.New) newFromStats += 1;
  }
  newCount = newFromStats + unseenInLibrary;

  report.totalSeen = totalSeen;
  report.totalCorrect = totalCorrect;
  report.accuracyPct = totalSeen > 0
    ? Math.round((totalCorrect * 100) / totalSeen)
    : 0;
  report.newCount = newCount;
  report.learningCount = learningCount;
  report.familiarCount = familiarCount;
  report.masteredCount = masteredCount;
  report.reviewDueCount = reviewDue;
  report.reviewDoneTodayCount = reviewDoneToday;
  const denom: number = Math.max(reviewDue, reviewDoneToday);
  report.reviewCompletionPct = denom > 0
    ? Math.round((reviewDoneToday * 100) / denom)
    : 0;

  // ----- Per-pack rows: iterate each pack's words, look up stats.
  // A word in N active packs counts toward each row independently.
  const allRows: PackReport[] = [];
  for (let i = 0; i < allPacks.length; i++) {
    const pack: Pack = allPacks[i];
    const isActive: boolean = activeSet.has(pack.id);
    const row: PackReport = new PackReport();
    row.packId = pack.id;
    row.name = pack.name;
    row.active = isActive;
    for (let j = 0; j < pack.words.length; j++) {
      const stat: WordStat | undefined = statByWordId.get(pack.words[j].id);
      if (stat !== undefined) {
        row.totalSeen += stat.seenCount;
        row.totalCorrect += stat.correctCount;
      }
    }
    if (isActive || row.totalSeen > 0) {
      row.accuracyPct = row.totalSeen > 0
        ? Math.round((row.totalCorrect * 100) / row.totalSeen)
        : 0;
      allRows.push(row);
    }
  }

  // Sort: active first (in activeIds order), then inactive by
  // accuracy ascending. Use simple O(n) lookups since n <= ~10
  // in practice.
  const orderedActive: PackReport[] = [];
  for (let i = 0; i < activeIds.length; i++) {
    for (let j = 0; j < allRows.length; j++) {
      if (allRows[j].active && allRows[j].packId === activeIds[i]) {
        orderedActive.push(allRows[j]);
        break;
      }
    }
  }
  const inactiveRows: PackReport[] = [];
  for (let i = 0; i < allRows.length; i++) {
    if (!allRows[i].active) inactiveRows.push(allRows[i]);
  }
  // Selection sort by accuracyPct ascending — keeps stable ordering
  // across ArkTS environments.
  for (let i = 0; i < inactiveRows.length; i++) {
    let minIdx: number = i;
    for (let j = i + 1; j < inactiveRows.length; j++) {
      if (inactiveRows[j].accuracyPct < inactiveRows[minIdx].accuracyPct) {
        minIdx = j;
      }
    }
    if (minIdx !== i) {
      const tmp: PackReport = inactiveRows[i];
      inactiveRows[i] = inactiveRows[minIdx];
      inactiveRows[minIdx] = tmp;
    }
  }
  for (let i = 0; i < orderedActive.length; i++) {
    report.packs.push(orderedActive[i]);
  }
  for (let i = 0; i < inactiveRows.length; i++) {
    report.packs.push(inactiveRows[i]);
  }
  return report;
}
```

- [ ] **Step 2: Run unit tests — all should pass**

Run: `hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -40`
Expected: All 12 cases under `LearningReportBuilder.build` pass.

If any test fails:
- `wordSharedBetweenActivePacksCountsTowardBoth` failing → check the per-pack row loop iterates `pack.words` (not deduped).
- `topLevelTotalsDedupeSharedWordsAcrossPacks` failing → check the top-level loop iterates `stats` (not packs).
- `inactivePacksSortByAccuracyAscending` failing → check the selection sort runs over `inactiveRows`, not `allRows`.

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/services/LearningReportBuilder.ets
git commit -m "$(cat <<'EOF'
feat(learning-report): aggregate per-pack with shared-word counting

Top-level totals iterate stats once (deduped by wordId).
Per-pack rows iterate each pack.words[] independently so a word
in N active packs counts toward N rows. Inactive-but-seen packs
appear after active ones, sorted by accuracy ascending.

Refs: docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md
EOF
)"
```

---

## Task 4: Update UI test for the new section id + add builtin-row smoke

**Files:**
- Modify: `entry/src/ohosTest/ets/test/LearningReportFlow.ui.test.ets`

- [ ] **Step 1: Swap `LearningReportCategorySection` for `LearningReportPackSection` in `reportButtonOpensLearningReportPage`**

In the file, replace (around line 94):

```typescript
      const catSection: Component | null =
        await driver.findComponent(ON.id('LearningReportCategorySection'));
      expect(reviewBar !== null).assertTrue();
      expect(catSection !== null).assertTrue();
```

with:

```typescript
      const packSection: Component | null =
        await driver.findComponent(ON.id('LearningReportPackSection'));
      expect(reviewBar !== null).assertTrue();
      expect(packSection !== null).assertTrue();
```

- [ ] **Step 2: Update file-level docstring**

Replace the V0.4.5 docstring (lines ~68-78) to reflect the V0.6.7.8 surface:

```typescript
/**
 * Learning Report acceptance:
 *  - HomePage 📋 → TodayPlanPage; TodayPlanPage 📊 → LearningReportPage.
 *  - LearningReportPage surfaces title, accuracy big-number,
 *    mastered counter, review progress bar, and the pack-breakdown
 *    section (V0.6.7.8 — replaces the V0.4.5 category section).
 *  - Back navigation returns to TodayPlanPage; tapping back again
 *    returns to HomePage.
 *  - On a fresh install (no recorder data), the page renders the
 *    zero-state values without crashing — the "0%" / "0" texts
 *    plus the empty-state hint are visible.
 */
```

- [ ] **Step 3: Add new case `reportRendersAllBuiltinPackRows`**

Insert this `it` block right before the closing `});` of the `describe` block (right after `emitsAllStateCountersInZeroState`, around line 137):

```typescript
    it('reportRendersAllBuiltinPackRows', 0, async (done: Function) => {
      // V0.6.7.8 smoke: the breakdown table renders one row per
      // builtin pack (5 active by default on fresh install). Row
      // ids follow the `pack-${pack.id}` convention from
      // LearningReportPage.packBreakdown.
      const driver: Driver = await launchApp();
      await returnToHome(driver);
      await openReport(driver);
      // Scroll until the pack section is visible — it sits at the
      // bottom of the report, below review.
      await scrollDownOnce(driver);
      const builtinIds: string[] = [
        'pack-fruit-forest',
        'pack-school-castle',
        'pack-home-cottage',
        'pack-animal-safari',
        'pack-ocean-realm',
      ];
      for (let i: number = 0; i < builtinIds.length; i++) {
        const row: Component | null =
          await driver.findComponent(ON.id(builtinIds[i]));
        if (row === null) {
          // Some viewports may need an extra scroll to reach the
          // bottom rows. Scroll once more and retry.
          await scrollDownOnce(driver);
          const retry: Component | null =
            await driver.findComponent(ON.id(builtinIds[i]));
          expect(retry !== null).assertTrue();
        } else {
          expect(true).assertTrue();
        }
      }
      done();
    });
```

Per Task 1 step 6, each `packRow(p)` already has `.id(\`pack-${p.packId}\`)`, so `findComponent(ON.id('pack-fruit-forest'))` works as expected here.

- [ ] **Step 4: Build with the new test in place**

Run: `hvigorw clean assembleHap --no-daemon 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Run the UI test suite**

Run: `scripts/run_ui_tests.sh --suite LearningReportFlow 2>&1 | tail -30`
Expected: 4 cases pass (3 existing + 1 new).

If `reportRendersAllBuiltinPackRows` fails finding e.g. `pack-ocean-realm`, the row is below the second scroll. Tweak the swipe coordinates or add a 3rd `scrollDownOnce(driver)` before retrying.

- [ ] **Step 6: Commit**

```bash
git add entry/src/ohosTest/ets/test/LearningReportFlow.ui.test.ets
git commit -m "$(cat <<'EOF'
test(learning-report): swap CategorySection for PackSection + add builtin row smoke

Update LearningReportFlow ohosTest to look up the new
LearningReportPackSection id. Add reportRendersAllBuiltinPackRows
case verifying all 5 builtin packs render after a fresh install
(uses pack-${packId} ids added on packRow in Task 1).

Refs: docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md
EOF
)"
```

---

## Task 5: Bump version + update docs

**Files:**
- Modify: `AppScope/app.json5`
- Modify: `docs/WordMagicGame_overall_spec.md`
- Modify: `docs/WordMagicGame_roadmap.md`

- [ ] **Step 1: Bump version**

In `AppScope/app.json5`, change:

```json
    "versionCode": 1006015,
    "versionName": "0.6.7.7",
```

to:

```json
    "versionCode": 1006016,
    "versionName": "0.6.7.8",
```

- [ ] **Step 2: Update `docs/WordMagicGame_overall_spec.md` banner**

Replace the banner header:

```
> 文档状态：当前版本基线（V0.6.7.7 — ConfigPage 倒计时自定义 + 我的词包行精简）
> 适用版本：V0.1 原型 → V0.6.7.7
```

with:

```
> 文档状态：当前版本基线（V0.6.7.8 — 学习报告按词包统计）
> 适用版本：V0.1 原型 → V0.6.7.8
```

- [ ] **Step 3: Add V0.6.7.8 row to §1 version table in `docs/WordMagicGame_overall_spec.md`**

Find the line starting with `| V0.6.7.7（当前） |` and insert this new row immediately ABOVE it, then change `V0.6.7.7（当前）` → `V0.6.7.7`:

```
| V0.6.7.8（当前） | 学习报告按词包统计 | **目的**：把 LearningReportPage 从 V0.4.5 时代的「按 category 维度（水果/地点/家庭/动物/海洋）聚合」迁到「按 pack 维度聚合」，与 V0.6.5+ 三层词包模型对齐 —— V0.6.6 已下线 ConfigPage 的 category chip 行，HomePage chip / PackManagerPage / BattlePage today-mode 全部以 pack 为单位，category 维度对家长 / 孩子已经不可见。**改动**：① `services/LearningReportBuilder.ets` 把 `CategoryReport` 替换为 `PackReport`（`packId` / `name` 英文 / `totalSeen` / `totalCorrect` / `accuracyPct` / `active` 6 个字段），删除 `describeCategory()`、`pickWeakCategories()` 与 `LearningReport.weakCategories` / `LearningReport.categories` 字段；`build()` 签名从 `(repo, recorder, nowMs)` 改为 `(library, activeIds, recorder, nowMs)`。Top-level totals 用 stats list 单次遍历（`recorder.statsForTest()` 已经按 wordId 唯一），dedupe 是天然的；per-pack rows 用 `pack.words[]` 独立遍历，**词包共享词的情况下每个 pack row 都计数**（per-pack independent counting），但 top-level 不会重复统计 —— 与「这个词包学过」的 mental model 一致。② `pages/LearningReportPage.ets` 删除「需要加强的分类」整张卡（`weakCard()` + `weakRow()`）+ 删除 `weakCategories` state，把 `categoryBreakdown()` 改名为 `packBreakdown()`，`categoryRow()` 改为 `packRow()` 并加 `.id('pack-${p.packId}')`；section id `LearningReportCategorySection → LearningReportPackSection`。`aboutToAppear` 增加 `loadHomeIntegration(ctx)` 调用（与 HomePage / PackManagerPage 同源），把 `library` + `selection.getActiveIds()` 喂给 builder。③ Row inclusion rule：active packs ∪ inactive-but-seen packs（`row.totalSeen > 0`）。Sort：active first (selection order)，inactive 按 accuracyPct 升序排在后面，无视觉 badge。**测试**：`entry/src/test/LearningReportBuilder.test.ets` 重写 12 个用例（旧 9 个 builder 用例 + 3 个 describeCategory 用例换成新 fixture 的 12 个），新增 4 个特性用例（`inactivePackWithSeenWordsStillAppears` / `inactivePackWithNoStatsIsExcluded` / `wordSharedBetweenActivePacksCountsTowardBoth` / `topLevelTotalsDedupeSharedWordsAcrossPacks`）以及排序用例（`activePacksSortBeforeInactiveOnes` / `inactivePacksSortByAccuracyAscending`）。`entry/src/ohosTest/ets/test/LearningReportFlow.ui.test.ets` 把 `LearningReportCategorySection` 引用换成 `LearningReportPackSection`，新增 `reportRendersAllBuiltinPackRows` 烟测断言 5 个 builtin pack 行（`pack-fruit-forest / pack-school-castle / pack-home-cottage / pack-animal-safari / pack-ocean-realm`）都渲染。**未做（YAGNI）**：报告行没有 source tag（builtin / official / family），家长在 PackManagerPage 已能看到；没有 active/inactive 切换；没有给 `WordStat` schema 加 `packId` 字段，跨包归因仍是 best-effort（共享词的实际 battle 归属信息没有持久化）。设计 spec：[`docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md`](superpowers/specs/2026-05-10-learning-report-by-pack-design.md)。 |
```

- [ ] **Step 4: Update §15.2 ohosTest index in `docs/WordMagicGame_overall_spec.md`**

Find the line starting with `- 学习报告：` and replace it with:

```
- 学习报告：`LearningReportFlow.ui.test.ets`。**V0.6.7.8 改造**：原 `分类详情` 卡片下线，改为 `词包详情`（`LearningReportPackSection`）；`reportButtonOpensLearningReportPage` 用例从断言 `LearningReportCategorySection` 改成断言 `LearningReportPackSection`；新增 `reportRendersAllBuiltinPackRows` 用例烟测 5 个 builtin pack 行（`pack-fruit-forest / pack-school-castle / pack-home-cottage / pack-animal-safari / pack-ocean-realm`）都渲染。`需要加强的分类` 卡 + `LearningReportWeakSection` id 一并下线。
```

- [ ] **Step 5: Update `docs/WordMagicGame_roadmap.md` 「最近更新」段**

In the line starting with `> 最近更新：`, replace the current `2026-05-10（新增 V0.6.7.7 ...` prefix with:

```
> 最近更新：2026-05-10（新增 V0.6.7.8 学习报告按词包统计：把 V0.4.5 时代的「按 category（水果 / 地点 / 家庭 / 动物 / 海洋）聚合」的 LearningReportPage 改成「按 pack 聚合」，与 V0.6.5+ 三层词包模型 + V0.6.6 已下线 category chip 的 ConfigPage 对齐。`services/LearningReportBuilder.ets` 把 `CategoryReport` 替换为 `PackReport`（packId / name / totalSeen / totalCorrect / accuracyPct / active），删除 `describeCategory()` / `pickWeakCategories()` / `LearningReport.weakCategories|categories`；`build()` 签名从 `(repo, recorder, nowMs)` 改成 `(library, activeIds, recorder, nowMs)`。Top-level totals 用 stats list 单遍（已按 wordId 唯一）天然 dedupe；per-pack rows 用 `pack.words[]` 独立遍历 — 共享词每个 pack row 都计数，top-level 不重复。`pages/LearningReportPage.ets` 删除「需要加强的分类」卡 + `weakCategories` state，`categoryBreakdown()` → `packBreakdown()`，section id `LearningReportCategorySection` → `LearningReportPackSection`，row id 新增 `pack-${p.packId}`。`aboutToAppear` 加 `loadHomeIntegration(ctx)` 拿 library + selection。Row inclusion = active ∪ inactive-with-stats，sort = active-first (selection order) + inactive by accuracyPct asc。**测试**：`entry/src/test/LearningReportBuilder.test.ets` 重写 12 用例覆盖新 logic 包括 4 个新特性用例 + 排序用例；`LearningReportFlow.ui.test.ets` 换 section id + 加 `reportRendersAllBuiltinPackRows` 5-builtin-row 烟测。`AppScope/app.json5` 推到 `0.6.7.8` (versionCode 1006016)。设计 spec：[`docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md`](superpowers/specs/2026-05-10-learning-report-by-pack-design.md)。**未做（YAGNI）**：报告行无 source tag（PackManagerPage 已有）；无 active/inactive 切换；`WordStat` 没加 `packId` schema，跨包归因仍是 membership lookup 而非 per-event。先前更新：2026-05-10（新增 V0.6.7.7 ConfigPage 倒计时自定义 + 我的词包行精简：
```

(The trailing `先前更新：2026-05-10（新增 V0.6.7.7 ...` line is the existing first paragraph — preserve it intact.)

- [ ] **Step 6: Commit docs + version bump**

```bash
git add AppScope/app.json5 docs/WordMagicGame_overall_spec.md docs/WordMagicGame_roadmap.md docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md docs/superpowers/plans/2026-05-10-learning-report-by-pack.md
git commit -m "$(cat <<'EOF'
docs(v0.6.7.8): bump version + record learning-report-by-pack design

Bumps to 0.6.7.8 / 1006016. Spec + plan committed alongside the
overall_spec / roadmap entries so docs/code stay in lockstep.

Refs: docs/superpowers/specs/2026-05-10-learning-report-by-pack-design.md
EOF
)"
```

---

## Task 6: Final verification

**Files:** none (read-only checks).

- [ ] **Step 1: Clean rebuild — main HAP**

Run: `hvigorw clean assembleHap --no-daemon 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 2: Verify zero ArkTS warnings**

Run: `hvigorw assembleHap --no-daemon 2>&1 | grep -i 'arkts:warn' ; echo done`
Expected: only `done` printed.

- [ ] **Step 3: Build ohosTest module**

Run: `hvigorw -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | tail -5`
Expected: `BUILD SUCCESSFUL`.

Then check no warnings:

Run: `hvigorw -p module=entry@ohosTest assembleHap --no-daemon 2>&1 | grep -i 'arkts:warn' ; echo done`
Expected: only `done` printed.

- [ ] **Step 4: Run all unit tests**

Run: `hvigorw -p module=entry@default test --no-daemon 2>&1 | tail -50`
Expected: all suites pass, including the new 12-case `LearningReportBuilder.build` block.

- [ ] **Step 5: Run the LearningReportFlow UI test on the emulator**

Run: `hdc list targets 2>&1`
Expected: at least one `127.0.0.1:5555` (or device serial).

If empty, start the emulator from DevEco Studio first.

Then:

```bash
hdc shell bm clean -d -n com.terryma.wordmagicgame -i 0
scripts/run_ui_tests.sh --suite LearningReportFlow 2>&1 | tail -30
```

Expected: `Pass: 4, Error: 0`.

- [ ] **Step 6: Run the ConfigFlow UI test as a regression guard**

Same V0.6.7.7 test we landed in the prior session; verify nothing about timer chips broke from this version bump.

Run:

```bash
hdc shell bm clean -d -n com.terryma.wordmagicgame -i 0
scripts/run_ui_tests.sh --suite ConfigFlow 2>&1 | tail -10
```

Expected: `Pass: 5, Error: 0`.

- [ ] **Step 7: Final state — git log + status**

Run: `git log --oneline -10 ; git status --short`
Expected: 5 new commits (Tasks 1-5; Task 6 is verification only), `git status` clean.

---

## Self-review checklist

After writing this plan, walk back through the spec and confirm each numbered section maps to a task:

| Spec section | Implementing task |
|---|---|
| §3 User-facing changes (Weak removed, 词包详情 rename, English labels) | Tasks 4 (weakCard delete + packBreakdown rename) + 4 step 6 (English from `Pack.name`) |
| §3 Row inclusion rule (active ∪ inactive-with-stats) | Task 3 step 1 (`if (isActive || row.totalSeen > 0)`) |
| §3 Sort order (active-first, inactive-by-accuracy-asc) | Task 3 step 1 (sort block at end) |
| §4.1 Data model (PackReport + LearningReport.packs) | Task 1 step 1 |
| §4.2 Builder signature change | Task 1 step 1 (stub) + Task 3 step 1 (logic) |
| §4.3 Top-level totals dedup via stats iteration | Task 3 step 1 (top-level loop iterates `stats`, not packs) |
| §4.3 Per-pack independent counting | Task 3 step 1 (per-pack loop iterates `pack.words[]`) |
| §4.4 Page rendering (packBreakdown / packRow) | Task 1 steps 4-6 |
| §5.1 Unit tests (12 cases) | Task 2 step 1 |
| §5.2 UI tests (section id + builtin-row smoke) | Task 4 steps 1-3 |
| §6 Edge cases | Covered by tests in Task 2 (inactive-with-stats, shared-word, fresh-install, library-empty falls into emptyState already in code) |
| §7 Implementation order | Tasks 1-6 follow the order |

**No placeholders found. No type drift between tasks (`PackReport`, `build()` signature, `loadHomeIntegration` usage are consistent across Tasks 1, 3, 4).**

---

## Execution choice

Plan complete and saved to `docs/superpowers/plans/2026-05-10-learning-report-by-pack.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session, batch with checkpoints.

Pick one and we'll proceed.
