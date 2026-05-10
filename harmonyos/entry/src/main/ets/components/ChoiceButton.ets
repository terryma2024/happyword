/**
 * ChoiceButton is the uniform answer-button used on the BattlePage.
 *
 * V0.1 design goals (spec §7.3, §9.2, §9.3):
 * - Large touch target so young children can tap confidently.
 * - Four visual states driven by a single `state` prop so T6/T7 can toggle
 *   feedback without duplicating button widgets:
 *     - Idle: default, waiting for input.
 *     - Correct: bright positive highlight after a right answer.
 *     - Wrong: red highlight on the chosen-wrong option.
 *     - Disabled: greyed out; no taps accepted.
 * - Tap handling stays in the parent. The component only reports which text
 *   was tapped so the parent (T6 BattleEngine) can decide what "correct"
 *   means without this view owning any game state.
 *
 * The `id` property is forwarded to `.id(...)` so UI tests can target
 * individual buttons (BattleOptionA/B/C) without relying on text matching.
 */
export enum ChoiceState {
  Idle = 'idle',
  Correct = 'correct',
  Wrong = 'wrong',
  Disabled = 'disabled',
}

@Reusable
@Component
export struct ChoiceButton {
  @Prop text: string = '';
  choiceId: string = '';
  @Prop state: ChoiceState = ChoiceState.Idle;
  onTap: (text: string) => void = (): void => {};

  // Idle uses the project's signature warm purple so the buttons read as
  // "magical" rather than plain system buttons. Feedback colours are chosen
  // for high contrast against the idle state and against each other.
  private static readonly BG_IDLE: string = '#7B4FA0';
  private static readonly BG_CORRECT: string = '#2ECC71';
  private static readonly BG_WRONG: string = '#E74C3C';
  private static readonly BG_DISABLED: string = '#B0B0B0';

  private backgroundFor(state: ChoiceState): string {
    if (state === ChoiceState.Correct) {
      return ChoiceButton.BG_CORRECT;
    }
    if (state === ChoiceState.Wrong) {
      return ChoiceButton.BG_WRONG;
    }
    if (state === ChoiceState.Disabled) {
      return ChoiceButton.BG_DISABLED;
    }
    return ChoiceButton.BG_IDLE;
  }

  private isInteractive(): boolean {
    return this.state === ChoiceState.Idle;
  }

  build() {
    Button(this.text)
      .id(this.choiceId)
      .type(ButtonType.Capsule)
      .layoutWeight(1)
      .height(60)
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .backgroundColor(this.backgroundFor(this.state))
      .enabled(this.isInteractive())
      .margin({ left: 8, right: 8 })
      .onClick((): void => {
        if (!this.isInteractive()) {
          return;
        }
        this.onTap(this.text);
      });
  }
}
