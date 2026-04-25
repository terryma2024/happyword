import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { CharacterCard, CharacterKind } from '../components/CharacterCard';
import { ChoiceButton, ChoiceState } from '../components/ChoiceButton';
import { WordRepository } from '../services/WordRepository';
import { QuestionGenerator } from '../services/QuestionGenerator';
import {
  BattleEngine,
  BattleConfig,
  AnswerOutcome,
  TickOutcome,
  DEFAULT_PLAYER_HP,
  DEFAULT_MONSTER_HP,
  DEFAULT_MONSTERS_TOTAL,
  DEFAULT_STARTING_SECONDS,
} from '../services/BattleEngine';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  GAME_MODE_NORMAL,
  GAME_MODE_REVIEW,
  cloneGameConfig,
  computeFinalPool
} from '../models/GameConfig';
import { WordEntry } from '../models/WordEntry';
import { BattleState, BattleStatus } from '../models/BattleState';
import { SessionResult } from '../models/SessionResult';
import { Question } from '../models/Question';
import { AudioService, ALL_SOUND_KEYS, SoundKeys } from '../services/AudioService';
import { PronunciationService, shouldAutoSpeak } from '../services/PronunciationService';
import { CritOverlay } from '../components/CritOverlay';
import { MagicProjectile } from '../components/MagicProjectile';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';

/**
 * BattlePage is the core gameplay screen.
 *
 * T6 scope (spec §4, §6.3, §9.1):
 * - Build a BattleEngine from the bundled word list in `aboutToAppear`.
 * - Mirror engine state into @State fields so the UI redraws after every
 *   answer: player HP, monster HP, monster index, combo counter, prompt,
 *   options, per-button feedback state.
 * - Clicking an option submits to the engine, highlights the tapped button
 *   as Correct / Wrong for a brief reveal window, then either loads the
 *   next question or navigates to ResultPage on win/lose.
 *
 * Timing model:
 * - During the reveal window (FEEDBACK_MS) all three option buttons are
 *   set to Disabled so kids can't double-tap into the next question and
 *   miss the feedback.
 *
 * T8 additions:
 * - Countdown timer: setInterval ticks the engine once per second and
 *   mirrors `remainingSeconds` into the header. When the engine reports
 *   `battleEnded` (time up) we route to ResultPage just like on a
 *   win/lose from submitAnswer.
 * - SessionResult is built on the engine the moment a battle ends and
 *   handed to ResultPage via router params so the page renders stats
 *   without needing the engine to outlive the navigation.
 *
 * The dev-only `[debug] end battle` link is kept as a smoke-test escape
 * hatch; it now also builds a best-effort SessionResult so the result
 * screen still displays plausible numbers.
 */

// V0.1 FEEDBACK_MS = 650 kept for V0.2. CritOverlay's ~700 ms
// timeline is owned by animateTo callbacks that fire regardless of
// whether the next question has loaded, so the full spectacle plays
// out even if FEEDBACK_MS elapses in the middle of it. Existing UI
// tests wait 800 ms after each tap, so leaving FEEDBACK_MS at 650
// keeps them green.
const FEEDBACK_MS: number = 650;
const TICK_MS: number = 1000;
/**
 * Review-mode battle overrides. Kept as top-level constants so unit
 * tests can import the same values and assert the review pool
 * behaviour without poking at private fields. Matches spec §15 Track
 * D: 3 monsters, 120 seconds.
 */
export const REVIEW_MODE_MONSTERS_TOTAL: number = 3;
export const REVIEW_MODE_STARTING_SECONDS: number = 120;
export const REVIEW_WINDOW_SIZE: number = 12;

@Entry
@Component
struct BattlePage {
  // Character metadata: cosmetic only, not driven by the engine.
  private readonly playerName: string = 'Magician';
  private readonly monsterName: string = 'Word Slime';

  // Engine and its inputs are not part of render state — plain fields that
  // survive across frames. They are populated asynchronously during
  // `aboutToAppear` so the first render shows the "Loading…" placeholder.
  private engine?: BattleEngine;
  private audio: AudioService = new AudioService();
  private tts: PronunciationService = new PronunciationService();
  private recorder: LearningRecorder = getLearningRecorder();
  private autoSpeak: boolean = true;
  /**
   * True when this battle was launched from HomePage's review button.
   * Drives the 3-monster / 120-s overrides and the mode reset after
   * the battle ends.
   */
  private isReviewMode: boolean = false;
  private feedbackTimer: number = -1;
  /**
   * Handle returned by setInterval for the 1Hz countdown driver. -1 when
   * no tick loop is running (before engine is ready, or after the battle
   * ended). Kept as a separate field from feedbackTimer so clearing one
   * never accidentally stops the other.
   */
  private tickTimer: number = -1;
  /**
   * Outstanding setTimeout handles for the delayed impact effects (hurt
   * pulses, shockwave, etc.) that fire after a magic projectile reaches
   * its target. Cleared on teardown so they cannot mutate @State on a
   * page that is no longer in the navigation stack.
   */
  private impactTimers: number[] = [];
  /**
   * Guard against re-entering onBattleEnded. Two paths can race to it —
   * a submitted answer and a timer tick firing at almost the same instant
   * — and we only want ONE router.replaceUrl per session.
   */
  private battleEndHandled: boolean = false;

  // Render-driving state, synchronised from engine.getState() after every
  // submitted answer.
  @State playerHp: number = DEFAULT_PLAYER_HP;
  @State playerMaxHp: number = DEFAULT_PLAYER_HP;
  @State monsterHp: number = DEFAULT_MONSTER_HP;
  @State monsterMaxHp: number = DEFAULT_MONSTER_HP;
  @State monsterIndex: number = 1;
  @State monsterTotal: number = DEFAULT_MONSTERS_TOTAL;
  @State comboCount: number = 0;
  @State remainingSeconds: number = DEFAULT_STARTING_SECONDS;

  /**
   * Monotonically-increasing pulse counters, passed through to
   * CharacterCard @Prop @Watch hooks. See CharacterCard for the
   * animation recipe tied to each counter.
   *   - playerHurtPulse: ++ on every wrong answer.
   *   - monsterHurtPulse: ++ on every correct non-crit answer.
   *   - playerNudgePulse: ++ on every correct non-crit answer.
   *   - monsterZoomPulse / playerCastPulse: ++ on every crit trigger.
   */
  @State playerHurtPulse: number = 0;
  @State monsterHurtPulse: number = 0;
  @State playerNudgePulse: number = 0;
  @State monsterZoomPulse: number = 0;
  @State playerCastPulse: number = 0;
  /**
   * Drives CritOverlay (full-bleed gold flash + expanding shockwave +
   * big floating damage number). ++ on every crit trigger; `critDamage`
   * mirrors outcome.damage so the overlay label renders the actual
   * multiplier.
   */
  @State critPulse: number = 0;
  @State critDamage: number = 2;

  /**
   * Drives MagicProjectile overlays. Forward fires from mage to monster
   * on every correct answer (and combo burst); backward fires from
   * monster to mage on wrong answers. `projectileIntensity` is read at
   * pulse time by MagicProjectile to scale the orb up and recolour it
   * gold for combo bursts.
   */
  @State projectileForwardPulse: number = 0;
  @State projectileBackwardPulse: number = 0;
  @State projectileIntensity: number = 1;

  // Question text shown while loading the dictionary. Real prompts overwrite
  // this once the engine produces its first question.
  @State prompt: string = 'Loading…';
  @State feedbackText: string = ' ';
  @State feedbackColor: string = '#2ECC71';

  // Options and their per-button states. Kept in parallel arrays so the
  // three ChoiceButtons below can each pick their props with a single
  // index. The IDs are stable (not regenerated on question change) because
  // UI tests target BattleOptionA/B/C by id and only care about text for
  // behavioural assertions.
  @State options: string[] = ['', '', ''];
  @State optionStates: ChoiceState[] = [
    ChoiceState.Disabled,
    ChoiceState.Disabled,
    ChoiceState.Disabled,
  ];
  private readonly optionIds: string[] = ['BattleOptionA', 'BattleOptionB', 'BattleOptionC'];

  aboutToAppear(): void {
    // Construct the engine off the UI thread: loading `words_v1.json` is
    // async, so we render the loading placeholder until the promise
    // resolves. On success we snapshot the engine's state into our @State
    // fields, which triggers the first real render of the battle UI.
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // Preload SFX in parallel with word-list loading. AudioService never
    // throws — asset failures are silently muted — so we don't chain.
    this.audio.preload(ctx, ALL_SOUND_KEYS).catch((err: BusinessError): void => {
      console.error(`BattlePage: AudioService.preload failed: ${JSON.stringify(err)}`);
    });
    // Kick the TTS engine off in parallel — init resolves ~100-500 ms
    // later on a healthy device, and speak() safely no-ops until then.
    this.tts.init().catch((err: BusinessError): void => {
      console.error(`BattlePage: PronunciationService.init failed: ${JSON.stringify(err)}`);
    });
    // Hydrate the learning recorder (idempotent — EntryAbility kicks
    // it off at app boot, this is a belt-and-braces guarantee in case
    // the user launches directly into BattlePage via a future deep
    // link). The `beginSession` resets per-session counters so the
    // ResultPage footer reflects THIS battle only.
    this.recorder.init(ctx).then((): void => {
      this.recorder.beginSession();
    }).catch((err: BusinessError): void => {
      console.error(`BattlePage: LearningRecorder.init failed: ${JSON.stringify(err)}`);
    });
    const repo: WordRepository = new WordRepository();
    repo.loadFromRawfile(ctx).then((): void => {
      const storedCfg: GameConfig | undefined =
        AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
      const cfg: GameConfig = cloneGameConfig(storedCfg !== undefined ? storedCfg : new GameConfig());
      this.autoSpeak = cfg.autoSpeak;
      this.isReviewMode = cfg.mode === GAME_MODE_REVIEW;

      // Universe pool: every word the player could be shown, honouring
      // their category filters. For review mode we then *narrow* this
      // to the set of wordIds they've recently answered wrong.
      const universe: WordEntry[] =
        computeFinalPool(repo.all(), cfg.enabledCategories, cfg.customWordsRaw);
      const finalEntries: WordEntry[] =
        this.isReviewMode ? this.buildReviewPool(universe) : universe;

      const finalRepo: WordRepository = new WordRepository();
      finalRepo.setEntries(finalEntries);

      const gen: QuestionGenerator = new QuestionGenerator(finalRepo);

      const bc: BattleConfig = new BattleConfig();
      bc.playerMaxHp = cfg.playerMaxHp;
      bc.monsterMaxHp = cfg.monsterMaxHp;
      // Review mode overrides (spec §15 Track D): a short, focused
      // challenge — 3 monsters / 120 s — so the learner sees every
      // word they just missed without a full 5-monster session.
      if (this.isReviewMode) {
        bc.monstersTotal = REVIEW_MODE_MONSTERS_TOTAL;
        bc.startingSeconds = REVIEW_MODE_STARTING_SECONDS;
      } else {
        bc.monstersTotal = cfg.monstersTotal;
        bc.startingSeconds = cfg.startingSeconds;
      }

      const engine: BattleEngine = new BattleEngine(gen, bc);
      engine.start();
      this.engine = engine;
      this.syncFromEngine();
      // Auto-speak the first question's English answer. Subsequent
      // auto-speaks happen inside the onOptionTap closure when the
      // next question is loaded.
      this.maybeAutoSpeakCurrent(false);
      // Enable the option buttons once the engine is ready. syncFromEngine
      // has already seeded prompt/options/lastAnswerWord from the first
      // question generated by engine.start().
      this.optionStates = [ChoiceState.Idle, ChoiceState.Idle, ChoiceState.Idle];
      // Start the countdown loop once the engine is ready. Using
      // setInterval rather than a self-rescheduling setTimeout keeps the
      // cadence consistent even if one tick's work stretches slightly.
      this.tickTimer = setInterval((): void => {
        this.onTick();
      }, TICK_MS);
    }).catch((err: BusinessError): void => {
      console.error(`BattlePage: failed to load word repository: ${JSON.stringify(err)}`);
      this.prompt = 'Failed to load words';
    });
  }

  aboutToDisappear(): void {
    // Make sure pending timers are cleared so they cannot fire after the
    // page is torn down (e.g. after navigating away via the [debug]
    // end-battle link or after the battle ends). Leaking setInterval
    // in particular would keep draining remainingSeconds in the
    // background and corrupt a subsequent replay.
    if (this.feedbackTimer >= 0) {
      clearTimeout(this.feedbackTimer);
      this.feedbackTimer = -1;
    }
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    for (let i = 0; i < this.impactTimers.length; i++) {
      clearTimeout(this.impactTimers[i]);
    }
    this.impactTimers = [];
    // Best-effort audio teardown. AudioService.dispose() swallows
    // per-player errors so we never need to await it.
    this.audio.dispose().catch((err: BusinessError): void => {
      console.error(`BattlePage: AudioService.dispose failed: ${JSON.stringify(err)}`);
    });
    this.tts.dispose();
  }

  /**
   * Build the review-mode word pool by intersecting
   * LearningRecorder.recentWrongIds with the active word universe.
   * Falls back to the universe itself when fewer than
   * MIN_POOL_SIZE matches are found — that can happen if the user
   * changed category filters after the wrong answers were recorded.
   *
   * Exposed as a private method (not a free function) so it can
   * remain untestable-at-the-function-level while still reading the
   * single getLearningRecorder() singleton that other tests may
   * swap out via __resetLearningRecorderForTest.
   */
  private buildReviewPool(universe: WordEntry[]): WordEntry[] {
    const wrongIds: string[] = this.recorder.recentWrongIds(REVIEW_WINDOW_SIZE);
    if (wrongIds.length === 0) {
      return universe;
    }
    const lookup: Map<string, WordEntry> = new Map<string, WordEntry>();
    for (let i = 0; i < universe.length; i++) {
      lookup.set(universe[i].id, universe[i]);
    }
    const pool: WordEntry[] = [];
    for (let i = 0; i < wrongIds.length; i++) {
      const hit: WordEntry | undefined = lookup.get(wrongIds[i]);
      if (hit !== undefined) {
        pool.push(hit);
      }
    }
    // Guard: QuestionGenerator requires at least 3 distinct entries to
    // produce valid 3-option questions. If the review set collapses
    // below that (user changed category filters etc.), degrade to
    // the full universe so the battle can still start.
    if (pool.length < 3) {
      return universe;
    }
    return pool;
  }

  /**
   * Auto-speak helper: bounces through the pure `shouldAutoSpeak`
   * predicate so the decision stays unit-testable. Callers pass
   * `isRevealing` true during the feedback window to suppress TTS
   * while the crit/hurt SFX are already playing.
   */
  private resetModeToNormal(): void {
    const storedCfg: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    if (storedCfg === undefined) {
      return;
    }
    if (storedCfg.mode === GAME_MODE_NORMAL) {
      return;
    }
    const next: GameConfig = cloneGameConfig(storedCfg);
    next.mode = GAME_MODE_NORMAL;
    AppStorage.setOrCreate<GameConfig>(GAME_CONFIG_STORAGE_KEY, next);
  }

  /**
   * Schedule an impact callback to run after the magic projectile
   * roughly reaches its target. The projectile spends ~80 ms spawning
   * and ~260 ms travelling (see MagicProjectile constants), so 320 ms
   * lands the impact a touch before the explode-out frame and reads as
   * the orb striking the character. Tracked in `impactTimers` so a
   * teardown clears any pending callbacks before they touch @State.
   */
  private scheduleImpact(cb: () => void): void {
    const id: number = setTimeout((): void => {
      cb();
    }, 320);
    this.impactTimers.push(id);
  }

  private maybeAutoSpeakCurrent(isRevealing: boolean): void {
    if (!shouldAutoSpeak(this.autoSpeak, this.tts.isAvailable, isRevealing)) {
      return;
    }
    if (this.lastAnswerWord.length === 0) {
      return;
    }
    this.tts.speak(this.lastAnswerWord);
  }

  /**
   * Drive the engine's countdown by 1 second. Runs from setInterval so it
   * keeps firing whether or not the user taps anything. On the tick that
   * actually ends the battle, we navigate — the engine guarantees a
   * single `battleEnded = true` outcome so there is no double-routing
   * risk from the timer side; the `battleEndHandled` flag is belt-and-
   * braces against a simultaneous submit.
   */
  private onTick(): void {
    const engine: BattleEngine | undefined = this.engine;
    if (engine === undefined) {
      return;
    }
    const outcome: TickOutcome = engine.tick(1);
    this.remainingSeconds = engine.getState().remainingSeconds;
    if (outcome.battleEnded) {
      if (this.tickTimer >= 0) {
        clearInterval(this.tickTimer);
        this.tickTimer = -1;
      }
      this.navigateToResult(engine.buildSessionResult());
    }
  }

  /** Copy engine state into @State fields so ArkUI re-renders the page. */
  private syncFromEngine(): void {
    const engine: BattleEngine | undefined = this.engine;
    if (engine === undefined) {
      return;
    }
    const state: BattleState = engine.getState();
    this.playerHp = state.playerHp;
    this.playerMaxHp = state.playerMaxHp;
    this.monsterHp = state.monsterHp;
    this.monsterMaxHp = state.monsterMaxHp;
    this.monsterIndex = state.monsterIndex;
    this.monsterTotal = state.monstersTotal;
    this.comboCount = state.comboCount;
    this.remainingSeconds = state.remainingSeconds;

    const q: Question | undefined = state.currentQuestion;
    if (q !== undefined) {
      this.prompt = q.promptZh;
      this.options = [q.options[0], q.options[1], q.options[2]];
      this.lastAnswerWord = q.answer;
      this.currentWordId = q.wordId;
    }
  }

  /**
   * Handle a tap on one of the three option buttons.
   *
   * Guards:
   *   - Ignore taps while the engine is still loading.
   *   - Ignore taps while the feedback window is active (all buttons are
   *     also Disabled during that window; this is a belt-and-braces check).
   *
   * Flow:
   *   1. Submit to the engine and pull the new state.
   *   2. Highlight the tapped button green/red, freeze the other two.
   *   3. After FEEDBACK_MS: either navigate to ResultPage (battle ended) or
   *      load the next question and re-enable the buttons.
   */
  private onOptionTap(text: string): void {
    const engine: BattleEngine | undefined = this.engine;
    if (engine === undefined) {
      return;
    }
    if (this.feedbackTimer >= 0) {
      return;
    }
    const tappedIndex: number = this.options.indexOf(text);
    if (tappedIndex < 0) {
      return;
    }

    // Capture the question state BEFORE submitting — submitAnswer mutates
    // currentQuestion to the next question, but we want to keep showing
    // the just-answered prompt and options during the reveal window.
    const answeredPrompt: string = this.prompt;
    const answeredOptions: string[] = this.options.slice();
    const correctWord: string = this.lastAnswerWord;
    const answeredWordId: string = this.currentWordId;

    const outcome: AnswerOutcome = engine.submitAnswer(text);
    // Record the answer BEFORE syncFromEngine rotates to the next
    // question so the wordId we pass is the one the player just
    // answered. Falls through silently if the recorder wasn't ready.
    if (answeredWordId.length > 0) {
      this.recorder.recordAnswer(answeredWordId, outcome.correct);
    }

    // Update stat displays (HP, combo, monster index) immediately so the
    // damage is visible before the reveal delay elapses.
    this.syncFromEngine();

    // Keep the answered question on screen for the reveal window —
    // syncFromEngine above would have replaced prompt/options with the
    // NEXT question's data.
    this.prompt = answeredPrompt;
    this.options = answeredOptions;

    // Highlight the tapped button; keep the other two disabled so the
    // player can't race through feedback.
    const newStates: ChoiceState[] = [
      ChoiceState.Disabled,
      ChoiceState.Disabled,
      ChoiceState.Disabled,
    ];
    newStates[tappedIndex] = outcome.correct ? ChoiceState.Correct : ChoiceState.Wrong;
    this.optionStates = newStates;

    // Feedback text (spec §4.3, §9.2):
    //   - burst: "连击 3！魔法爆发 ×2" in gold so the bonus reward is
    //     visually distinct from a plain correct answer and matches the
    //     spec's 魔法爆发 wording.
    //   - correct (non-burst): "正确！" in green.
    //   - wrong: "正确答案是 <word>" in red so kids still learn the word.
    if (outcome.comboTriggered) {
      this.feedbackText = `连击 3！魔法爆发 ×${outcome.damage}`;
      this.feedbackColor = '#FFB400';
      this.audio.play(SoundKeys.HIT_CRIT);
      // Crit path: launch a charged forward projectile and the cast
      // glow immediately, then time the impact spectacle (zoom +
      // shockwave + big floating damage number) to fire when the
      // projectile reaches the monster.
      this.projectileIntensity = outcome.damage;
      this.projectileForwardPulse += 1;
      this.playerCastPulse += 1;
      this.scheduleImpact((): void => {
        this.monsterZoomPulse += 1;
        this.critDamage = outcome.damage;
        this.critPulse += 1;
      });
    } else if (outcome.correct) {
      this.feedbackText = '正确！';
      this.feedbackColor = '#2ECC71';
      this.audio.play(SoundKeys.HIT_NORMAL);
      // Forward projectile flies first, monster hurt + shake fire on
      // arrival; player nudge is the recoil from casting and stays at
      // launch time so the lunge precedes the impact.
      this.projectileIntensity = 1;
      this.projectileForwardPulse += 1;
      this.playerNudgePulse += 1;
      this.scheduleImpact((): void => {
        this.monsterHurtPulse += 1;
      });
    } else {
      this.feedbackText = `正确答案是 ${correctWord}`;
      this.feedbackColor = '#E74C3C';
      this.audio.play(SoundKeys.ANSWER_WRONG);
      // Backward projectile: monster fires back at the mage. Player
      // hurt + shake fire on arrival.
      this.projectileIntensity = 1;
      this.projectileBackwardPulse += 1;
      this.scheduleImpact((): void => {
        this.playerHurtPulse += 1;
      });
    }
    // Layer a monster-defeat cue on top of the hit SFX when the final
    // blow landed but the battle is not yet over. The win-side cue is
    // handled in onBattleEnded so it doesn't double up with hit_crit.
    if (outcome.monsterDefeated && !outcome.battleEnded) {
      this.audio.play(SoundKeys.MONSTER_DEFEAT);
    }

    // Snapshot the next question now so the closure below doesn't have to
    // re-check engine state (which may be cleared on battle end).
    const nextQuestion: Question | undefined = engine.getState().currentQuestion;

    this.feedbackTimer = setTimeout((): void => {
      this.feedbackTimer = -1;
      this.feedbackText = ' ';

      if (outcome.battleEnded) {
        this.onBattleEnded(outcome);
        return;
      }

      if (nextQuestion !== undefined) {
        this.prompt = nextQuestion.promptZh;
        this.options = [nextQuestion.options[0], nextQuestion.options[1], nextQuestion.options[2]];
        this.lastAnswerWord = nextQuestion.answer;
        // New question loaded — feedback window is closed so it's
        // safe to auto-speak the answer now.
        this.maybeAutoSpeakCurrent(false);
      }
      this.optionStates = [ChoiceState.Idle, ChoiceState.Idle, ChoiceState.Idle];
    }, FEEDBACK_MS);
  }

  /**
   * The correct English word of the currently-displayed question. Captured
   * during syncFromEngine so that after submitAnswer() advances the engine
   * to the next question, the feedback text can still say "正确答案是 ..."
   * for the question the player just answered.
   */
  private lastAnswerWord: string = '';
  /**
   * WordId of the currently-displayed question. Tracked alongside
   * lastAnswerWord so LearningRecorder gets the stable identifier
   * (survives deck reshuffles) rather than the display string.
   */
  private currentWordId: string = '';

  private onBattleEnded(outcome: AnswerOutcome): void {
    const engine: BattleEngine | undefined = this.engine;
    if (engine === undefined) {
      return;
    }
    // Stop the countdown before we leave — the interval keeps ticking
    // otherwise and would attempt to drive an engine that has already
    // transitioned to Won/Lost.
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    // Play the terminal fanfare just before we navigate. AudioService
    // drops the cue silently if preload failed, and ResultPage doesn't
    // own an AudioService so this is the last chance to emit it.
    if (outcome.endStatus === BattleStatus.Won) {
      this.audio.play(SoundKeys.VICTORY);
    } else {
      this.audio.play(SoundKeys.DEFEAT);
    }
    this.navigateToResult(engine.buildSessionResult());
  }

  /**
   * Smoke-test affordance — ends the battle immediately by advancing the
   * engine's clock past zero, which flips it to Lost, then hands the
   * resulting SessionResult to ResultPage. If the engine hasn't finished
   * loading yet, fall back to an empty result so the navigation still
   * completes and the user can return to Home.
   */
  private onDebugEndBattle(): void {
    const engine: BattleEngine | undefined = this.engine;
    if (engine === undefined) {
      this.navigateToResult(new SessionResult());
      return;
    }
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    if (engine.getState().status === BattleStatus.Playing) {
      engine.tick(engine.getState().remainingSeconds + 1);
    }
    this.navigateToResult(engine.buildSessionResult());
  }

  /**
   * Shared router handoff for both answer-driven and timer-driven battle
   * endings. Serialises SessionResult through the router params bag;
   * ResultPage pulls it out of `router.getParams()`. The guard flag makes
   * concurrent submit/tick paths land on exactly one navigation.
   */
  private navigateToResult(result: SessionResult): void {
    if (this.battleEndHandled) {
      return;
    }
    this.battleEndHandled = true;
    // Enrich the engine-built SessionResult with learning-record
    // totals before ResultPage consumes it. The engine doesn't know
    // about the recorder, so this is the integration point.
    result.newlyLearnedCount = this.recorder.newlyLearnedCount;
    result.totalLearnedCount = this.recorder.totalLearnedCount;
    // Review mode is always a single-battle affordance — reset the
    // stored GameConfig back to 'normal' so the next HomePage launch
    // doesn't accidentally start another review session. Done even
    // when we weren't in review mode so a stale flag from a crashed
    // previous session gets cleaned up on any battle end.
    this.resetModeToNormal();
    // Force a final flush so counters survive a force-stop — disk
    // errors are swallowed inside flushNow() so nothing is leaked.
    this.recorder.flushNow().catch((err: BusinessError): void => {
      console.error(`BattlePage: LearningRecorder.flushNow failed: ${JSON.stringify(err)}`);
    });
    router.replaceUrl({
      url: 'pages/ResultPage',
      params: result,
    }).catch((err: BusinessError): void => {
      console.error(`BattlePage: replaceUrl ResultPage failed: ${JSON.stringify(err)}`);
    });
  }

  private formatTime(totalSeconds: number): string {
    const mins: number = Math.floor(totalSeconds / 60);
    const secs: number = totalSeconds % 60;
    const mm: string = mins < 10 ? `0${mins}` : `${mins}`;
    const ss: string = secs < 10 ? `0${secs}` : `${secs}`;
    return `${mm}:${ss}`;
  }

  @Builder
  private header() {
    Row() {
      Text(`Combo: ${this.comboCount}`)
        .id('BattleComboLabel')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557');
      Blank()
        .layoutWeight(1);
      Text('Battle')
        .id('BattleTitle')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');
      Blank()
        .layoutWeight(1);
      Text(`Time ${this.formatTime(this.remainingSeconds)}`)
        .id('BattleTimerLabel')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557');
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 });
  }

  @Builder
  private questionArea() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Text('Question')
          .fontSize(14)
          .fontColor('#457B9D');
        Text(this.prompt)
          .id('BattlePrompt')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557')
          .margin({ top: 16 });
        // Speaker button — tap re-plays the English pronunciation
        // regardless of the autoSpeak config. Rendered even when
        // TTS init failed so the UI layout is stable; the tap path
        // then silently no-ops via PronunciationService.isAvailable.
        Button('🔊')
          .id('BattleSpeakerButton')
          .type(ButtonType.Circle)
          .width(40)
          .height(40)
          .fontSize(18)
          .fontColor('#457B9D')
          .backgroundColor('#EAF2F8')
          .margin({ top: 12 })
          .onClick((): void => {
            if (this.lastAnswerWord.length > 0) {
              this.tts.speak(this.lastAnswerWord);
            }
          });
        Text(this.feedbackText)
          .id('BattleFeedback')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.feedbackColor)
          .margin({ top: 16 });
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);

      // Dev-only escape hatch: jump straight to ResultPage with whatever
      // stats are current. Builds a SessionResult from the *current*
      // BattleState (treating the mid-session numbers as a synthetic
      // Lost), so ResultPage always has real data to render. Mirrors the
      // production path — it goes through navigateToResult so the
      // tick-timer is cleaned up and the end-handled guard is honoured.
      Text('[debug] end battle')
        .id('BattleFinishButton')
        .fontSize(12)
        .fontColor('#888888')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .onClick((): void => {
          this.onDebugEndBattle();
        });
    }
    .id('QuestionArea')
    .layoutWeight(2)
    .height('100%')
    .padding(12);
  }

  @Builder
  private optionsRow() {
    Row({ space: 4 }) {
      ChoiceButton({
        text: this.options[0],
        choiceId: this.optionIds[0],
        state: this.optionStates[0],
        onTap: (t: string): void => {
          this.onOptionTap(t);
        },
      });
      ChoiceButton({
        text: this.options[1],
        choiceId: this.optionIds[1],
        state: this.optionStates[1],
        onTap: (t: string): void => {
          this.onOptionTap(t);
        },
      });
      ChoiceButton({
        text: this.options[2],
        choiceId: this.optionIds[2],
        state: this.optionStates[2],
        onTap: (t: string): void => {
          this.onOptionTap(t);
        },
      });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 20 });
  }

  build(): void {
    Stack() {
      // Main content — header, character row, options. The Stack wrapper
      // exists so CritOverlay can sit above everything on the Z axis
      // without forcing the option buttons beneath it to reflow.
      Column() {
        this.header();

        Row({ space: 16 }) {
          Column() {
            CharacterCard({
              kind: CharacterKind.Mage,
              name: this.playerName,
              hp: this.playerHp,
              maxHp: this.playerMaxHp,
              sublabel: '',
              hurtPulse: this.playerHurtPulse,
              nudgePulse: this.playerNudgePulse,
              castPulse: this.playerCastPulse,
            });
          }
          .id('PlayerArea')
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center);

          this.questionArea();

          Column() {
            CharacterCard({
              kind: CharacterKind.Slime,
              name: this.monsterName,
              hp: this.monsterHp,
              maxHp: this.monsterMaxHp,
              sublabel: `Monster ${this.monsterIndex} / ${this.monsterTotal}`,
              hurtPulse: this.monsterHurtPulse,
              zoomPulse: this.monsterZoomPulse,
            });
          }
          .id('MonsterArea')
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center);
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 20, right: 20, top: 4, bottom: 4 });

        this.optionsRow();
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F8F9FA');

      // Magic projectile overlays — sit between the battle scene and
      // the crit spectacle. Forward-firing orb travels mage -> monster
      // on correct answers (gold-recoloured & enlarged for combo
      // bursts); backward-firing orb travels monster -> mage on wrong
      // answers. Both ignore hit testing so option taps still land.
      MagicProjectile({
        projectilePulse: this.projectileForwardPulse,
        forward: true,
        intensity: this.projectileIntensity,
      });
      MagicProjectile({
        projectilePulse: this.projectileBackwardPulse,
        forward: false,
        intensity: 1,
      });

      // Crit spectacle layers — gold flash + expanding shockwave + big
      // floating damage number. CritOverlay sets hitTestBehavior =
      // Transparent so it never intercepts taps destined for the
      // ChoiceButtons.
      CritOverlay({ critPulse: this.critPulse, damage: this.critDamage });
    }
    .width('100%')
    .height('100%');
  }
}
