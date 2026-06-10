// Letter pool for spell questions: replaces the answer row. Tapping the
// next correct letter fills a slot; wrong taps shake and cost HP.
// Mirrors the BattleView spell pool (spellConsumedIndices/spellShakingPoolIndex).

import { Label, Node, tween, Vec3 } from 'cc';
import { makeCapsule, makeLabel, makeNode, redrawRoundedRect } from './nodeFactory';
import { layout, theme } from './theme';

const BUTTON_WIDTH = 96;
const BUTTON_HEIGHT = 76;
const SPACING = 24;

export class SpellPool {
    private row!: Node;
    private buttons: { node: Node; label: Label }[] = [];
    onLetterTap: ((poolIndex: number) => void) | null = null;

    build(parent: Node): void {
        this.row = makeNode('SpellPool', parent, 0, layout.answerRowY);
        this.row.active = false;
    }

    setLetters(letters: string[]): void {
        this.row.removeAllChildren();
        this.buttons = [];
        this.row.active = letters.length > 0;
        const step = BUTTON_WIDTH + SPACING;
        const startX = -((letters.length - 1) * step) / 2;
        letters.forEach((letter, i) => {
            const node = makeCapsule(`PoolButton${i}`, this.row,
                BUTTON_WIDTH, BUTTON_HEIGHT, theme.purple, { x: startX + i * step });
            const label = makeLabel(`PoolLabel${i}`, node, letter, 30, theme.white);
            node.on(Node.EventType.TOUCH_END, () => { this.onLetterTap?.(i); });
            this.buttons.push({ node, label });
        });
    }

    setVisible(visible: boolean): void {
        this.row.active = visible;
    }

    markConsumed(poolIndex: number): void {
        const button = this.buttons[poolIndex];
        if (!button) { return; }
        redrawRoundedRect(button.node, BUTTON_HEIGHT / 2, theme.capsuleDisabled);
    }

    /// ±9 px, 3 cycles, ~0.3 s (native: ±6 pt over the same duration).
    shake(poolIndex: number): void {
        const button = this.buttons[poolIndex];
        if (!button) { return; }
        const base = button.node.position.clone();
        tween(button.node)
            .to(0.05, { position: new Vec3(base.x + 9, base.y, 0) })
            .to(0.05, { position: new Vec3(base.x - 9, base.y, 0) })
            .to(0.05, { position: new Vec3(base.x + 9, base.y, 0) })
            .to(0.05, { position: new Vec3(base.x - 9, base.y, 0) })
            .to(0.05, { position: new Vec3(base.x + 9, base.y, 0) })
            .to(0.05, { position: base })
            .start();
    }
}
