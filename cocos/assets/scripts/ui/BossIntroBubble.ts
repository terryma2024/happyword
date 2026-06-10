// Monster intro dialogue bubble at 65% width / 20% height
// (BattleBossIntroLayoutSpec, BattleView.swift:3-6). The native side decides
// WHEN to show it (battle/bossIntro); the scene owns display and dismissal.

import { Node, tween, UIOpacity, Vec3 } from 'cc';
import { makeLabel, makeNode, makeRoundedRect } from './nodeFactory';
import { layout, theme } from './theme';

const BUBBLE_WIDTH = 460;
const BUBBLE_HEIGHT = 150;

export class BossIntroBubble {
    private bubble!: Node;
    private opacity!: UIOpacity;
    private nameLabel!: ReturnType<typeof makeLabel>;
    private enLabel!: ReturnType<typeof makeLabel>;
    private zhLabel!: ReturnType<typeof makeLabel>;

    build(parent: Node): void {
        const x = (0.65 - 0.5) * layout.designWidth;
        const y = (0.5 - 0.20) * layout.designHeight;
        this.bubble = makeRoundedRect('BossIntroBubble', parent,
            BUBBLE_WIDTH, BUBBLE_HEIGHT, 24, theme.white,
            { x, y, strokeHex: theme.gold, lineWidth: 3 });
        this.nameLabel = makeLabel('BossName', this.bubble, '', 26, theme.navy, { y: 42 });
        this.enLabel = makeLabel('BossLineEn', this.bubble, '', 22, theme.ink, { y: 4 });
        this.zhLabel = makeLabel('BossLineZh', this.bubble, '', 20, theme.textSecondary, { y: -34 });
        this.opacity = this.bubble.addComponent(UIOpacity);
        this.bubble.active = false;
    }

    show(name: string, lineEn: string, lineZh: string): void {
        this.nameLabel.string = name;
        this.enLabel.string = lineEn;
        this.zhLabel.string = lineZh;
        this.bubble.active = true;
        this.opacity.opacity = 0;
        this.bubble.setScale(new Vec3(0.85, 0.85, 1));
        tween(this.opacity).to(0.12, { opacity: 255 }).start();
        tween(this.bubble).to(0.16, { scale: new Vec3(1, 1, 1) }).start();
    }

    hide(): void {
        if (!this.bubble.active) { return; }
        tween(this.opacity)
            .to(0.15, { opacity: 0 })
            .call(() => { this.bubble.active = false; })
            .start();
    }
}
