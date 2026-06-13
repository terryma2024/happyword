/**
 * CocosBattleBridge — translates BattleEngine state and outcomes into bridge
 * messages for the embedded Cocos battle scene, and routes user intents from
 * the scene back into the engine (V1.1.0 Task 1.2).
 *
 * Port of ios/WordMagicGame/Features/CoreLoop/CocosBattleBridge.swift,
 * adapted to the ArkTS engine API. Battle logic stays in BattleEngine; this
 * adapter only mirrors what the native BattlePage does around it (audio cue
 * moments, TTS moments, boss-intro bookkeeping, result handoff).
 *
 * Transport seam: the adapter talks to the scene through {@link CocosTransport}
 * so unit tests need no Cocos engine. CocosBattlePage (Task 1.5) glues
 * CocosEngineHost.sendToScene / setSceneMessageHandler to this interface.
 *
 * Timing notes (mirrors native BattlePage):
 *   - FEEDBACK_MS (650 ms) elapses between the submit animation and the next
 *     battle/question — same hold the native page uses before swapping the
 *     answered question out. The scene buffers an early question anyway, but
 *     delaying here keeps auto-speak aligned with the question swap.
 *   - The player-hurt grunt rides a 340 ms delay so the voice cue lands with
 *     the backward projectile impact (BattlePage.schedulePlayerHurtGrunt).
 *   - battle/end goes out immediately; the finish callback fires once after
 *     the same 650 ms hold (Swift finishAfterFeedbackHold), preceded by the
 *     victory/defeat fanfare (BattlePage.onBattleEnded parity).
 */
import { BattleState, BattleStatus } from '../models/BattleState';
import { Question } from '../models/Question';
import { SessionResult } from '../models/SessionResult';
import {
  AnswerOutcome,
  BattleEngine,
  CatalogIndexProvider,
} from './BattleEngine';
import {
  MonsterEntry,
  battleLevelLabelForMonsterLevel,
  getMonsterByIndex,
} from '../data/MonsterCatalog';
import { SoundKeys } from './AudioService';
import { cocosImageKeyForCatalogIndex } from './BattleArtCatalog';
import {
  MonsterArtShape,
  PlayerArtShape,
  QuestionPayloadShape,
  SceneMessage,
  SceneSubmitOptionMessage,
  decodeSceneMessage,
  encodeAnimation,
  encodeBossIntro,
  encodeEnd,
  encodeInit,
  encodeQuestion,
  encodeState,
} from './CocosBridgeMessages';

/** Mirrors BattlePage FEEDBACK_MS / BattleView.clearFeedbackAfterDelay. */
export const COCOS_FEEDBACK_HOLD_MS: number = 650;
/** Mirrors BattlePage.schedulePlayerHurtGrunt (projectile spawn + travel). */
export const COCOS_PLAYER_HURT_GRUNT_MS: number = 340;

/** Player art keys shipped in the Cocos scene (same as the iOS bridge). */
const PLAYER_ART_IDLE: string = 'CharacterMagician';
const PLAYER_ART_FIGHT: string = 'CharacterMagicianFight';
const PLAYER_ART_HURT: string = 'CharacterMagicianBeaten';

/**
 * Scene transport seam. CocosBattlePage adapts CocosEngineHost to this;
 * tests use an in-memory fake.
 */
export interface CocosTransport {
  send(json: string): void;
  setHandler(handler: (json: string) => void): void;
}

/** Injectable delay scheduling so unit tests can run synchronously. */
export type DelayScheduler = (fn: () => void, ms: number) => void;

/**
 * Page-provided callbacks. The hosting page owns BattleAudioMixer and the
 * auto-speak gating (PronunciationService.shouldAutoSpeak) — the adapter
 * only encodes WHEN each cue fires, matching BattlePage:
 *
 *   playSfx(key)            → BattleAudioMixer.play(key) with a SoundKeys value
 *   speakWord(word)         → BattleAudioMixer.speakWord(word) (speaker tap)
 *   autoSpeakWord(word, k)  → gate via shouldAutoSpeak(autoSpeak,
 *                             isVoiceAvailable(), false, k) then speakWord
 *   onFinish(result)        → enrich + route to ResultPage (navigateToResult)
 *   onAnswerOutcome(...)    → BattlePage per-answer side-effect block
 *                             (recordAnswer, review marking, codex progress)
 */
export interface CocosBattleBridgeCallbacks {
  onFinish(result: SessionResult): void;
  playSfx(soundKey: string): void;
  speakWord(word: string): void;
  autoSpeakWord(word: string, questionKind: string): void;
  /**
   * Fired exactly once per accepted answer submit, right after
   * BattleEngine.submitAnswer — mirrors the per-answer block the native
   * BattlePage runs in onOptionTap / handleSpellSubmit and the iOS
   * AppCoordinator.submitBattleOptionForAnimation. Not fired for medium
   * fill-letter step advances (advancedStep, BattlePage parity), for
   * submits dropped by the feedback-hold guard, or after dispose().
   *
   * Scalars are passed instead of a pre-answer BattleState because
   * engine.getState() returns the LIVE state object — by the time the
   * callback runs it has already rotated to the next question.
   *
   * @param answeredWordId        wordId of the question the player answered.
   * @param preAnswerCatalogIndex monster catalog index BEFORE the answer —
   *                              the defeated monster's index when
   *                              outcome.monsterDefeated is true.
   */
  onAnswerOutcome(answeredWordId: string, preAnswerCatalogIndex: number, outcome: AnswerOutcome): void;
  /**
   * Optional: fired on EVERY battle/ready the scene delivers (including the
   * synthetic replay CocosEngineHost emits on page re-entry). The hosting
   * page uses the first invocation to cancel its ready-timeout fallback and
   * start the countdown interval.
   */
  onReady?(): void;
}

/**
 * Visual description of one answer outcome — port of the iOS
 * BattleAnimationEvent translation tables (BattleAnimationEvent.swift).
 */
class BattleAnimationEvent {
  projectileDirection: string = 'forward';
  projectileIntensity: number = 1;
  projectileLabel: string = '';
  playerMotion: string = 'idle';
  monsterMotion: string = 'idle';
  feedbackText: string = '';
  showsCritOverlay: boolean = false;
  damageLabel: string = '';
  playsMonsterDefeatCue: boolean = false;
}

function eventForOutcome(outcome: AnswerOutcome, word: string): BattleAnimationEvent {
  const e: BattleAnimationEvent = new BattleAnimationEvent();
  const intensity: number = Math.max(outcome.damage, 1);
  e.projectileLabel = word;
  e.projectileIntensity = intensity;
  e.damageLabel = `-${intensity}!`;
  e.playsMonsterDefeatCue = outcome.monsterDefeated && !outcome.battleEnded;
  if (outcome.comboTriggered) {
    e.projectileDirection = 'forward';
    e.playerMotion = 'cast';
    e.monsterMotion = 'zoom';
    e.feedbackText = `Combo 3! Magic Burst x${intensity}`;
    e.showsCritOverlay = true;
  } else if (outcome.correct) {
    e.projectileDirection = 'forward';
    e.playerMotion = 'nudge';
    e.monsterMotion = 'hurt';
    e.feedbackText = 'Correct!';
    e.showsCritOverlay = false;
  } else {
    e.projectileDirection = 'backward';
    e.playerMotion = 'hurt';
    e.monsterMotion = 'idle';
    e.feedbackText = `Correct answer: ${word}`;
    e.showsCritOverlay = false;
  }
  return e;
}

/** V0.8.4 — Spell letter-pool wrong tap (player −damage HP, question unchanged). */
function eventForSpellWrongTap(damage: number): BattleAnimationEvent {
  const e: BattleAnimationEvent = new BattleAnimationEvent();
  e.projectileDirection = 'backward';
  e.projectileIntensity = damage;
  e.projectileLabel = '';
  e.playerMotion = 'hurt';
  e.monsterMotion = 'idle';
  e.feedbackText = 'Try again';
  e.showsCritOverlay = false;
  e.damageLabel = `-${damage}`;
  e.playsMonsterDefeatCue = false;
  return e;
}

export class CocosBattleBridge {
  private readonly engine: BattleEngine;
  private readonly transport: CocosTransport;
  private readonly callbacks: CocosBattleBridgeCallbacks;
  private readonly catalogIndexProvider: CatalogIndexProvider;
  private readonly scheduler: DelayScheduler;

  private ready: boolean = false;
  private finishNotified: boolean = false;
  /**
   * Set by dispose() when the hosting page tears down. Once true the bridge
   * is inert: inbound messages are ignored, outbound sends stop, and every
   * already-scheduled closure (question hold, hurt grunt, finish hold)
   * becomes a no-op — so no callback can touch a destroyed page.
   */
  private disposed: boolean = false;
  /**
   * True while the 650 ms post-submit feedback hold is pending. A second
   * battle/submitOption racing the hold (double-tap in the scene) is dropped
   * so the engine receives exactly one submitAnswer per question swap —
   * parity with BattlePage's feedbackTimer guard in onOptionTap.
   */
  private holdActive: boolean = false;
  /** Mirrors Swift shownBossIntroCatalogIndices / lastBossIntroMonsterIndex. */
  private shownBossIntroCatalogIndices: Set<number> = new Set<number>();
  private lastBossIntroMonsterIndex: number = 0;

  constructor(
    engine: BattleEngine,
    transport: CocosTransport,
    callbacks: CocosBattleBridgeCallbacks,
    catalogIndexProvider?: CatalogIndexProvider,
    scheduler?: DelayScheduler,
  ) {
    this.engine = engine;
    this.transport = transport;
    this.callbacks = callbacks;
    this.catalogIndexProvider = catalogIndexProvider !== undefined
      ? catalogIndexProvider
      : (): number => {
        const idx: number = this.engine.getState().monsterIndex;
        return idx <= 0 ? 1 : idx;
      };
    this.scheduler = scheduler !== undefined
      ? scheduler
      : (fn: () => void, ms: number): void => {
        setTimeout(fn, ms);
      };
    this.transport.setHandler((json: string): void => {
      this.handleSceneMessage(json);
    });
  }

  get isReady(): boolean {
    return this.ready;
  }

  /**
   * Tear-down latch — call from the hosting page's aboutToDisappear. After
   * this, the bridge neither sends to the scene nor invokes any callback,
   * even from closures that were already scheduled before disposal.
   */
  dispose(): void {
    this.disposed = true;
  }

  /** Called by the hosting page's countdown timer after engine.tick(1). */
  sendStateTick(): void {
    if (this.disposed) {
      return;
    }
    this.sendState();
  }

  handleSceneMessage(json: string): void {
    if (this.disposed) {
      return;
    }
    const message: SceneMessage | null = decodeSceneMessage(json);
    if (message === null) {
      console.warn('CocosBattleBridge: ignoring unknown bridge message');
      return;
    }
    if (message.kind === 'battle/ready') {
      this.handleReady();
      return;
    }
    if (message.kind === 'battle/submitOption') {
      this.handleSubmit((message as SceneSubmitOptionMessage).option);
      return;
    }
    if (message.kind === 'battle/spellWrongTap') {
      this.handleSpellWrongTap();
      return;
    }
    if (message.kind === 'battle/speakAnswer') {
      this.handleSpeakAnswer();
      return;
    }
    if (message.kind === 'battle/escape') {
      this.handleEscape();
      return;
    }
    // battle/pong — health-check reply, nothing to do.
  }

  // ── Inbound handlers ───────────────────────────────────────────────────────

  /**
   * battle/ready acts as a full scene reset (contract README): re-send
   * init + state + question every time, including the synthetic ready that
   * CocosEngineHost replays on page re-entry.
   */
  private handleReady(): void {
    if (this.engine.getState().status === BattleStatus.Ready) {
      this.engine.start();
    }
    this.ready = true;
    if (this.callbacks.onReady !== undefined) {
      this.callbacks.onReady();
    }
    this.sendInit();
    this.sendState();
    this.sendQuestion();
    this.maybeSendBossIntro();
    this.autoSpeakCurrent();
  }

  /** Mirrors BattlePage.onOptionTap / handleSpellSubmit around the engine. */
  private handleSubmit(option: string): void {
    if (this.holdActive) {
      // Duplicate tap racing the 650 ms feedback hold — drop it (BattlePage
      // parity: option buttons are disabled while feedbackTimer is pending).
      return;
    }
    const state: BattleState = this.engine.getState();
    if (state.status !== BattleStatus.Playing || state.currentQuestion === undefined) {
      return;
    }
    const word: string = state.currentQuestion.answer;
    // Captured BEFORE submit: getState() returns the live state object, so
    // currentQuestion / the catalog index advance as part of submitAnswer.
    const answeredWordId: string = state.currentQuestion.wordId;
    const preAnswerCatalogIndex: number = this.catalogIndexProvider();

    let outcome: AnswerOutcome | undefined = undefined;
    try {
      outcome = this.engine.submitAnswer(option);
    } catch (err) {
      // Stale option from the scene (e.g. a tap racing the question swap) —
      // drop it instead of crashing the page, like the page-level guards do.
      console.warn(`CocosBattleBridge: submit rejected: ${(err as Error).message}`);
      return;
    }
    if (outcome === undefined) {
      return;
    }

    if (outcome.advancedStep) {
      // fill-letter-medium step advance: no damage, no animation — resync the
      // mutated question in place. BattlePage plays the normal hit cue here.
      this.callbacks.playSfx(SoundKeys.HIT_NORMAL);
      this.sendState();
      this.sendQuestion();
      return;
    }

    // Per-answer side effects (learning record, review marking, codex
    // progress) — same position as BattlePage: after the engine accepted
    // the answer, before any UI/scene feedback.
    this.callbacks.onAnswerOutcome(answeredWordId, preAnswerCatalogIndex, outcome);

    const event: BattleAnimationEvent = eventForOutcome(outcome, word);
    this.playSubmitAudio(outcome);
    this.sendAnimation(event, outcome.correct, outcome.comboTriggered, outcome.battleEnded);
    this.sendState();

    if (outcome.battleEnded) {
      this.finishAfterFeedbackHold(outcome.endStatus);
      return;
    }
    // Mirror the native FEEDBACK_MS hold: the answered question (and its
    // feedback) stays on screen 650 ms before the next question swaps in.
    this.holdActive = true;
    this.scheduler((): void => {
      this.holdActive = false;
      if (this.disposed) {
        return;
      }
      this.sendQuestion();
      this.maybeSendBossIntro();
      this.autoSpeakCurrent();
    }, COCOS_FEEDBACK_HOLD_MS);
  }

  /** Mirrors BattlePage.handleSpellWrongLetterTap. */
  private handleSpellWrongTap(): void {
    const damage: number = this.engine.applySpellLetterPenalty();
    if (damage <= 0) {
      return;
    }
    this.callbacks.playSfx(SoundKeys.ANSWER_WRONG);
    this.schedulePlayerHurtGrunt();
    const lost: boolean = this.engine.getState().status === BattleStatus.Lost;
    this.sendAnimation(eventForSpellWrongTap(damage), false, false, lost);
    this.sendState();
    if (lost) {
      this.finishAfterFeedbackHold(BattleStatus.Lost);
    }
  }

  /** Speaker tap in the scene — BattlePage parity: audio.speakWord(lastAnswerWord). */
  private handleSpeakAnswer(): void {
    const q: Question | undefined = this.engine.getState().currentQuestion;
    if (q !== undefined && q.answer.length > 0) {
      this.callbacks.speakWord(q.answer);
    }
  }

  /**
   * Mirrors BattlePage.onEscapeBattle: force the clock past zero (Lost) and
   * hand the built result to the page immediately — no battle/end, no hold.
   */
  private handleEscape(): void {
    const state: BattleState = this.engine.getState();
    if (state.status === BattleStatus.Playing) {
      this.engine.tick(state.remainingSeconds + 1);
    }
    if (this.finishNotified) {
      return;
    }
    this.finishNotified = true;
    const status: BattleStatus = this.engine.getState().status;
    if (status === BattleStatus.Won || status === BattleStatus.Lost) {
      this.callbacks.onFinish(this.engine.buildSessionResult());
    } else {
      // Engine never started — fall back to an empty result so navigation
      // still completes (BattlePage does the same with an undefined engine).
      this.callbacks.onFinish(new SessionResult());
    }
  }

  // ── Audio (BattlePage cue moments) ─────────────────────────────────────────

  private playSubmitAudio(outcome: AnswerOutcome): void {
    if (outcome.comboTriggered) {
      this.callbacks.playSfx(SoundKeys.HIT_CRIT);
    } else if (outcome.correct) {
      this.callbacks.playSfx(SoundKeys.HIT_NORMAL);
    } else {
      this.callbacks.playSfx(SoundKeys.ANSWER_WRONG);
      this.schedulePlayerHurtGrunt();
    }
    // Layered defeat cue when the final blow landed but the battle goes on;
    // the win-side fanfare is handled in finishAfterFeedbackHold.
    if (outcome.monsterDefeated && !outcome.battleEnded) {
      this.callbacks.playSfx(SoundKeys.MONSTER_DEFEAT);
    }
  }

  private schedulePlayerHurtGrunt(): void {
    this.scheduler((): void => {
      if (this.disposed) {
        return;
      }
      this.callbacks.playSfx(SoundKeys.PLAYER_HURT);
    }, COCOS_PLAYER_HURT_GRUNT_MS);
  }

  private autoSpeakCurrent(): void {
    const q: Question | undefined = this.engine.getState().currentQuestion;
    if (q !== undefined && q.answer.length > 0) {
      this.callbacks.autoSpeakWord(q.answer, q.kind);
    }
  }

  // ── Finish flow ────────────────────────────────────────────────────────────

  private finishAfterFeedbackHold(endStatus: BattleStatus | undefined): void {
    this.transport.send(encodeEnd(endStatus === BattleStatus.Won ? 'won' : 'lost'));
    this.scheduler((): void => {
      if (this.disposed || this.finishNotified) {
        return;
      }
      this.finishNotified = true;
      // Terminal fanfare just before the handoff (BattlePage.onBattleEnded).
      this.callbacks.playSfx(endStatus === BattleStatus.Won ? SoundKeys.VICTORY : SoundKeys.DEFEAT);
      this.callbacks.onFinish(this.engine.buildSessionResult());
    }, COCOS_FEEDBACK_HOLD_MS);
  }

  // ── Outbound ───────────────────────────────────────────────────────────────

  private sendInit(): void {
    const state: BattleState = this.engine.getState();
    const playerArt: PlayerArtShape = {
      idle: PLAYER_ART_IDLE,
      fight: PLAYER_ART_FIGHT,
      hurt: PLAYER_ART_HURT,
    };
    this.transport.send(encodeInit(
      state.playerMaxHp,
      state.monsterMaxHp,
      state.monstersTotal,
      state.remainingSeconds,
      playerArt,
    ));
  }

  private sendState(): void {
    const state: BattleState = this.engine.getState();
    const catalogIndex: number = this.catalogIndexProvider();
    const entry: MonsterEntry = getMonsterByIndex(catalogIndex);
    const monster: MonsterArtShape = {
      catalogIndex: catalogIndex,
      imageKey: cocosImageKeyForCatalogIndex(catalogIndex),
      name: entry.name,
      levelLabel: battleLevelLabelForMonsterLevel(entry.level),
      bonus: state.currentMonsterBonus,
    };
    this.transport.send(encodeState(
      state.playerHp,
      state.playerMaxHp,
      state.monsterHp,
      state.monsterMaxHp,
      state.monsterIndex,
      state.monstersTotal,
      state.remainingSeconds,
      state.comboCount,
      state.status,
      monster,
    ));
  }

  private sendQuestion(): void {
    const q: Question | undefined = this.engine.getState().currentQuestion;
    if (q === undefined) {
      return;
    }
    const payload: QuestionPayloadShape = {
      wordId: q.wordId,
      kind: q.kind,
      promptZh: q.promptZh,
      answer: q.answer,
      options: q.options,
      letterTemplate: q.letterTemplate,
      missingIndex: q.missingIndex,
      letterOptions: q.letterOptions,
      letterAnswer: q.letterAnswer,
      letterTemplateBase: q.letterTemplateBase,
      missingIndices: q.missingIndices,
      letterOptionsSteps: q.letterOptionsSteps,
      letterAnswers: q.letterAnswers,
      currentStep: q.currentStep,
      spellLetters: q.spellLetters,
      spellRevealedMask: q.spellRevealedMask,
      spellPool: q.spellPool,
      sentenceTemplate: q.sentenceTemplate,
      sentenceZh: q.sentenceZh,
    };
    this.transport.send(encodeQuestion(payload));
  }

  private sendAnimation(
    event: BattleAnimationEvent,
    correct: boolean,
    comboTriggered: boolean,
    battleEnded: boolean,
  ): void {
    this.transport.send(encodeAnimation(
      event.projectileDirection,
      event.projectileIntensity,
      event.projectileLabel,
      event.playerMotion,
      event.monsterMotion,
      event.feedbackText,
      event.showsCritOverlay,
      event.damageLabel,
      event.playsMonsterDefeatCue,
      correct,
      comboTriggered,
      battleEnded,
    ));
  }

  /**
   * Mirrors the Swift maybeSendBossIntro bookkeeping exactly: an intro is
   * sent the first time a monster's CATALOG index is seen, and only when the
   * engine's monster slot actually changed. The scene owns the 1.05 s
   * auto-dismiss. Dialogue comes from the monster catalog like the native
   * BattlePage's showIntroForCatalog.
   */
  private maybeSendBossIntro(): void {
    const state: BattleState = this.engine.getState();
    if (state.status !== BattleStatus.Playing) {
      return;
    }
    const catalogIndex: number = this.catalogIndexProvider();
    if (state.monsterIndex === this.lastBossIntroMonsterIndex
      || this.shownBossIntroCatalogIndices.has(catalogIndex)) {
      return;
    }
    const entry: MonsterEntry = getMonsterByIndex(catalogIndex);
    this.transport.send(encodeBossIntro(
      state.monsterIndex,
      entry.name,
      entry.dialogue.introLine.en,
      entry.dialogue.introLine.zh,
    ));
    this.shownBossIntroCatalogIndices.add(catalogIndex);
    this.lastBossIntroMonsterIndex = state.monsterIndex;
  }
}
