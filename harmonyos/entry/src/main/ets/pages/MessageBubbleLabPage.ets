import { common } from '@kit.AbilityKit';
import {
  MessageBubble,
  MessageBubblePadding,
} from '../components/MessageBubble';
import {
  MessageBubbleTailPreset,
} from '../components/MessageBubbleGeometry';
import {
  MessageBubbleLabState,
  createMessageBubbleLabState,
  labStateAdjustTip,
  labStateApplyPreset,
  labStateOutput,
} from '../components/MessageBubbleLabState';
import { requestPageOrientation } from '../utils/orientation';

const LAB_PRESETS: MessageBubbleTailPreset[] = [
  MessageBubbleTailPreset.TopLeft,
  MessageBubbleTailPreset.TopMiddle,
  MessageBubbleTailPreset.TopRight,
  MessageBubbleTailPreset.BottomLeft,
  MessageBubbleTailPreset.BottomMiddle,
  MessageBubbleTailPreset.BottomRight,
  MessageBubbleTailPreset.LeftTop,
  MessageBubbleTailPreset.LeftMiddle,
  MessageBubbleTailPreset.LeftBottom,
  MessageBubbleTailPreset.RightTop,
  MessageBubbleTailPreset.RightMiddle,
  MessageBubbleTailPreset.RightBottom,
];

@Entry
@Component
struct MessageBubbleLabPage {
  @State private state: MessageBubbleLabState = createMessageBubbleLabState();

  aboutToAppear(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'MessageBubbleLabPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
  }

  private contentPadding(): MessageBubblePadding {
    return {
      left: this.state.paddingX,
      right: this.state.paddingX,
      top: this.state.paddingY,
      bottom: this.state.paddingY,
    };
  }

  private applyPreset(preset: MessageBubbleTailPreset): void {
    this.state = labStateApplyPreset(this.state, preset);
  }

  private adjustTip(dx: number, dy: number): void {
    this.state = labStateAdjustTip(this.state, dx, dy);
  }

  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  @Builder
  private presetGrid() {
    Grid() {
      ForEach(LAB_PRESETS, (preset: MessageBubbleTailPreset) => {
        GridItem() {
          Button(`${preset}`)
            .id(`MessageBubbleLabPreset${preset}`)
            .fontSize(10)
            .height(28)
            .backgroundColor(this.state.selectedPreset === preset ? '#8B5CF6' : '#F5F0FF')
            .fontColor(this.state.selectedPreset === preset ? '#FFFFFF' : '#5B36D6')
            .onClick((): void => this.applyPreset(preset));
        }
      }, (preset: MessageBubbleTailPreset) => preset);
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(8)
    .rowsGap(6)
    .height(132);
  }

  @Builder
  private preview() {
    Stack() {
      MessageBubble({
        widthVp: this.state.widthVp,
        heightVp: this.state.heightVp,
        radiusVp: this.state.radiusVp,
        borderWidthVp: this.state.borderWidthVp,
        fillColor: this.state.fillColor,
        strokeColor: this.state.strokeColor,
        contentPadding: this.contentPadding(),
        tail: this.state.tail,
        bubbleShadow: { radius: 12, color: '#22000000', offsetX: 0, offsetY: 4 },
      }) {
        Column({ space: 6 }) {
          Text('Fern Lizard')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#4B2E83');
          Text('My green clue darts away.')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1D3557')
            .maxLines(2);
          Text('我的绿色线索飞跑。')
            .fontSize(13)
            .fontColor('#6E5F54');
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%');
      }
    }
    .id('MessageBubbleLabPreview')
    .width(420)
    .height(300)
    .borderRadius(16)
    .backgroundColor('#FAF8FF');
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Button('Back')
          .id('MessageBubbleLabBackButton')
          .height(36)
          .fontSize(14)
          .backgroundColor('#FFFFFF')
          .fontColor('#1D3557')
          .borderWidth(1)
          .borderColor('#B8D7F6')
          .onClick((): void => this.goBack());
        Text('Message Bubble Lab')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D3557')
          .layoutWeight(1)
          .textAlign(TextAlign.Center);
        Blank().width(72);
      }
      .width('100%');

      Row({ space: 18 }) {
        this.preview();
        Column({ space: 12 }) {
          Text('Presets')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D3557');
          this.presetGrid();
          Row({ space: 8 }) {
            Button('Tip X -')
              .id('MessageBubbleLabTipXMinus')
              .height(30)
              .fontSize(10)
              .onClick((): void => this.adjustTip(-4, 0));
            Button('Tip X +')
              .id('MessageBubbleLabTipXPlus')
              .height(30)
              .fontSize(10)
              .onClick((): void => this.adjustTip(4, 0));
            Button('Tip Y +')
              .id('MessageBubbleLabTipYPlus')
              .height(30)
              .fontSize(10)
              .onClick((): void => this.adjustTip(0, 4));
          }
          .width('100%');
          Text(labStateOutput(this.state))
            .id('MessageBubbleLabOutput')
            .fontSize(10)
            .fontColor('#3B2A65')
            .fontFamily('monospace')
            .padding(8)
            .backgroundColor('#F4F0FF')
            .borderRadius(10)
            .maxLines(5)
            .width('100%');
        }
        .layoutWeight(1);
      }
      .width('100%')
      .layoutWeight(1);
    }
    .id('MessageBubbleLabPage')
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor('#FFFFFF');
  }
}
