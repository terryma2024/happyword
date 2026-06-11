import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parseNativeMessage, serializeScriptMessage } from '../assets/scripts/bridge/messages';

const FIXTURES_DIR = join(__dirname, '../../shared/fixtures/cocos-battle-bridge');
const SCRIPT_TO_NATIVE = new Set([
    'battle/ready', 'battle/submitOption', 'battle/spellWrongTap',
    'battle/speakAnswer', 'battle/escape', 'battle/pong',
]);

describe('parseNativeMessage', () => {
    it('parses a battle/state envelope', () => {
        const json = JSON.stringify({
            v: 1, type: 'battle/state', payload: {
                playerHp: 9, playerMaxHp: 10, monsterHp: 1, monsterMaxHp: 1,
                monsterIndex: 1, monstersTotal: 2, remainingSeconds: 297,
                comboCount: 2, status: 'playing',
                monster: { catalogIndex: 3, imageKey: 'CharacterSnowGoblin', name: 'Snow Goblin', levelLabel: 'L1', bonus: false },
            },
        });
        const msg = parseNativeMessage(json);
        expect(msg?.type).toBe('battle/state');
        if (msg?.type === 'battle/state') expect(msg.payload.playerHp).toBe(9);
    });

    it('returns null for unknown type or wrong version', () => {
        expect(parseNativeMessage('{"v":1,"type":"nope","payload":{}}')).toBeNull();
        expect(parseNativeMessage('{"v":2,"type":"battle/state","payload":{}}')).toBeNull();
        expect(parseNativeMessage('not json')).toBeNull();
    });
});

describe('serializeScriptMessage', () => {
    it('wraps submitOption in a v1 envelope', () => {
        const json = serializeScriptMessage({ type: 'battle/submitOption', payload: { option: 'apple' } });
        expect(JSON.parse(json)).toEqual({ v: 1, type: 'battle/submitOption', payload: { option: 'apple' } });
    });
});

describe('shared contract fixtures', () => {
    const files = readdirSync(FIXTURES_DIR).filter(f => f.endsWith('.json'));

    it('covers every fixture file', () => {
        expect(files.length).toBeGreaterThanOrEqual(19);
    });

    for (const file of files) {
        const raw = readFileSync(join(FIXTURES_DIR, file), 'utf8');
        const envelope = JSON.parse(raw);

        if (SCRIPT_TO_NATIVE.has(envelope.type)) {
            it(`round-trips script fixture ${file}`, () => {
                const serialized = serializeScriptMessage({ type: envelope.type, payload: envelope.payload });
                expect(JSON.parse(serialized)).toEqual(envelope);
            });
        } else {
            it(`parses native fixture ${file}`, () => {
                const msg = parseNativeMessage(raw);
                expect(msg).not.toBeNull();
                expect(msg?.type).toBe(envelope.type);
            });
        }
    }
});
