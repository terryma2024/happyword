import { UIContext } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';

/**
 * V0.3.9: parent PIN gate dialog used by WishlistPage. Built as a
 * full-screen `@CustomDialog` so we can layout a virtual numeric
 * keypad (3×4) plus a row of 6 dot placeholders without competing
 * with the system keyboard. Pure helper functions are exported so
 * unit tests can cover the input edge cases independently of the
 * UI tree (CustomDialogController is not unit-test friendly).
 */

export const PIN_LENGTH: number = 6;

const DIGIT_RE: RegExp = /^[0-9]$/;

/** True when both buffers are exactly PIN_LENGTH digit characters and equal. */
export function validatePin(input: string, expected: string): boolean {
  if (input.length !== PIN_LENGTH || expected.length !== PIN_LENGTH) {
    return false;
  }
  for (let i = 0; i < PIN_LENGTH; i++) {
    if (!DIGIT_RE.test(input.charAt(i))) {
      return false;
    }
    if (!DIGIT_RE.test(expected.charAt(i))) {
      return false;
    }
  }
  return input === expected;
}

/** Append a single digit; no-op when buffer is full or input is not 0-9. */
export function pushDigit(buf: string, digit: string): string {
  if (digit.length !== 1 || !DIGIT_RE.test(digit)) {
    return buf;
  }
  if (buf.length >= PIN_LENGTH) {
    return buf;
  }
  return buf + digit;
}

/** Remove the last character (if any). */
export function popDigit(buf: string): string {
  if (buf.length === 0) {
    return buf;
  }
  return buf.substring(0, buf.length - 1);
}

const KEYPAD_ROWS: string[][] = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['', '0', '⌫'],
];

@CustomDialog
export struct ParentPinDialog {
  controller?: CustomDialogController;
  expectedPin: string = '';
  title: string = '请输入家长密码';
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  @State private buf: string = '';
  @State private errorVisible: boolean = false;
  @State private shakeOffset: number = 0;

  build() {
    Column({ space: 24 }) {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557')
        .id('ParentPinDialogTitle');

      Row({ space: 14 }) {
        ForEach([0, 1, 2, 3, 4, 5], (i: number): void => {
          Circle({ width: 16, height: 16 })
            .fill(i < this.buf.length ? '#1D3557' : '#FFFFFF')
            .stroke('#1D3557')
            .strokeWidth(1.5);
        }, (i: number): string => `dot-${i}`);
      }
      .id('ParentPinDialogDots')
      .translate({ x: this.shakeOffset, y: 0 });

      if (this.errorVisible) {
        Text('密码不正确，请重试')
          .fontSize(13)
          .fontColor('#E63946')
          .id('ParentPinDialogError');
      }

      Column({ space: 10 }) {
        ForEach(KEYPAD_ROWS, (row: string[], rowIdx: number): void => {
          Row({ space: 14 }) {
            ForEach(row, (cell: string, colIdx: number): void => {
              this.keypadCell(cell, rowIdx, colIdx);
            }, (cell: string, colIdx: number): string => `cell-${rowIdx}-${colIdx}`);
          };
        }, (row: string[], rowIdx: number): string => `row-${rowIdx}`);
      }
      .id('ParentPinDialogKeypad');

      Row({ space: 24 }) {
        Button('取消')
          .id('ParentPinDialogCancel')
          .width(110)
          .height(40)
          .backgroundColor('#F1F2F4')
          .fontColor('#1D3557')
          .onClick((): void => {
            this.dismiss();
            this.onCancel();
          });
      };
    }
    .padding({ top: 32, bottom: 32, left: 24, right: 24 })
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
    .width('86%')
    .id('ParentPinDialog');
  }

  @Builder
  private keypadCell(label: string, rowIdx: number, colIdx: number) {
    if (label.length === 0) {
      Column().width(64).height(64);
    } else if (label === '⌫') {
      Button('⌫')
        .id(`ParentPinDialogDelete`)
        .width(64)
        .height(64)
        .backgroundColor('#F1F2F4')
        .fontColor('#1D3557')
        .fontSize(20)
        .onClick((): void => {
          this.buf = popDigit(this.buf);
          this.errorVisible = false;
        });
    } else {
      Button(label)
        .id(`ParentPinDialogKey_${label}`)
        .width(64)
        .height(64)
        .backgroundColor('#FFFFFF')
        .borderColor('#1D3557')
        .borderWidth(1)
        .fontColor('#1D3557')
        .fontSize(22)
        .onClick((): void => {
          this.handleDigit(label);
        });
    }
  }

  private handleDigit(label: string): void {
    this.errorVisible = false;
    this.buf = pushDigit(this.buf, label);
    if (this.buf.length === PIN_LENGTH) {
      if (validatePin(this.buf, this.expectedPin)) {
        this.dismiss();
        this.onConfirm();
      } else {
        this.shakeOnError();
        this.buf = '';
        this.errorVisible = true;
      }
    }
  }

  private shakeOnError(): void {
    const ui: UIContext = this.getUIContext();
    ui.animateTo({ duration: 70, curve: Curve.Linear }, (): void => {
      this.shakeOffset = -8;
    });
    setTimeout((): void => {
      ui.animateTo({ duration: 70, curve: Curve.Linear }, (): void => {
        this.shakeOffset = 8;
      });
    }, 70);
    setTimeout((): void => {
      ui.animateTo({ duration: 70, curve: Curve.Linear }, (): void => {
        this.shakeOffset = 0;
      });
    }, 140);
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }
}

/**
 * Helper to surface lightweight feedback (e.g. wrong-pin toast).
 * Caller passes a UIContext (typically `this.getUIContext()` from the
 * host @Entry / @Component) since `promptAction.showToast` was
 * deprecated in favour of `UIContext.getPromptAction().showToast`.
 */
export function showPinToast(ui: UIContext, message: string): void {
  try {
    ui.getPromptAction().showToast({ message, duration: 1500 });
  } catch (err) {
    console.error(`showPinToast failed: ${JSON.stringify(err as BusinessError)}`);
  }
}
