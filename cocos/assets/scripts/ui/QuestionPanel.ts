// Center question panel with per-kind rendering:
// choice          — big Chinese prompt
// fill-letter(-medium) — prompt + letter template slots (missing shows _)
// sentence-cloze  — English template with blank + Chinese sentence
// spell           — prompt + spell slots (letter pool handled by SpellPool)
// Mirrors BattleView.swift questionPanel.

import { Label, Node } from 'cc';
import type { BattleQuestionPayload } from '../bridge/messages';
import { LetterTemplateSlot, metricsForGlyphCount, slotsFromTemplate } from './letterTemplate';
import { makeCapsule, makeLabel, makeNode } from './nodeFactory';
import { theme } from './theme';

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

        makeLabel('CaptionLabel', panel, 'Question', 26, theme.questionCaption, { y: 150 });
        this.promptLabel = makeLabel('PromptLabel', panel, '', 60, theme.navy, { y: 90 });

        this.sentenceTemplateLabel = makeLabel('SentenceTemplateLabel', panel, '', 30, theme.ink, { y: 100 });
        this.sentenceZhLabel = makeLabel('SentenceZhLabel', panel, '', 24, theme.textSecondary, { y: 56 });

        this.templateRow = makeNode('LetterTemplateRow', panel, 0, 20);

        this.speakerNode = makeCapsule('SpeakerButton', panel, 87, 87, theme.paleBlue, { y: -50 });
        makeLabel('SpeakerGlyph', this.speakerNode, '🔊', 42, theme.navy);
        this.speakerNode.on(Node.EventType.TOUCH_END, () => { this.onSpeakerTap?.(); });

        this.feedbackLabel = makeLabel('FeedbackLabel', panel, 'Choose the right spell', 24, theme.textSecondary, { y: -120 });
        this.feedbackLabel.isBold = false;
    }

    setQuestion(question: BattleQuestionPayload): void {
        const sentence = question.kind === 'sentence-cloze';
        this.promptLabel.node.active = !sentence;
        this.sentenceTemplateLabel.node.active = sentence;
        this.sentenceZhLabel.node.active = sentence;
        this.promptLabel.string = sentence ? '' : question.promptZh;
        this.sentenceTemplateLabel.string = question.sentenceTemplate;
        this.sentenceZhLabel.string = question.sentenceZh;

        switch (question.kind) {
            case 'fill-letter':
                this.renderTemplate(slotsFromTemplate(question.letterTemplate, question.missingIndex));
                break;
            case 'fill-letter-medium': {
                const missing = question.missingIndices[question.currentStep] ?? -1;
                this.renderTemplate(slotsFromTemplate(question.letterTemplateBase, missing));
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
        const scale = 1.5;
        const step = (metrics.width + metrics.gap) * scale;
        const startX = -((slots.length - 1) * step) / 2;
        slots.forEach((slot, i) => {
            const shown = slot.isMissing ? '_' : slot.glyph;
            const hex = slot.isMissing ? theme.textSecondary : theme.ink;
            const size = (slot.isMissing ? metrics.placeholderFontSize : metrics.filledFontSize) * scale;
            makeLabel(`Slot${i}`, this.templateRow, shown, size, hex, { x: startX + i * step });
        });
    }

    setFeedback(text: string, hex: string): void {
        this.feedbackLabel.string = text;
        this.feedbackLabel.color.fromHEX(hex);
        this.feedbackLabel.color = this.feedbackLabel.color.clone();
    }
}
