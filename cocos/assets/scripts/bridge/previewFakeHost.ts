// Browser-preview stand-in for the native host: cycles through one question
// per kind so renderers can be exercised without the JSB bridge. Pure TS.

import {
    BattleAnimationPayload, BattleInitPayload, BattleQuestionPayload, BattleStatePayload,
} from './messages';

const QUESTIONS: BattleQuestionPayload[] = [
    base({ kind: 'choice', promptZh: '苹果', answer: 'apple', options: ['orange', 'blueberry', 'apple'] }),
    base({ kind: 'fill-letter', promptZh: '苹果', answer: 'apple', letterTemplate: 'app_e', missingIndex: 3, letterOptions: ['l', 'r', 't'], letterAnswer: 'l' }),
    base({
        kind: 'fill-letter-medium', promptZh: '香蕉', answer: 'banana', letterTemplateBase: 'b_nan_',
        missingIndices: [1, 5], letterOptionsSteps: [['a', 'e', 'o'], ['a', 'i', 'u']], letterAnswers: ['a', 'a'],
    }),
    base({
        kind: 'spell', promptZh: '苹果', answer: 'apple',
        spellLetters: ['a', 'p', 'p', 'l', 'e'], spellRevealedMask: [true, false, false, false, false],
        spellPool: ['p', 'l', 'x', 'p', 'e', 'k'],
    }),
    base({
        kind: 'sentence-cloze', promptZh: '苹果', answer: 'apple', options: ['orange', 'apple', 'grape'],
        sentenceTemplate: 'I eat an ____ every day.', sentenceZh: '我每天吃一个苹果。',
    }),
];

function base(overrides: Partial<BattleQuestionPayload>): BattleQuestionPayload {
    return {
        wordId: 'w-preview', kind: 'choice', promptZh: '', answer: '', options: [],
        letterTemplate: '', missingIndex: -1, letterOptions: [], letterAnswer: '',
        letterTemplateBase: '', missingIndices: [], letterOptionsSteps: [], letterAnswers: [],
        currentStep: 0, spellLetters: [], spellRevealedMask: [], spellPool: [],
        sentenceTemplate: '', sentenceZh: '',
        ...overrides,
    };
}

export class PreviewFakeHost {
    private index = 0;
    private monsterHp = 5;
    private streak = 0;

    initPayload(): BattleInitPayload {
        return {
            playerMaxHp: 10, monsterMaxHp: 5, monstersTotal: 5, startingSeconds: 300,
            playerArt: { idle: 'CharacterMagician', fight: 'CharacterMagicianFight', hurt: 'CharacterMagicianBeaten' },
        };
    }

    statePayload(): BattleStatePayload {
        return {
            playerHp: 10, playerMaxHp: 10, monsterHp: this.monsterHp, monsterMaxHp: 5,
            monsterIndex: 1, monstersTotal: 5, remainingSeconds: 297, comboCount: this.streak,
            status: 'playing',
            monster: { catalogIndex: 3, imageKey: 'CharacterSnowGoblin', name: 'Snow Goblin', levelLabel: 'L1', bonus: this.index % 2 === 1 },
        };
    }

    currentQuestion(): BattleQuestionPayload {
        return QUESTIONS[this.index % QUESTIONS.length];
    }

    /// Returns the message sequence the native host would send for this answer.
    submit(option: string): { animation: BattleAnimationPayload; state: BattleStatePayload; question: BattleQuestionPayload } {
        const question = this.currentQuestion();
        const correct = this.isCorrect(option, question);
        // Mirror the engine's combo: every 3rd consecutive correct bursts x2.
        const combo = correct && this.streak === 2;
        this.streak = correct ? (combo ? 0 : this.streak + 1) : 0;
        const damage = combo ? 2 : 1;
        if (correct) { this.monsterHp = Math.max(0, this.monsterHp - damage); }
        if (this.monsterHp === 0) { this.monsterHp = 5; }
        this.index += 1;
        return {
            animation: {
                projectileDirection: correct ? 'forward' : 'backward',
                projectileIntensity: damage,
                projectileLabel: question.answer,
                playerMotion: combo ? 'cast' : (correct ? 'nudge' : 'hurt'),
                monsterMotion: combo ? 'zoom' : (correct ? 'hurt' : 'idle'),
                feedbackText: combo ? `Combo 3! Magic Burst x${damage}`
                    : (correct ? 'Correct!' : `Correct answer: ${question.answer}`),
                showsCritOverlay: combo,
                damageLabel: `-${damage}!`,
                playsMonsterDefeatCue: false,
                correct, comboTriggered: combo, battleEnded: false,
            },
            state: this.statePayload(),
            question: this.currentQuestion(),
        };
    }

    private isCorrect(option: string, question: BattleQuestionPayload): boolean {
        switch (question.kind) {
            case 'fill-letter': return option === question.letterAnswer;
            case 'fill-letter-medium': return option === question.letterAnswers[question.currentStep];
            default: return option === question.answer;
        }
    }
}
