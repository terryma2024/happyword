// Center question panel: caption, Chinese prompt, speaker button, feedback line.
// Static layout for Phase 1; per-kind renderers land in Phase 3.
// Mirrors BattleView.swift questionPanel.

import { Label, Node } from 'cc';
import { makeCapsule, makeLabel, makeNode } from './nodeFactory';
import { theme } from './theme';

export class QuestionPanel {
    private promptLabel!: Label;
    private feedbackLabel!: Label;
    speakerNode!: Node;
    onSpeakerTap: (() => void) | null = null;

    build(parent: Node): void {
        const panel = makeNode('QuestionPanel', parent, 0, 40);

        makeLabel('CaptionLabel', panel, 'Question', 22, theme.textSecondary, { y: 130 });
        this.promptLabel = makeLabel('PromptLabel', panel, '', 64, theme.ink, { y: 60 });

        this.speakerNode = makeCapsule('SpeakerButton', panel, 64, 64, theme.navy, { y: -30 });
        makeLabel('SpeakerGlyph', this.speakerNode, '♪', 30, theme.white);
        this.speakerNode.on(Node.EventType.TOUCH_END, () => { this.onSpeakerTap?.(); });

        this.feedbackLabel = makeLabel('FeedbackLabel', panel, 'Choose the right spell', 24, theme.textSecondary, { y: -110 });
        this.feedbackLabel.isBold = false;
    }

    setPrompt(text: string): void {
        this.promptLabel.string = text;
    }

    setFeedback(text: string, hex: string): void {
        this.feedbackLabel.string = text;
        this.feedbackLabel.color.fromHEX(hex);
        this.feedbackLabel.color = this.feedbackLabel.color.clone();
    }
}
