/**
 * V0.6.8 — single-field dialog used by `BoundDeviceInfoPage` to edit
 * the bound child's display nickname. Pattern mirrors
 * `AddCustomWishDialog`: pure validation helper exported for unit
 * tests, plus the `@CustomDialog` struct that drives the UI.
 *
 * Submit semantics:
 *   - `onSubmit(trimmed)` returns a `NicknameSubmitResult`. The dialog
 *     manages its own busy-state, inline error message, and close-on-
 *     success — so the parent only needs to drive the network call and
 *     return either `{ ok: true }` or `{ ok: false, message: '...' }`.
 *
 * Validation (matches the server contract documented in
 * `docs/superpowers/specs/2026-05-08-editable-child-nickname-design.md`):
 *   - non-empty after `trim()`
 *   - max 32 characters
 */

export const CHILD_NICKNAME_MAX_CHARS: number = 32;

export interface NicknameValidation {
  ok: boolean;
  message: string;
}

export interface NicknameSubmitResult {
  ok: boolean;
  message?: string;
}

export function validateChildNickname(input: string): NicknameValidation {
  const trimmed: string = input.trim();
  const out: NicknameValidation = { ok: false, message: '' };
  if (trimmed.length === 0) {
    out.message = '请输入孩子的名字';
    return out;
  }
  if (trimmed.length > CHILD_NICKNAME_MAX_CHARS) {
    out.message = `名字最多 ${CHILD_NICKNAME_MAX_CHARS} 个字符`;
    return out;
  }
  out.ok = true;
  return out;
}

@CustomDialog
export struct EditChildNicknameDialog {
  controller?: CustomDialogController;
  initialNickname: string = '';
  onSubmit: (trimmed: string) => Promise<NicknameSubmitResult> = async () => {
    return { ok: true };
  };
  onCancel: () => void = () => {};

  @State private nickname: string = '';
  @State private errorMessage: string = '';
  @State private busy: boolean = false;

  aboutToAppear(): void {
    this.nickname = this.initialNickname;
  }

  build(): void {
    Column({ space: 16 }) {
      Text('修改孩子的名字')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557')
        .id('EditChildNicknameDialogTitle');

      Column({ space: 8 }) {
        Text('名字')
          .fontSize(14)
          .fontColor('#888888');
        TextInput({ placeholder: '宝贝', text: this.nickname })
          .id('EditChildNicknameInput')
          .height(44)
          .fontSize(16)
          .placeholderColor('#BBBBBB')
          .borderRadius(8)
          .backgroundColor('#F1F2F4')
          .padding({ left: 12, right: 12 })
          .maxLength(CHILD_NICKNAME_MAX_CHARS)
          .enabled(!this.busy)
          .onChange((value: string): void => {
            this.nickname = value;
            this.errorMessage = '';
          });
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%');

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .id('EditChildNicknameError')
          .fontSize(13)
          .fontColor('#E63946');
      }

      Row({ space: 16 }) {
        Button('取消')
          .id('EditChildNicknameCancelButton')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#F1F2F4')
          .fontColor('#1D3557')
          .enabled(!this.busy)
          .onClick((): void => {
            this.dismiss();
            this.onCancel();
          });
        Button(this.busy ? '保存中…' : '保存')
          .id('EditChildNicknameSubmitButton')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#E63946')
          .fontColor('#FFFFFF')
          .enabled(!this.busy)
          .onClick((): void => {
            this.handleSubmit();
          });
      }
      .width('100%');
    }
    .padding({ top: 24, bottom: 24, left: 20, right: 20 })
    .backgroundColor('#FFFFFF')
    .borderRadius(20)
    .width('86%')
    .id('EditChildNicknameDialog');
  }

  private async handleSubmit(): Promise<void> {
    // Snapshot @State reads into locals once, then derive everything
    // from those (perf rule hp-arkui-use-local-var-to-replace-state-var
    // discourages repeated `this.<state>` reads in non-build methods).
    const current: string = this.nickname;
    const v: NicknameValidation = validateChildNickname(current);
    if (!v.ok) {
      this.errorMessage = v.message;
      return;
    }
    this.errorMessage = '';
    this.busy = true;
    let nextError: string = '';
    let close: boolean = false;
    try {
      const result: NicknameSubmitResult = await this.onSubmit(current.trim());
      if (result.ok) {
        close = true;
      } else if (result.message !== undefined && result.message.length > 0) {
        nextError = result.message;
      } else {
        nextError = '保存失败';
      }
    } catch (_err) {
      nextError = '保存失败，请稍后重试';
    }
    if (close) {
      this.dismiss();
      return;
    }
    this.busy = false;
    this.errorMessage = nextError;
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }
}
