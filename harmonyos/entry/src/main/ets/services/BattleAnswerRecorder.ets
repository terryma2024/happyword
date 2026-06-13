/**
 * BattleAnswerRecorder — the per-answer learning side effects shared by BOTH
 * battle frontends (v1.1.1 bugfix extraction).
 *
 * The native BattlePage used to run these statements inline in onOptionTap /
 * handleSpellSubmit / syncFromEngine; the Cocos battle path ran NONE of them,
 * so Cocos battles recorded no word stats, never marked review words (review
 * battles could never complete their plan), and dropped monster codex
 * encounter/defeat progress. The bodies moved here statement-for-statement —
 * BattlePage delegates, and CocosBattlePage wires {@link applyAnswerOutcome}
 * into CocosBattleBridgeCallbacks.onAnswerOutcome — so the two paths cannot
 * drift again.
 *
 * Persistence: LearningRecorder debounce-flushes itself on every
 * recordAnswer, and MonsterProgressStore saves on every mutation, so no
 * explicit save call is needed here (same as the old inline code).
 */
import { BusinessError } from '@ohos.base';
import { getLearningRecorder, LearningRecorder } from './LearningRecorder';
import {
  DailyLearningStateService,
  getDailyLearningStateService,
} from './DailyLearningStateService';
import { getMonsterProgressStore, MonsterProgressStore } from './MonsterProgressStore';
import { CocosAnswerOutcomeEvent } from './CocosBattleBridge';

export class BattleAnswerRecorder {
  private readonly recorder: LearningRecorder = getLearningRecorder();
  private readonly dailyStateService: DailyLearningStateService = getDailyLearningStateService();
  private readonly monsterProgress: MonsterProgressStore = getMonsterProgressStore();
  /** Mirrors the old BattlePage.isReviewMode flag (set from the session setup). */
  private isReviewMode: boolean = false;
  /** Moved from BattlePage.lastEncounterRecordedCatalogIndex. */
  private lastEncounterRecordedCatalogIndex: number = 0;

  setReviewMode(isReviewMode: boolean): void {
    this.isReviewMode = isReviewMode;
  }

  /**
   * Moved from BattlePage.markDailyReviewWordIfNeeded — review battles tick
   * the answered word off today's review plan.
   */
  markDailyReviewWordIfNeeded(wordId: string): void {
    if (!this.isReviewMode || wordId.length === 0) {
      return;
    }
    this.dailyStateService.markReviewedWords(Date.now(), [wordId])
      .catch((err: BusinessError): void => {
        console.error(`BattleAnswerRecorder: markReviewedWords failed: ${JSON.stringify(err)}`);
      });
  }

  /**
   * Moved from BattlePage.recordEncounterForCurrentMonster (incl. the
   * once-per-catalog-index dedup that lived in the page field).
   */
  recordEncounter(catalogIndex: number): void {
    if (catalogIndex <= 0 || catalogIndex === this.lastEncounterRecordedCatalogIndex) {
      return;
    }
    this.lastEncounterRecordedCatalogIndex = catalogIndex;
    this.monsterProgress.recordEncounter(catalogIndex);
  }

  /** Moved from BattlePage.recordMonsterDefeat. */
  recordMonsterDefeat(catalogIndex: number): void {
    if (catalogIndex <= 0) {
      return;
    }
    this.monsterProgress.recordDefeat(catalogIndex);
  }

  /**
   * Moved from the BattlePage onOptionTap / handleSpellSubmit recording
   * block: word stats + the review-day mark, keyed by the wordId of the
   * question the player just answered. Falls through silently on an empty
   * wordId (recorder not ready), like the old inline guard.
   */
  recordAnswer(answeredWordId: string, correct: boolean): void {
    if (answeredWordId.length === 0) {
      return;
    }
    this.recorder.recordAnswer(answeredWordId, correct);
    this.markDailyReviewWordIfNeeded(answeredWordId);
  }

  /**
   * The full native per-answer body for the Cocos path, in BattlePage order:
   *   1. medium step advances record nothing ("Do not record learning
   *      stats" — onOptionTap's advancedStep early return);
   *   2. encounter for the monster the answer was submitted against
   *      (normally a dedup no-op — it was recorded when the monster
   *      appeared);
   *   3. word stats + review mark;
   *   4. defeat against the PRE-answer catalog index;
   *   5. encounter for the post-answer monster (the freshly spawned one
   *      after a mid-battle defeat — BattlePage did this via syncFromEngine's
   *      recordEncounterForCurrentMonster; on the winning blow the slot does
   *      not advance, so the dedup makes this a no-op, same as the page).
   */
  applyAnswerOutcome(event: CocosAnswerOutcomeEvent): void {
    if (event.outcome.advancedStep) {
      return;
    }
    this.recordEncounter(event.preMonsterCatalogIndex);
    this.recordAnswer(event.answeredWordId, event.outcome.correct);
    if (event.outcome.monsterDefeated) {
      this.recordMonsterDefeat(event.preMonsterCatalogIndex);
    }
    this.recordEncounter(event.postMonsterCatalogIndex);
  }
}
