// Top status strip: Combo (left), Battle title (center), Countdown + Escape (right).
// Mirrors BattleView.swift topStatus.

import { Label, Node, UITransform } from 'cc';
import { makeCapsule, makeLabel, makeNode } from './nodeFactory';
import { layout, theme } from './theme';

export function formatCountdown(totalSeconds: number): string {
    const seconds = Math.max(0, Math.floor(totalSeconds));
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
}

export class TopStatusBar {
    private comboLabel!: Label;
    private countdownLabel!: Label;
    escapeNode!: Node;

    build(parent: Node): void {
        const bar = makeNode('TopStatusBar', parent, 0, layout.topStatusY);
        bar.getComponent(UITransform)!.setContentSize(layout.designWidth, 60);

        this.comboLabel = makeLabel('ComboLabel', bar, 'Combo: 0', 26, theme.navy, { x: -520 });
        makeLabel('TitleLabel', bar, 'Battle', 34, theme.ink, { x: 0 });
        this.countdownLabel = makeLabel('CountdownLabel', bar, 'Countdown 5:00', 26, theme.navy, { x: 380 });

        this.escapeNode = makeCapsule('EscapeButton', bar, 130, 50, theme.blue, { x: 560 });
        makeLabel('EscapeLabel', this.escapeNode, 'Escape', 24, theme.white);
    }

    setCombo(count: number): void {
        this.comboLabel.string = `Combo: ${count}`;
    }

    setCountdown(seconds: number): void {
        this.countdownLabel.string = `Countdown ${formatCountdown(seconds)}`;
    }
}
