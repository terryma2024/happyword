// Top status strip: Combo (left), Battle title (center), Countdown + Escape
// (right). Mirrors BattleView.swift topStatus: Escape is a small bordered
// button (pale fill, blue text) and disables while feedback is showing.

import { Label, Node, UIOpacity, UITransform } from 'cc';
import { formatCountdown } from './format';
import { makeCapsule, makeLabel, makeNode, redrawRoundedRect } from './nodeFactory';
import { layout, theme } from './theme';

const ESCAPE_WIDTH = 110;
const ESCAPE_HEIGHT = 46;
const ESCAPE_FILL = '#E8EDF4';

export class TopStatusBar {
    private barNode!: Node;
    private comboLabel!: Label;
    private countdownLabel!: Label;
    private escapeLabel!: Label;
    private escapeEnabled = true;
    escapeNode!: Node;
    onEscapeTap: (() => void) | null = null;

    build(parent: Node, topOffsetY = 0): void {
        const bar = makeNode('TopStatusBar', parent, 0, layout.topStatusY + topOffsetY);
        this.barNode = bar;
        bar.getComponent(UITransform)!.setContentSize(layout.designWidth, 60);

        this.comboLabel = makeLabel('ComboLabel', bar, 'Combo: 0', 28, theme.navy, { x: -520 });
        makeLabel('TitleLabel', bar, 'Battle', 44, theme.navy, { x: 0 });
        this.countdownLabel = makeLabel('CountdownLabel', bar, 'Countdown 5:00', 28, theme.navy, { x: 390 });

        this.escapeNode = makeCapsule('EscapeButton', bar, ESCAPE_WIDTH, ESCAPE_HEIGHT, ESCAPE_FILL, { x: 560 });
        this.escapeNode.addComponent(UIOpacity);
        this.escapeLabel = makeLabel('EscapeLabel', this.escapeNode, 'Escape', 22, theme.blue);
        this.escapeNode.on(Node.EventType.TOUCH_END, () => {
            if (this.escapeEnabled) { this.onEscapeTap?.(); }
        });
    }

    /// Re-anchor the bar after a resolution-policy recompute (window resize):
    /// the bar must hug the CURRENT visible top edge, so its Y is the design
    /// constant plus the policy-derived offset.
    setTopOffset(topOffsetY: number): void {
        this.barNode.setPosition(0, layout.topStatusY + topOffsetY);
    }

    setCombo(count: number): void {
        this.comboLabel.string = `Combo: ${count}`;
    }

    setCountdown(seconds: number): void {
        this.countdownLabel.string = `Countdown ${formatCountdown(seconds)}`;
    }

    /// Native parity: Escape disables (grays out) while feedback is showing.
    setEscapeEnabled(enabled: boolean): void {
        this.escapeEnabled = enabled;
        redrawRoundedRect(this.escapeNode, ESCAPE_HEIGHT / 2, ESCAPE_FILL);
        this.escapeLabel.color.fromHEX(enabled ? theme.blue : theme.capsuleDisabled);
        this.escapeLabel.color = this.escapeLabel.color.clone();
        this.escapeNode.getComponent(UIOpacity)!.opacity = enabled ? 255 : 160;
    }
}
