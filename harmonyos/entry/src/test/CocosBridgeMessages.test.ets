import { describe, it, expect } from '@ohos/hypium';
import { FIXTURES } from './CocosBridgeFixtures';
import {
  decodeSceneMessage,
  encodeInit,
  encodeState,
  encodeQuestion,
  encodeAnimation,
  encodeBossIntro,
  encodeEnd,
  encodePing,
  SceneMessage,
  SceneSubmitOptionMessage,
  ScenePongMessage,
  PlayerArtShape,
  MonsterArtShape,
  QuestionPayloadShape,
  InitPayloadShape,
  StatePayloadShape,
  AnimationPayloadShape,
  BossIntroPayloadShape,
  EndPayloadShape,
  PingPayloadShape,
} from '../main/ets/services/CocosBridgeMessages';

// ── Typed fixture envelope helpers ────────────────────────────────────────────
// ArkTS requires each interface field to use a named type — no inline object
// type shapes allowed.

interface FixtureEnvelope {
  v: number;
  type: string;
}

interface InitFixture extends FixtureEnvelope {
  payload: InitPayloadShape;
}

interface StateFixture extends FixtureEnvelope {
  payload: StatePayloadShape;
}

interface QuestionFixture extends FixtureEnvelope {
  payload: QuestionPayloadShape;
}

interface AnimationFixture extends FixtureEnvelope {
  payload: AnimationPayloadShape;
}

interface BossIntroFixture extends FixtureEnvelope {
  payload: BossIntroPayloadShape;
}

interface EndFixture extends FixtureEnvelope {
  payload: EndPayloadShape;
}

interface PingFixture extends FixtureEnvelope {
  payload: PingPayloadShape;
}

// PongFixture and SubmitOptionFixture share the same payload shapes as Ping
// and SubmitOption — define them with named types rather than inline objects.

interface EchoPayload {
  echo: string;
}

interface OptionPayload {
  option: string;
}

interface PongFixture extends FixtureEnvelope {
  payload: EchoPayload;
}

interface SubmitOptionFixture extends FixtureEnvelope {
  payload: OptionPayload;
}

// ── Deep equality (key-order-insensitive, JSON-parsed values only) ────────────

/**
 * Recursive deep-equality helper for JSON-parsed values.
 * Uses Object.keys() for enumeration (ArkTS-safe — no prototype methods).
 */
function jsonDeepEqual(a: Object | null | undefined, b: Object | null | undefined): boolean {
  if (a === b) {
    return true;
  }
  if (a === null || a === undefined || b === null || b === undefined) {
    return false;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    const aa = a as Object[];
    const bb = b as Object[];
    if (aa.length !== bb.length) {
      return false;
    }
    for (let i: number = 0; i < aa.length; i++) {
      if (!jsonDeepEqual(aa[i], bb[i])) {
        return false;
      }
    }
    return true;
  }
  if (Array.isArray(a) || Array.isArray(b)) {
    return false;
  }
  if (typeof a === 'object' && typeof b === 'object') {
    const aRec = a as Record<string, Object>;
    const bRec = b as Record<string, Object>;
    const aKeys: string[] = Object.keys(aRec);
    const bKeys: string[] = Object.keys(bRec);
    if (aKeys.length !== bKeys.length) {
      return false;
    }
    for (const k of aKeys) {
      if (!Object.keys(bRec).includes(k)) {
        return false;
      }
      if (!jsonDeepEqual(aRec[k], bRec[k])) {
        return false;
      }
    }
    return true;
  }
  return false;
}

export default function cocosBridgeMessagesTest() {
  describe('CocosBridgeMessages — fixture gates', () => {
    // ── Coverage ──────────────────────────────────────────────────────────
    it('coversAllFixtures', 0, () => {
      expect(FIXTURES.size).assertLargerOrEqual(19);
    });

    // ── Scene→Native decode ───────────────────────────────────────────────
    it('decodesSceneReady', 0, () => {
      const raw: string = FIXTURES.get('ready') ?? '';
      const msg: SceneMessage | null = decodeSceneMessage(raw);
      expect(msg).not().assertNull();
      expect(msg?.kind).assertEqual('battle/ready');
    });

    it('decodesSceneSubmitOption', 0, () => {
      const raw: string = FIXTURES.get('submit-option') ?? '';
      const msg: SceneMessage | null = decodeSceneMessage(raw);
      expect(msg).not().assertNull();
      expect(msg?.kind).assertEqual('battle/submitOption');
      if (msg instanceof SceneSubmitOptionMessage) {
        const fix: SubmitOptionFixture = JSON.parse(raw) as SubmitOptionFixture;
        expect(msg.option).assertEqual(fix.payload.option);
      }
    });

    it('decodesSceneSpellWrongTap', 0, () => {
      const raw: string = FIXTURES.get('spell-wrong-tap') ?? '';
      const msg: SceneMessage | null = decodeSceneMessage(raw);
      expect(msg).not().assertNull();
      expect(msg?.kind).assertEqual('battle/spellWrongTap');
    });

    it('decodesSceneSpeakAnswer', 0, () => {
      const raw: string = FIXTURES.get('speak-answer') ?? '';
      const msg: SceneMessage | null = decodeSceneMessage(raw);
      expect(msg).not().assertNull();
      expect(msg?.kind).assertEqual('battle/speakAnswer');
    });

    it('decodesSceneEscape', 0, () => {
      const raw: string = FIXTURES.get('escape') ?? '';
      const msg: SceneMessage | null = decodeSceneMessage(raw);
      expect(msg).not().assertNull();
      expect(msg?.kind).assertEqual('battle/escape');
    });

    it('decodesScenePong', 0, () => {
      const raw: string = FIXTURES.get('pong') ?? '';
      const msg: SceneMessage | null = decodeSceneMessage(raw);
      expect(msg).not().assertNull();
      expect(msg?.kind).assertEqual('battle/pong');
      if (msg instanceof ScenePongMessage) {
        const fix: PongFixture = JSON.parse(raw) as PongFixture;
        expect(msg.echo).assertEqual(fix.payload.echo);
      }
    });

    // ── Native→Scene round-trips ──────────────────────────────────────────
    it('roundTripsInit', 0, () => {
      const raw: string = FIXTURES.get('init') ?? '';
      const fix: InitFixture = JSON.parse(raw) as InitFixture;
      const encoded: string = encodeInit(
        fix.payload.playerMaxHp,
        fix.payload.monsterMaxHp,
        fix.payload.monstersTotal,
        fix.payload.startingSeconds,
        fix.payload.playerArt,
      );
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsState', 0, () => {
      const raw: string = FIXTURES.get('state') ?? '';
      const fix: StateFixture = JSON.parse(raw) as StateFixture;
      const encoded: string = encodeState(
        fix.payload.playerHp,
        fix.payload.playerMaxHp,
        fix.payload.monsterHp,
        fix.payload.monsterMaxHp,
        fix.payload.monsterIndex,
        fix.payload.monstersTotal,
        fix.payload.remainingSeconds,
        fix.payload.comboCount,
        fix.payload.status,
        fix.payload.monster,
      );
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsQuestionChoice', 0, () => {
      const raw: string = FIXTURES.get('question-choice') ?? '';
      const fix: QuestionFixture = JSON.parse(raw) as QuestionFixture;
      const encoded: string = encodeQuestion(fix.payload);
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsQuestionFillLetter', 0, () => {
      const raw: string = FIXTURES.get('question-fill-letter') ?? '';
      const fix: QuestionFixture = JSON.parse(raw) as QuestionFixture;
      const encoded: string = encodeQuestion(fix.payload);
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsQuestionFillLetterMedium', 0, () => {
      const raw: string = FIXTURES.get('question-fill-letter-medium') ?? '';
      const fix: QuestionFixture = JSON.parse(raw) as QuestionFixture;
      const encoded: string = encodeQuestion(fix.payload);
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsQuestionSpell', 0, () => {
      const raw: string = FIXTURES.get('question-spell') ?? '';
      const fix: QuestionFixture = JSON.parse(raw) as QuestionFixture;
      const encoded: string = encodeQuestion(fix.payload);
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsQuestionSentenceCloze', 0, () => {
      const raw: string = FIXTURES.get('question-sentence-cloze') ?? '';
      const fix: QuestionFixture = JSON.parse(raw) as QuestionFixture;
      const encoded: string = encodeQuestion(fix.payload);
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsAnimationCorrect', 0, () => {
      const raw: string = FIXTURES.get('animation-correct') ?? '';
      const fix: AnimationFixture = JSON.parse(raw) as AnimationFixture;
      const p = fix.payload;
      const encoded: string = encodeAnimation(
        p.projectileDirection, p.projectileIntensity, p.projectileLabel,
        p.playerMotion, p.monsterMotion, p.feedbackText,
        p.showsCritOverlay, p.damageLabel, p.playsMonsterDefeatCue,
        p.correct, p.comboTriggered, p.battleEnded,
      );
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsAnimationCombo', 0, () => {
      const raw: string = FIXTURES.get('animation-combo') ?? '';
      const fix: AnimationFixture = JSON.parse(raw) as AnimationFixture;
      const p = fix.payload;
      const encoded: string = encodeAnimation(
        p.projectileDirection, p.projectileIntensity, p.projectileLabel,
        p.playerMotion, p.monsterMotion, p.feedbackText,
        p.showsCritOverlay, p.damageLabel, p.playsMonsterDefeatCue,
        p.correct, p.comboTriggered, p.battleEnded,
      );
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsAnimationWrong', 0, () => {
      const raw: string = FIXTURES.get('animation-wrong') ?? '';
      const fix: AnimationFixture = JSON.parse(raw) as AnimationFixture;
      const p = fix.payload;
      const encoded: string = encodeAnimation(
        p.projectileDirection, p.projectileIntensity, p.projectileLabel,
        p.playerMotion, p.monsterMotion, p.feedbackText,
        p.showsCritOverlay, p.damageLabel, p.playsMonsterDefeatCue,
        p.correct, p.comboTriggered, p.battleEnded,
      );
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsBossIntro', 0, () => {
      const raw: string = FIXTURES.get('boss-intro') ?? '';
      const fix: BossIntroFixture = JSON.parse(raw) as BossIntroFixture;
      const encoded: string = encodeBossIntro(
        fix.payload.monsterIndex,
        fix.payload.name,
        fix.payload.introLineEn,
        fix.payload.introLineZh,
      );
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsEnd', 0, () => {
      const raw: string = FIXTURES.get('end') ?? '';
      const fix: EndFixture = JSON.parse(raw) as EndFixture;
      const encoded: string = encodeEnd(fix.payload.status);
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    it('roundTripsPing', 0, () => {
      const raw: string = FIXTURES.get('ping') ?? '';
      const fix: PingFixture = JSON.parse(raw) as PingFixture;
      const encoded: string = encodePing(fix.payload.echo);
      expect(jsonDeepEqual(JSON.parse(encoded) as Object, fix as Object)).assertTrue();
    });

    // ── Error handling ────────────────────────────────────────────────────
    it('decodeSceneMessageRejectsUnknownType', 0, () => {
      const result: SceneMessage | null = decodeSceneMessage('{"v":1,"type":"battle/unknown","payload":{}}');
      expect(result).assertNull();
    });

    it('decodeSceneMessageRejectsWrongVersion', 0, () => {
      const result: SceneMessage | null = decodeSceneMessage('{"v":2,"type":"battle/ready","payload":{}}');
      expect(result).assertNull();
    });

    it('decodeSceneMessageRejectsNonJson', 0, () => {
      const result: SceneMessage | null = decodeSceneMessage('not json');
      expect(result).assertNull();
    });

    // ── Field-value spot checks ───────────────────────────────────────────
    it('encodeInitFieldValues', 0, () => {
      const art: PlayerArtShape = {
        idle: 'CharacterMagician',
        fight: 'CharacterMagicianFight',
        hurt: 'CharacterMagicianBeaten',
      };
      const json: string = encodeInit(10, 1, 2, 300, art);
      const fix: InitFixture = JSON.parse(json) as InitFixture;
      expect(fix.v).assertEqual(1);
      expect(fix.type).assertEqual('battle/init');
      expect(fix.payload.playerMaxHp).assertEqual(10);
      expect(fix.payload.monstersTotal).assertEqual(2);
      expect(fix.payload.startingSeconds).assertEqual(300);
    });

    it('encodeStateFieldValues', 0, () => {
      const monster: MonsterArtShape = {
        catalogIndex: 3,
        imageKey: 'CharacterSnowGoblin',
        name: 'Snow Goblin',
        levelLabel: 'L1',
        bonus: false,
      };
      const json: string = encodeState(9, 10, 1, 1, 1, 2, 297, 2, 'playing', monster);
      const fix: StateFixture = JSON.parse(json) as StateFixture;
      expect(fix.type).assertEqual('battle/state');
      expect(fix.payload.playerHp).assertEqual(9);
      expect(fix.payload.status).assertEqual('playing');
    });
  });

  // ── All-fixtures gate ─────────────────────────────────────────────────────
  describe('CocosBridgeMessages — all-fixtures gate', () => {
    it('allFixturesDecodeOrRoundTrip', 0, () => {
      const SCENE_TYPES: Set<string> = new Set<string>([
        'battle/ready', 'battle/submitOption', 'battle/spellWrongTap',
        'battle/speakAnswer', 'battle/escape', 'battle/pong',
      ]);
      let processed: number = 0;
      FIXTURES.forEach((raw: string, _name: string) => {
        const envelope: FixtureEnvelope = JSON.parse(raw) as FixtureEnvelope;
        const msgType: string = envelope.type;
        if (SCENE_TYPES.has(msgType)) {
          const decoded: SceneMessage | null = decodeSceneMessage(raw);
          expect(decoded).not().assertNull();
          processed++;
        } else if (msgType === 'battle/init') {
          const fix: InitFixture = JSON.parse(raw) as InitFixture;
          const enc: string = encodeInit(
            fix.payload.playerMaxHp, fix.payload.monsterMaxHp,
            fix.payload.monstersTotal, fix.payload.startingSeconds,
            fix.payload.playerArt,
          );
          expect(jsonDeepEqual(JSON.parse(enc) as Object, fix as Object)).assertTrue();
          processed++;
        } else if (msgType === 'battle/state') {
          const fix: StateFixture = JSON.parse(raw) as StateFixture;
          const enc: string = encodeState(
            fix.payload.playerHp, fix.payload.playerMaxHp,
            fix.payload.monsterHp, fix.payload.monsterMaxHp,
            fix.payload.monsterIndex, fix.payload.monstersTotal,
            fix.payload.remainingSeconds, fix.payload.comboCount,
            fix.payload.status, fix.payload.monster,
          );
          expect(jsonDeepEqual(JSON.parse(enc) as Object, fix as Object)).assertTrue();
          processed++;
        } else if (msgType === 'battle/question') {
          const fix: QuestionFixture = JSON.parse(raw) as QuestionFixture;
          const enc: string = encodeQuestion(fix.payload);
          expect(jsonDeepEqual(JSON.parse(enc) as Object, fix as Object)).assertTrue();
          processed++;
        } else if (msgType === 'battle/animation') {
          const fix: AnimationFixture = JSON.parse(raw) as AnimationFixture;
          const p = fix.payload;
          const enc: string = encodeAnimation(
            p.projectileDirection, p.projectileIntensity, p.projectileLabel,
            p.playerMotion, p.monsterMotion, p.feedbackText,
            p.showsCritOverlay, p.damageLabel, p.playsMonsterDefeatCue,
            p.correct, p.comboTriggered, p.battleEnded,
          );
          expect(jsonDeepEqual(JSON.parse(enc) as Object, fix as Object)).assertTrue();
          processed++;
        } else if (msgType === 'battle/bossIntro') {
          const fix: BossIntroFixture = JSON.parse(raw) as BossIntroFixture;
          const enc: string = encodeBossIntro(
            fix.payload.monsterIndex, fix.payload.name,
            fix.payload.introLineEn, fix.payload.introLineZh,
          );
          expect(jsonDeepEqual(JSON.parse(enc) as Object, fix as Object)).assertTrue();
          processed++;
        } else if (msgType === 'battle/end') {
          const fix: EndFixture = JSON.parse(raw) as EndFixture;
          const enc: string = encodeEnd(fix.payload.status);
          expect(jsonDeepEqual(JSON.parse(enc) as Object, fix as Object)).assertTrue();
          processed++;
        } else if (msgType === 'battle/ping') {
          const fix: PingFixture = JSON.parse(raw) as PingFixture;
          const enc: string = encodePing(fix.payload.echo);
          expect(jsonDeepEqual(JSON.parse(enc) as Object, fix as Object)).assertTrue();
          processed++;
        }
      });
      expect(processed).assertLargerOrEqual(19);
    });
  });
}
