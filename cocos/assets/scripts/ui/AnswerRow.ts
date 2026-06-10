// Bottom answer row: capsules share the full row width like the native
// answerRow (.frame(maxWidth:.infinity), 18pt spacing, 62pt min height).

import { Label, Node } from 'cc';
import { AnswerSelection, capsuleColorHex } from './answerFeedback';
import { makeCapsule, makeLabel, makeNode, redrawRoundedRect } from './nodeFactory';
import { answerCapsuleWidth, layout, theme } from './theme';

export class AnswerRow {
    private row!: Node;
    private buttons: { node: Node; label: Label }[] = [];
    /// Invoked with the tapped option text. Set by the scene controller.
    onOptionTap: ((option: string) => void) | null = null;

    build(parent: Node): void {
        this.row = makeNode('AnswerRow', parent, 0, layout.answerRowY);
    }

    setOptions(options: string[]): void {
        this.row.removeAllChildren();
        this.buttons = [];
        const shown = options.filter(option => option.length > 0);
        this.row.active = shown.length > 0;
        if (shown.length === 0) {
            return;
        }

        const width = answerCapsuleWidth(shown.length);
        const step = width + layout.answerRowSpacing;
        const startX = -((shown.length - 1) * step) / 2;
        shown.forEach((option, i) => {
            const node = makeCapsule(`AnswerButton${i}`, this.row,
                width, layout.answerCapsuleHeight, theme.purple, { x: startX + i * step });
            const label = makeLabel(`AnswerLabel${i}`, node, option, 36, theme.white);
            node.on(Node.EventType.TOUCH_END, () => {
                if (this.onOptionTap) { this.onOptionTap(label.string); }
            });
            this.buttons.push({ node, label });
        });
    }

    /// Feedback colors while input is locked (BattleView.tint(for:) parity).
    setSelection(selection: AnswerSelection | null, locked: boolean): void {
        const radius = layout.answerCapsuleHeight / 2;
        for (const button of this.buttons) {
            redrawRoundedRect(button.node, radius,
                capsuleColorHex(button.label.string, selection, locked));
        }
    }
}
