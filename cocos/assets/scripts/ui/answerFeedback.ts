// Pure feedback color rules mirroring BattleView.tint(for:) and the
// feedback line colors (BattleView.swift:720-765). No 'cc' imports.

import { theme } from './theme';

export interface AnswerSelection {
    selected: string;
    correct: boolean;
}

/// Capsule fill for an answer option. While feedback is showing (locked),
/// the selected capsule turns green/red and the rest gray out.
export function capsuleColorHex(option: string, selection: AnswerSelection | null, locked: boolean): string {
    if (!locked || selection === null) {
        return theme.purple;
    }
    if (option !== selection.selected) {
        return theme.capsuleDisabled;
    }
    return selection.correct ? theme.capsuleCorrect : theme.capsuleWrong;
}

export function feedbackColorHex(outcome: { correct: boolean; comboTriggered: boolean }): string {
    if (outcome.comboTriggered) { return theme.gold; }
    return outcome.correct ? theme.feedbackGreen : theme.red;
}
