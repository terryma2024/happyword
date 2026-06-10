// Bottom answer row: three purple capsules. Static layout for Phase 1;
// tap handling + feedback colors land in Phase 3.
// Mirrors BattleView.swift answerRow.

import { Label, Node } from 'cc';
import { makeCapsule, makeLabel, makeNode } from './nodeFactory';
import { layout, theme } from './theme';

export class AnswerRow {
    private buttons: { node: Node; label: Label }[] = [];

    build(parent: Node): void {
        const row = makeNode('AnswerRow', parent, 0, layout.answerRowY);
        const spacing = layout.answerCapsuleWidth + 40;
        for (let i = 0; i < 3; i += 1) {
            const node = makeCapsule(`AnswerButton${i}`, row,
                layout.answerCapsuleWidth, layout.answerCapsuleHeight, theme.purple,
                { x: (i - 1) * spacing });
            const label = makeLabel(`AnswerLabel${i}`, node, '', 28, theme.white);
            this.buttons.push({ node, label });
        }
    }

    setOptions(options: string[]): void {
        this.buttons.forEach((button, i) => {
            const text = options[i] ?? '';
            button.node.active = text.length > 0;
            button.label.string = text;
        });
    }
}
