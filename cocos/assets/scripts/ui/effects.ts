// Combat effect layers: projectile flight, damage floaters, crit overlay.
// Mirrors MagicProjectileOverlay / DamageFloaterLabel / CritSpectacleOverlay.

import { Color, Graphics, Label, Node, tween, UIOpacity, UITransform, Vec3 } from 'cc';
import { color, makeLabel, makeNode } from './nodeFactory';
import { layout, theme } from './theme';

const PROJECTILE_FLIGHT_SECONDS = 0.34;
const FLOATER_RISE = 32;
const FLOATER_SECONDS = 0.65;
const MAX_FLOATERS_PER_SIDE = 4;
const FLOATER_STAGGER = 9;

function fillCircle(g: Graphics, radius: number, hex: string, alpha: number): void {
    const c = color(hex);
    c.a = alpha;
    g.fillColor = c;
    g.circle(0, 0, radius);
    g.fill();
}

export class ProjectileLayer {
    private layer!: Node;

    build(parent: Node): void {
        this.layer = makeNode('ProjectileLayer', parent);
    }

    /// Soft glow + colored capsule with the word (MagicProjectileOverlay):
    /// blue for a forward hit, red for a backward (wrong-answer) bounce,
    /// gold and larger for crits (intensity > 1).
    fly(direction: 'forward' | 'backward', label: string, intensity = 1): void {
        const crit = intensity > 1;
        const coreHex = crit ? theme.gold : (direction === 'forward' ? '#7AA8FF' : theme.red);
        const glowHex = crit ? '#FFE670' : coreHex;

        const margin = layout.designWidth * 0.34;
        const fromX = direction === 'forward' ? -margin : margin;
        const toX = -fromX;

        const node = makeNode('Projectile', this.layer, fromX, 0);

        // Concentric fading circles fake the native blurred glow.
        const glow = makeNode('ProjectileGlow', node);
        const g = glow.addComponent(Graphics);
        const baseRadius = crit ? 66 : 46;
        fillCircle(g, baseRadius, glowHex, 36);
        fillCircle(g, baseRadius * 0.78, glowHex, 60);
        fillCircle(g, baseRadius * 0.56, glowHex, 90);

        const capsuleWidth = Math.max(72, label.length * 14 + 28);
        const capsuleHeight = crit ? 40 : 34;
        const capsule = makeNode('ProjectileCapsule', node);
        capsule.getComponent(UITransform)!.setContentSize(capsuleWidth, capsuleHeight);
        const capsuleGraphics = capsule.addComponent(Graphics);
        capsuleGraphics.roundRect(-capsuleWidth / 2, -capsuleHeight / 2, capsuleWidth, capsuleHeight, capsuleHeight / 2);
        capsuleGraphics.fillColor = color(coreHex);
        capsuleGraphics.fill();
        capsuleGraphics.lineWidth = 2;
        capsuleGraphics.strokeColor = color(crit ? '#E8821E' : theme.navy);
        capsuleGraphics.roundRect(-capsuleWidth / 2, -capsuleHeight / 2, capsuleWidth, capsuleHeight, capsuleHeight / 2);
        capsuleGraphics.stroke();
        makeLabel('ProjectileLabel', capsule, label, crit ? 24 : 20, theme.white);

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

    /// Small "-N" that drifts up briefly from the card's top edge
    /// (native DamageFloaterLabel is light: ~17pt, short travel).
    show(side: 'player' | 'monster', text: string): void {
        if (this.active[side] >= MAX_FLOATERS_PER_SIDE) { return; }
        this.active[side] += 1;
        const baseX = side === 'player' ? -layout.fighterCardX : layout.fighterCardX;
        const offset = (this.active[side] - 1) * FLOATER_STAGGER;
        const baseY = layout.fighterCardY + layout.fighterCardHeight / 2 - 6;

        const node = makeNode('Floater', this.layer, baseX + offset, baseY + offset);
        const label = node.addComponent(Label);
        label.string = text;
        label.fontSize = 24;
        label.isBold = true;
        label.color = color(theme.red);
        const opacity = node.addComponent(UIOpacity);

        tween(node)
            .to(FLOATER_SECONDS, { position: new Vec3(baseX + offset, baseY + offset + FLOATER_RISE, 0) })
            .start();
        tween(opacity)
            .delay(FLOATER_SECONDS * 0.4)
            .to(FLOATER_SECONDS * 0.6, { opacity: 0 })
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

    /// Native CritSpectacleOverlay: the whole screen washes heavy gold,
    /// white rings burst outward from the center, and a huge RED damage
    /// label punches in, lingering past the wash (~1s total).
    show(damageLabel: string): void {
        // Full-screen heavy gold wash.
        const flash = makeNode('CritFlash', this.layer);
        flash.getComponent(UITransform)!.setContentSize(layout.designWidth * 2, layout.designHeight * 2);
        const flashGraphics = flash.addComponent(Graphics);
        flashGraphics.rect(-layout.designWidth, -layout.designHeight, layout.designWidth * 2, layout.designHeight * 2);
        flashGraphics.fillColor = color(theme.gold);
        flashGraphics.fill();
        const flashOpacity = flash.addComponent(UIOpacity);
        flashOpacity.opacity = 0;
        tween(flashOpacity)
            .to(0.12, { opacity: 128 })
            .delay(0.22)
            .to(0.55, { opacity: 0 })
            .call(() => flash.destroy())
            .start();

        // Expanding white rings.
        this.burstRing(radius => radius * 2.6, 150, 10, 0.55);
        this.burstRing(radius => radius * 3.1, 80, 6, 0.65);

        // Huge red damage label, scale punch + lingering fade.
        const burst = makeNode('CritLabel', this.layer, 0, 40);
        const label = burst.addComponent(Label);
        label.string = damageLabel;
        label.fontSize = 120;
        label.lineHeight = 130;
        label.isBold = true;
        label.color = color(theme.red);
        burst.setScale(new Vec3(0.4, 0.4, 1));
        const burstOpacity = burst.addComponent(UIOpacity);
        tween(burst)
            .to(0.14, { scale: new Vec3(1.25, 1.25, 1) })
            .to(0.12, { scale: new Vec3(1.0, 1.0, 1) })
            .start();
        tween(burstOpacity)
            .delay(0.85)
            .to(0.25, { opacity: 0 })
            .call(() => burst.destroy())
            .start();
    }

    private burstRing(grow: (radius: number) => number, radius: number, lineWidth: number, seconds: number): void {
        const ring = makeNode('CritRing', this.layer);
        const g = ring.addComponent(Graphics);
        const stroke = new Color(255, 255, 255, 235);
        g.lineWidth = lineWidth;
        g.strokeColor = stroke;
        g.circle(0, 0, radius);
        g.stroke();
        const opacity = ring.addComponent(UIOpacity);
        const scale = grow(radius) / radius;
        tween(ring)
            .to(seconds, { scale: new Vec3(scale, scale, 1) })
            .start();
        tween(opacity)
            .delay(seconds * 0.35)
            .to(seconds * 0.65, { opacity: 0 })
            .call(() => ring.destroy())
            .start();
    }
}
