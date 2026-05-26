import { common } from '@kit.AbilityKit';
import {
  MessageBubble,
  MessageBubblePadding,
} from '../components/MessageBubble';
import {
  MessageBubbleTailPreset,
} from '../components/MessageBubbleGeometry';
import {
  MessageBubbleAxisKey,
  MessageBubbleBoxValueKey,
  MessageBubbleColorKey,
  MessageBubbleLabState,
  MessageBubbleLabTipAction,
  MessageBubbleTailPointKey,
  MessageBubbleVisualValueKey,
  createMessageBubbleLabState,
  labStateAdjustBoxValue,
  labStateAdjustTip,
  labStateAdjustTailCoordinate,
  labStateAdjustVisualValue,
  labStateApplyPreset,
  labStateCycleColor,
  labStateOutput,
  labStateToggleShadow,
  messageBubbleLabTipActions,
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
const LAB_PANEL_WIDTH: number = 380;
const LAB_PANEL_HEIGHT: number = 300;

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

  private adjustTailCoordinate(pointKey: MessageBubbleTailPointKey, axisKey: MessageBubbleAxisKey, delta: number): void {
    this.state = labStateAdjustTailCoordinate(this.state, pointKey, axisKey, delta);
  }

  private adjustBoxValue(key: MessageBubbleBoxValueKey, delta: number): void {
    this.state = labStateAdjustBoxValue(this.state, key, delta);
  }

  private adjustVisualValue(key: MessageBubbleVisualValueKey, delta: number): void {
    this.state = labStateAdjustVisualValue(this.state, key, delta);
  }

  private cycleColor(key: MessageBubbleColorKey): void {
    this.state = labStateCycleColor(this.state, key);
  }

  private toggleShadow(): void {
    this.state = labStateToggleShadow(this.state);
  }

  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor('#2E225C')
      .width('100%');
  }

  @Builder
  private pill(label: string) {
    Text(label)
      .fontSize(10)
      .fontWeight(FontWeight.Bold)
      .fontColor('#5B36D6')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .border({ width: 1, color: '#D8C6FF' });
  }

  @Builder
  private valueStepper(
    label: string,
    value: string,
    unit: string,
    minusId: string,
    plusId: string,
    onMinus: () => void,
    onPlus: () => void,
  ) {
    Row({ space: 6 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#4A4268')
        .width(84);
      Button('-')
        .id(minusId)
        .width(36)
        .height(26)
        .fontSize(14)
        .fontColor('#FFFFFF')
        .onClick(onMinus);
      Text(value)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4A3A8A')
        .textAlign(TextAlign.Center)
        .height(26)
        .width(128)
        .borderRadius(8)
        .border({ width: 1, color: '#D8C6FF' });
      Button('+')
        .id(plusId)
        .width(36)
        .height(26)
        .fontSize(14)
        .fontColor('#FFFFFF')
        .onClick(onPlus);
      Text(unit)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#4A4268')
        .width(22);
    }
    .width('100%');
  }

  @Builder
  private coordinateControls() {
    Column({ space: 6 }) {
      this.valueStepper('Base start x', `${this.state.tail.baseStart.x}`, 'vp',
        'MessageBubbleLabBaseStartXMinus', 'MessageBubbleLabBaseStartXPlus',
        (): void => this.adjustTailCoordinate('baseStart', 'x', -2),
        (): void => this.adjustTailCoordinate('baseStart', 'x', 2));
      this.valueStepper('Base start y', `${this.state.tail.baseStart.y}`, 'vp',
        'MessageBubbleLabBaseStartYMinus', 'MessageBubbleLabBaseStartYPlus',
        (): void => this.adjustTailCoordinate('baseStart', 'y', -2),
        (): void => this.adjustTailCoordinate('baseStart', 'y', 2));
      this.valueStepper('Base end x', `${this.state.tail.baseEnd.x}`, 'vp',
        'MessageBubbleLabBaseEndXMinus', 'MessageBubbleLabBaseEndXPlus',
        (): void => this.adjustTailCoordinate('baseEnd', 'x', -2),
        (): void => this.adjustTailCoordinate('baseEnd', 'x', 2));
      this.valueStepper('Base end y', `${this.state.tail.baseEnd.y}`, 'vp',
        'MessageBubbleLabBaseEndYMinus', 'MessageBubbleLabBaseEndYPlus',
        (): void => this.adjustTailCoordinate('baseEnd', 'y', -2),
        (): void => this.adjustTailCoordinate('baseEnd', 'y', 2));
      this.valueStepper('Tip x', `${this.state.tail.tip.x}`, 'vp',
        'MessageBubbleLabTipXDirectMinus', 'MessageBubbleLabTipXDirectPlus',
        (): void => this.adjustTailCoordinate('tip', 'x', -2),
        (): void => this.adjustTailCoordinate('tip', 'x', 2));
      this.valueStepper('Tip y', `${this.state.tail.tip.y}`, 'vp',
        'MessageBubbleLabTipYDirectMinus', 'MessageBubbleLabTipYDirectPlus',
        (): void => this.adjustTailCoordinate('tip', 'y', -2),
        (): void => this.adjustTailCoordinate('tip', 'y', 2));
    }
    .width('100%');
  }

  @Builder
  private boxControls() {
    Column({ space: 6 }) {
      this.valueStepper('Width', `${this.state.widthVp}`, 'vp',
        'MessageBubbleLabWidthMinus', 'MessageBubbleLabWidthPlus',
        (): void => this.adjustBoxValue('widthVp', -10),
        (): void => this.adjustBoxValue('widthVp', 10));
      this.valueStepper('Height', `${this.state.heightVp}`, 'vp',
        'MessageBubbleLabHeightMinus', 'MessageBubbleLabHeightPlus',
        (): void => this.adjustBoxValue('heightVp', -10),
        (): void => this.adjustBoxValue('heightVp', 10));
      this.valueStepper('Padding X', `${this.state.paddingX}`, 'vp',
        'MessageBubbleLabPaddingXMinus', 'MessageBubbleLabPaddingXPlus',
        (): void => this.adjustBoxValue('paddingX', -2),
        (): void => this.adjustBoxValue('paddingX', 2));
      this.valueStepper('Padding Y', `${this.state.paddingY}`, 'vp',
        'MessageBubbleLabPaddingYMinus', 'MessageBubbleLabPaddingYPlus',
        (): void => this.adjustBoxValue('paddingY', -2),
        (): void => this.adjustBoxValue('paddingY', 2));
      this.valueStepper('Corner radius', `${this.state.radiusVp}`, 'vp',
        'MessageBubbleLabRadiusMinus', 'MessageBubbleLabRadiusPlus',
        (): void => this.adjustBoxValue('radiusVp', -2),
        (): void => this.adjustBoxValue('radiusVp', 2));
      this.valueStepper('Border width', `${this.state.borderWidthVp}`, 'vp',
        'MessageBubbleLabBorderMinus', 'MessageBubbleLabBorderPlus',
        (): void => this.adjustBoxValue('borderWidthVp', -1),
        (): void => this.adjustBoxValue('borderWidthVp', 1));
    }
    .width('100%');
  }

  @Builder
  private visualControls() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text('Fill / Stroke')
          .fontSize(11)
          .fontColor('#4A4268')
          .width(84);
        Button(this.state.fillColor)
          .id('MessageBubbleLabFillColor')
          .height(28)
          .fontSize(10)
          .fontColor('#5B36D6')
          .backgroundColor('#F5F0FF')
          .width(112)
          .onClick((): void => this.cycleColor('fillColor'));
        Button(this.state.strokeColor)
          .id('MessageBubbleLabStrokeColor')
          .height(28)
          .fontSize(10)
          .fontColor('#5B36D6')
          .backgroundColor('#F5F0FF')
          .width(112)
          .onClick((): void => this.cycleColor('strokeColor'));
      }
      .width('100%');
      this.valueStepper('Shadow r', `${this.state.shadowRadius}`, 'vp',
        'MessageBubbleLabShadowRadiusMinus', 'MessageBubbleLabShadowRadiusPlus',
        (): void => this.adjustVisualValue('shadowRadius', -2),
        (): void => this.adjustVisualValue('shadowRadius', 2));
      this.valueStepper('Shadow y', `${this.state.shadowOffsetY}`, 'vp',
        'MessageBubbleLabShadowYMinus', 'MessageBubbleLabShadowYPlus',
        (): void => this.adjustVisualValue('shadowOffsetY', -1),
        (): void => this.adjustVisualValue('shadowOffsetY', 1));
      Row({ space: 8 }) {
        Text('Shadow')
          .fontSize(11)
          .fontColor('#4A4268')
          .width(84);
        Button(this.state.shadowEnabled ? 'on' : 'off')
          .id('MessageBubbleLabShadowToggle')
          .height(28)
          .fontSize(10)
          .width(72)
          .onClick((): void => this.toggleShadow());
        this.pill('auto seamless');
        this.pill('internal only');
      }
      .width('100%');
    }
    .width('100%');
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
        bubbleShadow: {
          radius: this.state.shadowEnabled ? this.state.shadowRadius : 0,
          color: '#22000000',
          offsetX: 0,
          offsetY: this.state.shadowEnabled ? this.state.shadowOffsetY : 0,
        },
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
    .width(LAB_PANEL_WIDTH)
    .height(LAB_PANEL_HEIGHT)
    .borderRadius(16)
    .backgroundColor('#FAF8FF');
  }

  @Builder
  private demoPanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Demo');
      this.preview();
    }
    .width(LAB_PANEL_WIDTH);
  }

  @Builder
  private liveOutputPanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Live Output');
      Scroll() {
        Text(labStateOutput(this.state))
          .fontSize(10)
          .fontColor('#3B2A65')
          .fontFamily('monospace')
          .width('100%');
      }
      .id('MessageBubbleLabOutput')
      .height(LAB_PANEL_HEIGHT)
      .padding(10)
      .backgroundColor('#F4F0FF')
      .borderRadius(12)
      .scrollable(ScrollDirection.Vertical)
      .width('100%');
    }
    .width(LAB_PANEL_WIDTH);
  }

  @Builder
  private presetsPanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Presets');
      this.presetGrid();
      Row({ space: 8 }) {
        ForEach(messageBubbleLabTipActions(), (action: MessageBubbleLabTipAction) => {
          Button(action.label)
            .id(action.id)
            .height(30)
            .fontSize(10)
            .width(88)
            .onClick((): void => this.adjustTip(action.dx, action.dy));
        }, (action: MessageBubbleLabTipAction) => action.id);
      }
      .width('100%');
    }
    .width(LAB_PANEL_WIDTH);
  }

  @Builder
  private tailGeometryPanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Tail Geometry');
      Row({ space: 8 }) {
        this.pill('free triangle');
        this.pill('preset -> points');
        this.pill('vp');
      }
      .width('100%');
      this.coordinateControls();
    }
    .width(LAB_PANEL_WIDTH);
  }

  @Builder
  private bubbleBoxPanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Bubble Box');
      this.boxControls();
    }
    .width(LAB_PANEL_WIDTH);
  }

  @Builder
  private visualStylePanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Visual Style');
      this.visualControls();
    }
    .width(LAB_PANEL_WIDTH);
  }

  build() {
    Scroll() {
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

        Row({ space: 16 }) {
          this.demoPanel();
          this.liveOutputPanel();
          this.presetsPanel();
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);

        Row({ space: 16 }) {
          this.tailGeometryPanel();
          this.bubbleBoxPanel();
          this.visualStylePanel();
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);
      }
      .width('100%')
      .padding({ top: 24, left: 24, right: 24, bottom: 48 });
    }
    .id('MessageBubbleLabPage')
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .backgroundColor('#FFFFFF');
  }
}
