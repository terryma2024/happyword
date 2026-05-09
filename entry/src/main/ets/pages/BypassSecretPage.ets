import { BusinessError } from '@ohos.base';
import { loadBypassSecret, saveBypassSecret } from '../services/BackendEnv';

@Entry
@Component
struct BypassSecretPage {
  @State private secret: string = '';
  @State private errorMessage: string = '';

  aboutToAppear(): void {
    loadBypassSecret().then((s: string): void => {
      if (s.length > 0) {
        this.secret = s;
      }
    }).catch((err: BusinessError): void => {
      console.error(`BypassSecretPage.load failed: ${JSON.stringify(err)}`);
    });
  }

  build(): void {
    Column({ space: 12 }) {
      Text('Bypass Secret')
        .id('BypassSecretPageTitle')
        .fontSize(20)
        .fontWeight(FontWeight.Bold);

      TextInput({ placeholder: 'paste from Vercel project settings', text: this.secret })
        .id('BypassSecretPageInput')
        .height(44)
        .fontSize(15)
        .placeholderColor('#BBBBBB')
        .borderRadius(8)
        .backgroundColor('#F1F2F4')
        .padding({ left: 12, right: 12 })
        .type(InputType.Password)
        .onChange((v: string): void => {
          this.secret = v;
          this.errorMessage = '';
        });

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .id('BypassSecretPageError')
          .fontSize(12)
          .fontColor('#E63946');
      }

      Row({ space: 12 }) {
        Button('Cancel')
          .id('BypassSecretPageCancelButton')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F1F2F4')
          .fontColor('#1D3557')
          .onClick((): void => {
            this.getUIContext().getRouter().back();
          });

        Button('Save')
          .id('BypassSecretPageSaveButton')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#457B9D')
          .fontColor('#FFFFFF')
          .onClick((): void => {
            const trimmed: string = this.secret.trim();
            if (trimmed.length === 0) {
              this.errorMessage = 'Secret cannot be empty';
              return;
            }
            saveBypassSecret(trimmed).then((): void => {
              this.getUIContext().getRouter().back();
            }).catch((err: BusinessError): void => {
              console.error(`BypassSecretPage.save failed: ${JSON.stringify(err)}`);
              this.errorMessage = 'Failed to save';
            });
          });
      }
      .width('100%');
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start);
  }
}

