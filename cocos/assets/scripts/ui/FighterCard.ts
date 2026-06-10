// Fighter card (player left / monster right): rounded tint card, character
// sprite, name, subtitle, HP label + bar, level badge, bonus capsule.
// Mirrors BattleView.swift fighterCard.

import { Label, Node, UITransform } from 'cc';
import { loadCharacterSprite, makeBar, makeCapsule, makeLabel, makeNode, makeRoundedRect } from './nodeFactory';
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
        // Slightly left of center so the top-right bonus capsule never overlaps.
        this.hpLabel = makeLabel('HpLabel', this.cardNode, 'HP 10 / 10', 24, theme.navy, { x: -28, y: half - 40 });
        this.hpBar = makeBar('HpBar', this.cardNode, layout.hpBarWidth, layout.hpBarHeight, theme.hpGreen, { y: half - 72 });

        this.spriteNode = makeNode('CharacterSprite', this.cardNode, 0, 10);
        this.spriteNode.getComponent(UITransform)!.setContentSize(layout.fighterSpriteSize, layout.fighterSpriteSize);

        this.nameLabel = makeLabel('NameLabel', this.cardNode, '', 28, theme.ink, { y: -half + 80 });
        this.subtitleLabel = makeLabel('SubtitleLabel', this.cardNode, '', 20, theme.textSecondary, { y: -half + 44 });

        this.levelBadgeNode = makeCapsule('LevelBadge', this.cardNode, 56, 36, theme.navy, {
            x: -layout.fighterCardWidth / 2 + 44, y: half - 44,
        });
        this.levelBadgeLabel = makeLabel('LevelBadgeLabel', this.levelBadgeNode, 'L1', 20, theme.white);
        this.levelBadgeNode.active = false;

        this.bonusNode = makeCapsule('BonusBadge', this.cardNode, 90, 38, theme.gold, {
            x: layout.fighterCardWidth / 2 - 56, y: half - 44,
        });
        makeLabel('BonusLabel', this.bonusNode, 'Bonus', 20, theme.white);
        this.bonusNode.active = false;
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
