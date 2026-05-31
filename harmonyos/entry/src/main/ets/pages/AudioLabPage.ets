import { BusinessError } from '@ohos.base';
import { common } from '@kit.AbilityKit';
import { AudioLabController } from '../audio_lab/AudioLabController';
import {
  AudioLabConfig,
  AudioLabControllerDeps,
  AudioLabObserver,
  AudioLabSnapshot,
  AudioLabVoiceBackend,
  SfxDuringVoicePolicy,
} from '../audio_lab/AudioLabTypes';
import { PcmVoiceLabLane } from '../audio_lab/lanes/PcmVoiceLabLane';
import { RealVoiceLabLane } from '../audio_lab/lanes/VoiceLabLane';
import { requestPageOrientation } from '../utils/orientation';

const PANEL_WIDTH: number = 360;
const WIDE_PANEL_WIDTH: number = PANEL_WIDTH * 2 + 8;
const PAGE_PADDING: number = 22;
const PANEL_GAP: number = 8;
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

class PageAudioLabObserver implements AudioLabObserver {
  private readonly version: number;
  private readonly currentVersion: () => number;
  private readonly applySnapshot: (snapshot: AudioLabSnapshot) => void;

  constructor(version: number, currentVersion: () => number, applySnapshot: (snapshot: AudioLabSnapshot) => void) {
    this.version = version;
    this.currentVersion = currentVersion;
    this.applySnapshot = applySnapshot;
  }

  onEvent(): void {
  }

  onSnapshot(snapshot: AudioLabSnapshot): void {
    if (this.version === this.currentVersion()) {
      this.applySnapshot(snapshot);
    }
  }
}

@Entry
@Component
struct AudioLabPage {
  @State private snap: AudioLabSnapshot = new AudioLabSnapshot();
  @State private statusText: string = 'Initializing audio lab... PCM voice backend is selected by default.';
  @State private selectedWord: string = 'apple';
  @State private voiceBackend: AudioLabVoiceBackend = AudioLabVoiceBackend.PcmTts;
  @State private musicEnabled: boolean = true;
  @State private sfxEnabled: boolean = true;
  @State private voiceEnabled: boolean = true;
  @State private resumeMusicAfterVoice: boolean = false;
  @State private masterVolume: number = 1.0;
  @State private musicVolume: number = 0.32;
  @State private musicLoweredVolume: number = 0.08;
  @State private sfxDuringVoicePolicy: string = SfxDuringVoicePolicy.LowerVolume;
  @State private sfxDuringVoiceVolume: number = 0.35;
  private config: AudioLabConfig = new AudioLabConfig();
  private controller: AudioLabController = new AudioLabController();
  private controllerVersion: number = 0;

  aboutToAppear(): void {
    requestPageOrientation(
      this.getUIContext().getHostContext() as common.UIAbilityContext,
      'AudioLabPage',
      (px: number): number => this.getUIContext().px2vp(px),
    );
    this.controllerVersion += 1;
    this.controller = this.makeController(this.voiceBackend, this.controllerVersion);
    this.controller.updateConfig(this.config);
    this.controller.enter(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((): void => {
        this.statusText = 'Ready. PCM voice should mix over BGM without stopping it.';
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

  private syncConfigState(next: AudioLabConfig): void {
    this.musicEnabled = next.musicEnabled;
    this.sfxEnabled = next.sfxEnabled;
    this.voiceEnabled = next.voiceEnabled;
    this.resumeMusicAfterVoice = next.resumeMusicAfterVoice;
    this.masterVolume = next.masterVolume;
    this.musicVolume = next.musicVolume;
    this.musicLoweredVolume = next.musicLoweredVolume;
    this.sfxDuringVoicePolicy = next.sfxDuringVoicePolicy;
    this.sfxDuringVoiceVolume = next.sfxDuringVoiceVolume;
  }

  private backendLabel(backend: AudioLabVoiceBackend): string {
    if (backend === AudioLabVoiceBackend.PcmTts) {
      return 'PCM mix';
    }
    return 'System TTS';
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
    this.syncConfigState(next);
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

  private setMusicEnabled(isOn: boolean): void {
    if (isOn === this.config.musicEnabled) {
      return;
    }
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.musicEnabled = isOn;
    });
    if (!this.config.musicEnabled) {
      this.controller.stopMusic();
    }
    this.refreshSnapshot();
  }

  private setSfxEnabled(isOn: boolean): void {
    if (isOn === this.config.sfxEnabled) {
      return;
    }
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.sfxEnabled = isOn;
    });
  }

  private setVoiceEnabled(isOn: boolean): void {
    if (isOn === this.config.voiceEnabled) {
      return;
    }
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.voiceEnabled = isOn;
    });
  }

  private setResumeMusicAfterVoice(isOn: boolean): void {
    if (isOn === this.config.resumeMusicAfterVoice) {
      return;
    }
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.resumeMusicAfterVoice = isOn;
    });
  }

  private toggleMusic(): void {
    this.setMusicEnabled(!this.musicEnabled);
  }

  private toggleSfx(): void {
    this.setSfxEnabled(!this.sfxEnabled);
  }

  private toggleVoice(): void {
    this.setVoiceEnabled(!this.voiceEnabled);
  }

  private toggleResumeMusicAfterVoice(): void {
    this.setResumeMusicAfterVoice(!this.resumeMusicAfterVoice);
  }

  private makeController(backend: AudioLabVoiceBackend, version: number): AudioLabController {
    const deps: AudioLabControllerDeps = new AudioLabControllerDeps();
    if (backend === AudioLabVoiceBackend.PcmTts) {
      deps.voice = new PcmVoiceLabLane();
    } else {
      deps.voice = new RealVoiceLabLane();
    }
    const observer: AudioLabObserver = new PageAudioLabObserver(
      version,
      (): number => this.controllerVersion,
      (snapshot: AudioLabSnapshot): void => {
        this.snap = snapshot;
      },
    );
    return new AudioLabController(this.config, observer, deps);
  }

  private switchVoiceBackend(backend: AudioLabVoiceBackend): void {
    if (backend === this.voiceBackend) {
      return;
    }
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const label: string = this.backendLabel(backend);
    const previous: AudioLabController = this.controller;
    this.voiceBackend = backend;
    this.controllerVersion += 1;
    this.statusText = `Voice backend: ${label}.`;
    previous.exit().catch((err: BusinessError): void => {
      console.error(`AudioLabPage backend switch exit failed: ${JSON.stringify(err)}`);
    });
    this.controller = this.makeController(backend, this.controllerVersion);
    this.controller.updateConfig(this.config);
    this.controller.enter(ctx)
      .then((): void => {
        this.refreshSnapshot();
      })
      .catch((err: BusinessError): void => {
        this.statusText = `Backend switch failed: ${JSON.stringify(err)}`;
        this.refreshSnapshot();
      });
    this.refreshSnapshot();
  }

  private setPolicy(policy: string): void {
    this.updateConfig((draft: AudioLabConfig): void => {
      draft.sfxDuringVoicePolicy = policy as SfxDuringVoicePolicy;
    });
    this.statusText = `SFX during voice policy: ${this.policyLabel(policy)}.`;
    this.refreshSnapshot();
  }

  private selectWord(word: string): void {
    this.selectedWord = word;
    this.statusText = `Selected word: ${word}.`;
    this.refreshSnapshot();
  }

  private run(action: () => void, status: string): void {
    action();
    this.statusText = status;
    this.refreshSnapshot();
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor('#18324A')
      .width('100%');
  }

  @Builder
  private labButton(label: string, id: string, onClick: () => void) {
    Button(label)
      .id(id)
      .height(26)
      .fontSize(11)
      .fontColor('#123047')
      .backgroundColor('#EAF4F8')
      .borderRadius(7)
      .layoutWeight(1)
      .onClick(onClick);
  }

  @Builder
  private chip(label: string, selected: boolean, id: string, onClick: () => void) {
    Button(label)
      .id(id)
      .height(24)
      .fontSize(11)
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(selected ? '#FFFFFF' : '#315166')
      .backgroundColor(selected ? '#276C7D' : '#EEF3F4')
      .borderRadius(7)
      .layoutWeight(1)
      .onClick(onClick);
  }

  @Builder
  private compactToggle(label: string, value: boolean, id: string, onClick: () => void) {
    Button(`${label}  ${this.boolLabel(value)}`)
    .id(id)
    .height(26)
    .fontSize(11)
    .fontWeight(FontWeight.Bold)
    .fontColor(value ? '#FFFFFF' : '#536B78')
    .backgroundColor(value ? '#007B86' : '#EAF0F2')
    .borderRadius(13)
    .layoutWeight(1)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Up) {
        onClick();
      }
    });
  }

  @Builder
  private stepperRow(label: string, value: string, minusId: string, plusId: string, onMinus: () => void, onPlus: () => void) {
    Row({ space: 3 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#334B5A')
        .width(70)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Button('-')
        .id(minusId)
        .width(30)
        .height(24)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123047')
        .backgroundColor('#EAF4F8')
        .borderRadius(12)
        .onClick(onMinus);
      Text(value)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123047')
        .width(36);
      Button('+')
        .id(plusId)
        .width(30)
        .height(24)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#123047')
        .backgroundColor('#EAF4F8')
        .borderRadius(12)
        .onClick(onPlus);
    }
    .layoutWeight(1)
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private transportPanel() {
    Column({ space: 5 }) {
      this.sectionTitle('Transport');
      Row({ space: 6 }) {
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
      Row({ space: 6 }) {
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
      Row({ space: 6 }) {
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
      Row({ space: 6 }) {
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
    Column({ space: 5 }) {
      this.sectionTitle('Voice');
      Row({ space: 6 }) {
        Button(this.backendLabel(AudioLabVoiceBackend.PcmTts))
          .id('AudioLabBackendPcm')
          .height(24)
          .fontSize(11)
          .fontWeight(this.voiceBackend === AudioLabVoiceBackend.PcmTts ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.voiceBackend === AudioLabVoiceBackend.PcmTts ? '#FFFFFF' : '#315166')
          .backgroundColor(this.voiceBackend === AudioLabVoiceBackend.PcmTts ? '#276C7D' : '#EEF3F4')
          .borderRadius(7)
          .layoutWeight(1)
          .onClick((): void => this.switchVoiceBackend(AudioLabVoiceBackend.PcmTts));
        Button(this.backendLabel(AudioLabVoiceBackend.SystemTts))
          .id('AudioLabBackendSystem')
          .height(24)
          .fontSize(11)
          .fontWeight(this.voiceBackend === AudioLabVoiceBackend.SystemTts ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.voiceBackend === AudioLabVoiceBackend.SystemTts ? '#FFFFFF' : '#315166')
          .backgroundColor(this.voiceBackend === AudioLabVoiceBackend.SystemTts ? '#276C7D' : '#EEF3F4')
          .borderRadius(7)
          .layoutWeight(1)
          .onClick((): void => this.switchVoiceBackend(AudioLabVoiceBackend.SystemTts));
      }
      .width('100%');
      Row({ space: 6 }) {
        ForEach(LAB_WORDS, (word: string) => {
          Button(word)
            .id(`AudioLabWord_${word}`)
            .height(24)
            .fontSize(11)
            .fontWeight(this.selectedWord === word ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.selectedWord === word ? '#FFFFFF' : '#315166')
            .backgroundColor(this.selectedWord === word ? '#276C7D' : '#EEF3F4')
            .borderRadius(7)
            .layoutWeight(1)
            .onClick((): void => this.selectWord(word));
        }, (word: string): string => `${word}-${this.selectedWord === word ? 'selected' : 'idle'}`);
      }
      .width('100%');
      Row({ space: 6 }) {
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
      Row({ space: 6 }) {
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
      Row({ space: 6 }) {
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
    Column({ space: 5 }) {
      this.sectionTitle('Mix');
      Row({ space: 5 }) {
        Button(`BGM  ${this.boolLabel(this.musicEnabled)}`)
          .id('AudioLabToggleMusic')
          .height(26)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.musicEnabled ? '#FFFFFF' : '#536B78')
          .backgroundColor(this.musicEnabled ? '#007B86' : '#EAF0F2')
          .borderRadius(13)
          .layoutWeight(1)
          .onClick((): void => this.toggleMusic());
        Button(`SFX  ${this.boolLabel(this.sfxEnabled)}`)
          .id('AudioLabToggleSfx')
          .height(26)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.sfxEnabled ? '#FFFFFF' : '#536B78')
          .backgroundColor(this.sfxEnabled ? '#007B86' : '#EAF0F2')
          .borderRadius(13)
          .layoutWeight(1)
          .onClick((): void => this.toggleSfx());
        Button(`Voice  ${this.boolLabel(this.voiceEnabled)}`)
          .id('AudioLabToggleVoice')
          .height(26)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.voiceEnabled ? '#FFFFFF' : '#536B78')
          .backgroundColor(this.voiceEnabled ? '#007B86' : '#EAF0F2')
          .borderRadius(13)
          .layoutWeight(1)
          .onClick((): void => this.toggleVoice());
        Button(`Resume  ${this.boolLabel(this.resumeMusicAfterVoice)}`)
          .id('AudioLabToggleResume')
          .height(26)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resumeMusicAfterVoice ? '#FFFFFF' : '#536B78')
          .backgroundColor(this.resumeMusicAfterVoice ? '#007B86' : '#EAF0F2')
          .borderRadius(13)
          .layoutWeight(1)
          .onClick((): void => this.toggleResumeMusicAfterVoice());
      }
      .width('100%');
      Row({ space: 5 }) {
        Row({ space: 3 }) {
          Text('Master').fontSize(11).fontColor('#334B5A').width(70);
          Button() { Text('-').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#123047'); }
            .id('AudioLabMasterMinus').width(30).height(24)
            .backgroundColor('#EAF4F8').borderRadius(12).onClick((): void => this.adjustMaster(-0.05));
          Text(this.percent(this.masterVolume)).fontSize(11).fontWeight(FontWeight.Bold)
            .fontColor('#123047').textAlign(TextAlign.Center).width(36);
          Button() { Text('+').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#123047'); }
            .id('AudioLabMasterPlus').width(30).height(24)
            .backgroundColor('#EAF4F8').borderRadius(12).onClick((): void => this.adjustMaster(0.05));
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center);
        Row({ space: 3 }) {
          Text('BGM').fontSize(11).fontColor('#334B5A').width(70);
          Button() { Text('-').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#123047'); }
            .id('AudioLabMusicMinus').width(30).height(24)
            .backgroundColor('#EAF4F8').borderRadius(12).onClick((): void => this.adjustMusic(-0.05));
          Text(this.percent(this.musicVolume)).fontSize(11).fontWeight(FontWeight.Bold)
            .fontColor('#123047').textAlign(TextAlign.Center).width(36);
          Button() { Text('+').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#123047'); }
            .id('AudioLabMusicPlus').width(30).height(24)
            .backgroundColor('#EAF4F8').borderRadius(12).onClick((): void => this.adjustMusic(0.05));
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center);
        Row({ space: 3 }) {
          Text('BGM duck').fontSize(11).fontColor('#334B5A').width(70).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Button() { Text('-').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#123047'); }
            .id('AudioLabDuckMinus').width(30).height(24)
            .backgroundColor('#EAF4F8').borderRadius(12).onClick((): void => this.adjustDuck(-0.02));
          Text(this.percent(this.musicLoweredVolume)).fontSize(11).fontWeight(FontWeight.Bold)
            .fontColor('#123047').textAlign(TextAlign.Center).width(36);
          Button() { Text('+').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#123047'); }
            .id('AudioLabDuckPlus').width(30).height(24)
            .backgroundColor('#EAF4F8').borderRadius(12).onClick((): void => this.adjustDuck(0.02));
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center);
        Row({ space: 3 }) {
          Text('SFX voice').fontSize(11).fontColor('#334B5A').width(70).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
          Button() { Text('-').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#123047'); }
            .id('AudioLabSfxVoiceMinus').width(30).height(24)
            .backgroundColor('#EAF4F8').borderRadius(12).onClick((): void => this.adjustSfxDuringVoice(-0.05));
          Text(this.percent(this.sfxDuringVoiceVolume)).fontSize(11).fontWeight(FontWeight.Bold)
            .fontColor('#123047').textAlign(TextAlign.Center).width(36);
          Button() { Text('+').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#123047'); }
            .id('AudioLabSfxVoicePlus').width(30).height(24)
            .backgroundColor('#EAF4F8').borderRadius(12).onClick((): void => this.adjustSfxDuringVoice(0.05));
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center);
      }
      .width('100%');
    }
    .width(WIDE_PANEL_WIDTH);
  }

  @Builder
  private policyPanel() {
    Column({ space: 8 }) {
      this.sectionTitle('SFX During Voice');
      Row({ space: 8 }) {
        ForEach(POLICIES, (policy: string) => {
          Button(this.policyLabel(policy))
            .id(`AudioLabPolicy_${this.policyLabel(policy)}`)
            .height(24)
            .fontSize(11)
            .fontWeight(this.sfxDuringVoicePolicy === policy ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.sfxDuringVoicePolicy === policy ? '#FFFFFF' : '#315166')
            .backgroundColor(this.sfxDuringVoicePolicy === policy ? '#276C7D' : '#EEF3F4')
            .borderRadius(7)
            .layoutWeight(1)
            .onClick((): void => this.setPolicy(policy));
        }, (policy: string): string => `${policy}-${this.sfxDuringVoicePolicy === policy ? 'selected' : 'idle'}`);
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
      Column({ space: 10 }) {
        Row() {
          Button('Back')
            .id('AudioLabBackButton')
            .height(32)
            .fontSize(13)
            .backgroundColor('#FFFFFF')
            .fontColor('#1D3557')
            .borderWidth(1)
            .borderColor('#B8D7F6')
            .onClick((): void => this.goBack());
          Text('Audio Lab')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D3557')
            .layoutWeight(1)
            .textAlign(TextAlign.Center);
          Blank().width(72);
        }
        .width('100%');

        this.mixPanel();

        Row({ space: PANEL_GAP }) {
          this.transportPanel();
          this.voicePanel();
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);

        Row({ space: PANEL_GAP }) {
          this.policyPanel();
          this.statusPanel();
        }
        .width('100%')
        .alignItems(VerticalAlign.Top);
      }
      .width('100%')
      .padding({ top: 12, left: PAGE_PADDING, right: PAGE_PADDING, bottom: 24 });
    }
    .id('AudioLabPage')
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .backgroundColor('#FFFFFF');
  }
}
