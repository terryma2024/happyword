// Pure view-model helpers (no 'cc' imports — vitest runs these headless).

import type { BattleQuestionPayload } from '../bridge/messages';

export function formatCountdown(totalSeconds: number): string {
    const seconds = Math.max(0, Math.floor(totalSeconds));
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
}

/// Which strings the bottom answer row shows for a question. Spell uses a
/// letter pool rendered by the question panel instead (Phase 3).
export function optionsForQuestion(question: BattleQuestionPayload): string[] {
    switch (question.kind) {
        case 'choice':
        case 'sentence-cloze':
            return question.options;
        case 'fill-letter':
            return question.letterOptions;
        case 'fill-letter-medium':
            return question.letterOptionsSteps[question.currentStep] ?? [];
        case 'spell':
            return [];
    }
}
