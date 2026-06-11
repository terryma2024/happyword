/**
 * ArkTS bridge codec for the Cocos battle scene ↔ native host channel.
 *
 * Contract: shared/contracts/cocos-battle-bridge/battle-bridge.schema.json
 * Envelope: { v: 1, type: string, payload: object }
 *
 * Ported from cocos/assets/scripts/bridge/messages.ts — same type strings,
 * same payload field names and optionality, same version check logic.
 *
 * Naming conventions:
 *   encodeX(...)  → string   — native→scene messages (native is the encoder)
 *   decodeSceneMessage(json) → SceneMessage | null
 *                             — scene→native messages (native is the decoder)
 */

// ── Typed envelope shapes for JSON.stringify ────────────────────────────────

interface PlayerArtShape {
  idle: string;
  fight: string;
  hurt: string;
}

interface MonsterArtShape {
  catalogIndex: number;
  imageKey: string;
  name: string;
  levelLabel: string;
  bonus: boolean;
}

interface InitPayloadShape {
  playerMaxHp: number;
  monsterMaxHp: number;
  monstersTotal: number;
  startingSeconds: number;
  playerArt: PlayerArtShape;
}

interface InitEnvelopeShape {
  v: number;
  type: string;
  payload: InitPayloadShape;
}

interface StatePayloadShape {
  playerHp: number;
  playerMaxHp: number;
  monsterHp: number;
  monsterMaxHp: number;
  monsterIndex: number;
  monstersTotal: number;
  remainingSeconds: number;
  comboCount: number;
  status: string;
  monster: MonsterArtShape;
}

interface StateEnvelopeShape {
  v: number;
  type: string;
  payload: StatePayloadShape;
}

interface QuestionPayloadShape {
  wordId: string;
  kind: string;
  promptZh: string;
  answer: string;
  options: string[];
  letterTemplate: string;
  missingIndex: number;
  letterOptions: string[];
  letterAnswer: string;
  letterTemplateBase: string;
  missingIndices: number[];
  letterOptionsSteps: string[][];
  letterAnswers: string[];
  currentStep: number;
  spellLetters: string[];
  spellRevealedMask: boolean[];
  spellPool: string[];
  sentenceTemplate: string;
  sentenceZh: string;
}

interface QuestionEnvelopeShape {
  v: number;
  type: string;
  payload: QuestionPayloadShape;
}

interface AnimationPayloadShape {
  projectileDirection: string;
  projectileIntensity: number;
  projectileLabel: string;
  playerMotion: string;
  monsterMotion: string;
  feedbackText: string;
  showsCritOverlay: boolean;
  damageLabel: string;
  playsMonsterDefeatCue: boolean;
  correct: boolean;
  comboTriggered: boolean;
  battleEnded: boolean;
}

interface AnimationEnvelopeShape {
  v: number;
  type: string;
  payload: AnimationPayloadShape;
}

interface BossIntroPayloadShape {
  monsterIndex: number;
  name: string;
  introLineEn: string;
  introLineZh: string;
}

interface BossIntroEnvelopeShape {
  v: number;
  type: string;
  payload: BossIntroPayloadShape;
}

interface EndPayloadShape {
  status: string;
}

interface EndEnvelopeShape {
  v: number;
  type: string;
  payload: EndPayloadShape;
}

interface PingPayloadShape {
  echo: string;
}

interface PingEnvelopeShape {
  v: number;
  type: string;
  payload: PingPayloadShape;
}

// ── Typed raw envelope for parsing (scene → native) ─────────────────────────

interface RawEnvelope {
  v: number;
  type: string;
  payload: Record<string, Object>;
}

// ── Discriminated union: scene → native ─────────────────────────────────────

export class SceneReadyMessage {
  readonly kind: string = 'battle/ready';
}

export class SceneSubmitOptionMessage {
  readonly kind: string = 'battle/submitOption';
  readonly option: string;
  constructor(option: string) {
    this.option = option;
  }
}

export class SceneSpellWrongTapMessage {
  readonly kind: string = 'battle/spellWrongTap';
}

export class SceneSpeakAnswerMessage {
  readonly kind: string = 'battle/speakAnswer';
}

export class SceneEscapeMessage {
  readonly kind: string = 'battle/escape';
}

export class ScenePongMessage {
  readonly kind: string = 'battle/pong';
  readonly echo: string;
  constructor(echo: string) {
    this.echo = echo;
  }
}

/**
 * Discriminated union of all messages the scene may send to native.
 * Discriminate on `kind`.
 */
export type SceneMessage =
  | SceneReadyMessage
  | SceneSubmitOptionMessage
  | SceneSpellWrongTapMessage
  | SceneSpeakAnswerMessage
  | SceneEscapeMessage
  | ScenePongMessage;

// ── Raw envelope export (for test helpers) ───────────────────────────────────

/**
 * Envelope returned by JSON.parse — consumers read `v`, `type`, `payload`.
 */
export class NativeMessage {
  v: number = 0;
  type: string = '';
  payload: Record<string, Object> = {};
}

// ── Scene→Native decoder ─────────────────────────────────────────────────────

const SCENE_TYPES: Set<string> = new Set<string>([
  'battle/ready',
  'battle/submitOption',
  'battle/spellWrongTap',
  'battle/speakAnswer',
  'battle/escape',
  'battle/pong',
]);

/**
 * Parse a JSON string sent by the Cocos battle scene to native.
 * Returns null for non-JSON, wrong version, or unknown type.
 */
export function decodeSceneMessage(json: string): SceneMessage | null {
  let raw: RawEnvelope;
  try {
    raw = JSON.parse(json) as RawEnvelope;
  } catch {
    return null;
  }
  if (raw.v !== 1 || typeof raw.type !== 'string' || !SCENE_TYPES.has(raw.type)) {
    return null;
  }
  const payload: Record<string, Object> = raw.payload ?? {};
  if (raw.type === 'battle/ready') {
    return new SceneReadyMessage();
  }
  if (raw.type === 'battle/submitOption') {
    const opt: Object | undefined = payload['option'];
    return new SceneSubmitOptionMessage(typeof opt === 'string' ? opt : '');
  }
  if (raw.type === 'battle/spellWrongTap') {
    return new SceneSpellWrongTapMessage();
  }
  if (raw.type === 'battle/speakAnswer') {
    return new SceneSpeakAnswerMessage();
  }
  if (raw.type === 'battle/escape') {
    return new SceneEscapeMessage();
  }
  if (raw.type === 'battle/pong') {
    const echo: Object | undefined = payload['echo'];
    return new ScenePongMessage(typeof echo === 'string' ? echo : '');
  }
  return null;
}

// ── Native→Scene encoders ────────────────────────────────────────────────────

/**
 * Encode a battle/init message (native → scene).
 */
export function encodeInit(
  playerMaxHp: number,
  monsterMaxHp: number,
  monstersTotal: number,
  startingSeconds: number,
  playerArt: PlayerArtShape,
): string {
  const envelope: InitEnvelopeShape = {
    v: 1,
    type: 'battle/init',
    payload: {
      playerMaxHp,
      monsterMaxHp,
      monstersTotal,
      startingSeconds,
      playerArt,
    },
  };
  return JSON.stringify(envelope);
}

/**
 * Encode a battle/state message (native → scene).
 */
export function encodeState(
  playerHp: number,
  playerMaxHp: number,
  monsterHp: number,
  monsterMaxHp: number,
  monsterIndex: number,
  monstersTotal: number,
  remainingSeconds: number,
  comboCount: number,
  status: string,
  monster: MonsterArtShape,
): string {
  const envelope: StateEnvelopeShape = {
    v: 1,
    type: 'battle/state',
    payload: {
      playerHp,
      playerMaxHp,
      monsterHp,
      monsterMaxHp,
      monsterIndex,
      monstersTotal,
      remainingSeconds,
      comboCount,
      status,
      monster,
    },
  };
  return JSON.stringify(envelope);
}

/**
 * Encode a battle/question message (native → scene).
 * Accepts the typed question payload directly.
 */
export function encodeQuestion(payload: QuestionPayloadShape): string {
  const envelope: QuestionEnvelopeShape = {
    v: 1,
    type: 'battle/question',
    payload,
  };
  return JSON.stringify(envelope);
}

/**
 * Encode a battle/animation message (native → scene).
 */
export function encodeAnimation(
  projectileDirection: string,
  projectileIntensity: number,
  projectileLabel: string,
  playerMotion: string,
  monsterMotion: string,
  feedbackText: string,
  showsCritOverlay: boolean,
  damageLabel: string,
  playsMonsterDefeatCue: boolean,
  correct: boolean,
  comboTriggered: boolean,
  battleEnded: boolean,
): string {
  const envelope: AnimationEnvelopeShape = {
    v: 1,
    type: 'battle/animation',
    payload: {
      projectileDirection,
      projectileIntensity,
      projectileLabel,
      playerMotion,
      monsterMotion,
      feedbackText,
      showsCritOverlay,
      damageLabel,
      playsMonsterDefeatCue,
      correct,
      comboTriggered,
      battleEnded,
    },
  };
  return JSON.stringify(envelope);
}

/**
 * Encode a battle/bossIntro message (native → scene).
 */
export function encodeBossIntro(
  monsterIndex: number,
  name: string,
  introLineEn: string,
  introLineZh: string,
): string {
  const envelope: BossIntroEnvelopeShape = {
    v: 1,
    type: 'battle/bossIntro',
    payload: { monsterIndex, name, introLineEn, introLineZh },
  };
  return JSON.stringify(envelope);
}

/**
 * Encode a battle/end message (native → scene).
 */
export function encodeEnd(status: string): string {
  const envelope: EndEnvelopeShape = {
    v: 1,
    type: 'battle/end',
    payload: { status },
  };
  return JSON.stringify(envelope);
}

/**
 * Encode a battle/ping message (native → scene).
 */
export function encodePing(echo: string): string {
  const envelope: PingEnvelopeShape = {
    v: 1,
    type: 'battle/ping',
    payload: { echo },
  };
  return JSON.stringify(envelope);
}

// ── Re-exported types for callers ────────────────────────────────────────────

export type {
  PlayerArtShape,
  MonsterArtShape,
  QuestionPayloadShape,
  InitPayloadShape,
  StatePayloadShape,
  AnimationPayloadShape,
  BossIntroPayloadShape,
  EndPayloadShape,
  PingPayloadShape,
};
