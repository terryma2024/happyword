/**
 * V0.6.2 — DevMenu prompt for the Vercel "Protection Bypass for
 * Automation" secret. Shown when the user taps a Preview-deployment
 * card and no bypass secret is yet stored.
 *
 * The secret is project-wide (per Vercel project, not per
 * deployment) so the user enters it once and we persist it via
 * `BackendEnv.saveBypassSecret`. From then on every API request to a
 * Preview deployment automatically attaches
 * `x-vercel-protection-bypass: <secret>` (see `BackendHeaders.ets`).
 *
 * Mirrors the `AddCustomWishDialog` pattern: the consumer constructs
 * a `CustomDialogController` with an explicit local handle and routes
 * `onSubmit` / `onCancel` through closures that close the dialog on
 * the captured handle. The auto-bound `controller` field on the
 * @CustomDialog struct has been observed to bind unreliably with
 * `customStyle: true`, so we don't depend on it.
 */

@CustomDialog
export struct BypassSecretDialog {
  /** Auto-bound by ArkUI. We don't rely on it (see file docstring) but
   *  declare it for compatibility with the @CustomDialog contract. */
  controller?: CustomDialogController;

  /** Optional pre-fill — used when the user is editing an existing
   *  secret rather than entering one for the first time. */
  initialSecret: string = '';

  /** Fires when the user taps "Save". The dialog is already closed by
   *  the consumer's closure; this callback receives the trimmed
   *  secret and is expected to persist + retry the probe. */
  onSubmit: (secret: string) => void = (_s: string) => {};

  /** Fires when the user taps "Cancel" (or backdrop, autoCancel). The
   *  dialog is already closed; consumer should abort the env switch. */
  onCancel: () => void = () => {};

  @State private secret: string = '';
  @State private errorMessage: string = '';

  aboutToAppear(): void {
    if (this.initialSecret.length > 0) {
      this.secret = this.initialSecret;
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('Vercel Bypass Secret')
        .id('BypassSecretDialogTitle')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D3557');

      Text('Preview deployments are auth-gated by Vercel Deployment Protection. Paste the project\'s "Protection Bypass for Automation" secret to let the device through.')
        .fontSize(12)
        .fontColor('#666666')
        .width('100%');

      Column({ space: 6 }) {
        Text('Secret')
          .fontSize(13)
          .fontColor('#888888');
        TextInput({ placeholder: 'paste from Vercel project settings', text: this.secret })
          .id('BypassSecretInput')
          .height(44)
          .fontSize(15)
          .placeholderColor('#BBBBBB')
          .borderRadius(8)
          .backgroundColor('#F1F2F4')
          .padding({ left: 12, right: 12 })
          // type(Password) hides the value behind dots; users
          // copy-paste the secret from the dashboard so this is
          // pure UX hygiene, not a security boundary.
          .type(InputType.Password)
          .onChange((value: string): void => {
            this.secret = value;
            this.errorMessage = '';
          });
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%');

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .id('BypassSecretError')
          .fontSize(12)
          .fontColor('#E63946');
      }

      Row({ space: 12 }) {
        Button('Cancel')
          .id('BypassSecretCancelButton')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F1F2F4')
          .fontColor('#1D3557')
          .onClick((): void => {
            this.onCancel();
          });
        Button('Save')
          .id('BypassSecretSubmitButton')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#457B9D')
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
    .id('BypassSecretDialog');
  }

  private handleSubmit(): void {
    const trimmed: string = this.secret.trim();
    if (trimmed.length === 0) {
      this.errorMessage = 'Secret cannot be empty';
      return;
    }
    this.onSubmit(trimmed);
  }
}
