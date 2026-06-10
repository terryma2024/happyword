import { describe, expect, it } from 'vitest';
import { SpellViewState } from '../assets/scripts/ui/spellView';

// apple with first letter revealed; pool has duplicates and decoys.
function makeState(): SpellViewState {
    return new SpellViewState(
        ['a', 'p', 'p', 'l', 'e'],
        [true, false, false, false, false],
        ['p', 'l', 'x', 'p', 'e', 'k'],
    );
}

describe('SpellViewState', () => {
    it('expects the first hidden letter', () => {
        expect(makeState().nextExpectedLetter()).toBe('p');
    });

    it('fills on a correct pool tap and consumes that pool index', () => {
        const state = makeState();
        expect(state.tapPool(0)).toBe('fill');       // p
        expect(state.consumedPoolIndices.has(0)).toBe(true);
        expect(state.nextExpectedLetter()).toBe('p');
        expect(state.tapPool(3)).toBe('fill');       // second p
        expect(state.nextExpectedLetter()).toBe('l');
    });

    it('rejects a wrong pool tap without consuming', () => {
        const state = makeState();
        expect(state.tapPool(2)).toBe('wrong');      // x
        expect(state.consumedPoolIndices.has(2)).toBe(false);
        expect(state.filledCount).toBe(0);
    });

    it('rejects taps on consumed indices', () => {
        const state = makeState();
        state.tapPool(0);
        expect(state.tapPool(0)).toBe('ignored');
    });

    it('completes when the word is fully spelled', () => {
        const state = makeState();
        expect(state.tapPool(0)).toBe('fill');       // p
        expect(state.tapPool(3)).toBe('fill');       // p
        expect(state.tapPool(1)).toBe('fill');       // l
        expect(state.tapPool(4)).toBe('complete');   // e
        expect(state.filledCount).toBe(4);
    });
});
