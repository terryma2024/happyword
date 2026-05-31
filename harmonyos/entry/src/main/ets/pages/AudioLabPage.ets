import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { AudioLabController } from '../audio_lab/AudioLabController';
import {
  AudioLabConfig,
  AudioLabSnapshot,
  SfxDuringVoicePolicy,
} from '../audio_lab/AudioLabTypes';
import { requestPageOrientation } from '../utils/orientation';

const PANEL_WIDTH: number = 360;
const LAB_WORDS: string[] = ['apple', 'dragon', 'magic', 'school'];
const POLICIES: string[] = [
  SfxDuringVoicePolicy.PlayFull,
  SfxDuringVoicePolicy.LowerVolume,
  SfxDuringVoicePolicy.SuppressNonCritical,
  SfxDuringVoicePolicy.DelayUntilVoiceEnds,
];

function cloneAudioLabConfig(src: AudioLabConfig): AudioLabConfig {
  const out: AudioLabConfig = new AudioLabConfig();
  out.musicEnabled = src.musicEnabled;
  out.sfxEnabled = src.sfxEnabled;
  out.voiceEnabled = src.voiceEnabled;
  out.masterVolume = src.masterVolume;
  out.musicVolume = src.musicVolume;
  out.musicLoweredVolume = src.musicLoweredVolume;
  out.sfxVolume = src.sfxVolume;
  out.voiceVolume = src.voiceVolume;
  out.voiceLowerDurationMs = src.voiceLowerDurationMs;
  out.comboLowerDurationMs = src.comboLowerDurationMs;
  out.sfxDuringVoicePolicy = src.sfxDuringVoicePolicy;
  out.sfxDuringVoiceVolume = src.sfxDuringVoiceVolume;
  out.resumeMusicAfterVoice = src.resumeMusicAfterVoice;
  return out;
}

@Entry
@Component
struct AudioLabPage {
  @State private config: AudioLabConfig = new AudioLabConfig();
  @State private snap: AudioLabSnapshot = new AudioLabSnapshot();
  @State private statusText: string = 'Initializing audio lab... Single-resume after voice is on by default.';
  @State private selectedWord: string = 'apple';
  private controller: AudioLabController = new AudioLabController();

  aboutToAppear(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'AudioLabPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
    this.controller.updateConfig(this.config);
    this.controller.enter(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((): void => {
        this.statusText = 'Ready. BGM should duck during voice and resume once after the voice timeout.';
        this.refreshSnapshot();
      })
      .catch((err: BusinessError): void => {
        this.statusText = `Init failed: ${JSON.stringify(err)}`;
        this.refreshSnapshot();
      });
  }

  aboutToDisappear(): void {
    this.controller.exit().catch((err: BusinessError): void => {
      console.error(`AudioLabPage.exit failed: ${JSON.stringify(err)}`);
    });
  }

  private goBack(): void {
    this.controller.exit().catch((err: BusinessError): void => {
      console.error(`AudioLabPage.goBack exit failed: ${JSON.stringify(err)}`);
    });
    this.getUIContext().getRouter().back();
  }

  private refreshSnapshot(): void {
    this.snap = this.controller.snapshot();
  }

  private percent(value: number): string {
    return `${Math.round(value * 100)}%`;
  }

  private boolLabel(value: boolean): string {
    return value ? 'on' : 'off';
  }

  private policyLabel(policy: string): string {
    if (policy === SfxDuringVoicePolicy.PlayFull) {
      return 'full';
    }
    if (policy === SfxDuringVoicePolicy.LowerVolume) {
      return 'lower';
    }
    if (policy === SfxDuringVoicePolicy.SuppressNonCritical) {
      return 'suppress';
    }
    return 'delay';
  }

  private updateConfig(mutator: (draft: AudioLabConfig) => void): void {
    const next: AudioLabConfig = cloneAudioLabConfig(this.config);
    mutator(next);
    this.config = next;
    this.controller.updateConfig(next);
    this.refreshSnapshot();
  }

  private clamp01(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private adjustMaster(delta: number): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.masterVolume = this.clamp01(draft.masterVolume + delta);
    });
  }

  private adjustMusic(delta: number): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.musicVolume = this.clamp01(draft.musicVolume + delta);
    });
    this.controller.startMusic();
    this.refreshSnapshot();
  }

  private adjustDuck(delta: number): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.musicLoweredVolume = this.clamp01(draft.musicLoweredVolume + delta);
    });
  }

  private adjustSfxDuringVoice(delta: number): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.sfxDuringVoiceVolume = this.clamp01(draft.sfxDuringVoiceVolume + delta);
    });
  }

  private toggleMusic(): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.musicEnabled = !draft.musicEnabled;
    });
    if (!this.config.musicEnabled) {
      this.controller.stopMusic();
    }
    this.refreshSnapshot();
  }

  private toggleSfx(): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.sfxEnabled = !draft.sfxEnabled;
    });
  }

  private toggleVoice(): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.voiceEnabled = !draft.voiceEnabled;
    });
  }

  private toggleResume(): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.resumeMusicAfterVoice = !draft.resumeMusicAfterVoice;
    });
  }

  private setPolicy(policy: string): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.sfxDuringVoicePolicy = policy as SfxDuringVoicePolicy;
    });
  }

  private run(action: () => void, status: string): void {
    action();
    this.statusText = status;
    this.refreshSnapshot();
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor('#18324A')
      .width('100%');
  }

  @Builder
  private labButton(label: string, id: string, onClick: () => void) {
    Button(label)
      .id(id)
      .height(40)
      .fontSize(14)
      .fontColor('#123047')
      .backgroundColor('#EAF4F8')
      .borderRadius(8)
      .onClick(onClick);
  }

  @Builder
  private chip(label: string, selected: boolean, id: string, onClick: () => void) {
    Button(label)
      .id(id)
      .height(34)
      .fontSize(13)
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(selected ? '#FFFFFF' : '#315166')
      .backgroundColor(selected ? '#276C7D' : '#EEF3F4')
      .borderRadius(8)
      .onClick(onClick);
  }

  @Builder
  private toggleChip(label: string, value: boolean, id: string, onClick: () => void) {
    this.chip(`${label}: ${this.boolLabel(value)}`, value, id, onClick);
  }

  @Builder
  private stepper(label: string, value: string, minusId: string, plusId: string, onMinus: () => void, onPlus: () => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontColor('#334B5A')
        .width(122);
      Button('-')
        .id(minusId)
        .width(36)
        .height(30)
        .fontSize(14)
        .backgroundColor('#EEF3F4')
        .fontColor('#123047')
        .onClick(onMinus);
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123047')
        .textAlign(TextAlign.Center)
        .width(70);
      Button('+')
        .id(plusId)
        .width(36)
        .height(30)
        .fontSize(14)
        .backgroundColor('#EEF3F4')
        .fontColor('#123047')
        .onClick(onPlus);
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private transportPanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Transport');
      Row({ space: 8 }) {
        this.labButton('Start BGM', 'AudioLabStartMusic', (): void => this.run(
          (): void => this.controller.startMusic(),
          'BGM loop requested.',
        ));
        this.labButton('Stop BGM', 'AudioLabStopMusic', (): void => this.run(
          (): void => this.controller.stopMusic(),
          'BGM stopped.',
        ));
      }
      .width('100%');
      Row({ space: 8 }) {
        this.labButton('Normal hit', 'AudioLabNormalHit', (): void => this.run(
          (): void => this.controller.playNormalAttack(),
          'Played normal attack SFX.',
        ));
        this.labButton('Combo hit', 'AudioLabComboHit', (): void => this.run(
          (): void => this.controller.playComboAttack(),
          'Played combo SFX with temporary BGM duck.',
        ));
      }
      .width('100%');
      Row({ space: 8 }) {
        this.labButton('Wrong', 'AudioLabWrong', (): void => this.run(
          (): void => this.controller.playWrongAnswer(),
          'Played wrong-answer SFX.',
        ));
        this.labButton('Hurt', 'AudioLabHurt', (): void => this.run(
          (): void => this.controller.playPlayerHurt(),
          'Played critical player-hurt SFX.',
        ));
      }
      .width('100%');
      Row({ space: 8 }) {
        this.labButton('Victory', 'AudioLabVictory', (): void => this.run(
          (): void => this.controller.playVictory(),
          'Played victory SFX.',
        ));
        this.labButton('Defeat', 'AudioLabDefeat', (): void => this.run(
          (): void => this.controller.playDefeat(),
          'Played defeat SFX.',
        ));
      }
      .width('100%');
    }
    .width(PANEL_WIDTH);
  }

  @Builder
  private voicePanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Voice');
      Row({ space: 8 }) {
        ForEach(LAB_WORDS, (word: string) => {
          this.chip(word, this.selectedWord === word, `AudioLabWord_${word}`, (): void => {
            this.selectedWord = word;
          });
        }, (word: string): string => word);
      }
      .width('100%');
      Row({ space: 8 }) {
        this.labButton('Speak', 'AudioLabSpeak', (): void => this.run(
          (): void => this.controller.speakWord(this.selectedWord),
          `Speaking ${this.selectedWord}.`,
        ));
        this.labButton('Speak over BGM', 'AudioLabSpeakOverMusic', (): void => this.run(
          (): void => this.controller.demoSpeakOverMusic(this.selectedWord),
          `BGM plus voice for ${this.selectedWord}.`,
        ));
      }
      .width('100%');
      Row({ space: 8 }) {
        this.labButton('Combo over BGM', 'AudioLabComboOverMusic', (): void => this.run(
          (): void => this.controller.demoComboOverMusic(),
          'Combo attack over BGM.',
        ));
        this.labButton('SFX during voice', 'AudioLabSfxDuringVoice', (): void => this.run(
          (): void => this.controller.demoSfxDuringVoice(this.selectedWord),
          'Voice, BGM, non-critical SFX, combo SFX, and critical SFX fired together.',
        ));
      }
      .width('100%');
      Row({ space: 8 }) {
        this.labButton('Wrong sequence', 'AudioLabWrongSequence', (): void => this.run(
          (): void => this.controller.demoWrongAnswerSequence(),
          'Wrong answer plus player hurt sequence.',
        ));
        this.labButton('Win sequence', 'AudioLabWinSequence', (): void => this.run(
          (): void => this.controller.demoVictorySequence(),
          'Stopped BGM then played victory.',
        ));
      }
      .width('100%');
    }
    .width(PANEL_WIDTH);
  }

  @Builder
  private mixPanel() {
    Column({ space: 10 }) {
      this.sectionTitle('Mix');
      Row({ space: 8 }) {
        this.toggleChip('BGM', this.config.musicEnabled, 'AudioLabToggleMusic', (): void => this.toggleMusic());
        this.toggleChip('SFX', this.config.sfxEnabled, 'AudioLabToggleSfx', (): void => this.toggleSfx());
        this.toggleChip('Voice', this.config.voiceEnabled, 'AudioLabToggleVoice', (): void => this.toggleVoice());
      }
      .width('100%');
      this.stepper('Master', this.percent(this.config.masterVolume),
        'AudioLabMasterMinus', 'AudioLabMasterPlus',
        (): void => this.adjustMaster(-0.05),
        (): void => this.adjustMaster(0.05));
      this.stepper('BGM', this.percent(this.config.musicVolume),
        'AudioLabMusicMinus', 'AudioLabMusicPlus',
        (): void => this.adjustMusic(-0.05),
        (): void => this.adjustMusic(0.05));
      this.stepper('BGM duck', this.percent(this.config.musicLoweredVolume),
        'AudioLabDuckMinus', 'AudioLabDuckPlus',
        (): void => this.adjustDuck(-0.02),
        (): void => this.adjustDuck(0.02));
      this.stepper('SFX while voice', this.percent(this.config.sfxDuringVoiceVolume),
        'AudioLabSfxVoiceMinus', 'AudioLabSfxVoicePlus',
        (): void => this.adjustSfxDuringVoice(-0.05),
        (): void => this.adjustSfxDuringVoice(0.05));
      this.toggleChip('Resume after voice', this.config.resumeMusicAfterVoice, 'AudioLabToggleResume', (): void => this.toggleResume());
    }
    .width(PANEL_WIDTH);
  }

  @Builder
  private policyPanel() {
    Column({ space: 10 }) {
      this.sectionTitle('SFX During Voice');
      Row({ space: 8 }) {
        ForEach(POLICIES, (policy: string) => {
          this.chip(
            this.policyLabel(policy),
            this.config.sfxDuringVoicePolicy === policy,
            `AudioLabPolicy_${this.policyLabel(policy)}`,
            (): void => this.setPolicy(policy),
          );
        }, (policy: string): string => policy);
      }
      .width('100%');
      Text('Try Speak over BGM, then SFX during voice. Critical hurt/victory/defeat cues still play under suppress and delay policies.')
        .fontSize(12)
        .lineHeight(18)
        .fontColor('#536B78')
        .width('100%');
    }
    .width(PANEL_WIDTH);
  }

  @Builder
  private statusPanel() {
    Column({ space: 8 }) {
      this.sectionTitle('Status');
      Text(this.statusText)
        .id('AudioLabStatus')
        .fontSize(13)
        .lineHeight(19)
        .fontColor('#334B5A')
        .width('100%');
      Text(`music=${this.snap.musicState} voice=${this.snap.voiceActive ? 'active' : 'idle'} volume=${this.percent(this.snap.musicVolume)} timers=${this.snap.pendingTimers}`)
        .id('AudioLabSnapshot')
        .fontSize(12)
        .fontColor('#536B78')
        .width('100%');
      Text(`last=${this.snap.lastEvent.length > 0 ? this.snap.lastEvent : 'none'} delayed=${this.snap.pendingDelayedSfx.length > 0 ? this.snap.pendingDelayedSfx : 'none'} resume=${this.snap.resumeAttempts}`)
        .fontSize(12)
        .fontColor('#536B78')
        .width('100%');
      if (this.snap.lastError.length > 0) {
        Text(this.snap.lastError)
          .fontSize(12)
          .lineHeight(18)
          .fontColor('#B42318')
          .width('100%');
      }
    }
    .width(PANEL_WIDTH);
  }

  build(): void {
    Scroll() {
      Column({ space: 18 }) {
        Row() {
          Button('Back')
            .id('AudioLabBackButton')
            .height(36)
            .fontSize(14)
            .backgroundColor('#FFFFFF')
            .fontColor('#1D3557')
            .borderWidth(1)
            .borderColor('#B8D7F6')
            .onClick((): void => this.goBack());
          Text('Audio Lab')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D3557')
            .layoutWeight(1)
            .textAlign(TextAlign.Center);
          Blank().width(72);
        }
        .width('100%');

        Row({ space: 18 }) {
          this.transportPanel();
          this.voicePanel();
          this.mixPanel();
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);

        Row({ space: 18 }) {
          this.policyPanel();
          this.statusPanel();
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);
      }
      .width('100%')
      .padding({ top: 24, left: 24, right: 24, bottom: 48 });
    }
    .id('AudioLabPage')
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .backgroundColor('#FFFFFF');
  }
}
