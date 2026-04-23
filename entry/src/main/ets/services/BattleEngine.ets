import { Question } from '../models/Question';
import { BattleState, BattleStatus } from '../models/BattleState';
import { SessionResult } from '../models/SessionResult';
import { QuestionGenerator } from './QuestionGenerator';

/**
 * Battle rules (spec §4.1, §4.2, §4.3, §4.4, §8.3) as of T8:
 *
 * - The player starts with {@link DEFAULT_PLAYER_HP} HP and faces
 *   {@link DEFAULT_MONSTERS_TOTAL} monsters, each with
 *   {@link DEFAULT_MONSTER_HP} HP.
 * - A correct answer deals 1 damage to the current monster; a wrong answer
 *   deals 1 damage to the player.
 * - Combo: each correct answer increments `comboCount`. When that
 *   increment pushes the counter to {@link COMBO_BURST_THRESHOLD}
 *   (= 3), the current answer's damage is doubled to
 *   {@link COMBO_BURST_DAMAGE} (= 2), the outcome is marked
 *   {@link AnswerOutcome.comboTriggered}, and `comboCount` is reset to 0
 *   before the next question is picked. Defeating a monster does NOT
 *   reset combo; only a wrong answer or a burst trigger does.
 * - Countdown: `state.remainingSeconds` starts at
 *   {@link DEFAULT_STARTING_SECONDS} (5 minutes). BattlePage drives the
 *   timer via {@link tick} once per second; when the counter reaches 0
 *   the engine transitions to {@link BattleStatus.Lost} regardless of
 *   player HP (spec §2.1 failure condition).
 *
 * Construction split:
 *
 *   new BattleEngine(generator, config?)  // pure, no side-effects
 *   engine.start()                        // must be called before submitAnswer()
 *
 * `start()` exists so BattlePage can construct the engine during
 * `aboutToAppear` and still defer the first question until it is ready to
 * render — useful once the RNG source changes between unit tests (seeded
 * Mulberry32) and production (Math.random).
 */

export const DEFAULT_PLAYER_HP: number = 5;
export const DEFAULT_MONSTER_HP: number = 3;
export const DEFAULT_MONSTERS_TOTAL: number = 5;
export const DEFAULT_STARTING_SECONDS: number = 300;

/** Consecutive corrects required to trigger the magic-burst bonus. */
export const COMBO_BURST_THRESHOLD: number = 3;
/** Monster damage dealt on the answer that triggers the burst. */
export const COMBO_BURST_DAMAGE: number = 2;

/**
 * Optional overrides for BattleEngine. Fields are plain public properties so
 * callers can construct one, fill in a subset, and hand it to the engine —
 * ArkTS strict mode doesn't like partial interface literals.
 */
export class BattleConfig {
  playerMaxHp?: number;
  monsterMaxHp?: number;
  monstersTotal?: number;
  startingSeconds?: number;
}

/**
 * The result of a single submitted answer. BattlePage uses this to drive
 * short-term UI feedback (highlight the tapped button, schedule the next
 * question, navigate to ResultPage on end-of-battle) without having to diff
 * two BattleState snapshots itself.
 *
 * `endStatus` is undefined while the battle continues, and set to
 * `BattleStatus.Won` or `BattleStatus.Lost` on the final answer that ends
 * the session. Callers should check `battleEnded` first.
 */
export class AnswerOutcome {
  correct: boolean = false;
  damage: number = 0;
  /**
   * True when this answer pushed the combo counter to
   * {@link COMBO_BURST_THRESHOLD} and the 2× damage bonus fired. The UI
   * uses this flag to show the "magic burst" feedback for the reveal
   * window — reading it from the outcome (rather than from the post-submit
   * comboCount, which has been reset to 0) makes the feedback
   * unambiguous.
   */
  comboTriggered: boolean = false;
  monsterDefeated: boolean = false;
  newMonsterSpawned: boolean = false;
  battleEnded: boolean = false;
  endStatus?: BattleStatus;
}

/**
 * The result of a single {@link BattleEngine.tick} call.
 *
 * `battleEnded` is true exactly once — on the tick that transitions the
 * engine from Playing to Lost because time ran out. Subsequent ticks on
 * an already-finished engine are no-ops and emit `battleEnded = false`,
 * so BattlePage can safely keep its interval running until the next
 * render cycle clears it.
 */
export class TickOutcome {
  battleEnded: boolean = false;
  endStatus?: BattleStatus;
}

export class BattleEngine {
  private readonly generator: QuestionGenerator;
  private readonly state_: BattleState;

  constructor(generator: QuestionGenerator, config?: BattleConfig) {
    this.generator = generator;
    const state: BattleState = new BattleState();

    const playerMaxHp: number = (config !== undefined && config.playerMaxHp !== undefined)
      ? config.playerMaxHp
      : DEFAULT_PLAYER_HP;
    const monsterMaxHp: number = (config !== undefined && config.monsterMaxHp !== undefined)
      ? config.monsterMaxHp
      : DEFAULT_MONSTER_HP;
    const monstersTotal: number = (config !== undefined && config.monstersTotal !== undefined)
      ? config.monstersTotal
      : DEFAULT_MONSTERS_TOTAL;
    const startingSeconds: number = (config !== undefined && config.startingSeconds !== undefined)
      ? config.startingSeconds
      : DEFAULT_STARTING_SECONDS;

    state.playerMaxHp = playerMaxHp;
    state.playerHp = playerMaxHp;
    state.monsterMaxHp = monsterMaxHp;
    state.monsterHp = monsterMaxHp;
    state.monsterIndex = 1;
    state.monstersTotal = monstersTotal;
    state.remainingSeconds = startingSeconds;
    state.status = BattleStatus.Ready;
    this.state_ = state;
  }

  /**
   * Enter Playing status and spawn the first question. Safe to call once per
   * engine; calling again while already Playing is a no-op so BattlePage's
   * `aboutToAppear` can run defensively. Throws if the engine has already
   * finished (Won/Lost) because that would silently reset the score.
   */
  start(): void {
    if (this.state_.status === BattleStatus.Playing) {
      return;
    }
    if (this.state_.status === BattleStatus.Won || this.state_.status === BattleStatus.Lost) {
      throw new Error('BattleEngine: cannot start() after battle has ended');
    }
    this.state_.status = BattleStatus.Playing;
    const q: Question = this.generator.nextQuestion();
    this.state_.currentQuestion = q;
    this.rememberWord(q.wordId);
  }

  /** Immutable-ish view of the current state. Callers must not mutate. */
  getState(): BattleState {
    return this.state_;
  }

  /**
   * Apply one answer submission and return a description of what happened.
   *
   * Preconditions (each throws on violation so UI bugs surface as real errors
   * instead of silently corrupting the score):
   *   - `status` is Playing.
   *   - `option` is one of `currentQuestion.options`.
   */
  submitAnswer(option: string): AnswerOutcome {
    if (this.state_.status !== BattleStatus.Playing) {
      throw new Error(`BattleEngine.submitAnswer called while status=${this.state_.status}`);
    }
    const q: Question | undefined = this.state_.currentQuestion;
    if (q === undefined) {
      throw new Error('BattleEngine.submitAnswer called with no current question');
    }
    if (q.options.indexOf(option) < 0) {
      throw new Error(`BattleEngine.submitAnswer: option "${option}" is not on the current question`);
    }

    const outcome: AnswerOutcome = new AnswerOutcome();
    const correct: boolean = option === q.answer;
    outcome.correct = correct;
    outcome.damage = 1;

    this.state_.totalAnswers += 1;
    if (correct) {
      this.state_.correctAnswers += 1;
      this.state_.comboCount += 1;
      // Magic burst (spec §4.3): the answer that pushes the combo to
      // COMBO_BURST_THRESHOLD deals double damage and resets the counter
      // immediately. The reset happens before the next question is picked
      // so the visible combo label returns to 0 on the next paint.
      if (this.state_.comboCount >= COMBO_BURST_THRESHOLD) {
        outcome.damage = COMBO_BURST_DAMAGE;
        outcome.comboTriggered = true;
        this.state_.comboCount = 0;
      }
      this.state_.monsterHp -= outcome.damage;

      if (this.state_.monsterHp <= 0) {
        this.state_.monsterHp = 0;
        this.state_.defeatedMonsters += 1;
        outcome.monsterDefeated = true;

        if (this.state_.defeatedMonsters >= this.state_.monstersTotal) {
          // Final monster down — player wins.
          this.state_.status = BattleStatus.Won;
          this.state_.currentQuestion = undefined;
          outcome.battleEnded = true;
          outcome.endStatus = BattleStatus.Won;
          return outcome;
        }

        // Spawn the next monster at full HP and pick a fresh question.
        this.state_.monsterIndex += 1;
        this.state_.monsterHp = this.state_.monsterMaxHp;
        outcome.newMonsterSpawned = true;
      }
    } else {
      this.state_.comboCount = 0;
      this.state_.playerHp -= outcome.damage;
      if (this.state_.playerHp <= 0) {
        this.state_.playerHp = 0;
        this.state_.status = BattleStatus.Lost;
        this.state_.currentQuestion = undefined;
        outcome.battleEnded = true;
        outcome.endStatus = BattleStatus.Lost;
        return outcome;
      }
    }

    // Battle continues — pick the next question, avoiding a same-word repeat
    // for a smoother flow (spec §5.2 last bullet).
    const next: Question = this.generator.nextQuestion(q.wordId);
    this.state_.currentQuestion = next;
    this.rememberWord(next.wordId);
    return outcome;
  }

  /**
   * Advance the countdown by {@code deltaSeconds}. BattlePage calls this
   * once per second via setInterval (spec §10.3 — timer owned by page
   * lifecycle, engine only applies the delta).
   *
   * Semantics:
   *   - If the battle already ended (Won/Lost), tick is a no-op. This
   *     lets callers run a cheap clean-up loop without worrying about
   *     races against navigation.
   *   - While Playing, remainingSeconds decreases. On hitting 0 the
   *     engine transitions to Lost, clears the current question, and
   *     returns `battleEnded = true` (exactly once).
   */
  tick(deltaSeconds: number): TickOutcome {
    const outcome: TickOutcome = new TickOutcome();
    if (this.state_.status !== BattleStatus.Playing) {
      return outcome;
    }
    this.state_.remainingSeconds -= deltaSeconds;
    if (this.state_.remainingSeconds <= 0) {
      this.state_.remainingSeconds = 0;
      this.state_.status = BattleStatus.Lost;
      this.state_.currentQuestion = undefined;
      outcome.battleEnded = true;
      outcome.endStatus = BattleStatus.Lost;
    }
    return outcome;
  }

  /**
   * Produce a frozen {@link SessionResult} describing the finished
   * battle. Only valid once status is Won or Lost — calling it earlier
   * throws because ResultPage would otherwise show stats that can still
   * change. Star rating comes straight from spec §4.4:
   *
   *   3 stars — Won with correctRate ≥ 0.8.
   *   2 stars — Won with correctRate < 0.8,
   *             OR Lost with ≥ 3 monsters defeated.
   *   1 star  — Lost with ≥ 1 monster defeated.
   *   0 stars — Otherwise (no monster defeated).
   *
   * The OR branch on tier 2 interprets the spec's slightly compressed
   * wording: a loss that still cleared three or more monsters is
   * rewarded with 2 stars.
   */
  buildSessionResult(): SessionResult {
    if (this.state_.status !== BattleStatus.Won && this.state_.status !== BattleStatus.Lost) {
      throw new Error(`BattleEngine.buildSessionResult: battle not finished (status=${this.state_.status})`);
    }
    const r: SessionResult = new SessionResult();
    r.status = this.state_.status;
    r.defeatedMonsters = this.state_.defeatedMonsters;
    r.monstersTotal = this.state_.monstersTotal;
    r.totalAnswers = this.state_.totalAnswers;
    r.correctAnswers = this.state_.correctAnswers;
    r.correctRate = this.state_.totalAnswers > 0
      ? this.state_.correctAnswers / this.state_.totalAnswers
      : 0;
    r.learnedWordCount = this.state_.learnedWordIds.length;
    r.stars = this.computeStars();
    return r;
  }

  /** Dedupe guard — learnedWordIds is conceptually a Set. */
  private rememberWord(wordId: string): void {
    const ids: string[] = this.state_.learnedWordIds;
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] === wordId) {
        return;
      }
    }
    ids.push(wordId);
  }

  private computeStars(): number {
    const won: boolean = this.state_.status === BattleStatus.Won;
    const defeated: number = this.state_.defeatedMonsters;
    const rate: number = this.state_.totalAnswers > 0
      ? this.state_.correctAnswers / this.state_.totalAnswers
      : 0;

    if (won && rate >= 0.8) {
      return 3;
    }
    if (won || defeated >= 3) {
      return 2;
    }
    if (defeated >= 1) {
      return 1;
    }
    return 0;
  }
}
