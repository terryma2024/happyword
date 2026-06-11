import { describe, expect, it } from 'vitest';
import { formatCountdown, optionsForQuestion } from '../assets/scripts/ui/format';
import type { BattleQuestionPayload } from '../assets/scripts/bridge/messages';

function question(overrides: Partial<BattleQuestionPayload>): BattleQuestionPayload {
    return {
        wordId: 'w', kind: 'choice', promptZh: '苹果', answer: 'apple', options: [],
        letterTemplate: '', missingIndex: -1, letterOptions: [], letterAnswer: '',
        letterTemplateBase: '', missingIndices: [], letterOptionsSteps: [], letterAnswers: [],
        currentStep: 0, spellLetters: [], spellRevealedMask: [], spellPool: [],
        sentenceTemplate: '', sentenceZh: '',
        ...overrides,
    };
}

describe('formatCountdown', () => {
    it('formats minutes and zero-padded seconds', () => {
        expect(formatCountdown(297)).toBe('4:57');
        expect(formatCountdown(60)).toBe('1:00');
        expect(formatCountdown(5)).toBe('0:05');
        expect(formatCountdown(-3)).toBe('0:00');
    });
});

describe('optionsForQuestion', () => {
    it('uses options for choice and sentence-cloze', () => {
        expect(optionsForQuestion(question({ kind: 'choice', options: ['a', 'b', 'c'] }))).toEqual(['a', 'b', 'c']);
        expect(optionsForQuestion(question({ kind: 'sentence-cloze', options: ['x', 'y', 'z'] }))).toEqual(['x', 'y', 'z']);
    });

    it('uses letterOptions for fill-letter', () => {
        expect(optionsForQuestion(question({ kind: 'fill-letter', letterOptions: ['l', 'r', 't'] }))).toEqual(['l', 'r', 't']);
    });

    it('uses the current step options for fill-letter-medium', () => {
        const q = question({
            kind: 'fill-letter-medium',
            letterOptionsSteps: [['a', 'e', 'o'], ['a', 'i', 'u']],
            currentStep: 1,
        });
        expect(optionsForQuestion(q)).toEqual(['a', 'i', 'u']);
    });

    it('returns empty for spell (pool rendered separately)', () => {
        expect(optionsForQuestion(question({ kind: 'spell', spellPool: ['p', 'l'] }))).toEqual([]);
    });
});
