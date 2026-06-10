import { describe, expect, it } from 'vitest';
import { parseNativeMessage, serializeScriptMessage } from '../assets/scripts/bridge/messages';

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
