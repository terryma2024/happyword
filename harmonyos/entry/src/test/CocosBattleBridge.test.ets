import { describe, it, expect } from '@ohos/hypium';
import { Question, QuestionKind } from '../main/ets/models/Question';
import { BattleStatus } from '../main/ets/models/BattleState';
import { SessionResult } from '../main/ets/models/SessionResult';
import { IQuestionSource } from '../main/ets/services/IQuestionSource';
import { BattleConfig, BattleEngine } from '../main/ets/services/BattleEngine';
import { SoundKeys } from '../main/ets/services/AudioService';
import {
  MonsterArtShape,
  NativeMessage,
} from '../main/ets/services/CocosBridgeMessages';
import {
  CocosAnswerOutcomeEvent,
  CocosBattleBridge,
  CocosBattleBridgeCallbacks,
  CocosTransport,
  COCOS_FEEDBACK_HOLD_MS,
  COCOS_PLAYER_HURT_GRUNT_MS,
} from '../main/ets/services/CocosBattleBridge';
import { cocosImageKeyForCatalogIndex } from '../main/ets/services/BattleArtCatalog';

// ── Deterministic question sources ───────────────────────────────────────────

class StubQuestionSource implements IQuestionSource {
  nextQuestion(_lastWordId?: string): Question {
    const q: Question = new Question();
    q.kind = QuestionKind.Choice;
    q.promptZh = '猫';
    q.answer = 'cat';
    q.options = ['cat', 'dog', 'pig'];
    q.wordId = 'w-cat';
    return q;
  }
}

/** Always serves the same two-blank medium fill-letter question shape. */
class MediumQuestionSource implements IQuestionSource {
  nextQuestion(_lastWordId?: string): Question {
    const q: Question = new Question();
    q.kind = QuestionKind.FillLetterMedium;
    q.promptZh = '猫';
    q.answer = 'cat';
    q.wordId = 'w-cat';
    q.letterTemplateBase = 'c__';
    q.missingIndices = [1, 2];
    q.letterOptionsSteps = [['a', 'x', 'y'], ['t', 'p', 'q']];
    q.letterAnswers = ['a', 't'];
    return q;
  }
}

// ── Fakes ────────────────────────────────────────────────────────────────────

class FakeTransport implements CocosTransport {
  sent: string[] = [];
  private handler: (json: string) => void = (_json: string): void => {};

  send(json: string): void {
    this.sent.push(json);
  }

  setHandler(handler: (json: string) => void): void {
    this.handler = handler;
  }

  inject(json: string): void {
    this.handler(json);
  }

  clear(): void {
    this.sent = [];
  }

  sentTypes(): string[] {
    const out: string[] = [];
    for (let i = 0; i < this.sent.length; i++) {
      out.push((JSON.parse(this.sent[i]) as NativeMessage).type);
    }
    return out;
  }

  lastPayloadOfType(type: string): Record<string, Object> | undefined {
    for (let i = this.sent.length - 1; i >= 0; i--) {
      const msg: NativeMessage = JSON.parse(this.sent[i]) as NativeMessage;
      if (msg.type === type) {
        return msg.payload;
      }
    }
    return undefined;
  }
}

class ScheduledCall {
  fn: () => void = (): void => {};
  ms: number = 0;
}

class FakeScheduler {
  calls: ScheduledCall[] = [];

  schedule(fn: () => void, ms: number): void {
    const call: ScheduledCall = new ScheduledCall();
    call.fn = fn;
    call.ms = ms;
    this.calls.push(call);
  }

  /** Run and drain everything currently scheduled (not re-entrant safe; fine for tests). */
  runAll(): void {
    const pending: ScheduledCall[] = this.calls;
    this.calls = [];
    for (let i = 0; i < pending.length; i++) {
      pending[i].fn();
    }
  }
}

class RecordingCallbacks implements CocosBattleBridgeCallbacks {
  finishResults: SessionResult[] = [];
  sfx: string[] = [];
  spoken: string[] = [];
  autoSpoken: string[] = [];
  readyCount: number = 0;
  answerEvents: CocosAnswerOutcomeEvent[] = [];

  onFinish(result: SessionResult): void {
    this.finishResults.push(result);
  }

  onReady(): void {
    this.readyCount += 1;
  }

  onAnswerOutcome(event: CocosAnswerOutcomeEvent): void {
    this.answerEvents.push(event);
  }

  playSfx(soundKey: string): void {
    this.sfx.push(soundKey);
  }

  speakWord(word: string): void {
    this.spoken.push(word);
  }

  autoSpeakWord(word: string, _questionKind: string): void {
    this.autoSpoken.push(word);
  }
}

// ── Harness ──────────────────────────────────────────────────────────────────

class BridgeHarness {
  engine: BattleEngine;
  transport: FakeTransport;
  scheduler: FakeScheduler;
  callbacks: RecordingCallbacks;
  bridge: CocosBattleBridge;

  constructor(engine: BattleEngine) {
    this.engine = engine;
    this.transport = new FakeTransport();
    this.scheduler = new FakeScheduler();
    this.callbacks = new RecordingCallbacks();
    const scheduler: FakeScheduler = this.scheduler;
    this.bridge = new CocosBattleBridge(
      engine,
      this.transport,
      this.callbacks,
      undefined,
      (fn: () => void, ms: number): void => {
        scheduler.schedule(fn, ms);
      },
    );
  }

  injectReady(): void {
    this.transport.inject('{"v":1,"type":"battle/ready","payload":{}}');
  }

  injectSubmit(option: string): void {
    this.transport.inject(`{"v":1,"type":"battle/submitOption","payload":{"option":"${option}"}}`);
  }
}

function makeHarness(monstersTotal: number, monsterMaxHp: number, playerMaxHp: number,
  source?: IQuestionSource): BridgeHarness {
  const bc: BattleConfig = new BattleConfig();
  bc.monstersTotal = monstersTotal;
  bc.monsterMaxHp = monsterMaxHp;
  bc.playerMaxHp = playerMaxHp;
  bc.startingSeconds = 300;
  bc.rng = (): number => 0.99;
  const src: IQuestionSource = source !== undefined ? source : new StubQuestionSource();
  return new BridgeHarness(new BattleEngine(src, bc));
}

const READY_TYPES: string = 'battle/init,battle/state,battle/question,battle/bossIntro';

export default function cocosBattleBridgeTest() {
  describe('CocosBattleBridge', () => {
    it('readySendsInitStateQuestionAndBossIntro', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      h.injectReady();

      expect(h.bridge.isReady).assertTrue();
      expect(h.transport.sentTypes().join(',')).assertEqual(READY_TYPES);

      const init: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/init');
      expect(init !== undefined).assertTrue();
      expect(init!['playerMaxHp'] as number).assertEqual(10);
      expect(init!['monsterMaxHp'] as number).assertEqual(5);
      expect(init!['monstersTotal'] as number).assertEqual(2);
      expect(init!['startingSeconds'] as number).assertEqual(300);

      const state: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/state');
      expect(state !== undefined).assertTrue();
      expect(state!['status'] as string).assertEqual('playing');
      const monster: MonsterArtShape = state!['monster'] as MonsterArtShape;
      expect(monster.catalogIndex).assertEqual(1);
      expect(monster.imageKey).assertEqual('CharacterSlime');
      expect(monster.levelLabel).assertEqual('L1');

      const question: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/question');
      expect(question !== undefined).assertTrue();
      expect(question!['answer'] as string).assertEqual('cat');
      expect(question!['kind'] as string).assertEqual('choice');

      const intro: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/bossIntro');
      expect(intro !== undefined).assertTrue();
      expect(intro!['monsterIndex'] as number).assertEqual(1);
      expect((intro!['introLineEn'] as string).length > 0).assertTrue();

      // First question auto-speaks the answer through the hook.
      expect(h.callbacks.autoSpoken.join(',')).assertEqual('cat');
      // Nothing rides the delay scheduler on ready.
      expect(h.scheduler.calls.length).assertEqual(0);
    });

    it('correctSubmitSendsAnimationStateThenQuestionAfterHold', 0, () => {
      const h: BridgeHarness = makeHarness(5, 5, 10);
      h.injectReady();
      h.transport.clear();

      h.injectSubmit('cat');

      expect(h.engine.getState().totalAnswers).assertEqual(1);
      expect(h.transport.sentTypes().join(',')).assertEqual('battle/animation,battle/state');
      const animation: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/animation');
      expect(animation!['correct'] as boolean).assertTrue();
      expect(animation!['projectileDirection'] as string).assertEqual('forward');
      expect(animation!['playerMotion'] as string).assertEqual('nudge');
      expect(animation!['monsterMotion'] as string).assertEqual('hurt');
      expect(animation!['feedbackText'] as string).assertEqual('Correct!');
      expect(animation!['damageLabel'] as string).assertEqual('-1!');
      expect(animation!['battleEnded'] as boolean).assertFalse();
      expect(h.callbacks.sfx.join(',')).assertEqual(SoundKeys.HIT_NORMAL);

      // Next question goes out only after the 650 ms feedback hold.
      expect(h.scheduler.calls.length).assertEqual(1);
      expect(h.scheduler.calls[0].ms).assertEqual(COCOS_FEEDBACK_HOLD_MS);
      h.scheduler.runAll();
      expect(h.transport.sentTypes().join(',')).assertEqual('battle/animation,battle/state,battle/question');
      // Auto-speak fires again for the next question (ready + post-hold).
      expect(h.callbacks.autoSpoken.join(',')).assertEqual('cat,cat');
    });

    it('wrongSubmitSendsBackwardAnimationWithoutMonsterDamage', 0, () => {
      const h: BridgeHarness = makeHarness(5, 5, 10);
      h.injectReady();
      h.transport.clear();
      const monsterHpBefore: number = h.engine.getState().monsterHp;

      h.injectSubmit('dog');

      expect(h.engine.getState().monsterHp).assertEqual(monsterHpBefore);
      expect(h.engine.getState().playerHp).assertEqual(9);
      expect(h.transport.sentTypes().join(',')).assertEqual('battle/animation,battle/state');
      const animation: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/animation');
      expect(animation!['correct'] as boolean).assertFalse();
      expect(animation!['projectileDirection'] as string).assertEqual('backward');
      expect(animation!['playerMotion'] as string).assertEqual('hurt');
      expect(animation!['monsterMotion'] as string).assertEqual('idle');
      expect(animation!['feedbackText'] as string).assertEqual('Correct answer: cat');

      // Wrong answer plays buzzer immediately and schedules the hurt grunt
      // for the projectile impact, then the question hold.
      expect(h.callbacks.sfx.join(',')).assertEqual(SoundKeys.ANSWER_WRONG);
      expect(h.scheduler.calls.length).assertEqual(2);
      expect(h.scheduler.calls[0].ms).assertEqual(COCOS_PLAYER_HURT_GRUNT_MS);
      expect(h.scheduler.calls[1].ms).assertEqual(COCOS_FEEDBACK_HOLD_MS);
      h.scheduler.runAll();
      expect(h.callbacks.sfx.join(','))
        .assertEqual(`${SoundKeys.ANSWER_WRONG},${SoundKeys.PLAYER_HURT}`);
      expect(h.transport.sentTypes().join(',')).assertEqual('battle/animation,battle/state,battle/question');
    });

    it('comboBurstSendsCritAnimationAndCritSfx', 0, () => {
      const h: BridgeHarness = makeHarness(5, 5, 10);
      h.injectReady();
      // Drain the feedback hold between answers — submits racing the hold
      // are dropped by design (see duplicateSubmitDuringFeedbackHoldIsDropped).
      h.injectSubmit('cat');
      h.scheduler.runAll();
      h.injectSubmit('cat');
      h.scheduler.runAll();
      h.transport.clear();
      h.callbacks.sfx = [];

      h.injectSubmit('cat');

      const animation: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/animation');
      expect(animation!['comboTriggered'] as boolean).assertTrue();
      expect(animation!['showsCritOverlay'] as boolean).assertTrue();
      expect(animation!['projectileIntensity'] as number).assertEqual(2);
      expect(animation!['playerMotion'] as string).assertEqual('cast');
      expect(animation!['monsterMotion'] as string).assertEqual('zoom');
      expect(animation!['feedbackText'] as string).assertEqual('Combo 3! Magic Burst x2');
      expect(animation!['damageLabel'] as string).assertEqual('-2!');
      expect(h.callbacks.sfx.join(',')).assertEqual(SoundKeys.HIT_CRIT);
    });

    it('monsterDefeatMidBattlePlaysDefeatCueAndIntroducesNextMonster', 0, () => {
      const h: BridgeHarness = makeHarness(2, 1, 10);
      h.injectReady();
      h.transport.clear();
      h.callbacks.sfx = [];

      h.injectSubmit('cat');

      const animation: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/animation');
      expect(animation!['playsMonsterDefeatCue'] as boolean).assertTrue();
      expect(animation!['battleEnded'] as boolean).assertFalse();
      expect(h.callbacks.sfx.join(','))
        .assertEqual(`${SoundKeys.HIT_NORMAL},${SoundKeys.MONSTER_DEFEAT}`);

      h.scheduler.runAll();
      expect(h.transport.sentTypes().join(','))
        .assertEqual('battle/animation,battle/state,battle/question,battle/bossIntro');
      const intro: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/bossIntro');
      expect(intro!['monsterIndex'] as number).assertEqual(2);
    });

    it('mediumStepAdvanceResendsStateAndQuestionImmediately', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10, new MediumQuestionSource());
      h.injectReady();
      h.transport.clear();
      h.callbacks.sfx = [];

      h.injectSubmit('a');

      // No damage, no animation, no hold: state + in-place question update only.
      expect(h.transport.sentTypes().join(',')).assertEqual('battle/state,battle/question');
      expect(h.scheduler.calls.length).assertEqual(0);
      expect(h.callbacks.sfx.join(',')).assertEqual(SoundKeys.HIT_NORMAL);
      const question: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/question');
      expect(question!['currentStep'] as number).assertEqual(1);
      expect(question!['letterTemplateBase'] as string).assertEqual('ca_');
    });

    it('spellWrongTapSendsPenaltyAnimationAndState', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      h.injectReady();
      h.transport.clear();
      h.callbacks.sfx = [];

      h.transport.inject('{"v":1,"type":"battle/spellWrongTap","payload":{}}');

      expect(h.engine.getState().playerHp).assertEqual(9);
      expect(h.transport.sentTypes().join(',')).assertEqual('battle/animation,battle/state');
      const animation: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/animation');
      expect(animation!['feedbackText'] as string).assertEqual('Try again');
      expect(animation!['projectileDirection'] as string).assertEqual('backward');
      expect(animation!['damageLabel'] as string).assertEqual('-1');
      expect(animation!['battleEnded'] as boolean).assertFalse();
      expect(h.callbacks.sfx.join(',')).assertEqual(SoundKeys.ANSWER_WRONG);
      // Hurt grunt rides the impact delay.
      expect(h.scheduler.calls.length).assertEqual(1);
      expect(h.scheduler.calls[0].ms).assertEqual(COCOS_PLAYER_HURT_GRUNT_MS);
      h.scheduler.runAll();
      expect(h.callbacks.sfx.join(','))
        .assertEqual(`${SoundKeys.ANSWER_WRONG},${SoundKeys.PLAYER_HURT}`);
    });

    it('spellWrongTapAtOneHpEndsBattleLost', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 1);
      h.injectReady();
      h.transport.clear();

      h.transport.inject('{"v":1,"type":"battle/spellWrongTap","payload":{}}');

      expect(h.transport.sentTypes().join(','))
        .assertEqual('battle/animation,battle/state,battle/end');
      const animation: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/animation');
      expect(animation!['battleEnded'] as boolean).assertTrue();
      const end: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/end');
      expect(end!['status'] as string).assertEqual('lost');
      h.scheduler.runAll();
      expect(h.callbacks.finishResults.length).assertEqual(1);
      expect(h.callbacks.finishResults[0].status).assertEqual(BattleStatus.Lost);
      expect(h.callbacks.sfx.indexOf(SoundKeys.DEFEAT) >= 0).assertTrue();
    });

    it('speakAnswerInvokesSpeakHookWithoutSceneTraffic', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      h.injectReady();
      h.transport.clear();

      h.transport.inject('{"v":1,"type":"battle/speakAnswer","payload":{}}');

      expect(h.callbacks.spoken.join(',')).assertEqual('cat');
      expect(h.transport.sent.length).assertEqual(0);
    });

    it('escapeInvokesFinishWithBuiltSessionResult', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      h.injectReady();
      h.transport.clear();

      h.transport.inject('{"v":1,"type":"battle/escape","payload":{}}');

      // Escape routes immediately — no battle/end and no delay.
      expect(h.transport.sent.length).assertEqual(0);
      expect(h.scheduler.calls.length).assertEqual(0);
      expect(h.callbacks.finishResults.length).assertEqual(1);
      expect(h.callbacks.finishResults[0].status).assertEqual(BattleStatus.Lost);
      expect(h.callbacks.finishResults[0].monstersTotal).assertEqual(2);
    });

    it('winningFinalMonsterSendsEndAndFinishesOnce', 0, () => {
      const h: BridgeHarness = makeHarness(1, 1, 10);
      h.injectReady();
      h.transport.clear();
      h.callbacks.sfx = [];

      h.injectSubmit('cat');

      expect(h.transport.sentTypes().join(','))
        .assertEqual('battle/animation,battle/state,battle/end');
      const end: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/end');
      expect(end!['status'] as string).assertEqual('won');
      // No defeat cue layered on the final blow (the end fanfare covers it).
      const animation: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/animation');
      expect(animation!['playsMonsterDefeatCue'] as boolean).assertFalse();
      expect(animation!['battleEnded'] as boolean).assertTrue();

      expect(h.scheduler.calls.length).assertEqual(1);
      expect(h.scheduler.calls[0].ms).assertEqual(COCOS_FEEDBACK_HOLD_MS);
      const call: ScheduledCall = h.scheduler.calls[0];
      call.fn();
      call.fn(); // double fire must not finish twice
      expect(h.callbacks.finishResults.length).assertEqual(1);
      expect(h.callbacks.finishResults[0].status).assertEqual(BattleStatus.Won);
      expect(h.callbacks.sfx.indexOf(SoundKeys.VICTORY) >= 0).assertTrue();
    });

    it('secondReadyResendsFullInitStateQuestion', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      h.injectReady();
      h.transport.clear();

      h.injectReady();

      // Full reset replay — but the monster-1 intro was already shown.
      expect(h.transport.sentTypes().join(','))
        .assertEqual('battle/init,battle/state,battle/question');
    });

    it('sendStateTickSendsStateOnly', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      h.injectReady();
      h.transport.clear();

      h.engine.tick(1);
      h.bridge.sendStateTick();

      expect(h.transport.sentTypes().join(',')).assertEqual('battle/state');
      const state: Record<string, Object> | undefined = h.transport.lastPayloadOfType('battle/state');
      expect(state!['remainingSeconds'] as number).assertEqual(299);
    });

    it('garbageMessagesAreIgnored', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);

      h.transport.inject('not json at all');
      h.transport.inject('{"v":1,"type":"battle/unknown","payload":{}}');

      expect(h.bridge.isReady).assertFalse();
      expect(h.transport.sent.length).assertEqual(0);
    });

    it('onReadyHookFiresOnEveryReady', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      expect(h.callbacks.readyCount).assertEqual(0);

      h.injectReady();
      expect(h.callbacks.readyCount).assertEqual(1);

      // Re-entry replay (CocosEngineHost synthetic ready) fires it again.
      h.injectReady();
      expect(h.callbacks.readyCount).assertEqual(2);
    });

    it('duplicateSubmitDuringFeedbackHoldIsDropped', 0, () => {
      const h: BridgeHarness = makeHarness(5, 5, 10);
      h.injectReady();
      h.transport.clear();

      h.injectSubmit('cat');
      // Second tap racing the 650 ms hold — engine must see exactly one answer.
      h.injectSubmit('cat');

      expect(h.engine.getState().totalAnswers).assertEqual(1);
      expect(h.transport.sentTypes().join(',')).assertEqual('battle/animation,battle/state');

      // After the hold elapses the next submit is accepted again.
      h.scheduler.runAll();
      h.injectSubmit('cat');
      expect(h.engine.getState().totalAnswers).assertEqual(2);
    });

    it('disposeMakesScheduledQuestionClosureANoOp', 0, () => {
      const h: BridgeHarness = makeHarness(5, 5, 10);
      h.injectReady();
      h.transport.clear();
      h.callbacks.autoSpoken = [];

      h.injectSubmit('cat');
      expect(h.scheduler.calls.length).assertEqual(1);
      h.bridge.dispose();
      h.scheduler.runAll();

      // No battle/question after the hold, no auto-speak callback.
      expect(h.transport.sentTypes().join(',')).assertEqual('battle/animation,battle/state');
      expect(h.callbacks.autoSpoken.length).assertEqual(0);
    });

    it('disposeMakesFinishHoldClosureANoOp', 0, () => {
      const h: BridgeHarness = makeHarness(1, 1, 10);
      h.injectReady();
      h.transport.clear();
      h.callbacks.sfx = [];

      h.injectSubmit('cat');
      expect(h.transport.lastPayloadOfType('battle/end') !== undefined).assertTrue();
      h.bridge.dispose();
      h.scheduler.runAll();

      // Page tore down before the 650 ms finish hold: no onFinish, no fanfare.
      expect(h.callbacks.finishResults.length).assertEqual(0);
      expect(h.callbacks.sfx.indexOf(SoundKeys.VICTORY)).assertEqual(-1);
    });

    it('messagesAndTicksAfterDisposeAreIgnored', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      h.injectReady();
      h.transport.clear();
      h.callbacks.spoken = [];

      h.bridge.dispose();

      h.injectSubmit('cat');
      h.transport.inject('{"v":1,"type":"battle/speakAnswer","payload":{}}');
      h.transport.inject('{"v":1,"type":"battle/escape","payload":{}}');
      h.bridge.sendStateTick();

      expect(h.engine.getState().totalAnswers).assertEqual(0);
      expect(h.transport.sent.length).assertEqual(0);
      expect(h.callbacks.spoken.length).assertEqual(0);
      expect(h.callbacks.finishResults.length).assertEqual(0);
    });

    // ── onAnswerOutcome (per-answer side-effects hook, v1.1.1) ───────────────

    it('answerOutcomeFiresOncePerAcceptedSubmitWithPreSubmitInfo', 0, () => {
      const h: BridgeHarness = makeHarness(5, 5, 10);
      h.injectReady();

      h.injectSubmit('cat');

      expect(h.callbacks.answerEvents.length).assertEqual(1);
      const event: CocosAnswerOutcomeEvent = h.callbacks.answerEvents[0];
      // The hook carries the PRE-submit question/monster info — the engine is
      // stateful, so the bridge must capture these before submitAnswer runs.
      expect(event.answeredWordId).assertEqual('w-cat');
      expect(event.preMonsterCatalogIndex).assertEqual(1);
      expect(event.outcome.correct).assertTrue();
      expect(event.outcome.advancedStep).assertFalse();

      // Next accepted submit fires it again — exactly once each.
      h.scheduler.runAll();
      h.injectSubmit('dog');
      expect(h.callbacks.answerEvents.length).assertEqual(2);
      expect(h.callbacks.answerEvents[1].outcome.correct).assertFalse();
    });

    it('answerOutcomeCarriesPreCatalogIndexAcrossMonsterDefeat', 0, () => {
      const h: BridgeHarness = makeHarness(2, 1, 10);
      h.injectReady();

      h.injectSubmit('cat'); // one-HP monster: defeat + next monster spawns

      expect(h.callbacks.answerEvents.length).assertEqual(1);
      const event: CocosAnswerOutcomeEvent = h.callbacks.answerEvents[0];
      // recordMonsterDefeat needs the PRE-answer catalog index (1), while the
      // encounter for the freshly spawned monster uses the post index (2).
      expect(event.preMonsterCatalogIndex).assertEqual(1);
      expect(event.postMonsterCatalogIndex).assertEqual(2);
      expect(event.outcome.monsterDefeated).assertTrue();
      expect(event.outcome.battleEnded).assertFalse();
    });

    it('answerOutcomeFiresForFinalBlowThatEndsBattle', 0, () => {
      const h: BridgeHarness = makeHarness(1, 1, 10);
      h.injectReady();

      h.injectSubmit('cat'); // final blow — battle Won

      expect(h.callbacks.answerEvents.length).assertEqual(1);
      const event: CocosAnswerOutcomeEvent = h.callbacks.answerEvents[0];
      expect(event.outcome.monsterDefeated).assertTrue();
      expect(event.outcome.battleEnded).assertTrue();
      // The engine does not advance the monster slot on the winning blow.
      expect(event.preMonsterCatalogIndex).assertEqual(1);
      expect(event.postMonsterCatalogIndex).assertEqual(1);
    });

    it('answerOutcomeFiresForMediumStepAdvance', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10, new MediumQuestionSource());
      h.injectReady();

      h.injectSubmit('a'); // step 0 correct — in-place advance, no damage

      expect(h.callbacks.answerEvents.length).assertEqual(1);
      const event: CocosAnswerOutcomeEvent = h.callbacks.answerEvents[0];
      expect(event.outcome.advancedStep).assertTrue();
      expect(event.answeredWordId).assertEqual('w-cat');
    });

    it('answerOutcomeNotFiredForDuplicateSubmitDuringFeedbackHold', 0, () => {
      const h: BridgeHarness = makeHarness(5, 5, 10);
      h.injectReady();

      h.injectSubmit('cat');
      // Second tap racing the 650 ms hold — dropped before the engine call,
      // so no side-effects hook either.
      h.injectSubmit('cat');

      expect(h.engine.getState().totalAnswers).assertEqual(1);
      expect(h.callbacks.answerEvents.length).assertEqual(1);
    });

    it('answerOutcomeNotFiredAfterDispose', 0, () => {
      const h: BridgeHarness = makeHarness(5, 5, 10);
      h.injectReady();
      h.bridge.dispose();

      h.injectSubmit('cat');

      expect(h.callbacks.answerEvents.length).assertEqual(0);
    });

    it('answerOutcomeNotFiredForSubmitsAfterBattleEnd', 0, () => {
      const h: BridgeHarness = makeHarness(1, 1, 10);
      h.injectReady();

      h.injectSubmit('cat'); // final blow — battle Won
      expect(h.callbacks.answerEvents.length).assertEqual(1);

      // Racing the finish hold and after it: status != Playing drops both.
      h.injectSubmit('cat');
      h.scheduler.runAll();
      h.injectSubmit('cat');
      expect(h.callbacks.answerEvents.length).assertEqual(1);
    });

    it('answerOutcomeNotFiredForSpellWrongTap', 0, () => {
      const h: BridgeHarness = makeHarness(2, 5, 10);
      h.injectReady();

      h.transport.inject('{"v":1,"type":"battle/spellWrongTap","payload":{}}');

      // Native BattlePage parity: handleSpellWrongLetterTap records no learning.
      expect(h.engine.getState().playerHp).assertEqual(9);
      expect(h.callbacks.answerEvents.length).assertEqual(0);
    });

    it('cocosImageKeyMapsCodexKeysToCharacterArtNames', 0, () => {
      expect(cocosImageKeyForCatalogIndex(1)).assertEqual('CharacterSlime');
      expect(cocosImageKeyForCatalogIndex(4)).assertEqual('CharacterPumpkinKing');
      expect(cocosImageKeyForCatalogIndex(8)).assertEqual('CharacterSnowQueen');
      // Wrap-around mirrors getMonsterByIndex.
      expect(cocosImageKeyForCatalogIndex(101)).assertEqual('CharacterSlime');
      expect(cocosImageKeyForCatalogIndex(0)).assertEqual('CharacterSlime');
    });
  });
}
