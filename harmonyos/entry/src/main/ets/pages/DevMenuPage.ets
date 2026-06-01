import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import {
  DevMenuToolEntry,
  devMenuToolEntries,
} from '../services/DevMenuToolEntries';
import { requestPageOrientation } from '../utils/orientation';

@Entry
@Component
struct DevMenuPage {
  private applyOrientationPolicy(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'DevMenuPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  aboutToAppear(): void {
    this.applyOrientationPolicy();
  }

  onPageShow(): void {
    this.applyOrientationPolicy();
  }

  private openTool(entry: DevMenuToolEntry): void {
    this.getUIContext().getRouter().pushUrl({ url: entry.route })
      .catch((err: BusinessError): void => {
        console.error(`DevMenuPage.openTool ${entry.route} failed: ${JSON.stringify(err)}`);
      });
  }

  @Builder
  private toolCard(entry: DevMenuToolEntry): void {
    Column() {
      Text(entry.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#073B4C')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
    }
    .id(entry.id)
    .layoutWeight(1)
    .height(92)
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(entry.backgroundColor)
    .border({ width: 1, color: '#D9EAEE' })
    .onClick((): void => this.openTool(entry));
  }

  build(): void {
    Scroll() {
      Column() {
        Row() {
          Button('Back')
            .fontSize(14)
            .height(36)
            .onClick((): void => {
              this.getUIContext().getRouter().back();
            });
          Text('Developer Options')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 16 });
          Blank();
        }
        .width('100%')
        .margin({ bottom: 18 });

        Row({ space: 12 }) {
          ForEach(devMenuToolEntries(), (entry: DevMenuToolEntry) => {
            this.toolCard(entry);
          }, (entry: DevMenuToolEntry) => entry.id);
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor('#FFFFFF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END]);
  }
}
