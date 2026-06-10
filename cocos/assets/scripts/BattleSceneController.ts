// Battle scene orchestrator: builds the layout and drives it from live
// bridge state. Battle logic lives in the native host; this scene renders
// state snapshots and reports user input (contract:
// shared/contracts/cocos-battle-bridge/).

import { _decorator, Component, ResolutionPolicy, view } from 'cc';
import { BridgeClient } from './bridge/BridgeClient';
import {
    BattleAnimationPayload, BattleInitPayload, BattleQuestionPayload, BattleStatePayload,
    NativeToScriptMessage,
} from './bridge/messages';
import { AnswerRow } from './ui/AnswerRow';
import { FighterCard } from './ui/FighterCard';
import { optionsForQuestion } from './ui/format';
import { makeRoundedRect } from './ui/nodeFactory';
import { QuestionPanel } from './ui/QuestionPanel';
import { TopStatusBar } from './ui/TopStatusBar';
import { layout, theme } from './ui/theme';

const { ccclass } = _decorator;

const IDLE_FEEDBACK = 'Choose the right spell';

@ccclass('BattleSceneController')
export class BattleSceneController extends Component {
    private topStatus = new TopStatusBar();
    private playerCard = new FighterCard();
    private monsterCard = new FighterCard();
    private questionPanel = new QuestionPanel();
    private answerRow = new AnswerRow();
    private bridge = new BridgeClient();
    private playerArt = { idle: 'CharacterMagician', fight: 'CharacterMagicianFight', hurt: 'CharacterMagicianBeaten' };
    private inputLocked = true;

    onLoad() {
        // Landscape battle: lock the 720 design height so wide phone aspect
        // ratios letterbox horizontally instead of cropping the top status
        // bar and answer row (default fitWidth crops vertically on ~2.17:1).
        view.setDesignResolutionSize(layout.designWidth, layout.designHeight, ResolutionPolicy.FIXED_HEIGHT);

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

        this.answerRow.onOptionTap = (option) => {
            if (this.inputLocked) { return; }
            this.bridge.send({ type: 'battle/submitOption', payload: { option } });
        };
        this.topStatus.onEscapeTap = () => {
            this.bridge.send({ type: 'battle/escape', payload: {} });
        };
        this.questionPanel.onSpeakerTap = () => {
            this.bridge.send({ type: 'battle/speakAnswer', payload: {} });
        };

        this.bridge.onMessage = (msg) => this.handleMessage(msg);
        this.bridge.start();
    }

    private handleMessage(msg: NativeToScriptMessage) {
        switch (msg.type) {
            case 'battle/init': this.applyInit(msg.payload); break;
            case 'battle/state': this.applyState(msg.payload); break;
            case 'battle/question': this.applyQuestion(msg.payload); break;
            case 'battle/animation': this.applyAnimation(msg.payload); break;
            case 'battle/bossIntro': break; // Phase 3: boss intro bubble
            case 'battle/end': this.inputLocked = true; break;
            case 'battle/ping':
                this.bridge.send({ type: 'battle/pong', payload: { echo: msg.payload.echo } });
                break;
        }
    }

    /// battle/init is a full scene reset (sent on first ready AND on re-entry).
    private applyInit(payload: BattleInitPayload) {
        this.playerArt = payload.playerArt;
        this.playerCard.setIdentity(this.playerArt.idle, 'Magician', 'Player');
        this.playerCard.setHp(payload.playerMaxHp, payload.playerMaxHp);
        this.topStatus.setCombo(0);
        this.topStatus.setCountdown(payload.startingSeconds);
        this.questionPanel.setFeedback(IDLE_FEEDBACK, theme.textSecondary);
        this.inputLocked = false;
    }

    private applyState(payload: BattleStatePayload) {
        this.topStatus.setCombo(payload.comboCount);
        this.topStatus.setCountdown(payload.remainingSeconds);
        this.playerCard.setHp(payload.playerHp, payload.playerMaxHp);
        this.monsterCard.setIdentity(
            payload.monster.imageKey,
            payload.monster.name,
            `Monster ${payload.monsterIndex} / ${payload.monstersTotal}`,
        );
        this.monsterCard.setHp(payload.monsterHp, payload.monsterMaxHp);
        this.monsterCard.setLevelBadge(payload.monster.levelLabel);
        this.monsterCard.setBonusVisible(payload.monster.bonus);
        if (payload.status !== 'playing') {
            this.inputLocked = true;
        }
    }

    private applyQuestion(payload: BattleQuestionPayload) {
        this.questionPanel.setPrompt(payload.promptZh);
        this.answerRow.setOptions(optionsForQuestion(payload));
        this.questionPanel.setFeedback(IDLE_FEEDBACK, theme.textSecondary);
        this.inputLocked = false;
    }

    /// Phase 2: feedback line only. Phase 3 adds motions/projectiles/floaters.
    private applyAnimation(payload: BattleAnimationPayload) {
        const color = payload.comboTriggered
            ? theme.gold
            : (payload.correct ? theme.feedbackGreen : theme.red);
        this.questionPanel.setFeedback(payload.feedbackText, color);
    }
}
