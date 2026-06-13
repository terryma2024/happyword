import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { CharacterCard, CharacterKind } from '../components/CharacterCard';
import { ChoiceButton, ChoiceState } from '../components/ChoiceButton';
import { SpellingArea } from '../components/SpellingArea';
import { BattleStageScheduler } from '../services/BattleStageScheduler';
import {
  LetterSlotView,
  buildLetterSlots,
  letterSlotRenderKey,
} from '../services/LetterSlotKey';
import {
  BattleEngine,
  AnswerOutcome,
  TickOutcome,
  DEFAULT_PLAYER_HP,
  DEFAULT_MONSTER_HP,
  DEFAULT_MONSTERS_TOTAL,
  DEFAULT_STARTING_SECONDS,
} from '../services/BattleEngine';
import { GameConfig } from '../models/GameConfig';
import { TodaySessionPlan } from '../models/AdventureRegion';
import { Pack } from '../models/Pack';
import {
  BattleSessionSetup,
  buildBattleSessionSetup,
  initBattleSessionStores,
} from '../services/BattleSessionFactory';
import {
  BattleResultEnrichmentInputs,
  enrichAndFlushSessionResult,
} from '../services/BattleResultEnricher';
import { BattleState, BattleStatus } from '../models/BattleState';
import { SessionResult } from '../models/SessionResult';
import { Question, QuestionKind } from '../models/Question';
import {
  MonsterDialogue,
  MonsterEntry,
  battleLevelLabelForMonsterLevel,
  getMonsterByIndex,
} from '../data/MonsterCatalog';
import { PLAYER_CHARACTER_ASSET, assetPathForEntry } from '../data/CharacterAssets';
import { SoundKeys } from '../services/AudioService';
import { BattleAudioMixer } from '../services/BattleAudioMixer';
import { shouldAutoSpeak } from '../services/PronunciationService';
import { CritOverlay } from '../components/CritOverlay';
import { DamageFloaterLabel } from '../components/DamageFloaterLabel';
import { MagicProjectile } from '../components/MagicProjectile';
import { MessageBubble } from '../components/MessageBubble';
import { MessageBubbleTail } from '../components/MessageBubbleGeometry';
import { getLearningRecorder, LearningRecorder } from '../services/LearningRecorder';
import { BattleAnswerRecorder } from '../services/BattleAnswerRecorder';
import { LetterMetrics, letterMetricsForLength } from '../services/LetterMetrics';
import {
  BossDialogueIntroDecision,
  BossDialogueIntroDecisionKind,
  BossDialogueSequencer,
} from '../services/BossDialogueSequencer';
import { requestPageOrientation } from '../utils/orientation';

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
 * Escape in the header ends the battle early (timer forced to zero → Lost)
 * and routes to ResultPage with a SessionResult built from current stats.
 */

// V0.1 FEEDBACK_MS = 650 kept for V0.2. CritOverlay's ~700 ms
// timeline is owned by animateTo callbacks that fire regardless of
// whether the next question has loaded, so the full spectacle plays
// out even if FEEDBACK_MS elapses in the middle of it. Existing UI
// tests wait 800 ms after each tap, so leaving FEEDBACK_MS at 650
// keeps them green.
const FEEDBACK_MS: number = 650;
const ORDINARY_BOSS_INTRO_MS: number = 2400;
const TICK_MS: number = 1000;
const BOSS_MESSAGE_BUBBLE_TAIL: MessageBubbleTail = {
  baseStart: { x: 172, y: 96 },
  baseEnd: { x: 196, y: 96 },
  tip: { x: 212, y: 112 },
};
/** V0.8.3 — max concurrent damage floaters per battle side. */
const MAX_FLOATERS_PER_SIDE: number = 4;
/** V0.8.3 — vertical offset between stacked floaters on the same side. */
const FLOATER_STACK_OFFSET_VP: number = 6;
/** Per-word answer tally used to compute review-only accuracy. */
class AnswerCount {
  correct: number = 0;
  total: number = 0;
}

/** Pending damage floater instance (V0.8.3). */
class FloaterPending {
  amount: number = 1;
  key: number = 0;
  stackOffsetVp: number = 0;
}

const LETTER_TEXT_FILLED: string = '#1D3557';
const LETTER_TEXT_MISSING: string = '#E63946';
const LETTER_BG_MISSING: string = '#FCEAEA';
const LETTER_BG_PENDING: string = '#F1F3F5';
const LETTER_TEXT_PENDING: string = '#A3A3A3';

@Entry
@Component
struct BattlePage {
  // Character metadata: cosmetic only, not driven by the engine.
  private readonly playerName: string = 'Magician';

  // Engine and its inputs are not part of render state — plain fields that
  // survive across frames. They are populated asynchronously during
  // `aboutToAppear` so the first render shows the "Loading…" placeholder.
  private engine?: BattleEngine;
  private audio: BattleAudioMixer = new BattleAudioMixer();
  private recorder: LearningRecorder = getLearningRecorder();
  /**
   * v1.1.1: the per-answer learning side effects (word stats, review-day
   * mark, monster encounter/defeat progress) moved statement-for-statement
   * into this shared service so the Cocos battle path records them too.
   * The old isReviewMode / dailyStateService / monsterProgress /
   * lastEncounterRecordedCatalogIndex fields live inside it now.
   */
  private answerRecorder: BattleAnswerRecorder = new BattleAnswerRecorder();
  private autoSpeak: boolean = true;
  /**
   * V0.3: True when this battle was launched from the today-adventure
   * card. Mutually exclusive with isReviewMode. Drives plan-based
   * monster slots, FillLetter rendering on Spelling/Boss, and the
   * "first-today reward" branch on ResultPage (Phase C).
   */
  private isTodayMode: boolean = false;
  private todayPlan: TodaySessionPlan | undefined = undefined;
  private todayStageScheduler: BattleStageScheduler | undefined = undefined;
  /**
   * V0.6.5.1: the Pack handed off by HomePage when launching today's
   * adventure via a chip. When present, BattlePage builds its
   * bundleRepo from `pack.words` directly so PlanQuestionSource can
   * resolve every wordId in the plan even when the bundled rawfile no
   * longer carries the same category. `undefined` means we are on
   * the legacy fallback path (review mode, normal mode, or HomePage
   * was on a synthetic fallback Pack at chip-tap time).
   */
  private activePack: Pack | undefined = undefined;
  /**
   * Per-wordId answer counters captured during the live battle.
   * navigateToResult uses this to compute review-pool accuracy
   * separately from the all-time `correctRate` so the Phase C
   * `review-80` coin reward fires on the right metric.
   */
  private sessionAnswers: Map<string, AnswerCount> = new Map<string, AnswerCount>();
  private feedbackTimer: number = -1;
  /**
   * Handle returned by setInterval for the 1Hz countdown driver. -1 when
   * no tick loop is running (before engine is ready, or after the battle
   * ended). Kept as a separate field from feedbackTimer so clearing one
   * never accidentally stops the other.
   */
  private tickTimer: number = -1;
  private bossIntroTimer: number = -1;
  private bossDefeatTimer: number = -1;
  private bossDialogueSequencer: BossDialogueSequencer = new BossDialogueSequencer();
  private lastIntroMonsterIndex: number = 0;
  private currentMonsterCatalogIndex: number = 1;
  private introShownCatalogIndices: number[] = [];
  private defeatShownCatalogIndices: number[] = [];
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
  // Mirror of MonsterCatalog entry for the monster currently in
  // combat. Updated inside syncFromState whenever monsterIndex
  // changes, then read by the slime CharacterCard (name +
  // bodyFill/bodyStroke) and the backward MagicProjectile (accent
  // colors). Initialised to entry 1 so the first paint of the page
  // before BattleEngine emits its first state still shows Slime.
  @State currentMonster: MonsterEntry = getMonsterByIndex(1);
  @State bossIntroVisible: boolean = false;
  @State superBossIntroVisible: boolean = false;
  @State bossDefeatVisible: boolean = false;
  @State bossDialogueName: string = '';
  @State bossDialogueIntroEn: string = '';
  @State bossDialogueIntroZh: string = '';
  @State bossDialogueDefeatEn: string = '';
  @State bossDialogueDefeatZh: string = '';
  /** V0.8.3 — mirrors engine {@link BattleState.currentMonsterBonus}. */
  @State currentMonsterBonus: boolean = false;
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

  /** V0.8.3 — FIFO damage floater queues (player / monster). */
  @State playerFloaters: FloaterPending[] = [];
  @State monsterFloaters: FloaterPending[] = [];
  private nextFloaterKey: number = 0;

  /**
   * V0.4.8: when the player is mid-cast (forward projectile in flight)
   * we swap the magician's portrait to its fight pose. Flips on at pulse
   * time and back off after SPAWN_MS + TRAVEL_MS + IMPACT_MS settle
   * (~560 ms) so the swap aligns with the impact frame and returns to
   * idle exactly when the cast/zoom animations finish.
   */
  @State playerFighting: boolean = false;
  private playerFightingTimer: number = -1;

  // Question text shown while loading the dictionary. Real prompts overwrite
  // this once the engine produces its first question.
  @State prompt: string = 'Loading…';
  @State feedbackText: string = ' ';
  @State feedbackColor: string = '#2ECC71';
  @State sentenceTemplate: string = '';
  @State sentenceZh: string = '';

  // V0.3 fill-letter render state. For Choice questions these stay
  // at their defaults and BattlePage renders the existing prompt
  // layout; for FillLetter the LetterTemplate row replaces it.
  @State currentQuestionKind: string = 'choice';
  @State letterTemplate: string = '';
  @State letterMissingIndex: number = -1;
  @State pendingMissingIndex: number = -1;
  @State isMedium: boolean = false;
  @State currentStep: number = 0;
  @State totalSteps: number = 1;

  // V0.4.1 Spell render state. Holds the current Spell question while
  // the SpellingArea component renders. Empty/default Question while
  // the active question is anything else; SpellingArea is only mounted
  // when currentQuestionKind === Spell so the default value never
  // shows on screen.
  @State currentSpellQuestion: Question = new Question();

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

  private optionIdFor(index: number): string {
    if (this.currentQuestionKind === QuestionKind.SentenceCloze) {
      return `BattleSentenceClozeOption_${index}`;
    }
    return this.optionIds[index];
  }

  private applySentenceClozeText(template: string, zh: string): void {
    this.sentenceTemplate = template;
    this.sentenceZh = zh;
  }

  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'BattlePage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
    // Construct the engine off the UI thread: loading `words_v1.json` is
    // async, so we render the loading placeholder until the promise
    // resolves. On success we snapshot the engine's state into our @State
    // fields, which triggers the first real render of the battle UI.
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // Hydrate the learning recorder / coin / check-in / monster-progress
    // stores (idempotent; shared with CocosBattlePage via the factory).
    initBattleSessionStores(ctx);
    // V1.1.0 Task 1.5: the engine/source construction block moved verbatim
    // into BattleSessionFactory so the Cocos battle page builds sessions
    // through the exact same path. The onConfigReady hook keeps the audio
    // mixer entering at the same point in the sequence as before.
    buildBattleSessionSetup(ctx, (cfg: GameConfig): void => {
      this.audio.enter(ctx, cfg).catch((err: BusinessError): void => {
        console.error(`BattlePage: BattleAudioMixer.enter failed: ${JSON.stringify(err)}`);
      });
    }).then((setup: BattleSessionSetup): void => {
      this.autoSpeak = setup.cfg.autoSpeak;
      this.answerRecorder.setReviewMode(setup.isReviewMode);
      this.isTodayMode = setup.isTodayMode;
      this.todayPlan = setup.todayPlan;
      this.todayStageScheduler = setup.todayStageScheduler;
      this.activePack = setup.activePack;
      this.engine = setup.engine;
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

  onPageShow(): void {
    this.applyOrientationPolicy();
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
    this.clearBossDialogueTimers();
    if (this.playerFightingTimer >= 0) {
      clearTimeout(this.playerFightingTimer);
      this.playerFightingTimer = -1;
    }
    for (let i = 0; i < this.impactTimers.length; i++) {
      clearTimeout(this.impactTimers[i]);
    }
    this.impactTimers = [];
    // Best-effort audio teardown. BattleAudioMixer releases BGM, SFX,
    // and the PCM voice renderer without blocking navigation.
    this.audio.exit().catch((err: BusinessError): void => {
      console.error(`BattlePage: BattleAudioMixer.exit failed: ${JSON.stringify(err)}`);
    });
    // V0.6.4: fire-and-forget cloud sync once a battle ends so the
    // learning deltas land on the server before the parent reloads
    // their dashboard. The CloudSyncService is intentionally tolerant
    // of unbound or offline state so we never need to await/guard.
    const sync = this.recorder.getCloudSync();
    if (sync !== undefined) {
      sync.syncOnce().catch((err: BusinessError): void => {
        console.error(`BattlePage: cloud sync failed: ${JSON.stringify(err)}`);
      });
    }
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

  /**
   * V0.4.8: bump `projectileForwardPulse` and flip `playerFighting`
   * for the duration of the cast. Centralised so the four
   * forward-shot call sites (correct / combo on Choice/FillLetter,
   * correct / combo on Spell) all behave identically and we never
   * forget to schedule the reset timer.
   *
   * The 560 ms reset window covers MagicProjectile's
   * SPAWN_MS (80) + TRAVEL_MS (260) + IMPACT_MS (160) + a 60 ms
   * settle so the magician returns to idle right as the impact
   * spectacle relaxes, not before the projectile arrives.
   */
  private triggerForwardCast(): void {
    this.projectileForwardPulse += 1;
    if (this.playerFightingTimer >= 0) {
      clearTimeout(this.playerFightingTimer);
    }
    this.playerFighting = true;
    this.playerFightingTimer = setTimeout((): void => {
      this.playerFighting = false;
      this.playerFightingTimer = -1;
    }, 560);
  }

  /**
   * V0.4.8: schedule the player-hurt grunt to play when the backward
   * projectile reaches the mage. Mirrors MagicProjectile's spawn
   * (80 ms) + travel (260 ms) timing so the voice cue arrives with
   * the impact, not at submit time. Tracked through `impactTimers`
   * so `aboutToDisappear` can cancel it on a back-press.
   */
  private schedulePlayerHurtGrunt(): void {
    const id: number = setTimeout((): void => {
      this.audio.play(SoundKeys.PLAYER_HURT);
    }, 340);
    this.impactTimers.push(id);
  }

  private pushFloater(side: string, amount: number): void {
    const dmg: number = amount >= 2 ? 2 : 1;
    const pending: FloaterPending = new FloaterPending();
    pending.amount = dmg;
    pending.key = this.nextFloaterKey;
    this.nextFloaterKey += 1;
    if (side === 'player') {
      pending.stackOffsetVp = this.playerFloaters.length * FLOATER_STACK_OFFSET_VP;
      const next: FloaterPending[] = this.playerFloaters.slice();
      if (next.length >= MAX_FLOATERS_PER_SIDE) {
        next.shift();
      }
      next.push(pending);
      this.playerFloaters = next;
      return;
    }
    pending.stackOffsetVp = this.monsterFloaters.length * FLOATER_STACK_OFFSET_VP;
    const monsterNext: FloaterPending[] = this.monsterFloaters.slice();
    if (monsterNext.length >= MAX_FLOATERS_PER_SIDE) {
      monsterNext.shift();
    }
    monsterNext.push(pending);
    this.monsterFloaters = monsterNext;
  }

  private removeFloater(side: string, key: number): void {
    if (side === 'player') {
      this.playerFloaters = this.playerFloaters.filter((item: FloaterPending) => item.key !== key);
      return;
    }
    this.monsterFloaters = this.monsterFloaters.filter((item: FloaterPending) => item.key !== key);
  }

  private clearBossDialogueTimers(): void {
    if (this.bossIntroTimer >= 0) {
      clearTimeout(this.bossIntroTimer);
      this.bossIntroTimer = -1;
    }
    if (this.bossDefeatTimer >= 0) {
      clearTimeout(this.bossDefeatTimer);
      this.bossDefeatTimer = -1;
    }
  }

  private showIntroForCurrentMonster(): void {
    const catalogIndex: number = this.currentMonsterCatalogIndex;
    const decision: BossDialogueIntroDecision = this.bossDialogueSequencer.requestIntro(
      this.monsterIndex,
      catalogIndex,
      this.lastIntroMonsterIndex,
      this.introShownCatalogIndices,
    );
    if (decision.kind === BossDialogueIntroDecisionKind.Skip) {
      this.bossIntroVisible = false;
      this.superBossIntroVisible = false;
      return;
    }
    if (decision.kind === BossDialogueIntroDecisionKind.Defer) {
      this.bossIntroVisible = false;
      this.superBossIntroVisible = false;
      return;
    }
    this.showIntroForCatalog(decision.monsterIndex, decision.catalogIndex);
  }

  private showIntroForCatalog(monsterIndex: number, catalogIndex: number): void {
    if (monsterIndex === this.lastIntroMonsterIndex ||
      this.introShownCatalogIndices.indexOf(catalogIndex) >= 0) {
      return;
    }
    this.lastIntroMonsterIndex = monsterIndex;
    this.introShownCatalogIndices.push(catalogIndex);
    const entry: MonsterEntry = getMonsterByIndex(catalogIndex);
    const d: MonsterDialogue = entry.dialogue;
    this.bossDialogueName = entry.name;
    this.bossDialogueIntroEn = d.introLine.en;
    this.bossDialogueIntroZh = d.introLine.zh;
    this.bossIntroVisible = true;
    this.superBossIntroVisible = false;
    if (this.bossIntroTimer >= 0) {
      clearTimeout(this.bossIntroTimer);
    }
    this.bossIntroTimer = setTimeout((): void => {
      this.bossIntroVisible = false;
      this.superBossIntroVisible = false;
      this.bossIntroTimer = -1;
    }, ORDINARY_BOSS_INTRO_MS);
  }

  private showDefeatForMonster(entry: MonsterEntry, catalogIndex: number): void {
    this.bossDialogueName = entry.name;
    if (this.defeatShownCatalogIndices.indexOf(catalogIndex) < 0) {
      this.defeatShownCatalogIndices.push(catalogIndex);
    }
    this.bossDefeatVisible = false;
    if (this.bossDefeatTimer >= 0) {
      clearTimeout(this.bossDefeatTimer);
      this.bossDefeatTimer = -1;
    }
    this.releaseIntroAfterDefeat();
  }

  private releaseIntroAfterDefeat(): void {
    const decision: BossDialogueIntroDecision = this.bossDialogueSequencer.releaseAfterDefeat();
    if (decision.kind === BossDialogueIntroDecisionKind.Show) {
      this.showIntroForCatalog(decision.monsterIndex, decision.catalogIndex);
    }
  }

  @Builder
  playerDamageFloaters() {
    ForEach(this.playerFloaters, (item: FloaterPending, index: number) => {
      DamageFloaterLabel({
        amount: item.amount,
        stackOffsetVp: item.stackOffsetVp,
        labelId: index === this.playerFloaters.length - 1
          ? 'BattleDamageFloaterLabel_player'
          : `BattleDamageFloaterLabel_player_${item.key}`,
        onDispose: (): void => {
          this.removeFloater('player', item.key);
        },
      });
    }, (item: FloaterPending) => `floater_${item.key}`);
  }

  @Builder
  monsterDamageFloaters() {
    ForEach(this.monsterFloaters, (item: FloaterPending, index: number) => {
      DamageFloaterLabel({
        amount: item.amount,
        stackOffsetVp: item.stackOffsetVp,
        labelId: index === this.monsterFloaters.length - 1
          ? 'BattleDamageFloaterLabel_monster'
          : `BattleDamageFloaterLabel_monster_${item.key}`,
        onDispose: (): void => {
          this.removeFloater('monster', item.key);
        },
      });
    }, (item: FloaterPending) => `floater_${item.key}`);
  }

  @Builder
  bossIntroBubble() {
    if (this.bossIntroVisible) {
      Stack() {
        MessageBubble({
          widthVp: 224,
          heightVp: 96,
          radiusVp: 18,
          borderWidthVp: 1,
          fillColor: '#FFFDF6',
          strokeColor: '#E7D7B6',
          contentPadding: { left: 10, right: 10, top: 10, bottom: 10 },
          tail: BOSS_MESSAGE_BUBBLE_TAIL,
          bubbleShadow: { radius: 12, color: '#22000000', offsetX: 0, offsetY: 4 },
        }) {
          Column({ space: 3 }) {
            Text(this.bossDialogueName)
              .id('BattleBossIntroName')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#6B4A23');
            Text(this.bossDialogueIntroEn)
              .id('BattleBossIntroLineEn')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1D3557')
              .maxLines(2);
            Text(this.bossDialogueIntroZh)
              .id('BattleBossIntroLineZh')
              .fontSize(11)
              .fontColor('#6E5F54')
              .maxLines(2);
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .height('100%');
        }
      }
      .id('BattleBossIntroBubble')
      .width(248)
      .height(144)
      .position({ x: '55%', y: '11%' })
      .hitTestBehavior(HitTestMode.None);
    }
  }

  @Builder
  superBossIntroBanner() {
    if (this.superBossIntroVisible) {
      Column({ space: 6 }) {
        Text(`SUPERBOSS ${this.bossDialogueName}`)
          .id('BattleSuperBossIntroTitle')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#7C3E00')
          .maxLines(1);
        Text(this.bossDialogueIntroEn)
          .id('BattleSuperBossIntroLineEn')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557')
          .textAlign(TextAlign.Center)
          .maxLines(2);
        Text(this.bossDialogueIntroZh)
          .id('BattleSuperBossIntroLineZh')
          .fontSize(12)
          .fontColor('#6E5F54')
          .textAlign(TextAlign.Center)
          .maxLines(2);
      }
      .id('BattleSuperBossIntroBanner')
      .width('76%')
      .padding(16)
      .borderRadius(20)
      .borderWidth(2)
      .borderColor('#D79522')
      .backgroundColor('#FFF4CD')
      .shadow({ radius: 18, color: '#33000000', offsetX: 0, offsetY: 6 })
      .alignItems(HorizontalAlign.Center)
      .position({ x: '12%', y: '18%' })
      .hitTestBehavior(HitTestMode.Block);
    }
  }

  @Builder
  bossDefeatBubble() {
    if (this.bossDefeatVisible) {
      Stack() {
        MessageBubble({
          widthVp: 224,
          heightVp: 96,
          radiusVp: 18,
          borderWidthVp: 1,
          fillColor: '#FFFDF6',
          strokeColor: '#D5E7B3',
          contentPadding: { left: 10, right: 10, top: 10, bottom: 10 },
          tail: BOSS_MESSAGE_BUBBLE_TAIL,
          bubbleShadow: { radius: 12, color: '#22000000', offsetX: 0, offsetY: 4 },
        }) {
          Column({ space: 3 }) {
            Text(this.bossDialogueName)
              .id('BattleBossDefeatName')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#4F6B2B');
            Text(this.bossDialogueDefeatEn)
              .id('BattleBossDefeatLineEn')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1D3557')
              .maxLines(2);
            Text(this.bossDialogueDefeatZh)
              .id('BattleBossDefeatLineZh')
              .fontSize(11)
              .fontColor('#6E5F54')
              .maxLines(2);
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .height('100%');
        }
      }
      .id('BattleBossDefeatBubble')
      .width(248)
      .height(144)
      .position({ x: '55%', y: '14%' })
      .hitTestBehavior(HitTestMode.None);
    }
  }

  /**
   * Auto-speak helper: bounces through the pure `shouldAutoSpeak`
   * predicate so the decision stays unit-testable. Callers pass
   * `isRevealing` true during the feedback window to suppress TTS
   * while the crit/hurt SFX are already playing.
   */
  private maybeAutoSpeakCurrent(isRevealing: boolean): void {
    if (!shouldAutoSpeak(this.autoSpeak, this.audio.isVoiceAvailable(), isRevealing, this.currentQuestionKind)) {
      return;
    }
    if (this.lastAnswerWord.length === 0) {
      return;
    }
    this.audio.speakWord(this.lastAnswerWord);
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
    // Re-read catalog every sync. getMonsterByIndex is a constant-
    // time array lookup, so the cost is negligible and keeping the
    // assignment unconditional avoids a stale @State if the engine
    // ever resets monsterIndex back to 1 between battles.
    this.currentMonsterCatalogIndex = this.resolveMonsterCatalogIndex(state);
    this.currentMonster = getMonsterByIndex(this.currentMonsterCatalogIndex);
    this.recordEncounterForCurrentMonster();
    this.currentMonsterBonus = state.currentMonsterBonus;
    this.comboCount = state.comboCount;
    this.remainingSeconds = state.remainingSeconds;
    this.showIntroForCurrentMonster();

    const q: Question | undefined = state.currentQuestion;
    if (q !== undefined) {
      this.prompt = q.promptZh;
      this.lastAnswerWord = q.answer;
      this.currentWordId = q.wordId;
      this.currentQuestionKind = q.kind;
      this.applySentenceClozeText('', '');
      if (q.kind === QuestionKind.FillLetterMedium) {
        this.isMedium = true;
        this.currentStep = q.currentStep;
        this.totalSteps = q.missingIndices.length;
        this.letterTemplate = q.letterTemplateBase;
        this.letterMissingIndex = q.missingIndices[q.currentStep];
        this.pendingMissingIndex = q.missingIndices[q.currentStep === 0 ? 1 : 0];
        this.options = [
          q.letterOptionsSteps[q.currentStep][0],
          q.letterOptionsSteps[q.currentStep][1],
          q.letterOptionsSteps[q.currentStep][2],
        ];
      } else if (q.kind === QuestionKind.FillLetter) {
        this.isMedium = false;
        this.currentStep = 0;
        this.totalSteps = 1;
        this.pendingMissingIndex = -1;
        this.letterTemplate = q.letterTemplate;
        this.letterMissingIndex = q.missingIndex;
        this.options = [q.letterOptions[0], q.letterOptions[1], q.letterOptions[2]];
      } else if (q.kind === QuestionKind.Spell) {
        this.isMedium = false;
        this.currentStep = 0;
        this.totalSteps = 1;
        this.pendingMissingIndex = -1;
        this.letterTemplate = '';
        this.letterMissingIndex = -1;
        this.options = ['', '', ''];
        this.currentSpellQuestion = q;
      } else if (q.kind === QuestionKind.SentenceCloze) {
        this.isMedium = false;
        this.currentStep = 0;
        this.totalSteps = 1;
        this.pendingMissingIndex = -1;
        this.letterTemplate = '';
        this.letterMissingIndex = -1;
        this.applySentenceClozeText(q.sentenceTemplate, q.sentenceZh);
        this.options = [q.options[0], q.options[1], q.options[2]];
      } else {
        this.isMedium = false;
        this.currentStep = 0;
        this.totalSteps = 1;
        this.pendingMissingIndex = -1;
        this.letterTemplate = '';
        this.letterMissingIndex = -1;
        this.options = [q.options[0], q.options[1], q.options[2]];
      }
    }
  }

  private resolveMonsterCatalogIndex(state: BattleState): number {
    const stageScheduler: BattleStageScheduler | undefined = this.todayStageScheduler;
    if (this.isTodayMode && stageScheduler !== undefined) {
      return stageScheduler.catalogIndexForMonster(state.monsterIndex);
    }
    if (this.isTodayMode && this.todayPlan !== undefined) {
      const slots: number = this.todayPlan.monsterSlots.length;
      if (slots > 0) {
        const i: number = state.monsterIndex <= 0 ? 0 : (state.monsterIndex - 1) % slots;
        return this.todayPlan.monsterSlots[i].catalogIndex;
      }
    }
    return state.monsterIndex <= 0 ? 1 : state.monsterIndex;
  }

  private recordEncounterForCurrentMonster(): void {
    // v1.1.1: body (incl. the dedup) moved into BattleAnswerRecorder so the
    // Cocos battle path shares it.
    this.answerRecorder.recordEncounter(this.currentMonsterCatalogIndex);
  }

  private recordMonsterDefeat(catalogIndex: number): void {
    this.answerRecorder.recordMonsterDefeat(catalogIndex);
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
    // FillLetter questions carry their own template/missing-index, so
    // those snapshots ride along too; otherwise the reveal window
    // would show the answered prompt against the NEXT question's
    // letter template (or vice versa).
    const answeredPrompt: string = this.prompt;
    const answeredOptions: string[] = this.options.slice();
    const answeredKind: string = this.currentQuestionKind;
    const answeredLetterTemplate: string = this.letterTemplate;
    const answeredLetterMissingIndex: number = this.letterMissingIndex;
    const answeredPendingMissingIndex: number = this.pendingMissingIndex;
    const answeredIsMedium: boolean = this.isMedium;
    const answeredStep: number = this.currentStep;
    const answeredTotalSteps: number = this.totalSteps;
    const answeredSentenceTemplate: string = this.sentenceTemplate;
    const answeredSentenceZh: string = this.sentenceZh;
    const correctWord: string = this.lastAnswerWord;
    const answeredWordId: string = this.currentWordId;
    const defeatedMonsterBeforeAnswer: MonsterEntry = this.currentMonster;
    const defeatedMonsterCatalogBeforeAnswer: number = this.currentMonsterCatalogIndex;

    const outcome: AnswerOutcome = engine.submitAnswer(text);

    if (outcome.advancedStep) {
      // Atomic medium: step 0 correct. Do not record learning stats and do not
      // rotate the question; just show a brief feedback and resync to step 1.
      const tappedIndex2: number = answeredOptions.indexOf(text);
      const states2: ChoiceState[] = [
        ChoiceState.Disabled,
        ChoiceState.Disabled,
        ChoiceState.Disabled,
      ];
      if (tappedIndex2 >= 0) {
        states2[tappedIndex2] = ChoiceState.Correct;
      }
      this.optionStates = states2;
      this.feedbackText = '答对啦！下一空';
      this.feedbackColor = '#2ECC71';
      this.audio.play(SoundKeys.HIT_NORMAL);
      this.feedbackTimer = setTimeout((): void => {
        this.feedbackTimer = -1;
        this.feedbackText = ' ';
        this.syncFromEngine();
        this.optionStates = [ChoiceState.Idle, ChoiceState.Idle, ChoiceState.Idle];
      }, FEEDBACK_MS);
      return;
    }

    // Record the answer BEFORE syncFromEngine rotates to the next
    // question so the wordId we pass is the one the player just
    // answered. Falls through silently if the recorder wasn't ready.
    this.answerRecorder.recordAnswer(answeredWordId, outcome.correct);
    if (answeredWordId.length > 0) {
      const prev: AnswerCount | undefined = this.sessionAnswers.get(answeredWordId);
      const acc: AnswerCount = prev !== undefined ? prev : new AnswerCount();
      acc.total += 1;
      if (outcome.correct) {
        acc.correct += 1;
      }
      this.sessionAnswers.set(answeredWordId, acc);
    }

    // Update stat displays (HP, combo, monster index) immediately so the
    // damage is visible before the reveal delay elapses.
    if (outcome.monsterDefeated) {
      this.bossDialogueSequencer.beginDefeatTransition();
      this.recordMonsterDefeat(defeatedMonsterCatalogBeforeAnswer);
    }
    this.syncFromEngine();
    if (outcome.monsterDefeated) {
      this.showDefeatForMonster(defeatedMonsterBeforeAnswer, defeatedMonsterCatalogBeforeAnswer);
    }

    // Keep the answered question on screen for the reveal window —
    // syncFromEngine above would have replaced prompt/options/kind/
    // letter-template with the NEXT question's data.
    this.prompt = answeredPrompt;
    this.options = answeredOptions;
    this.currentQuestionKind = answeredKind;
    this.letterTemplate = answeredLetterTemplate;
    this.letterMissingIndex = answeredLetterMissingIndex;
    this.pendingMissingIndex = answeredPendingMissingIndex;
    this.isMedium = answeredIsMedium;
    this.currentStep = answeredStep;
    this.totalSteps = answeredTotalSteps;
    this.applySentenceClozeText(answeredSentenceTemplate, answeredSentenceZh);

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
      this.triggerForwardCast();
      this.playerCastPulse += 1;
      this.scheduleImpact((): void => {
        this.monsterZoomPulse += 1;
        this.critDamage = outcome.damage;
        this.critPulse += 1;
        this.pushFloater('monster', outcome.damage);
      });
    } else if (outcome.correct) {
      this.feedbackText = '正确！';
      this.feedbackColor = '#2ECC71';
      this.audio.play(SoundKeys.HIT_NORMAL);
      // Forward projectile flies first, monster hurt + shake fire on
      // arrival; player nudge is the recoil from casting and stays at
      // launch time so the lunge precedes the impact.
      this.projectileIntensity = 1;
      this.triggerForwardCast();
      this.playerNudgePulse += 1;
      this.scheduleImpact((): void => {
        this.monsterHurtPulse += 1;
        this.pushFloater('monster', outcome.damage);
      });
    } else {
      this.feedbackText = `正确答案是 ${correctWord}`;
      this.feedbackColor = '#E74C3C';
      this.audio.play(SoundKeys.ANSWER_WRONG);
      // V0.4.8: layer the player-hurt grunt on top of the buzzer so
      // the monster's counter-attack lands with a softer voice cue
      // when the projectile arrives. Delay matches the projectile's
      // SPAWN_MS + TRAVEL_MS so the grunt lines up with the impact
      // frame, not the answer-submit moment.
      this.schedulePlayerHurtGrunt();
      // Backward projectile: monster fires back at the mage. Player
      // hurt + shake fire on arrival.
      this.projectileIntensity = 1;
      this.projectileBackwardPulse += 1;
      this.scheduleImpact((): void => {
        this.playerHurtPulse += 1;
        this.pushFloater('player', outcome.damage);
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
        this.lastAnswerWord = nextQuestion.answer;
        // Populate the option buttons from the field that matches the
        // question kind. For FillLetter questions `nextQuestion.options`
        // is empty by contract — the three letter candidates live in
        // `letterOptions`. Without this branch the buttons would render
        // with no text on the very first FillLetter shown after a
        // Choice question (e.g. monster-2 in today's adventure).
        this.currentQuestionKind = nextQuestion.kind;
        this.applySentenceClozeText('', '');
        if (nextQuestion.kind === QuestionKind.FillLetterMedium) {
          this.isMedium = true;
          this.currentStep = nextQuestion.currentStep;
          this.totalSteps = nextQuestion.missingIndices.length;
          this.letterTemplate = nextQuestion.letterTemplateBase;
          this.letterMissingIndex = nextQuestion.missingIndices[nextQuestion.currentStep];
          this.pendingMissingIndex = nextQuestion.missingIndices[nextQuestion.currentStep === 0 ? 1 : 0];
          this.options = [
            nextQuestion.letterOptionsSteps[nextQuestion.currentStep][0],
            nextQuestion.letterOptionsSteps[nextQuestion.currentStep][1],
            nextQuestion.letterOptionsSteps[nextQuestion.currentStep][2],
          ];
        } else if (nextQuestion.kind === QuestionKind.FillLetter) {
          this.isMedium = false;
          this.currentStep = 0;
          this.totalSteps = 1;
          this.pendingMissingIndex = -1;
          this.options = [
            nextQuestion.letterOptions[0],
            nextQuestion.letterOptions[1],
            nextQuestion.letterOptions[2],
          ];
          this.letterTemplate = nextQuestion.letterTemplate;
          this.letterMissingIndex = nextQuestion.missingIndex;
        } else if (nextQuestion.kind === QuestionKind.SentenceCloze) {
          this.isMedium = false;
          this.currentStep = 0;
          this.totalSteps = 1;
          this.pendingMissingIndex = -1;
          this.options = [
            nextQuestion.options[0],
            nextQuestion.options[1],
            nextQuestion.options[2],
          ];
          this.letterTemplate = '';
          this.letterMissingIndex = -1;
          this.applySentenceClozeText(nextQuestion.sentenceTemplate, nextQuestion.sentenceZh);
        } else {
          this.isMedium = false;
          this.currentStep = 0;
          this.totalSteps = 1;
          this.pendingMissingIndex = -1;
          this.options = [
            nextQuestion.options[0],
            nextQuestion.options[1],
            nextQuestion.options[2],
          ];
          this.letterTemplate = '';
          this.letterMissingIndex = -1;
          this.applySentenceClozeText('', '');
        }
        // New question loaded — feedback window is closed so it's
        // safe to auto-speak the answer now.
        this.maybeAutoSpeakCurrent(false);
      }
      this.optionStates = [ChoiceState.Idle, ChoiceState.Idle, ChoiceState.Idle];
    }, FEEDBACK_MS);
  }

  /**
   * V0.8.4 — wrong Spell pool letter: -1 HP without submitting the word.
   */
  private handleSpellWrongLetterTap(): void {
    const engine: BattleEngine | undefined = this.engine;
    if (engine === undefined) {
      return;
    }
    if (this.feedbackTimer >= 0) {
      return;
    }
    const damage: number = engine.applySpellLetterPenalty();
    if (damage <= 0) {
      return;
    }
    this.syncFromEngine();
    this.audio.play(SoundKeys.ANSWER_WRONG);
    this.schedulePlayerHurtGrunt();
    this.projectileIntensity = 1;
    this.projectileBackwardPulse += 1;
    this.scheduleImpact((): void => {
      this.playerHurtPulse += 1;
      this.pushFloater('player', damage);
    });
    if (engine.getState().status === BattleStatus.Lost) {
      const outcome: AnswerOutcome = new AnswerOutcome();
      outcome.battleEnded = true;
      outcome.endStatus = BattleStatus.Lost;
      this.onBattleEnded(outcome);
    }
  }

  /**
   * V0.4.1 Spell submit handler — invoked by SpellingArea when every
   * slot is correctly filled. By the time we get here the answer is
   * guaranteed correct (SpellingArea rejects wrong taps locally), so
   * the engine path mirrors the correct branch of `onOptionTap`
   * minus the per-option button highlighting (Spell has no
   * ChoiceButtons).
   */
  private handleSpellSubmit(answer: string): void {
    const engine: BattleEngine | undefined = this.engine;
    if (engine === undefined) {
      return;
    }
    if (this.feedbackTimer >= 0) {
      return;
    }
    const answeredPrompt: string = this.prompt;
    const answeredKind: string = this.currentQuestionKind;
    const correctWord: string = this.lastAnswerWord;
    const answeredWordId: string = this.currentWordId;
    const answeredSpellQuestion: Question = this.currentSpellQuestion;
    const defeatedMonsterBeforeAnswer: MonsterEntry = this.currentMonster;
    const defeatedMonsterCatalogBeforeAnswer: number = this.currentMonsterCatalogIndex;

    const outcome: AnswerOutcome = engine.submitAnswer(answer);

    this.answerRecorder.recordAnswer(answeredWordId, outcome.correct);
    if (answeredWordId.length > 0) {
      const prev: AnswerCount | undefined = this.sessionAnswers.get(answeredWordId);
      const acc: AnswerCount = prev !== undefined ? prev : new AnswerCount();
      acc.total += 1;
      if (outcome.correct) {
        acc.correct += 1;
      }
      this.sessionAnswers.set(answeredWordId, acc);
    }

    if (outcome.monsterDefeated) {
      this.bossDialogueSequencer.beginDefeatTransition();
      this.recordMonsterDefeat(defeatedMonsterCatalogBeforeAnswer);
    }
    this.syncFromEngine();
    if (outcome.monsterDefeated) {
      this.showDefeatForMonster(defeatedMonsterBeforeAnswer, defeatedMonsterCatalogBeforeAnswer);
    }

    // Hold the answered Spell on screen during the feedback window
    // exactly like onOptionTap does for Choice / FillLetter.
    this.prompt = answeredPrompt;
    this.currentQuestionKind = answeredKind;
    this.currentSpellQuestion = answeredSpellQuestion;

    // Spell answers go through the correct-non-crit / crit branches only.
    if (outcome.comboTriggered) {
      this.feedbackText = `连击 3！魔法爆发 ×${outcome.damage}`;
      this.feedbackColor = '#FFB400';
      this.audio.play(SoundKeys.HIT_CRIT);
      this.projectileIntensity = outcome.damage;
      this.triggerForwardCast();
      this.playerCastPulse += 1;
      this.scheduleImpact((): void => {
        this.monsterZoomPulse += 1;
        this.critDamage = outcome.damage;
        this.critPulse += 1;
        this.pushFloater('monster', outcome.damage);
      });
    } else {
      this.feedbackText = '正确！';
      this.feedbackColor = '#2ECC71';
      this.audio.play(SoundKeys.HIT_NORMAL);
      this.projectileIntensity = 1;
      this.triggerForwardCast();
      this.playerNudgePulse += 1;
      this.scheduleImpact((): void => {
        this.monsterHurtPulse += 1;
        this.pushFloater('monster', outcome.damage);
      });
    }
    if (outcome.monsterDefeated && !outcome.battleEnded) {
      this.audio.play(SoundKeys.MONSTER_DEFEAT);
    }

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
        this.lastAnswerWord = nextQuestion.answer;
        this.currentQuestionKind = nextQuestion.kind;
        if (nextQuestion.kind === QuestionKind.FillLetterMedium) {
          this.isMedium = true;
          this.currentStep = nextQuestion.currentStep;
          this.totalSteps = nextQuestion.missingIndices.length;
          this.letterTemplate = nextQuestion.letterTemplateBase;
          this.letterMissingIndex = nextQuestion.missingIndices[nextQuestion.currentStep];
          this.pendingMissingIndex = nextQuestion.missingIndices[nextQuestion.currentStep === 0 ? 1 : 0];
          this.options = [
            nextQuestion.letterOptionsSteps[nextQuestion.currentStep][0],
            nextQuestion.letterOptionsSteps[nextQuestion.currentStep][1],
            nextQuestion.letterOptionsSteps[nextQuestion.currentStep][2],
          ];
        } else if (nextQuestion.kind === QuestionKind.FillLetter) {
          this.isMedium = false;
          this.currentStep = 0;
          this.totalSteps = 1;
          this.pendingMissingIndex = -1;
          this.options = [
            nextQuestion.letterOptions[0],
            nextQuestion.letterOptions[1],
            nextQuestion.letterOptions[2],
          ];
          this.letterTemplate = nextQuestion.letterTemplate;
          this.letterMissingIndex = nextQuestion.missingIndex;
        } else if (nextQuestion.kind === QuestionKind.Spell) {
          this.isMedium = false;
          this.currentStep = 0;
          this.totalSteps = 1;
          this.pendingMissingIndex = -1;
          this.letterTemplate = '';
          this.letterMissingIndex = -1;
          this.options = ['', '', ''];
          this.currentSpellQuestion = nextQuestion;
        } else {
          this.isMedium = false;
          this.currentStep = 0;
          this.totalSteps = 1;
          this.pendingMissingIndex = -1;
          this.options = [
            nextQuestion.options[0],
            nextQuestion.options[1],
            nextQuestion.options[2],
          ];
          this.letterTemplate = '';
          this.letterMissingIndex = -1;
        }
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
    // Play the terminal fanfare just before we navigate. BattleAudioMixer
    // drops the cue silently if preload failed or action SFX are muted, and
    // ResultPage doesn't own a mixer so this is the last chance to emit it.
    if (outcome.endStatus === BattleStatus.Won) {
      this.audio.play(SoundKeys.VICTORY);
    } else {
      this.audio.play(SoundKeys.DEFEAT);
    }
    this.navigateToResult(engine.buildSessionResult());
  }

  /**
   * Escape — ends the battle immediately by advancing the engine's clock
   * past zero (Lost), then routes to ResultPage. If the engine hasn't
   * finished loading yet, fall back to an empty result so navigation still
   * completes.
   */
  private onEscapeBattle(): void {
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
    // V1.1.0 Task 1.5: the enrichment (learning totals, today rewards,
    // mode reset, store flushes) moved verbatim into BattleResultEnricher
    // so CocosBattlePage runs the identical flow.
    const inputs: BattleResultEnrichmentInputs = new BattleResultEnrichmentInputs();
    inputs.isTodayMode = this.isTodayMode;
    inputs.todayPlan = this.todayPlan;
    inputs.activePack = this.activePack;
    enrichAndFlushSessionResult(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      result,
      inputs,
    );
    this.getUIContext().getRouter().replaceUrl({
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
      Button('Escape', { type: ButtonType.Normal })
        .id('BattleEscapeButton')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557')
        .backgroundColor(Color.Transparent)
        .borderWidth(1)
        .borderColor('#A8CCF0')
        .borderRadius(18)
        .height(36)
        .padding({ left: 12, right: 12 })
        .margin({ left: 8 })
        .enabled(this.feedbackTimer < 0)
        .onClick((): void => {
          this.onEscapeBattle();
        });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 });
  }

  /**
   * Pre-compute the slot list for the letter-template row. The visible row
   * hides normal phrase spaces, so each slot keeps its original template
   * index before deciding whether it is the active or pending blank.
   */
  private letterSlots(): LetterSlotView[] {
    if (this.letterTemplate.length === 0) {
      return [];
    }
    return buildLetterSlots(this.letterTemplate, this.letterMissingIndex, this.pendingMissingIndex);
  }

  private letterTemplateGlyphs(): string[] {
    const out: string[] = [];
    let i: number = 0;
    while (i < this.letterTemplate.length) {
      const c: string = this.letterTemplate.charAt(i);
      if (c !== ' ') {
        out.push(c);
        i++;
        continue;
      }
      let run: number = 0;
      while (i + run < this.letterTemplate.length && this.letterTemplate.charAt(i + run) === ' ') {
        run++;
      }
      if (run >= 3) {
        out.push(' ');
      }
      i += run;
    }
    return out;
  }

  /**
   * Length-banded LetterMetrics for the current letterTemplate.
   * Helper instead of an inline const because ArkTS @Builder
   * bodies forbid local declarations between the opening brace and
   * the first UI node — but they DO permit method calls inside
   * property expressions, which keeps the per-letter modifiers
   * dynamic without breaking @State observability for the Builder.
   */
  private letterMetrics(): LetterMetrics {
    return letterMetricsForLength(this.letterTemplateGlyphs().length);
  }

  /**
   * Letter-template row. Reads `this.letterTemplate`,
   * `this.letterMissingIndex`, and `this.pendingMissingIndex`
   * directly so ArkUI re-invokes the Builder whenever those
   * @State values change — the previous param-based version
   * (slots / metrics computed at the call site) caused stale
   * Text widgets to linger after the question rotated, because
   * the Builder body referenced only its local parameters and
   * therefore never registered as an observer of letterTemplate.
   *
   * The bucket selection is a method call (this.letterMetrics())
   * so it stays observable: each property re-evaluates when
   * letterTemplate updates, picking width/gap/font for the new
   * length. Long prompts like "supermarket" (11 letters) still
   * tighten enough to fit inside QuestionArea.
   */
  @Builder
  private letterTemplateRow() {
    Row({ space: this.letterMetrics().gap }) {
      ForEach(this.letterSlots(), (item: LetterSlotView, _idx: number) => {
        Stack() {
          if (item.isMissing) {
            Column()
              .width(this.letterMetrics().width)
              .height(this.letterMetrics().height)
              .backgroundColor(LETTER_BG_MISSING)
              .borderRadius(6);
            Text('_')
              .id(`LetterSlotText_${item.idx}`)
              .fontSize(this.letterMetrics().fontPlaceholder)
              .fontWeight(FontWeight.Bold)
              .fontColor(LETTER_TEXT_MISSING);
          } else if (item.isPending) {
            Column()
              .width(this.letterMetrics().width)
              .height(this.letterMetrics().height)
              .backgroundColor(LETTER_BG_PENDING)
              .borderRadius(6);
            Text(item.glyph === '_' ? '_' : item.glyph)
              .id(`LetterSlotText_${item.idx}`)
              .fontSize(this.letterMetrics().fontPlaceholder)
              .fontWeight(FontWeight.Bold)
              .fontColor(LETTER_TEXT_PENDING);
          } else {
            Text(item.glyph)
              .id(`LetterSlotText_${item.idx}`)
              .fontSize(this.letterMetrics().fontFilled)
              .fontWeight(FontWeight.Bold)
              .fontColor(LETTER_TEXT_FILLED);
          }
        }
        .width(this.letterMetrics().width)
        .height(this.letterMetrics().height)
        .alignContent(Alignment.Center);
      }, (item: LetterSlotView, _idx: number): string =>
        letterSlotRenderKey(item.idx, item.glyph, item.isMissing, item.isPending));
    }
    .id('LetterTemplateRow')
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 12 });
  }

  @Builder
  private questionArea() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Text('Question')
          .fontSize(14)
          .fontColor('#457B9D');
        if (this.currentQuestionKind === QuestionKind.SentenceCloze) {
          Text(this.sentenceTemplate)
            .id('BattleSentenceClozePrompt')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D3557')
            .textAlign(TextAlign.Center)
            .margin({ top: 12 });
          Text(this.sentenceZh)
            .id('BattleSentenceClozeZh')
            .fontSize(15)
            .fontColor('#457B9D')
            .textAlign(TextAlign.Center)
            .margin({ top: 8 });
        } else {
          Text(this.prompt)
            .id('BattlePrompt')
            .fontSize((this.currentQuestionKind === QuestionKind.FillLetter
              || this.currentQuestionKind === QuestionKind.FillLetterMedium) ? 20 : 28)
            .fontWeight((this.currentQuestionKind === QuestionKind.FillLetter
              || this.currentQuestionKind === QuestionKind.FillLetterMedium)
              ? FontWeight.Medium : FontWeight.Bold)
            .fontColor((this.currentQuestionKind === QuestionKind.FillLetter
              || this.currentQuestionKind === QuestionKind.FillLetterMedium)
              ? '#457B9D' : '#1D3557')
            .margin({ top: (this.currentQuestionKind === QuestionKind.FillLetter
              || this.currentQuestionKind === QuestionKind.FillLetterMedium) ? 8 : 16 });
        }
        if (this.currentQuestionKind === QuestionKind.FillLetter
          || this.currentQuestionKind === QuestionKind.FillLetterMedium) {
          this.letterTemplateRow();
        }
        if (this.currentQuestionKind === QuestionKind.Spell) {
          SpellingArea({
            question: this.currentSpellQuestion,
            areaId: 'BattleSpellArea',
            onSpellComplete: (answer: string): void => {
              this.handleSpellSubmit(answer);
            },
            onWrongLetterTap: (): void => {
              this.handleSpellWrongLetterTap();
            },
          })
        }
        // Speaker button — tap re-plays the English pronunciation
        // regardless of the autoSpeak config. Rendered even when
        // TTS init failed so the UI layout is stable; the tap path
        // then silently no-ops via BattleAudioMixer voice availability.
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
              this.audio.speakWord(this.lastAnswerWord);
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

    }
    .id('QuestionArea')
    .layoutWeight(2)
    .height('100%')
    .padding(12);
  }

  @Builder
  private optionsRow() {
    if (this.currentQuestionKind !== QuestionKind.Spell) {
      Row({ space: 4 }) {
        ChoiceButton({
          text: this.options[0],
          choiceId: this.optionIdFor(0),
          state: this.optionStates[0],
          onTap: (t: string): void => {
            this.onOptionTap(t);
          },
        });
        ChoiceButton({
          text: this.options[1],
          choiceId: this.optionIdFor(1),
          state: this.optionStates[1],
          onTap: (t: string): void => {
            this.onOptionTap(t);
          },
        });
        ChoiceButton({
          text: this.options[2],
          choiceId: this.optionIdFor(2),
          state: this.optionStates[2],
          onTap: (t: string): void => {
            this.onOptionTap(t);
          },
        });
      }
      .width('100%')
      .id(this.currentQuestionKind === QuestionKind.SentenceCloze ? 'BattleOptionsRow_SentenceCloze' : 'BattleOptionsRow')
      .padding({ left: 20, right: 20, top: 16, bottom: 20 });
    } else {
      // Spell questions own their input via SpellingArea inside
      // questionArea(); reserve a small bottom padding so the page
      // layout doesn't snap up when transitioning to a Spell.
      Column()
        .id('BattleOptionsRow_SpellPlaceholder')
        .width('100%')
        .height(20);
    }
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
            Stack({ alignContent: Alignment.Top }) {
              CharacterCard({
                kind: CharacterKind.Mage,
                name: this.playerName,
                hp: this.playerHp,
                maxHp: this.playerMaxHp,
                sublabel: '',
                hurtPulse: this.playerHurtPulse,
                nudgePulse: this.playerNudgePulse,
                castPulse: this.playerCastPulse,
                assetPath: PLAYER_CHARACTER_ASSET,
                // V0.4.8: alt portrait toggled visible while a forward
                // projectile is mid-flight. Both images mount once and
                // are decoded once; the swap is opacity-only so it
                // never blocks the UI thread on a cast.
                altAssetPath: 'character/magican_fight.svg',
                altActive: this.playerFighting,
                // V0.6.x: swap to the "被攻击" pose for the duration of
                // each hurt-pulse window. CharacterCard owns the timing
                // (true on impact, false on settle) so this prop is just
                // the asset path — no extra state plumbing here.
                hurtAssetPath: 'character/magican_beaten.svg',
              });
              Column() {
                this.playerDamageFloaters();
              }
              .width('100%')
              .margin({ top: -10 })
              .hitTestBehavior(HitTestMode.None);
            }
            .width('100%');
          }
          .id('PlayerArea')
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center);

          this.questionArea();

          Column() {
            Stack({ alignContent: Alignment.Top }) {
              Stack({ alignContent: Alignment.TopEnd }) {
                CharacterCard({
                  kind: CharacterKind.Slime,
                  name: this.currentMonster.name,
                  hp: this.monsterHp,
                  maxHp: this.monsterMaxHp,
                  sublabel: `Monster ${this.monsterIndex} / ${this.monsterTotal}`,
                  levelBadge: battleLevelLabelForMonsterLevel(this.currentMonster.level),
                  hurtPulse: this.monsterHurtPulse,
                  zoomPulse: this.monsterZoomPulse,
                  assetPath: assetPathForEntry(this.currentMonster),
                });
                if (this.currentMonsterBonus) {
                  Text('✨')
                    .id(`MonsterBonusStar_${this.monsterIndex}`)
                    .fontSize(22)
                    .margin({ top: 4, right: 8 });
                }
              }
              .width('100%');
              Column() {
                this.monsterDamageFloaters();
              }
              .width('100%')
              .margin({ top: -12 })
              .hitTestBehavior(HitTestMode.None);
            }
            .width('100%');
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

      this.bossIntroBubble();
      this.superBossIntroBanner();
      this.bossDefeatBubble();

      // Magic projectile overlays — sit between the battle scene and
      // the crit spectacle. Forward-firing orb travels mage -> monster
      // on correct answers (gold-recoloured & enlarged for combo
      // bursts); backward-firing orb travels monster -> mage on wrong
      // answers. Both ignore hit testing so option taps still land.
      MagicProjectile({
        projectilePulse: this.projectileForwardPulse,
        forward: true,
        intensity: this.projectileIntensity,
        // V0.4.8: stamp the answer word inside the orb so the cast
        // reinforces the spelling the player just produced.
        label: this.lastAnswerWord,
      });
      MagicProjectile({
        projectilePulse: this.projectileBackwardPulse,
        forward: false,
        intensity: 1,
        // V0.4.8: backward shot carries the same word so the kid
        // sees what they missed flying toward the mage.
        label: this.lastAnswerWord,
        accentCore: this.currentMonster.fill,
        // Glow tracks the core fill; outerOpacity 0.65 makes the
        // shared color read as a halo around the core orb.
        accentGlow: this.currentMonster.fill,
        accentRing: this.currentMonster.stroke,
      });

      // Crit spectacle layers — gold flash + expanding shockwave + big
      // floating damage number. CritOverlay sets hitTestBehavior =
      // Transparent so it never intercepts taps destined for the
      // ChoiceButtons.
      CritOverlay({ critPulse: this.critPulse, damage: this.critDamage });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F9FA')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
