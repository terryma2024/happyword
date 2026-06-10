// Fighter card (player left / monster right): rounded tint card, character
// sprite, name, subtitle, HP label + bar, level badge, bonus capsule.
// Mirrors BattleView.swift fighterCard.

import { Graphics, Label, Node, tween, UIOpacity, UITransform, Vec3 } from 'cc';
import { color, loadCharacterSprite, makeBar, makeCapsule, makeLabel, makeNode, makeRoundedRect } from './nodeFactory';
import { layout, theme } from './theme';

export interface FighterCardConfig {
    nodeName: string;
    tintHex: string;
    x: number;
}

export class FighterCard {
    private spriteNode!: Node;
    private nameLabel!: Label;
    private subtitleLabel!: Label;
    private hpLabel!: Label;
    private hpBar!: { node: Node; setRatio: (ratio: number) => void };
    private levelBadgeNode!: Node;
    private levelBadgeLabel!: Label;
    private bonusNode!: Node;
    private hurtFlash!: UIOpacity;
    private towardCenterSign = 1;
    private currentImageKey = '';
    cardNode!: Node;

    build(parent: Node, config: FighterCardConfig): void {
        this.cardNode = makeRoundedRect(
            config.nodeName, parent,
            layout.fighterCardWidth, layout.fighterCardHeight, layout.fighterCardCornerRadius,
            config.tintHex,
            { x: config.x, strokeHex: config.tintHex, lineWidth: 2 },
        );

        const half = layout.fighterCardHeight / 2;
        this.hpLabel = makeLabel('HpLabel', this.cardNode, 'HP 10 / 10', 22, theme.navy, { y: half - 40 });
        this.hpBar = makeBar('HpBar', this.cardNode, layout.hpBarWidth, layout.hpBarHeight, theme.hpGreen, { y: half - 72 });

        this.spriteNode = makeNode('CharacterSprite', this.cardNode, 0, 10);
        this.spriteNode.getComponent(UITransform)!.setContentSize(layout.fighterSpriteSize, layout.fighterSpriteSize);

        this.nameLabel = makeLabel('NameLabel', this.cardNode, '', 28, theme.ink, { y: -half + 80 });
        this.subtitleLabel = makeLabel('SubtitleLabel', this.cardNode, '', 20, theme.textSecondary, { y: -half + 44 });

        this.levelBadgeNode = makeCapsule('LevelBadge', this.cardNode, 56, 36, theme.navy, {
            x: -layout.fighterCardWidth / 2 + 32, y: half - 40,
        });
        this.levelBadgeLabel = makeLabel('LevelBadgeLabel', this.levelBadgeNode, 'L1', 20, theme.white);
        this.levelBadgeNode.active = false;

        // Below the HP bar so it never collides with the HP label.
        this.bonusNode = makeCapsule('BonusBadge', this.cardNode, 90, 38, theme.gold, {
            x: layout.fighterCardWidth / 2 - 56, y: half - 96,
        });
        makeLabel('BonusLabel', this.bonusNode, 'Bonus', 20, theme.white);
        this.bonusNode.active = false;

        this.towardCenterSign = config.x < 0 ? 1 : -1;
        const flashNode = makeNode('HurtFlash', this.cardNode);
        flashNode.getComponent(UITransform)!.setContentSize(layout.fighterCardWidth, layout.fighterCardHeight);
        const g = flashNode.addComponent(Graphics);
        g.roundRect(-layout.fighterCardWidth / 2, -layout.fighterCardHeight / 2,
            layout.fighterCardWidth, layout.fighterCardHeight, layout.fighterCardCornerRadius);
        g.fillColor = color(theme.red);
        g.fill();
        this.hurtFlash = flashNode.addComponent(UIOpacity);
        this.hurtFlash.opacity = 0;
    }

    /// Mirrors the BattleView fighter motions (nudge/hurt/cast/zoom).
    /// `textures` lets the player card swap pose art during the motion.
    playMotion(effect: string, textures?: { temp: string; revert: string }): void {
        const base = this.cardNode.position.clone();
        switch (effect) {
            case 'nudge':
                tween(this.cardNode)
                    .to(0.12, { position: new Vec3(base.x + 26 * this.towardCenterSign, base.y, 0) })
                    .to(0.14, { position: base })
                    .start();
                break;
            case 'cast':
                tween(this.cardNode)
                    .to(0.15, { scale: new Vec3(1.12, 1.12, 1) })
                    .to(0.18, { scale: new Vec3(1, 1, 1) })
                    .start();
                break;
            case 'zoom':
                tween(this.cardNode)
                    .to(0.12, { scale: new Vec3(1.18, 1.18, 1) })
                    .to(0.2, { scale: new Vec3(1, 1, 1) })
                    .start();
                break;
            case 'hurt':
                tween(this.hurtFlash)
                    .to(0.08, { opacity: 110 })
                    .to(0.3, { opacity: 0 })
                    .start();
                break;
            default:
                return;
        }
        if (textures) {
            this.swapTexture(textures.temp, textures.revert, 0.45);
        }
    }

    /// Quick fade/scale-in when a new monster takes the card.
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
        this.hpBar.setRatio(maxHp > 0 ? hp / maxHp : 0);
    }

    setLevelBadge(label: string | null): void {
        this.levelBadgeNode.active = label !== null;
        if (label !== null) { this.levelBadgeLabel.string = label; }
    }

    setBonusVisible(visible: boolean): void {
        this.bonusNode.active = visible;
    }
}
