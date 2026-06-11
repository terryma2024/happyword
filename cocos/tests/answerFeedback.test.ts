import { describe, expect, it } from 'vitest';
import { capsuleColorHex, feedbackColorHex } from '../assets/scripts/ui/answerFeedback';
import { theme } from '../assets/scripts/ui/theme';

describe('capsuleColorHex', () => {
    it('shows purple when input is unlocked', () => {
        expect(capsuleColorHex('apple', null, false)).toBe(theme.purple);
    });

    it('greens the selected option on a correct answer', () => {
        expect(capsuleColorHex('apple', { selected: 'apple', correct: true }, true)).toBe(theme.capsuleCorrect);
    });

    it('muted-reds the selected option on a wrong answer', () => {
        expect(capsuleColorHex('apple', { selected: 'apple', correct: false }, true)).toBe(theme.capsuleWrong);
    });

    it('grays unselected options while feedback shows', () => {
        expect(capsuleColorHex('orange', { selected: 'apple', correct: true }, true)).toBe(theme.capsuleDisabled);
    });
});

describe('feedbackColorHex', () => {
    it('gold for combo, green for correct, red for wrong', () => {
        expect(feedbackColorHex({ correct: true, comboTriggered: true })).toBe(theme.gold);
        expect(feedbackColorHex({ correct: true, comboTriggered: false })).toBe(theme.feedbackGreen);
        expect(feedbackColorHex({ correct: false, comboTriggered: false })).toBe(theme.red);
    });
});
