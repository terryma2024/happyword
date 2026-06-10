// Battle scene orchestrator. Phase 1: builds the static three-column layout
// with screenshot-parity placeholder data (assets/screenshots/ios/
// latest-simulator/feature-ios-battle.png). Phase 2 wires live bridge state.

import { _decorator, Component } from 'cc';
import { AnswerRow } from './ui/AnswerRow';
import { FighterCard } from './ui/FighterCard';
import { makeRoundedRect } from './ui/nodeFactory';
import { QuestionPanel } from './ui/QuestionPanel';
import { TopStatusBar } from './ui/TopStatusBar';
import { layout, theme } from './ui/theme';

const { ccclass } = _decorator;

@ccclass('BattleSceneController')
export class BattleSceneController extends Component {
    private topStatus = new TopStatusBar();
    private playerCard = new FighterCard();
    private monsterCard = new FighterCard();
    private questionPanel = new QuestionPanel();
    private answerRow = new AnswerRow();

    onLoad() {
        makeRoundedRect('PageBackground', this.node,
            layout.designWidth * 2, layout.designHeight * 2, 0, theme.page);
        this.topStatus.build(this.node);
        this.playerCard.build(this.node, {
            nodeName: 'PlayerCard', tintHex: theme.paleBlue, x: -layout.fighterCardX,
        });
        this.monsterCard.build(this.node, {
            nodeName: 'MonsterCard', tintHex: theme.palePink, x: layout.fighterCardX,
        });
        this.questionPanel.build(this.node);
        this.answerRow.build(this.node);

        this.applyPlaceholderState();
    }

    /// Screenshot-parity placeholder until the bridge drives real state (Phase 2).
    private applyPlaceholderState() {
        this.topStatus.setCombo(0);
        this.topStatus.setCountdown(297);

        this.playerCard.setIdentity('CharacterMagician', 'Magician', 'Player');
        this.playerCard.setHp(10, 10);

        this.monsterCard.setIdentity('CharacterSnowGoblin', 'Snow Goblin', 'Monster 1 / 2');
        this.monsterCard.setHp(1, 1);
        this.monsterCard.setLevelBadge('L1');

        this.questionPanel.setPrompt('苹果');
        this.answerRow.setOptions(['orange', 'blueberry', 'apple']);
    }
}
