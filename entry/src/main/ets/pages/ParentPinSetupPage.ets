import { router } from '@kit.ArkUI';
import {
  GameConfig,
  GAME_CONFIG_STORAGE_KEY,
  cloneGameConfig,
} from '../models/GameConfig';
import {
  PIN_LENGTH,
  pushDigit,
  popDigit,
} from '../components/ParentPinDialog';

/**
 * V0.3.9: two-step parent PIN setup. The page is reachable from the
 * 家长密码 row in ConfigPage. Step 1 captures the new 6-digit PIN;
 * step 2 confirms it. On match the page persists `parentPin` into
 * the AppStorage-backed GameConfig and routes back. On mismatch the
 * UI clears both buffers and returns to step 1 with a red hint —
 * no lockout, no attempt counter (matches the dialog policy).
 *
 * Modifying an existing PIN is the same flow: any new pair simply
 * overwrites the old value. Recovery happens by re-running setup.
 */

const KEYPAD_ROWS: string[][] = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['', '0', '⌫'],
];

@Entry
@Component
struct ParentPinSetupPage {
  @State private step: number = 1;
  @State private firstBuf: string = '';
  @State private secondBuf: string = '';
  @State private mismatch: boolean = false;
  @State private hadExistingPin: boolean = false;

  aboutToAppear(): void {
    const stored: GameConfig | undefined =
      AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
    this.hadExistingPin = stored !== undefined && stored.parentPin.length === PIN_LENGTH;
  }

  build(): void {
    Column({ space: 24 }) {
      this.headerRow();
      this.titleBlock();
      this.dotRow();
      if (this.mismatch) {
        Text('两次密码不一致，请重新设置')
          .fontSize(13)
          .fontColor('#E63946')
          .id('ParentPinSetupMismatchHint');
      }
      this.keypad();
      Button('取消')
        .id('ParentPinSetupCancel')
        .width(160).height(44)
        .backgroundColor('#BDBDBD')
        .onClick((): void => router.back());
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, left: 24, right: 24, bottom: 24 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FFFFFF');
  }

  @Builder
  private headerRow() {
    Row() {
      Text(this.hadExistingPin ? '修改家长密码' : '设置家长密码')
        .id('ParentPinSetupTitle')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1D3557');
    }
    .width('100%')
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  private titleBlock() {
    Text(this.step === 1 ? '请输入 6 位数字密码' : '请再次输入以确认')
      .id('ParentPinSetupStepLabel')
      .fontSize(16)
      .fontColor('#457B9D');
  }

  @Builder
  private dotRow() {
    Row({ space: 14 }) {
      ForEach([0, 1, 2, 3, 4, 5], (i: number): void => {
        Circle({ width: 16, height: 16 })
          .fill(i < this.activeBuf().length ? '#1D3557' : '#FFFFFF')
          .stroke('#1D3557')
          .strokeWidth(1.5);
      }, (i: number): string => `dot-${i}`);
    }
    .id('ParentPinSetupDots');
  }

  @Builder
  private keypad() {
    Column({ space: 10 }) {
      ForEach(KEYPAD_ROWS, (row: string[], rowIdx: number): void => {
        Row({ space: 14 }) {
          ForEach(row, (cell: string, colIdx: number): void => {
            this.keypadCell(cell, rowIdx, colIdx);
          }, (cell: string, colIdx: number): string => `cell-${rowIdx}-${colIdx}`);
        };
      }, (row: string[], rowIdx: number): string => `row-${rowIdx}`);
    }
    .id('ParentPinSetupKeypad');
  }

  @Builder
  private keypadCell(label: string, rowIdx: number, colIdx: number) {
    if (label.length === 0) {
      Column().width(64).height(64);
    } else if (label === '⌫') {
      Button('⌫')
        .id('ParentPinSetupDelete')
        .width(64)
        .height(64)
        .backgroundColor('#F1F2F4')
        .fontColor('#1D3557')
        .fontSize(20)
        .onClick((): void => this.handleBackspace());
    } else {
      Button(label)
        .id(`ParentPinSetupKey_${label}`)
        .width(64)
        .height(64)
        .backgroundColor('#FFFFFF')
        .borderColor('#1D3557')
        .borderWidth(1)
        .fontColor('#1D3557')
        .fontSize(22)
        .onClick((): void => this.handleDigit(label));
    }
  }

  private activeBuf(): string {
    return this.step === 1 ? this.firstBuf : this.secondBuf;
  }

  private handleDigit(label: string): void {
    this.mismatch = false;
    if (this.step === 1) {
      this.firstBuf = pushDigit(this.firstBuf, label);
      if (this.firstBuf.length === PIN_LENGTH) {
        this.step = 2;
      }
    } else {
      this.secondBuf = pushDigit(this.secondBuf, label);
      if (this.secondBuf.length === PIN_LENGTH) {
        this.commitOrReset();
      }
    }
  }

  private handleBackspace(): void {
    this.mismatch = false;
    if (this.step === 1) {
      this.firstBuf = popDigit(this.firstBuf);
    } else {
      // Backspace on an empty step-2 buffer rewinds to step 1 so
      // the parent can correct a step-1 typo without restarting.
      if (this.secondBuf.length === 0) {
        this.step = 1;
        this.firstBuf = popDigit(this.firstBuf);
      } else {
        this.secondBuf = popDigit(this.secondBuf);
      }
    }
  }

  private commitOrReset(): void {
    if (this.firstBuf === this.secondBuf
        && this.firstBuf.length === PIN_LENGTH) {
      const stored: GameConfig | undefined =
        AppStorage.get<GameConfig>(GAME_CONFIG_STORAGE_KEY);
      const next: GameConfig =
        cloneGameConfig(stored !== undefined ? stored : new GameConfig());
      next.parentPin = this.firstBuf;
      AppStorage.set<GameConfig>(GAME_CONFIG_STORAGE_KEY, next);
      router.back();
      return;
    }
    this.mismatch = true;
    this.step = 1;
    this.firstBuf = '';
    this.secondBuf = '';
  }
}
