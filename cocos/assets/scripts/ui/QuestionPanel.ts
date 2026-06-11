// Center question panel with per-kind rendering (mirrors BattleView.swift
// questionPanel / spellingTemplate / letterTemplateSlot):
// choice          — big Chinese prompt (42pt)
// fill-letter(-medium) — smaller prompt (28pt) + letter template slots:
//   missing slot = pink rounded box + red underscore; pending (medium other
//   step) = gray box + gray glyph; filled = navy glyph, no box
// sentence-cloze  — English template with blank + Chinese sentence
// spell           — prompt + spell slots (letter pool handled by SpellPool)

import { Graphics, Label, Node, UITransform } from 'cc';
import type { BattleQuestionPayload } from '../bridge/messages';
import { LetterTemplateSlot, metricsForGlyphCount, slotsFromTemplate } from './letterTemplate';
import { color, makeCapsule, makeLabel, makeNode } from './nodeFactory';
import { theme } from './theme';

const SLOT_SCALE = 1.5;
const PROMPT_LARGE = 63;   // native 42pt (choice)
const PROMPT_SMALL = 42;   // native 28pt (template kinds)
const MISSING_BG = '#FCEBEB';
const MISSING_TEXT = '#E63845';
const PENDING_BG = '#F2F2F5';
const PENDING_TEXT = '#A3A3A3';
const FILLED_TEXT = '#1C3657';

export class QuestionPanel {
    private promptLabel!: Label;
    private feedbackLabel!: Label;
    private sentenceTemplateLabel!: Label;
    private sentenceZhLabel!: Label;
    private templateRow!: Node;
    speakerNode!: Node;
    onSpeakerTap: (() => void) | null = null;

    build(parent: Node): void {
        const panel = makeNode('QuestionPanel', parent, 0, 40);

        makeLabel('CaptionLabel', panel, 'Question', 26, theme.questionCaption, { y: 165 });
        this.promptLabel = makeLabel('PromptLabel', panel, '', PROMPT_LARGE, theme.navy, { y: 95 });

        this.sentenceTemplateLabel = makeLabel('SentenceTemplateLabel', panel, '', 30, theme.navy, { y: 105 });
        this.sentenceZhLabel = makeLabel('SentenceZhLabel', panel, '', 24, theme.textSecondary, { y: 60 });

        this.templateRow = makeNode('LetterTemplateRow', panel, 0, 20);

        this.speakerNode = makeCapsule('SpeakerButton', panel, 87, 87, theme.paleBlue, { y: -85 });
        makeLabel('SpeakerGlyph', this.speakerNode, '🔊', 42, theme.navy);
        this.speakerNode.on(Node.EventType.TOUCH_END, () => { this.onSpeakerTap?.(); });

        this.feedbackLabel = makeLabel('FeedbackLabel', panel, 'Choose the right spell', 24, theme.textSecondary, { y: -168 });
        this.feedbackLabel.isBold = false;
    }

    setQuestion(question: BattleQuestionPayload): void {
        const sentence = question.kind === 'sentence-cloze';
        const hasTemplate = question.kind !== 'choice' && !sentence;
        this.promptLabel.node.active = !sentence;
        this.sentenceTemplateLabel.node.active = sentence;
        this.sentenceZhLabel.node.active = sentence;
        this.promptLabel.string = sentence ? '' : question.promptZh;
        this.promptLabel.fontSize = hasTemplate ? PROMPT_SMALL : PROMPT_LARGE;
        this.promptLabel.lineHeight = Math.round(this.promptLabel.fontSize * 1.2);
        this.sentenceTemplateLabel.string = question.sentenceTemplate;
        this.sentenceZhLabel.string = question.sentenceZh;

        switch (question.kind) {
            case 'fill-letter':
                this.renderTemplate(slotsFromTemplate(question.letterTemplate, question.missingIndex));
                break;
            case 'fill-letter-medium': {
                const missing = question.missingIndices[question.currentStep] ?? -1;
                const pendingStep = question.currentStep === 0 ? 1 : 0;
                const pending = question.missingIndices[pendingStep] ?? -1;
                this.renderTemplate(slotsFromTemplate(question.letterTemplateBase, missing, pending));
                break;
            }
            case 'spell':
                this.renderSpellSlots(question);
                break;
            default:
                this.renderTemplate([]);
        }
    }

    /// Spell slots: revealed letters show, hidden show _ until filled locally.
    renderSpellSlots(question: BattleQuestionPayload, filledCount = 0): void {
        const slots = question.spellLetters.map((letter, i) => ({
            glyph: letter,
            originalIndex: i,
            isMissing: !question.spellRevealedMask[i] && i >= this.firstHiddenIndex(question, filledCount),
            isPending: false,
        }));
        this.renderTemplate(slots);
    }

    private firstHiddenIndex(question: BattleQuestionPayload, filledCount: number): number {
        let remaining = filledCount;
        for (let i = 0; i < question.spellLetters.length; i += 1) {
            if (question.spellRevealedMask[i]) { continue; }
            if (remaining > 0) { remaining -= 1; continue; }
            return i;
        }
        return question.spellLetters.length;
    }

    private renderTemplate(slots: LetterTemplateSlot[]): void {
        this.templateRow.removeAllChildren();
        this.templateRow.active = slots.length > 0;
        if (slots.length === 0) { return; }

        // Swift metrics are iPhone points; design space is ~1.5x.
        const metrics = metricsForGlyphCount(slots.length);
        const slotWidth = metrics.width * SLOT_SCALE;
        const slotHeight = metrics.height * SLOT_SCALE;
        const step = slotWidth + metrics.gap * SLOT_SCALE;
        const startX = -((slots.length - 1) * step) / 2;

        slots.forEach((slot, i) => {
            const slotNode = makeNode(`Slot${i}`, this.templateRow, startX + i * step, 0);
            slotNode.getComponent(UITransform)!.setContentSize(slotWidth, slotHeight);
            if (slot.glyph === ' ') { return; }

            let textHex = FILLED_TEXT;
            let fontSize = metrics.filledFontSize * SLOT_SCALE;
            let glyph = slot.glyph;
            let bgHex: string | null = null;
            if (slot.isMissing) {
                bgHex = MISSING_BG;
                textHex = MISSING_TEXT;
                fontSize = metrics.placeholderFontSize * SLOT_SCALE;
                glyph = '_';
            } else if (slot.isPending) {
                bgHex = PENDING_BG;
                textHex = PENDING_TEXT;
                fontSize = metrics.placeholderFontSize * SLOT_SCALE;
            }

            if (bgHex !== null) {
                const g = slotNode.addComponent(Graphics);
                g.roundRect(-slotWidth / 2, -slotHeight / 2, slotWidth, slotHeight, 9);
                g.fillColor = color(bgHex);
                g.fill();
            }
            makeLabel('Glyph', slotNode, glyph, fontSize, textHex);
        });
    }

    setFeedback(text: string, hex: string): void {
        this.feedbackLabel.string = text;
        this.feedbackLabel.color.fromHEX(hex);
        this.feedbackLabel.color = this.feedbackLabel.color.clone();
    }
}
