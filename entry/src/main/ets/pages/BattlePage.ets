import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { CharacterCard, CharacterKind } from '../components/CharacterCard';
import { ChoiceButton, ChoiceState } from '../components/ChoiceButton';
import { WordRepository } from '../services/WordRepository';
import { QuestionGenerator } from '../services/QuestionGenerator';
import {
  BattleEngine,
  AnswerOutcome,
  TickOutcome,
  DEFAULT_PLAYER_HP,
  DEFAULT_MONSTER_HP,
  DEFAULT_MONSTERS_TOTAL,
  DEFAULT_STARTING_SECONDS,
} from '../services/BattleEngine';
import { BattleState, BattleStatus } from '../models/BattleState';
import { SessionResult } from '../models/SessionResult';
import { Question } from '../models/Question';

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

const FEEDBACK_MS: number = 650;
const TICK_MS: number = 1000;

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
  private feedbackTimer: number = -1;
  /**
   * Handle returned by setInterval for the 1Hz countdown driver. -1 when
   * no tick loop is running (before engine is ready, or after the battle
   * ended). Kept as a separate field from feedbackTimer so clearing one
   * never accidentally stops the other.
   */
  private tickTimer: number = -1;
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
    const repo: WordRepository = new WordRepository();
    repo.loadFromRawfile(ctx).then((): void => {
      const gen: QuestionGenerator = new QuestionGenerator(repo);
      const engine: BattleEngine = new BattleEngine(gen);
      engine.start();
      this.engine = engine;
      this.syncFromEngine();
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

    const outcome: AnswerOutcome = engine.submitAnswer(text);

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
    } else if (outcome.correct) {
      this.feedbackText = '正确！';
      this.feedbackColor = '#2ECC71';
    } else {
      this.feedbackText = `正确答案是 ${correctWord}`;
      this.feedbackColor = '#E74C3C';
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
  }
}
