import { Question } from './Question';

/**
 * BattleStatus captures the four lifecycle states a battle session can be in
 * (spec §4.1, §8.3). UI code branches on this to decide whether to render
 * the playing screen, disable inputs, or navigate to ResultPage.
 *
 *   Ready   — engine constructed but `start()` not yet called.
 *   Playing — at least one monster alive and player HP > 0.
 *   Won     — every monster in the wave has been defeated.
 *   Lost    — player HP reached 0 before all monsters fell.
 */
export enum BattleStatus {
  Ready = 'ready',
  Playing = 'playing',
  Won = 'won',
  Lost = 'lost',
}

/**
 * Snapshot of a battle in progress (spec §8.3).
 *
 * V0.1 uses a page-held state object rather than a global store
 * (spec §10.2). Fields are plain public properties so ArkUI @State wrappers
 * and unit tests can read them without ceremony. BattleEngine owns the
 * mutations; callers should treat the returned state as read-only and
 * reflect it into @State fields.
 *
 * `currentQuestion` is `undefined` before `BattleEngine.start()` has
 * spawned the first question and after the final win/loss transition.
 * Consumers must null-check before rendering.
 */
export class BattleState {
  playerHp: number = 0;
  playerMaxHp: number = 0;
  monsterHp: number = 0;
  monsterMaxHp: number = 0;
  monsterIndex: number = 1;
  monstersTotal: number = 0;
  comboCount: number = 0;
  remainingSeconds: number = 300;
  totalAnswers: number = 0;
  correctAnswers: number = 0;
  defeatedMonsters: number = 0;
  /**
   * Unique wordIds the player has been shown this session. Conceptually
   * a Set — kept as an array because ArkTS strict mode dislikes generic
   * Set literals crossing module boundaries, and the V0.1 session only
   * ever sees a few dozen words so O(n) dedupe is fine. Consumers must
   * treat it as an unordered collection. Feeds ResultPage's "学习单词"
   * line per spec §6.4.
   */
  learnedWordIds: string[] = [];
  currentQuestion?: Question;
  status: BattleStatus = BattleStatus.Ready;
}
