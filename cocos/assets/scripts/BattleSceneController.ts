// Battle scene orchestrator: builds the layout and drives it from live
// bridge state. Battle logic lives in the native host; this scene renders
// state snapshots and reports user input (contract:
// shared/contracts/cocos-battle-bridge/).

import { _decorator, Component, game, ResolutionPolicy, sys, view } from 'cc';
import { BridgeClient } from './bridge/BridgeClient';
import {
    BattleAnimationPayload, BattleInitPayload, BattleQuestionPayload, BattleStatePayload,
    NativeToScriptMessage,
} from './bridge/messages';
import { PreviewFakeHost } from './bridge/previewFakeHost';
import { AnimationStep, planAnimation } from './ui/animationPlan';
import { AnswerRow } from './ui/AnswerRow';
import { feedbackColorHex } from './ui/answerFeedback';
import { BossIntroBubble } from './ui/BossIntroBubble';
import { CritOverlay, FloaterLayer, ProjectileLayer } from './ui/effects';
import { FighterCard } from './ui/FighterCard';
import { optionsForQuestion } from './ui/format';
import { makeRoundedRect } from './ui/nodeFactory';
import { QuestionPanel } from './ui/QuestionPanel';
import { SpellPool } from './ui/SpellPool';
import { SpellViewState } from './ui/spellView';
import { TopStatusBar } from './ui/TopStatusBar';
import { layout, theme } from './ui/theme';

const { ccclass } = _decorator;

const IDLE_FEEDBACK = 'Choose the right spell';
/// Mirrors BattleView.clearFeedbackAfterDelay (650 ms feedback hold).
const FEEDBACK_HOLD_SECONDS = 0.65;

@ccclass('BattleSceneController')
export class BattleSceneController extends Component {
    private topStatus = new TopStatusBar();
    private playerCard = new FighterCard();
    private monsterCard = new FighterCard();
    private questionPanel = new QuestionPanel();
    private answerRow = new AnswerRow();
    private spellPool = new SpellPool();
    private projectileLayer = new ProjectileLayer();
    private floaterLayer = new FloaterLayer();
    private critOverlay = new CritOverlay();
    private bossIntro = new BossIntroBubble();
    private bridge = new BridgeClient();
    private bossIntroMonsterIndex = 0;
    private lastMonsterIndex = 0;
    private previewHost: PreviewFakeHost | null = null;
    private playerArt = { idle: 'CharacterMagician', fight: 'CharacterMagicianFight', hurt: 'CharacterMagicianBeaten' };
    private inputLocked = true;
    private lastTappedOption = '';
    private feedbackHolding = false;
    private pendingQuestion: BattleQuestionPayload | null = null;
    private spellState: SpellViewState | null = null;
    private currentQuestion: BattleQuestionPayload | null = null;

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
        this.spellPool.build(this.node);
        // Effect layers attach last so they render above the cards.
        this.projectileLayer.build(this.node);
        this.floaterLayer.build(this.node);
        this.critOverlay.build(this.node);
        this.bossIntro.build(this.node);

        this.answerRow.onOptionTap = (option) => this.submitOption(option);
        this.spellPool.onLetterTap = (poolIndex) => this.handleSpellPoolTap(poolIndex);
        this.topStatus.onEscapeTap = () => {
            this.bridge.send({ type: 'battle/escape', payload: {} });
        };
        this.questionPanel.onSpeakerTap = () => {
            this.bridge.send({ type: 'battle/speakAnswer', payload: {} });
        };

        this.bridge.onMessage = (msg) => this.handleMessage(msg);
        this.bridge.start();

        if (!sys.isNative) {
            this.startPreviewMode();
        }
    }

    /// Browsers stop requestAnimationFrame for hidden/occluded windows,
    /// freezing the whole game loop (Framerate 0, scheduled callbacks never
    /// fire). Worker timers are exempt from that throttling, so a tiny
    /// worker pumps frames manually whenever the page is hidden — automation
    /// keeps working without needing the window to be visible.
    private startHiddenTabPump() {
        try {
            const g = globalThis as any;
            const blob = new g.Blob(['setInterval(() => postMessage(0), 33);'], { type: 'text/javascript' });
            const worker = new g.Worker(g.URL.createObjectURL(blob));
            worker.onmessage = () => {
                if (g.document?.visibilityState === 'hidden') {
                    game.step();
                }
            };
        } catch (error) {
            console.warn('[preview] hidden-tab frame pump unavailable', error);
        }
    }

    /// Browser preview has no JSB bridge; a fake host cycles question kinds.
    private startPreviewMode() {
        this.startHiddenTabPump();
        this.previewHost = new PreviewFakeHost();
        this.scheduleOnce(() => {
            const host = this.previewHost!;
            this.applyInit(host.initPayload());
            this.applyState(host.statePayload());
            this.applyQuestion(host.currentQuestion());
            this.showBossIntro(1, 'Snow Goblin',
                'Bounce into my wiggly quiz!', '跳进我的软软小题吧！');
        }, 0.3);
    }

    private submitOption(option: string) {
        if (this.inputLocked) { return; }
        this.lastTappedOption = option;
        if (this.previewHost) {
            const reply = this.previewHost.submit(option);
            this.applyAnimation(reply.animation);
            this.applyState(reply.state);
            this.applyQuestion(reply.question);
            return;
        }
        this.bridge.send({ type: 'battle/submitOption', payload: { option } });
    }

    private handleMessage(msg: NativeToScriptMessage) {
        switch (msg.type) {
            case 'battle/init': this.applyInit(msg.payload); break;
            case 'battle/state': this.applyState(msg.payload); break;
            case 'battle/question': this.applyQuestion(msg.payload); break;
            case 'battle/animation': this.applyAnimation(msg.payload); break;
            case 'battle/bossIntro':
                this.showBossIntro(msg.payload.monsterIndex, msg.payload.name,
                    msg.payload.introLineEn, msg.payload.introLineZh);
                break;
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
        this.feedbackHolding = false;
        this.pendingQuestion = null;
        this.inputLocked = false;
    }

    private applyState(payload: BattleStatePayload) {
        this.topStatus.setCombo(payload.comboCount);
        this.topStatus.setCountdown(payload.remainingSeconds);
        this.playerCard.setHp(payload.playerHp, payload.playerMaxHp);
        if (payload.monsterIndex !== this.lastMonsterIndex) {
            if (this.lastMonsterIndex > 0) {
                this.monsterCard.playSpawnTransition();
            }
            this.lastMonsterIndex = payload.monsterIndex;
            if (this.bossIntroMonsterIndex !== payload.monsterIndex) {
                this.bossIntro.hide();
            }
        }
        this.monsterCard.setIdentity(
            payload.monster.imageKey,
            payload.monster.name,
            `Monster ${payload.monsterIndex} / ${payload.monstersTotal}`,
        );
        this.monsterCard.setHp(payload.monsterHp, payload.monsterMaxHp);
        this.monsterCard.setLevelBadge(payload.monster.levelLabel);
        if (payload.status !== 'playing') {
            this.inputLocked = true;
        }
    }

    /// While feedback is on screen the next question is buffered and applied
    /// after the 650 ms hold (mirrors the native swap timing).
    private applyQuestion(payload: BattleQuestionPayload) {
        if (this.feedbackHolding) {
            this.pendingQuestion = payload;
            return;
        }
        this.showQuestion(payload);
    }

    private showQuestion(payload: BattleQuestionPayload) {
        this.currentQuestion = payload;
        this.questionPanel.setQuestion(payload);
        this.answerRow.setOptions(optionsForQuestion(payload));
        if (payload.kind === 'spell') {
            this.spellState = new SpellViewState(
                payload.spellLetters, payload.spellRevealedMask, payload.spellPool);
            this.spellPool.setLetters(payload.spellPool);
        } else {
            this.spellState = null;
            this.spellPool.setVisible(false);
        }
        this.questionPanel.setFeedback(IDLE_FEEDBACK, theme.textSecondary);
        this.topStatus.setEscapeEnabled(true);
        this.inputLocked = false;
    }

    private handleSpellPoolTap(poolIndex: number) {
        if (this.inputLocked) { return; }
        const state = this.spellState;
        const question = this.currentQuestion;
        if (!state || !question) { return; }

        switch (state.tapPool(poolIndex)) {
            case 'fill':
                this.spellPool.markConsumed(poolIndex);
                this.questionPanel.renderSpellSlots(question, state.filledCount);
                break;
            case 'complete':
                this.spellPool.markConsumed(poolIndex);
                this.questionPanel.renderSpellSlots(question, state.filledCount);
                this.submitOption(question.answer);
                break;
            case 'wrong':
                this.spellPool.shake(poolIndex);
                if (this.previewHost) {
                    this.questionPanel.setFeedback('Try again', theme.red);
                } else {
                    this.bridge.send({ type: 'battle/spellWrongTap', payload: {} });
                }
                break;
            case 'ignored':
                break;
        }
    }

    private applyAnimation(payload: BattleAnimationPayload) {
        this.inputLocked = true;
        this.feedbackHolding = true;
        this.topStatus.setEscapeEnabled(false);
        this.answerRow.setSelection(
            { selected: this.lastTappedOption, correct: payload.correct },
            true,
        );
        this.questionPanel.setFeedback(payload.feedbackText, feedbackColorHex(payload));

        for (const step of planAnimation(payload)) {
            if (step.delayMs === 0) {
                this.runAnimationStep(step);
            } else {
                this.scheduleOnce(() => this.runAnimationStep(step), step.delayMs / 1000);
            }
        }

        this.scheduleOnce(() => {
            this.feedbackHolding = false;
            if (this.pendingQuestion) {
                const next = this.pendingQuestion;
                this.pendingQuestion = null;
                this.showQuestion(next);
            } else {
                this.answerRow.setSelection(null, false);
                this.inputLocked = false;
            }
        }, FEEDBACK_HOLD_SECONDS);
    }

    /// Auto-dismisses after ~1.05 s (native parity) unless a newer monster
    /// replaced it first.
    private showBossIntro(monsterIndex: number, name: string, lineEn: string, lineZh: string) {
        this.bossIntroMonsterIndex = monsterIndex;
        this.bossIntro.show(name, lineEn, lineZh);
        this.scheduleOnce(() => {
            if (this.bossIntroMonsterIndex === monsterIndex) {
                this.bossIntro.hide();
            }
        }, 1.05);
    }

    private runAnimationStep(step: AnimationStep) {
        switch (step.target) {
            case 'projectile':
                this.projectileLayer.fly(step.effect as 'forward' | 'backward', step.label ?? '', step.intensity ?? 1);
                break;
            case 'player':
                this.playerCard.playMotion(step.effect, this.playerPoseTextures(step.effect));
                break;
            case 'monster':
                this.monsterCard.playMotion(step.effect);
                break;
            case 'crit':
                this.critOverlay.show(step.label ?? '');
                break;
            case 'floaterPlayer':
                this.floaterLayer.show('player', step.label ?? '');
                break;
            case 'floaterMonster':
                this.floaterLayer.show('monster', step.label ?? '');
                break;
        }
    }

    private playerPoseTextures(effect: string): { temp: string; revert: string } | undefined {
        switch (effect) {
            case 'hurt': return { temp: this.playerArt.hurt, revert: this.playerArt.idle };
            // Native swaps to the fight pose for normal hits too (triggerPlayerNudge).
            case 'nudge':
            case 'cast': return { temp: this.playerArt.fight, revert: this.playerArt.idle };
            default: return undefined;
        }
    }
}
