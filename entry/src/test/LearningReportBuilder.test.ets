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

function makePack(
  id: string,
  name: string,
  source: 'builtin' | 'global' | 'family',
  wordIds: string[],
  category: string,
): Pack {
  const p: Pack = new Pack();
  p.id = id;
  p.name = name;
  p.labelZh = '';
  p.source = source;
  p.version = 1;
  p.publishedAtMs = 0;
  p.scene = new SceneMetadata();
  const words: WordEntry[] = [];
  for (let i: number = 0; i < wordIds.length; i++) {
    words.push(makeWord(wordIds[i], category));
  }
  p.words = words;
  return p;
}

/**
 * Standard 3-pack fixture used by most cases:
 *   - fruit-forest (builtin, 5 words)
 *   - school-castle (builtin, 4 words)
 *   - space-station (global, 3 words)
 *
 * activeIds defaults to the 2 builtins (ACTIVE_BUILTINS); tests
 * that need inactive-but-seen behavior pass space-station's words
 * into the recorder while leaving it out of activeIds.
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
  for (let i: number = 0; i < stats.length; i++) {
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
  for (let i: number = 0; i < report.packs.length; i++) {
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
      // 5 + 4 + 3 = 12 unique wordIds in the library union.
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
      // fruit-forest: (4+2) / (4+4) = 6 / 8 = 75
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
      // The kid played space-station at some point — it has stats —
      // but it's not in activeIds today.
      const stats: WordStat[] = [
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
      // 3 + 2 = 5 seen, 2 + 1 = 3 correct, 60%
      expect(report.packs[2].totalSeen).assertEqual(5);
      expect(report.packs[2].totalCorrect).assertEqual(3);
      expect(report.packs[2].accuracyPct).assertEqual(60);
    });

    it('inactivePackWithNoStatsIsExcluded', 0, () => {
      const lib: PackLibrary = makeLibrary();
      // space-station is inactive AND has zero stats — it must NOT
      // render.
      const rec: LearningRecorder = makeRecorder([]);
      const report: LearningReport =
        new LearningReportBuilder().build(lib, ACTIVE_BUILTINS, rec, NOW);
      expect(report.packs.length).assertEqual(2);
      for (let i: number = 0; i < report.packs.length; i++) {
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
      // Pass active ids in reverse to confirm selection order
      // (not alphabetical) is honored for the active cluster.
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
