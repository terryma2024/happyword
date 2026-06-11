import { describe, expect, it } from 'vitest';
import { metricsForGlyphCount, slotsFromTemplate } from '../assets/scripts/ui/letterTemplate';

describe('slotsFromTemplate', () => {
    it('maps glyphs with original indices and missing flag', () => {
        const slots = slotsFromTemplate('app_e', 3);
        expect(slots.map(s => s.glyph)).toEqual(['a', 'p', 'p', '_', 'e']);
        expect(slots[3]).toMatchObject({ isMissing: true, originalIndex: 3 });
        expect(slots[0]).toMatchObject({ isMissing: false, isPending: false, originalIndex: 0 });
    });

    it('collapses a run of spaces into one slot', () => {
        const slots = slotsFromTemplate('ice  cream', 4);
        expect(slots.map(s => s.glyph)).toEqual(['i', 'c', 'e', ' ', 'c', 'r', 'e', 'a', 'm']);
        expect(slots[3].originalIndex).toBe(3);
        expect(slots[4].originalIndex).toBe(5);
    });

    it('marks pending index', () => {
        const slots = slotsFromTemplate('app_e', 3, 3);
        expect(slots[3].isPending).toBe(true);
    });
});

describe('metricsForGlyphCount', () => {
    it('matches Swift thresholds', () => {
        expect(metricsForGlyphCount(6)).toEqual({ width: 16, height: 44, gap: 3, filledFontSize: 30, placeholderFontSize: 26 });
        expect(metricsForGlyphCount(9)).toEqual({ width: 16, height: 40, gap: 2, filledFontSize: 25, placeholderFontSize: 22 });
        expect(metricsForGlyphCount(12)).toEqual({ width: 16, height: 36, gap: 2, filledFontSize: 22, placeholderFontSize: 20 });
        expect(metricsForGlyphCount(13)).toEqual({ width: 16, height: 32, gap: 2, filledFontSize: 19, placeholderFontSize: 17 });
    });
});
