import {
  CUSTOM_WISH_NAME_MIN_CHARS,
  CUSTOM_WISH_NAME_MAX_CHARS,
  CUSTOM_WISH_COST_MIN,
  CUSTOM_WISH_COST_MAX,
  CUSTOM_WISH_DEFAULT_EMOJI,
} from '../services/WishlistStore';

/**
 * V0.4.7 — parent-facing dialog for creating a custom wishlist
 * entry. Three inputs (name / cost / emoji) with inline validation.
 * The dialog only emits a final `(name, cost, emoji)` triple via
 * `onSubmit`; persistence + id generation lives in WishlistStore.
 *
 * The pure helpers exported below let the unit-test suite exercise
 * the validation logic without standing up a CustomDialogController.
 */

export interface CustomWishFormResult {
  name: string;
  costCoins: number;
  iconEmoji: string;
}

export interface CustomWishValidation {
  ok: boolean;
  message: string;
}

/**
 * Validate the raw form state. Returns `{ ok: true, message: '' }`
 * when ready to submit; otherwise returns the first user-facing
 * error string (Chinese, single line, fits on the dialog).
 */
export function validateCustomWishForm(
  name: string,
  costRaw: string,
  emoji: string,
): CustomWishValidation {
  const trimmed: string = name.trim();
  const out: CustomWishValidation = { ok: false, message: '' };
  if (trimmed.length < CUSTOM_WISH_NAME_MIN_CHARS) {
    out.message = '请输入愿望名称';
    return out;
  }
  if (trimmed.length > CUSTOM_WISH_NAME_MAX_CHARS) {
    out.message = `名称最多 ${CUSTOM_WISH_NAME_MAX_CHARS} 字`;
    return out;
  }
  const costStr: string = costRaw.trim();
  if (costStr.length === 0 || !/^[0-9]+$/.test(costStr)) {
    out.message = '魔法币数量必须是数字';
    return out;
  }
  const cost: number = parseInt(costStr, 10);
  if (cost < CUSTOM_WISH_COST_MIN || cost > CUSTOM_WISH_COST_MAX) {
    out.message = `数量需在 ${CUSTOM_WISH_COST_MIN} ~ ${CUSTOM_WISH_COST_MAX} 之间`;
    return out;
  }
  const trimmedEmoji: string = emoji.trim();
  if (trimmedEmoji.length > 4) {
    out.message = '表情最多 1-2 个字符';
    return out;
  }
  out.ok = true;
  return out;
}

/**
 * Pure helper that mirrors the dialog's "submit" path. Returns
 * the canonical form result on success and `undefined` when
 * validation fails. UI tests can drive this via `validateCustomWishForm`
 * + `buildCustomWishFormResult`.
 */
export function buildCustomWishFormResult(
  name: string,
  costRaw: string,
  emoji: string,
): CustomWishFormResult | undefined {
  const v: CustomWishValidation = validateCustomWishForm(name, costRaw, emoji);
  if (!v.ok) {
    return undefined;
  }
  const trimmed: string = name.trim();
  const cost: number = parseInt(costRaw.trim(), 10);
  let iconEmoji: string = emoji.trim();
  if (iconEmoji.length === 0) {
    iconEmoji = CUSTOM_WISH_DEFAULT_EMOJI;
  }
  const out: CustomWishFormResult = { name: trimmed, costCoins: cost, iconEmoji };
  return out;
}

@CustomDialog
export struct AddCustomWishDialog {
  controller?: CustomDialogController;
  onSubmit: (result: CustomWishFormResult) => void = () => {};
  onCancel: () => void = () => {};

  @State private name: string = '';
  @State private costRaw: string = '';
  @State private emoji: string = '';
  @State private errorMessage: string = '';

  build() {
    Column({ space: 16 }) {
      Text('添加魔法愿望')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557')
        .id('AddCustomWishDialogTitle');

      Column({ space: 8 }) {
        Text('愿望名称')
          .fontSize(14)
          .fontColor('#888888');
        TextInput({ placeholder: `1-${CUSTOM_WISH_NAME_MAX_CHARS} 字`, text: this.name })
          .id('AddCustomWishNameInput')
          .height(44)
          .fontSize(16)
          .placeholderColor('#BBBBBB')
          .borderRadius(8)
          .backgroundColor('#F1F2F4')
          .padding({ left: 12, right: 12 })
          .maxLength(CUSTOM_WISH_NAME_MAX_CHARS)
          .onChange((value: string): void => {
            this.name = value;
            this.errorMessage = '';
          });
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%');

      Column({ space: 8 }) {
        Text('需要的魔法币数量')
          .fontSize(14)
          .fontColor('#888888');
        TextInput({ placeholder: `${CUSTOM_WISH_COST_MIN}-${CUSTOM_WISH_COST_MAX}`, text: this.costRaw })
          .id('AddCustomWishCostInput')
          .type(InputType.Number)
          .height(44)
          .fontSize(16)
          .placeholderColor('#BBBBBB')
          .borderRadius(8)
          .backgroundColor('#F1F2F4')
          .padding({ left: 12, right: 12 })
          .onChange((value: string): void => {
            this.costRaw = value;
            this.errorMessage = '';
          });
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%');

      Column({ space: 8 }) {
        Text('表情图标 (留空使用 ⭐)')
          .fontSize(14)
          .fontColor('#888888');
        TextInput({ placeholder: '🎬 / 🎁 / 🍦 ...', text: this.emoji })
          .id('AddCustomWishEmojiInput')
          .height(44)
          .fontSize(16)
          .placeholderColor('#BBBBBB')
          .borderRadius(8)
          .backgroundColor('#F1F2F4')
          .padding({ left: 12, right: 12 })
          .maxLength(4)
          .onChange((value: string): void => {
            this.emoji = value;
            this.errorMessage = '';
          });
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%');

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .id('AddCustomWishError')
          .fontSize(13)
          .fontColor('#E63946');
      }

      Row({ space: 16 }) {
        Button('取消')
          .id('AddCustomWishCancelButton')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#F1F2F4')
          .fontColor('#1D3557')
          .onClick((): void => {
            this.dismiss();
            this.onCancel();
          });
        Button('添加')
          .id('AddCustomWishSubmitButton')
          .layoutWeight(1)
          .height(44)
          .backgroundColor('#E63946')
          .fontColor('#FFFFFF')
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
    .id('AddCustomWishDialog');
  }

  private handleSubmit(): void {
    const v: CustomWishValidation = validateCustomWishForm(
      this.name,
      this.costRaw,
      this.emoji,
    );
    if (!v.ok) {
      this.errorMessage = v.message;
      return;
    }
    const result: CustomWishFormResult | undefined = buildCustomWishFormResult(
      this.name,
      this.costRaw,
      this.emoji,
    );
    if (result === undefined) {
      // Defensive: validation already flagged this path, but keep the
      // safety net in case future refactors decouple the two helpers.
      this.errorMessage = '请检查输入';
      return;
    }
    this.dismiss();
    this.onSubmit(result);
  }

  private dismiss(): void {
    if (this.controller !== undefined) {
      this.controller.close();
    }
  }
}
