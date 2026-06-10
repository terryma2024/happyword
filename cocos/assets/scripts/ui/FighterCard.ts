// Fighter card mirroring the native layout (BattleView.swift fighterCard):
// top-to-bottom — character art (with hurt circle / cast glow overlays),
// name (+inline level badge), subtitle, left-aligned HP label, full-width
// HP bar with gray track.

import { Graphics, HorizontalTextAlignment, Label, Layout, Node, tween, UIOpacity, UITransform, Vec3 } from 'cc';
import { color, loadCharacterSprite, makeCapsule, makeLabel, makeNode, makeRoundedRect } from './nodeFactory';
import { layout, theme } from './theme';

export interface FighterCardConfig {
    nodeName: string;
    tintHex: string;
    x: number;
}

const HURT_RED = '#E63848';

export class FighterCard {
    private spriteNode!: Node;
    private spriteRegion!: Node;
    private glowOpacity!: UIOpacity;
    private hurtOpacity!: UIOpacity;
    private nameLabel!: Label;
    private subtitleLabel!: Label;
    private hpLabel!: Label;
    private hpFill!: Node;
    private hpFillGraphics!: Graphics;
    private levelBadgeNode!: Node;
    private levelBadgeLabel!: Label;
    private towardCenterSign = 1;
    private currentImageKey = '';
    cardNode!: Node;

    build(parent: Node, config: FighterCardConfig): void {
        const width = layout.fighterCardWidth;
        const height = layout.fighterCardHeight;
        const half = height / 2;
        const pad = layout.fighterCardPadding;
        const innerWidth = width - pad * 2;

        this.cardNode = makeRoundedRect(
            config.nodeName, parent, width, height, layout.fighterCardCornerRadius,
            config.tintHex,
            { x: config.x, y: layout.fighterCardY, strokeHex: config.tintHex, lineWidth: 2 },
        );
        this.towardCenterSign = config.x < 0 ? 1 : -1;

        // --- character art region (top) ---
        this.spriteRegion = makeNode('SpriteRegion', this.cardNode, 0, half - 110);  // art center ~110 below card top

        const glowNode = makeNode('CastGlow', this.spriteRegion);
        const glowGraphics = glowNode.addComponent(Graphics);
        glowGraphics.circle(0, 0, 92);
        glowGraphics.fillColor = color(theme.gold);
        glowGraphics.fill();
        this.glowOpacity = glowNode.addComponent(UIOpacity);
        this.glowOpacity.opacity = 0;

        this.spriteNode = makeNode('CharacterSprite', this.spriteRegion);
        this.spriteNode.getComponent(UITransform)!
            .setContentSize(layout.fighterSpriteFit, layout.fighterSpriteFit);

        // Translucent red circle over the art only (native hurtOpacity circle).
        const hurtNode = makeNode('HurtCircle', this.spriteRegion);
        const hurtGraphics = hurtNode.addComponent(Graphics);
        hurtGraphics.circle(0, 0, 95);
        hurtGraphics.fillColor = color(HURT_RED);
        hurtGraphics.fill();
        this.hurtOpacity = hurtNode.addComponent(UIOpacity);
        this.hurtOpacity.opacity = 0;

        // --- name row with inline level badge ---
        const nameRow = makeNode('NameRow', this.cardNode, 0, half - 242);
        const rowLayout = nameRow.addComponent(Layout);
        rowLayout.type = Layout.Type.HORIZONTAL;
        rowLayout.resizeMode = Layout.ResizeMode.CONTAINER;
        rowLayout.spacingX = 10;
        this.nameLabel = makeLabel('NameLabel', nameRow, '', 30, theme.navy);
        this.levelBadgeNode = makeCapsule('LevelBadge', nameRow, 46, 30, theme.navy);
        this.levelBadgeLabel = makeLabel('LevelBadgeLabel', this.levelBadgeNode, 'L1', 17, theme.white);
        this.levelBadgeNode.active = false;

        this.subtitleLabel = makeLabel('SubtitleLabel', this.cardNode, '', 24, theme.textSecondary, { y: half - 295 });

        // --- HP label (left aligned) + full-width bar with track ---
        this.hpLabel = makeLabel('HpLabel', this.cardNode, 'HP 10 / 10', 24, theme.navy, {
            x: -width / 2 + pad, y: half - 343,
        });
        this.hpLabel.horizontalAlign = HorizontalTextAlignment.LEFT;
        this.hpLabel.node.getComponent(UITransform)!.setAnchorPoint(0, 0.5);

        const track = makeNode('HpTrack', this.cardNode, 0, half - 378);
        track.getComponent(UITransform)!.setContentSize(innerWidth, layout.hpBarHeight);
        const trackGraphics = track.addComponent(Graphics);
        trackGraphics.roundRect(-innerWidth / 2, -layout.hpBarHeight / 2, innerWidth, layout.hpBarHeight, layout.hpBarHeight / 2);
        trackGraphics.fillColor = color(theme.hpTrack);
        trackGraphics.fill();

        this.hpFill = makeNode('HpFill', this.cardNode, 0, half - 378);
        this.hpFill.getComponent(UITransform)!.setContentSize(innerWidth, layout.hpBarHeight);
        this.hpFillGraphics = this.hpFill.addComponent(Graphics);
        this.drawHpFill(1);
    }

    private drawHpFill(ratio: number): void {
        const innerWidth = layout.fighterCardWidth - layout.fighterCardPadding * 2;
        const w = Math.max(0, Math.min(1, ratio)) * innerWidth;
        this.hpFillGraphics.clear();
        if (w <= 0) { return; }
        this.hpFillGraphics.roundRect(-innerWidth / 2, -layout.hpBarHeight / 2, w, layout.hpBarHeight, layout.hpBarHeight / 2);
        this.hpFillGraphics.fillColor = color(theme.hpGreen);
        this.hpFillGraphics.fill();
    }

    setIdentity(imageKey: string, name: string, subtitle: string): void {
        this.nameLabel.string = name;
        this.subtitleLabel.string = subtitle;
        if (imageKey !== this.currentImageKey) {
            this.currentImageKey = imageKey;
            loadCharacterSprite(this.spriteNode, imageKey);
        }
    }

    setHp(hp: number, maxHp: number): void {
        this.hpLabel.string = `HP ${hp} / ${maxHp}`;
        this.drawHpFill(maxHp > 0 ? hp / maxHp : 0);
    }

    setLevelBadge(label: string | null): void {
        this.levelBadgeNode.active = label !== null;
        if (label !== null) { this.levelBadgeLabel.string = label; }
    }

    /// Mirrors the BattleView fighter motions (BattleView.swift:916-997).
    /// `textures` lets the player card swap pose art during the motion.
    playMotion(effect: string, textures?: { temp: string; revert: string }): void {
        const base = this.cardNode.position.clone();
        switch (effect) {
            case 'nudge':
                tween(this.cardNode)
                    .to(0.06, { position: new Vec3(base.x + 12 * this.towardCenterSign, base.y, 0) })
                    .delay(0.06)
                    .to(0.08, { position: base })
                    .start();
                break;
            case 'cast':
                // Scale + rocking rotation + gold glow (triggerPlayerCast).
                tween(this.cardNode)
                    .to(0.18, { scale: new Vec3(1.15, 1.15, 1), angle: 10 })
                    .to(0.18, { angle: -10 })
                    .to(0.16, { scale: new Vec3(1, 1, 1), angle: 0 })
                    .start();
                tween(this.glowOpacity)
                    .to(0.18, { opacity: 200 })
                    .delay(0.2)
                    .to(0.2, { opacity: 0 })
                    .start();
                break;
            case 'zoom':
                tween(this.cardNode)
                    .to(0.22, { scale: new Vec3(1.12, 1.12, 1) })
                    .delay(0.12)
                    .to(0.16, { scale: new Vec3(1, 1, 1) })
                    .start();
                break;
            case 'hurt':
                // Recoil away from center + translucent red circle over the art.
                tween(this.cardNode)
                    .to(0.08, { position: new Vec3(base.x - 10 * this.towardCenterSign, base.y, 0) })
                    .to(0.2, { position: base })
                    .start();
                tween(this.hurtOpacity)
                    .to(0.08, { opacity: 85 })
                    .to(0.34, { opacity: 0 })
                    .start();
                break;
            default:
                return;
        }
        if (textures) {
            this.swapTexture(textures.temp, textures.revert, 0.48);
        }
    }

    /// Quick scale-in when a new monster takes the card.
    playSpawnTransition(): void {
        this.cardNode.setScale(new Vec3(0.88, 0.88, 1));
        tween(this.cardNode)
            .to(0.18, { scale: new Vec3(1.04, 1.04, 1) })
            .to(0.12, { scale: new Vec3(1, 1, 1) })
            .start();
    }

    private swapTexture(tempKey: string, revertKey: string, seconds: number): void {
        this.currentImageKey = tempKey;
        loadCharacterSprite(this.spriteNode, tempKey);
        tween(this.spriteNode)
            .delay(seconds)
            .call(() => {
                this.currentImageKey = revertKey;
                loadCharacterSprite(this.spriteNode, revertKey);
            })
            .start();
    }
}
