import { describe, expect, it } from 'vitest';
import { fitTrimmedContentSize } from '../assets/scripts/ui/spriteFit';

describe('fitTrimmedContentSize', () => {
    it('preserves the trimmed content aspect (tall idle magician 363x477)', () => {
        const s = fitTrimmedContentSize(512, 512, 363, 477, 185, 185);
        expect(s.width).toBeCloseTo(363 * 185 / 512, 5);
        expect(s.height).toBeCloseTo(477 * 185 / 512, 5);
        expect(s.height).toBeGreaterThan(s.width);                 // tall, not square
        expect(s.width / s.height).toBeCloseTo(363 / 477, 5);
    });

    it('reduces to the full square box for an untrimmed square frame', () => {
        const s = fitTrimmedContentSize(512, 512, 512, 512, 185, 185);
        expect(s.width).toBeCloseTo(185, 5);
        expect(s.height).toBeCloseTo(185, 5);
    });

    it('keeps a genuinely wide pose wide (fight frame 466x413)', () => {
        const s = fitTrimmedContentSize(512, 512, 466, 413, 185, 185);
        expect(s.width).toBeGreaterThan(s.height);
        expect(s.width / s.height).toBeCloseTo(466 / 413, 5);
    });
});
