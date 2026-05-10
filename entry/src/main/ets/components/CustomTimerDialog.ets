/**
 * V0.6.7.7 — single-numeric-field dialog used by `pages/ConfigPage`'s
 * 自定义 timer button to let the parent dial in any battle countdown
 * outside the four `TIMER_CHOICES` chips (30s / 3m / 5m / 10m). The
 * primary motivation is UI-test ergonomics: the
 * `customTimer3sTriggersFastBattleTimeout` flow uses this dialog to
 * inject 3s so the timer-expiry path triggers in seconds rather than
 * forcing the suite to wait the full 30s minimum chip.
 *
 * Pure validation helpers are exported so unit tests can cover the
 * edge cases (empty / NaN / out-of-range / float) independently of
 * the UI tree — `CustomDialogController` is awkward to drive from
 * Hypium's `describe`/`it` harness.
 *
 * Submit semantics:
 *   - `onSubmit(seconds)` is called with the validated integer second
 *     count when the parent taps 确定. The dialog closes itself on a
 *     successful submit; the caller need not call `controller.close()`.
 *   - `onCancel()` fires when the parent taps 取消 (or backdrop). The
 *     dialog also self-closes in that case.
 *
 * Validation:
 *   - input must be a non-empty digit-only string after `trim()`
 *   - parsed integer must satisfy
 *     `TIMER_CUSTOM_MIN ≤ n ≤ TIMER_CUSTOM_MAX` (defined in
 *     `models/GameConfig.ets`).
 */

import {
  TIMER_CUSTOM_MIN,
  TIMER_CUSTOM_MAX,
} from '../models/GameConfig';

const DIGITS_RE: RegExp = /^[0-9]+$/;

export interface CustomTimerValidation {
  ok: boolean;
  /** Parsed integer seconds when `ok === true`; otherwise 0. */
  seconds: number;
  /** User-facing error message when `ok === false`; otherwise empty. */
  message: string;
}

/**
 * Pure validator. Trims whitespace, rejects empty / non-digit input,
 * and bounds-checks against `[TIMER_CUSTOM_MIN, TIMER_CUSTOM_MAX]`.
 */
export function validateCustomTimerSeconds(input: string): CustomTimerValidation {
  const trimmed: string = input.trim();
  const out: CustomTimerValidation = { ok: false, seconds: 0, message: '' };
  if (trimmed.length === 0) {
    out.message = '请输入秒数';
    return out;
  }
  if (!DIGITS_RE.test(trimmed)) {
    // Reject negatives / floats / scientific notation. Forces the
    // dialog into a strictly-positive-integer contract that matches
    // BattleEngine.startingSeconds expectations.
    out.message = '请输入正整数秒数';
    return out;
  }
  const parsed: number = parseInt(trimmed, 10);
  if (!Number.isFinite(parsed) || Number.isNaN(parsed)) {
    out.message = '请输入正整数秒数';
    return out;
  }
  if (parsed < TIMER_CUSTOM_MIN) {
    out.message = `最少 ${TIMER_CUSTOM_MIN} 秒`;
    return out;
  }
  if (parsed > TIMER_CUSTOM_MAX) {
    out.message = `最多 ${TIMER_CUSTOM_MAX} 秒`;
    return out;
  }
  out.ok = true;
  out.seconds = parsed;
  return out;
}

@CustomDialog
export struct CustomTimerDialog {
  controller?: CustomDialogController;
  initialSeconds: number = 30;
  onSubmit: (seconds: number) => void = (): void => {};
  onCancel: () => void = (): void => {};

  @State private inputValue: string = '';
  @State private errorMessage: string = '';

  aboutToAppear(): void {
    // Pre-populate with the current saved value so a parent only has
    // to tweak (not retype). When the value happens to already be in
    // TIMER_CHOICES the chip will re-highlight as soon as they save.
    this.inputValue = `${this.initialSeconds}`;
  }

  build(): void {
    Column({ space: 16 }) {
      Text('自定义倒计时')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557')
        .id('CustomTimerDialogTitle');

      Text(`请输入倒计时秒数（${TIMER_CUSTOM_MIN} - ${TIMER_CUSTOM_MAX}）`)
        .id('CustomTimerDialogHint')
        .fontSize(14)
        .fontColor('#6B7280');

      TextInput({ placeholder: '秒', text: this.inputValue })
        .id('CustomTimerDialogInput')
        .type(InputType.Number)
        .height(44)
        .fontSize(16)
        .placeholderColor('#BBBBBB')
        .borderRadius(8)
        .backgroundColor('#F1F2F4')
        .padding({ left: 12, right: 12 })
        // Cap input length at 4 digits — `TIMER_CUSTOM_MAX` is 3600
        // (4 digits). Prevents the user from accidentally tapping
        // "999999" and then having the validator complain.
        .maxLength(4)
        .onChange((value: string): void => {
          this.inputValue = value;
          this.errorMessage = '';
        });

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .id('CustomTimerDialogError')
          .fontSize(13)
          .fontColor('#E63946');
      }

      Row({ space: 16 }) {
        Button('取消')
          .id('CustomTimerDialogCancelButton')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#F1F2F4')
          .fontColor('#1D3557')
          .onClick((): void => {
            this.dismiss();
            this.onCancel();
          });
        Button('确定')
          .id('CustomTimerDialogConfirmButton')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#E63946')
          .fontColor('#FFFFFF')
          .onClick((): void => {
            this.handleConfirm();
          });
      }
      .width('100%');
    }
    .padding({ top: 24, bottom: 24, left: 20, right: 20 })
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
    .width('72%')
    .id('CustomTimerDialog');
  }

  private handleConfirm(): void {
    const v: CustomTimerValidation = validateCustomTimerSeconds(this.inputValue);
    if (!v.ok) {
      this.errorMessage = v.message;
      return;
    }
    this.dismiss();
    this.onSubmit(v.seconds);
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }
}
