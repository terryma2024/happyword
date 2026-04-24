import { BattleStatus } from './BattleState';

/**
 * Frozen summary of a finished battle (spec §6.4, §7.3).
 *
 * ResultPage *consumes* this — it never re-derives stats from BattleState.
 * Keeping everything pre-computed means the page survives the engine
 * being torn down (e.g. when the user taps "再来一局" and a fresh engine
 * is constructed).
 *
 * Fields are plain public properties because SessionResult travels across
 * the router via `router.replaceUrl({ params })`, and ArkTS strict-mode
 * object literals serialise cleanly when every field has a declared type.
 */
export class SessionResult {
  /** Won or Lost — Ready/Playing are never emitted here. */
  status: BattleStatus = BattleStatus.Lost;

  /** 0..monstersTotal. Feeds the "击败怪物：N / M" line. */
  defeatedMonsters: number = 0;
  /** Total wave size. Carried along so the view doesn't need the engine. */
  monstersTotal: number = 0;

  /** Total answers submitted (correct + wrong). */
  totalAnswers: number = 0;
  /** Correct subset. */
  correctAnswers: number = 0;
  /**
   * correctAnswers / totalAnswers, clamped to 0 when no answers were
   * submitted (time-expired sessions can end with 0 taps). Stored as a
   * 0..1 float; the view formats the percent.
   */
  correctRate: number = 0;

  /** Unique word count the player was exposed to during the session. */
  learnedWordCount: number = 0;

  /** 0..3 per the spec §4.4 star table. */
  stars: number = 0;

  /**
   * V0.2 additions (spec §15 / learning record). Both come from
   * LearningRecorder at the moment the battle ends.
   * - newlyLearnedCount: words that crossed 0→1 correctness in THIS
   *   session. Mirrors `LearningRecorder.newlyLearnedCount`.
   * - totalLearnedCount: distinct words ever answered correctly at
   *   least once, across all prior sessions. Mirrors
   *   `LearningRecorder.totalLearnedCount` captured post-record.
   */
  newlyLearnedCount: number = 0;
  totalLearnedCount: number = 0;
}
