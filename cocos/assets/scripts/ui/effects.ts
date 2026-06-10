// Combat effect layers: projectile flight, damage floaters, crit overlay.
// Mirrors MagicProjectileOverlay / DamageFloaterLabel / CritSpectacleOverlay.

import { Graphics, Label, Node, tween, UIOpacity, UITransform, Vec3 } from 'cc';
import { color, makeLabel, makeNode } from './nodeFactory';
import { layout, theme } from './theme';

const PROJECTILE_FLIGHT_SECONDS = 0.34;
const FLOATER_RISE = 56;
const FLOATER_SECONDS = 0.8;
const MAX_FLOATERS_PER_SIDE = 4;
const FLOATER_STAGGER = 9;

export class ProjectileLayer {
    private layer!: Node;

    build(parent: Node): void {
        this.layer = makeNode('ProjectileLayer', parent);
    }

    fly(direction: 'forward' | 'backward', label: string): void {
        const fromX = direction === 'forward' ? -layout.fighterCardX + 150 : layout.fighterCardX - 150;
        const toX = -fromX;

        const node = makeNode('Projectile', this.layer, fromX, 0);
        const g = node.addComponent(Graphics);
        g.circle(0, 0, 18);
        g.fillColor = color(theme.gold);
        g.fill();
        makeLabel('ProjectileLabel', node, label, 22, theme.navy, { y: 34 });
        node.addComponent(UIOpacity);

        tween(node)
            .to(PROJECTILE_FLIGHT_SECONDS, { position: new Vec3(toX, 0, 0) })
            .call(() => node.destroy())
            .start();
    }
}

export class FloaterLayer {
    private layer!: Node;
    private active = { player: 0, monster: 0 };

    build(parent: Node): void {
        this.layer = makeNode('FloaterLayer', parent);
    }

    show(side: 'player' | 'monster', text: string): void {
        if (this.active[side] >= MAX_FLOATERS_PER_SIDE) { return; }
        this.active[side] += 1;
        const baseX = side === 'player' ? -layout.fighterCardX : layout.fighterCardX;
        const offset = (this.active[side] - 1) * FLOATER_STAGGER;

        const node = makeNode('Floater', this.layer, baseX + offset, 130 + offset);
        const label = node.addComponent(Label);
        label.string = text;
        label.fontSize = 34;
        label.isBold = true;
        label.color = color(theme.red);
        const opacity = node.addComponent(UIOpacity);

        tween(node)
            .to(FLOATER_SECONDS, { position: new Vec3(baseX + offset, 130 + offset + FLOATER_RISE, 0) })
            .start();
        tween(opacity)
            .to(FLOATER_SECONDS, { opacity: 0 })
            .call(() => {
                this.active[side] = Math.max(0, this.active[side] - 1);
                node.destroy();
            })
            .start();
    }
}

export class CritOverlay {
    private layer!: Node;

    build(parent: Node): void {
        this.layer = makeNode('CritOverlay', parent);
    }

    show(damageLabel: string): void {
        const flash = makeNode('CritFlash', this.layer);
        flash.getComponent(UITransform)!.setContentSize(layout.designWidth * 2, layout.designHeight * 2);
        const g = flash.addComponent(Graphics);
        g.rect(-layout.designWidth, -layout.designHeight, layout.designWidth * 2, layout.designHeight * 2);
        g.fillColor = color(theme.gold);
        g.fill();
        const flashOpacity = flash.addComponent(UIOpacity);
        flashOpacity.opacity = 0;

        const burst = makeNode('CritLabel', this.layer, 0, 140);
        const label = burst.addComponent(Label);
        label.string = damageLabel;
        label.fontSize = 72;
        label.isBold = true;
        label.color = color(theme.gold);
        burst.setScale(new Vec3(0.4, 0.4, 1));
        const burstOpacity = burst.addComponent(UIOpacity);

        tween(flashOpacity)
            .to(0.1, { opacity: 90 })
            .to(0.4, { opacity: 0 })
            .call(() => flash.destroy())
            .start();
        tween(burst)
            .to(0.16, { scale: new Vec3(1.25, 1.25, 1) })
            .to(0.12, { scale: new Vec3(1.0, 1.0, 1) })
            .delay(0.25)
            .start();
        tween(burstOpacity)
            .delay(0.5)
            .to(0.15, { opacity: 0 })
            .call(() => burst.destroy())
            .start();
    }
}
