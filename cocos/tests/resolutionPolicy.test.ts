import { describe, expect, it } from 'vitest';
import { choosePolicy, resolvePolicyAndOffset, topStatusOffsetY } from '../assets/scripts/ui/resolutionPolicy';

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

describe('resolvePolicyAndOffset', () => {
    it('combines policy + offset for wide phones (offset 0)', () => {
        expect(resolvePolicyAndOffset(2622, 1206, 1565, 720))
            .toEqual({ policy: 'fixedHeight', topOffsetY: 0 });
    });
    it('combines policy + offset for squarish tablets', () => {
        const r = resolvePolicyAndOffset(2800, 1840, 1565, 720);
        expect(r.policy).toBe('fixedWidth');
        expect(r.topOffsetY).toBeCloseTo((1565 * 1840 / 2800 - 720) / 2, 1);
    });
    it('Mate 60 Pro landscape (2720x1260, aspect 2.158 just under design) is near-full-bleed fixedWidth', () => {
        const r = resolvePolicyAndOffset(2720, 1260, 1565, 720);
        expect(r.policy).toBe('fixedWidth');
        // visibleH = 1565 * 1260/2720 = 724.9 — only ~2.5 design units of
        // letterbox per edge, i.e. visually full screen and centered.
        expect(r.topOffsetY).toBeCloseTo((1565 * 1260 / 2720 - 720) / 2, 1);
        expect(r.topOffsetY).toBeLessThan(3);
    });
    it('recomputes when the same scene survives a window resize (freeform -> maximized)', () => {
        // Freeform window on MatePad: content area 1644x1162.
        const small = resolvePolicyAndOffset(1644, 1162, 1565, 720);
        // Maximized: 2800x1840. The offset must shrink to the new geometry,
        // otherwise the top bar overshoots the visible top edge.
        const big = resolvePolicyAndOffset(2800, 1840, 1565, 720);
        expect(small.policy).toBe('fixedWidth');
        expect(big.policy).toBe('fixedWidth');
        expect(big.topOffsetY).toBeLessThan(small.topOffsetY);
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
