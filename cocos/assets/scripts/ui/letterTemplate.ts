// Port of LetterTemplateLayout from ios/WordMagicGame/Features/CoreLoop/BattleView.swift:8-68.
// Pure TS — no 'cc' imports so vitest can run it headless.

export interface LetterTemplateSlot {
    glyph: string;
    originalIndex: number;
    isMissing: boolean;
    isPending: boolean;
}

export interface LetterTemplateMetrics {
    width: number;
    height: number;
    gap: number;
    filledFontSize: number;
    placeholderFontSize: number;
}

export function slotsFromTemplate(template: string, missingIndex: number, pendingIndex = -1): LetterTemplateSlot[] {
    const chars = Array.from(template);
    const output: LetterTemplateSlot[] = [];
    let index = 0;

    while (index < chars.length) {
        const char = chars[index];
        if (char !== ' ') {
            output.push({
                glyph: char,
                originalIndex: index,
                isMissing: index === missingIndex,
                isPending: index === pendingIndex,
            });
            index += 1;
            continue;
        }

        let run = 0;
        while (index + run < chars.length && chars[index + run] === ' ') {
            run += 1;
        }
        output.push({
            glyph: ' ',
            originalIndex: index,
            isMissing: index === missingIndex,
            isPending: index === pendingIndex,
        });
        index += run;
    }

    return output;
}

export function metricsForGlyphCount(count: number): LetterTemplateMetrics {
    if (count <= 6) {
        return { width: 16, height: 44, gap: 3, filledFontSize: 30, placeholderFontSize: 26 };
    } else if (count <= 9) {
        return { width: 16, height: 40, gap: 2, filledFontSize: 25, placeholderFontSize: 22 };
    } else if (count <= 12) {
        return { width: 16, height: 36, gap: 2, filledFontSize: 22, placeholderFontSize: 20 };
    }
    return { width: 16, height: 32, gap: 2, filledFontSize: 19, placeholderFontSize: 17 };
}
