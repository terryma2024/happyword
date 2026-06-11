// Pure spell-question state (BattleView spellSlots/spellConsumedIndices
// parity): the player taps pool letters to fill hidden slots in order;
// completing the word submits the full answer. No 'cc' imports.

export type SpellTapResult = 'fill' | 'complete' | 'wrong' | 'ignored';

export class SpellViewState {
    readonly consumedPoolIndices = new Set<number>();
    filledCount = 0;

    constructor(
        private readonly letters: string[],
        private readonly revealedMask: boolean[],
        private readonly pool: string[],
    ) {}

    /// The letter the next hidden slot expects, or null when complete.
    nextExpectedLetter(): string | null {
        const index = this.nextHiddenIndex();
        return index === null ? null : this.letters[index];
    }

    tapPool(poolIndex: number): SpellTapResult {
        if (this.consumedPoolIndices.has(poolIndex)) { return 'ignored'; }
        const expected = this.nextExpectedLetter();
        if (expected === null) { return 'ignored'; }
        if (this.pool[poolIndex] !== expected) { return 'wrong'; }

        this.consumedPoolIndices.add(poolIndex);
        this.filledCount += 1;
        return this.nextHiddenIndex() === null ? 'complete' : 'fill';
    }

    /// Index of the first hidden slot not yet filled, or null when done.
    private nextHiddenIndex(): number | null {
        let remaining = this.filledCount;
        for (let i = 0; i < this.letters.length; i += 1) {
            if (this.revealedMask[i]) { continue; }
            if (remaining > 0) { remaining -= 1; continue; }
            return i;
        }
        return null;
    }
}
