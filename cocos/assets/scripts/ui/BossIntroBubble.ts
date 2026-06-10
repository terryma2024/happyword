// Monster intro speech bubble mirroring the native MessageBubble bossStyle
// (BattleView.swift:1086-1131, MessageBubble.swift): cream fill, light-brown
// hairline border, bottom-right tail pointing at the monster, soft shadow.
// Centered at 65% width / 20% height; the scene owns display and dismissal.

import { Graphics, Label, Node, tween, UITransform, Vec3 } from 'cc';
import { color, makeLabel, makeNode } from './nodeFactory';
import { layout } from './theme';

// Native points x1.5 (design space).
const WIDTH = 336;
const HEIGHT = 144;
const RADIUS = 27;
const TAIL_BASE = 36;
const TAIL_LENGTH = 24;
const TAIL_INSET = 42;   // from the right edge to the tail base start
const FILL = '#FFFCF5';
const STROKE = '#E8D6B5';
const NAME_BROWN = '#6B4A24';
const LINE_NAVY = '#1C3657';
const ZH_GRAY = '#6E5F54';
const SHADOW_ALPHA = 36;

export class BossIntroBubble {
    private bubble!: Node;
    private nameLabel!: ReturnType<typeof makeLabel>;
    private enLabel!: ReturnType<typeof makeLabel>;
    private zhLabel!: ReturnType<typeof makeLabel>;

    build(parent: Node): void {
        const x = (0.65 - 0.5) * layout.designWidth;
        const y = (0.5 - 0.20) * layout.designHeight;
        this.bubble = makeNode('BossIntroBubble', parent, x, y);

        const g = this.bubble.addComponent(Graphics);
        this.drawBubble(g);

        this.nameLabel = makeLabel('BossName', this.bubble, '', 18, NAME_BROWN, { y: 40 });
        this.enLabel = makeLabel('BossLineEn', this.bubble, '', 21, LINE_NAVY, { y: 6 });
        this.enLabel.isBold = false;
        this.zhLabel = makeLabel('BossLineZh', this.bubble, '', 17, ZH_GRAY, { y: -28 });
        this.zhLabel.isBold = false;
        // Long lines shrink to fit instead of clipping (native minimumScaleFactor).
        for (const label of [this.enLabel, this.zhLabel]) {
            label.overflow = Label.Overflow.SHRINK;
            label.node.getComponent(UITransform)!.setContentSize(WIDTH - 28, 30);
        }

        this.bubble.active = false;
    }

    private drawBubble(g: Graphics): void {
        const halfW = WIDTH / 2;
        const halfH = HEIGHT / 2;
        const tailStartX = halfW - TAIL_INSET - TAIL_BASE;
        const tailTipX = halfW - TAIL_INSET + 12 - TAIL_BASE / 2;

        // Soft drop shadow (no blur in Graphics; a dark offset plate).
        const shadow = color('#000000');
        shadow.a = SHADOW_ALPHA;
        g.fillColor = shadow;
        g.roundRect(-halfW, -halfH - 6, WIDTH, HEIGHT, RADIUS);
        g.fill();

        // Bubble body.
        g.fillColor = color(FILL);
        g.roundRect(-halfW, -halfH, WIDTH, HEIGHT, RADIUS);
        g.fill();
        g.lineWidth = 1.5;
        g.strokeColor = color(STROKE);
        g.roundRect(-halfW, -halfH, WIDTH, HEIGHT, RADIUS);
        g.stroke();

        // Bottom-right tail pointing down at the monster.
        g.fillColor = color(FILL);
        g.moveTo(tailStartX, -halfH + 1);
        g.lineTo(tailStartX + TAIL_BASE, -halfH + 1);
        g.lineTo(tailTipX, -halfH - TAIL_LENGTH);
        g.close();
        g.fill();
        g.strokeColor = color(STROKE);
        g.moveTo(tailStartX, -halfH);
        g.lineTo(tailTipX, -halfH - TAIL_LENGTH);
        g.lineTo(tailStartX + TAIL_BASE, -halfH);
        g.stroke();
    }

    show(name: string, lineEn: string, lineZh: string): void {
        this.nameLabel.string = name;
        this.enLabel.string = lineEn;
        this.zhLabel.string = lineZh;
        this.bubble.active = true;
        this.bubble.setScale(new Vec3(0.85, 0.85, 1));
        tween(this.bubble)
            .to(0.14, { scale: new Vec3(1, 1, 1) })
            .start();
    }

    hide(): void {
        if (!this.bubble.active) { return; }
        tween(this.bubble)
            .to(0.12, { scale: new Vec3(0.85, 0.85, 1) })
            .call(() => { this.bubble.active = false; })
            .start();
    }
}
