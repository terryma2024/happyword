import { describe, expect, it } from 'vitest';
import { choosePolicy, topStatusOffsetY } from '../assets/scripts/ui/resolutionPolicy';

describe('choosePolicy', () => {
    it('keeps FIXED_HEIGHT on wide phones', () => {
        expect(choosePolicy(2622, 1206, 1565, 720)).toBe('fixedHeight'); // iPhone 16 Pro
    });
    it('uses FIXED_WIDTH on 3:2 tablets', () => {
        expect(choosePolicy(2800, 1840, 1565, 720)).toBe('fixedWidth'); // MatePad Air
    });
    it('treats the exact design aspect as FIXED_HEIGHT', () => {
        expect(choosePolicy(1565, 720, 1565, 720)).toBe('fixedHeight');
    });
});

describe('topStatusOffsetY', () => {
    it('is zero under fixedHeight', () => {
        expect(topStatusOffsetY('fixedHeight', 2622, 1206, 1565, 720)).toBe(0);
    });
    it('shifts the bar up by half the extra visible height under fixedWidth', () => {
        // MatePad: visibleHeight = 1565 * 1840/2800 = 1028.43; extra = 308.43; offset = +154.2
        const offset = topStatusOffsetY('fixedWidth', 2800, 1840, 1565, 720);
        expect(offset).toBeCloseTo((1565 * 1840 / 2800 - 720) / 2, 1);
    });
});
