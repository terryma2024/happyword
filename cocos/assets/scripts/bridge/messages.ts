// Bridge message codecs shared by the Cocos battle scene and its tests.
// Pure TS — must NOT import from 'cc' so vitest can run it headless.
// Contract: shared/contracts/cocos-battle-bridge/ (envelope {v:1,type,payload}).

export interface MonsterArtPayload {
    catalogIndex: number;
    imageKey: string;
    name: string;
    levelLabel: string;
    bonus: boolean;
}

export interface BattleInitPayload {
    playerMaxHp: number;
    monsterMaxHp: number;
    monstersTotal: number;
    startingSeconds: number;
    playerArt: { idle: string; fight: string; hurt: string };
}

export interface BattleStatePayload {
    playerHp: number;
    playerMaxHp: number;
    monsterHp: number;
    monsterMaxHp: number;
    monsterIndex: number;
    monstersTotal: number;
    remainingSeconds: number;
    comboCount: number;
    status: 'ready' | 'playing' | 'won' | 'lost';
    monster: MonsterArtPayload;
}

export interface BattleQuestionPayload {
    wordId: string;
    kind: 'choice' | 'fill-letter' | 'fill-letter-medium' | 'spell' | 'sentence-cloze';
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

export interface BattleAnimationPayload {
    projectileDirection: 'forward' | 'backward';
    projectileIntensity: number;
    projectileLabel: string;
    playerMotion: 'idle' | 'nudge' | 'hurt' | 'cast' | 'zoom';
    monsterMotion: 'idle' | 'nudge' | 'hurt' | 'cast' | 'zoom';
    feedbackText: string;
    showsCritOverlay: boolean;
    damageLabel: string;
    playsMonsterDefeatCue: boolean;
    correct: boolean;
    comboTriggered: boolean;
    battleEnded: boolean;
}

export interface BattleBossIntroPayload {
    monsterIndex: number;
    name: string;
    introLineEn: string;
    introLineZh: string;
}

export interface BattleEndPayload {
    status: 'won' | 'lost';
}

export type NativeToScriptMessage =
    | { type: 'battle/init'; payload: BattleInitPayload }
    | { type: 'battle/state'; payload: BattleStatePayload }
    | { type: 'battle/question'; payload: BattleQuestionPayload }
    | { type: 'battle/animation'; payload: BattleAnimationPayload }
    | { type: 'battle/bossIntro'; payload: BattleBossIntroPayload }
    | { type: 'battle/end'; payload: BattleEndPayload }
    | { type: 'battle/ping'; payload: { echo: string } };

export type ScriptToNativeMessage =
    | { type: 'battle/ready'; payload: Record<string, never> }
    | { type: 'battle/submitOption'; payload: { option: string } }
    | { type: 'battle/spellWrongTap'; payload: Record<string, never> }
    | { type: 'battle/speakAnswer'; payload: Record<string, never> }
    | { type: 'battle/escape'; payload: Record<string, never> }
    | { type: 'battle/pong'; payload: { echo: string } };

const NATIVE_TYPES = new Set<string>([
    'battle/init', 'battle/state', 'battle/question', 'battle/animation',
    'battle/bossIntro', 'battle/end', 'battle/ping',
]);

export function parseNativeMessage(json: string): NativeToScriptMessage | null {
    try {
        const raw = JSON.parse(json);
        if (raw?.v !== 1 || typeof raw.type !== 'string' || !NATIVE_TYPES.has(raw.type)) {
            console.warn(`[bridge] ignoring message: ${String(raw?.type)}`);
            return null;
        }
        return { type: raw.type, payload: raw.payload } as NativeToScriptMessage;
    } catch {
        console.warn('[bridge] ignoring non-JSON message');
        return null;
    }
}

export function serializeScriptMessage(msg: ScriptToNativeMessage): string {
    return JSON.stringify({ v: 1, type: msg.type, payload: msg.payload });
}
