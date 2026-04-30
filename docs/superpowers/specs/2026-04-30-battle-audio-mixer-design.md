# WordMagicGame Battle Audio Mixer Design

- **Date:** 2026-04-30
- **Roadmap:** [WordMagicGame_roadmap.md §V0.4.8.7](../../WordMagicGame_roadmap.md)
- **Status:** Design-for-implementation; no code changes in this spec step
- **Target version:** Dedicated audio-policy version after V0.4.8
- **Depends on:** Existing `AudioService`, `PronunciationService`, and BattlePage feedback flow
- **Out-of-scope:** Cocos2D battle rewrite, online audio assets, voice recognition, background playback outside BattlePage, true PCM mixer in the first implementation

## 1. 背景与目标

### 1.1 问题背景

当前战斗页已经有多种声音反馈：

- 普通攻击 / 暴击 / 怪物击败 / 胜利 / 失败等短音效由 `AudioService` 封装。
- 单词朗读由 `PronunciationService` 封装 CoreSpeechKit TTS。
- V0.4.8 曾尝试加入战斗 BGM，但已回退。主要原因是 TTS 会从系统层面强制暂停 BGM，后续多种恢复策略都会让 `SpellQuestionFlow` UI 测试出现 flake。

现在的需求不是简单恢复一条 BGM 播放调用，而是让战斗场景同时具备：

```text
1. 循环战斗 BGM
2. 多种攻击 / combo / 受伤 / 结算音效
3. 单词朗读
4. 清晰的优先级和音量关系
5. 不破坏拼写题点击稳定性
```

### 1.2 一句话设计

> 新增 `BattleAudioMixer` 作为战斗音频总控。第一版采用“逻辑混音”而不做 PCM 级真实混音：BGM、短音效、TTS 分属不同 lane，由 Mixer 统一处理生命周期、音量 duck、优先级、恢复节流和降级策略。

### 1.3 成功标准

- 战斗页进入后可播放无缝循环 BGM。
- 普通攻击、combo、受伤、怪物击败、胜利、失败音效可与 BGM 共存。
- 单词朗读时 BGM 自动降低音量，不盖住发音。
- TTS 导致 BGM 被系统暂停时，Mixer 只做一次克制恢复，不做轮询式抢救。
- `SpellQuestionFlow.ui.test.ets` 连跑 5 次 100% 通过后才允许合入。
- 页面退出后不残留 BGM、timer、player 或 TTS 监听。

## 2. 总体架构

### 2.1 模块结构

```text
BattlePage
  └─ BattleAudioMixer
       ├─ MusicLane
       │    └─ BGM AVPlayer, loop, volume duck, lifecycle
       ├─ SfxLane
       │    └─ AudioService or future SoundPool-backed short SFX
       └─ VoiceLane
            └─ PronunciationService, TTS listener / timeout bridge
```

`BattlePage` 只发送游戏语义事件，不直接控制播放器：

```text
enterBattle(ctx)
exitBattle()
startBattleBgm()
stopBattleBgm()
playNormalAttack()
playComboAttack()
playPlayerHurt()
playMonsterDefeat()
playVictory()
playDefeat()
speakWord(word)
```

### 2.2 Lane 职责

| Lane | 责任 | 第一版实现 | 后续可替换 |
| --- | --- | --- | --- |
| `MusicLane` | 播放低音量循环 BGM，支持 duck / stop / release | 专用 `AVPlayer` | `AudioRenderer` PCM loop |
| `SfxLane` | 播放短促反馈音效，可叠加在 BGM 上 | 复用 / 扩展 `AudioService` | `SoundPool` 或 native low-latency backend |
| `VoiceLane` | 播放单词朗读，通知 Mixer 朗读开始 / 结束 | 扩展 `PronunciationService` listener | TTS synthesize-to-PCM 后混音 |

### 2.3 为什么不是直接扩展 `AudioService`

`AudioService` 当前是一个轻量 SFX facade：一 key 一个 `AVPlayer`，`play(key)` fire-and-forget。BGM + TTS 的问题不是单个播放器能力，而是跨音轨编排：

- 何时降低 BGM 音量。
- 何时允许恢复 BGM。
- 页面退出后如何取消延迟恢复。
- TTS 没有回调或系统强制暂停时如何降级。
- combo / victory / defeat 与 BGM 的优先级如何统一。

这些逻辑放进 `BattleAudioMixer` 更清晰，也能避免 `AudioService` 从 SFX 工具类膨胀成战斗流程控制器。

## 3. 音频优先级与听感策略

### 3.1 优先级

从高到低：

```text
Voice / word pronunciation
  > terminal fanfare (victory / defeat)
  > combo attack
  > normal attack / hurt / monster defeat
  > BGM
```

### 3.2 音量策略

建议默认值：

| 场景 | BGM 音量 | SFX 音量 | Voice 音量 |
| --- | --- | --- | --- |
| 普通战斗 | 0.28-0.35 | 0.85-1.0 | 1.0 |
| 普通攻击 | 0.28-0.35 | 0.9 | 1.0 |
| combo 攻击 | 0.18-0.24, 300-500 ms 后恢复 | 1.0 | 1.0 |
| 单词朗读 | 0.08-0.12, 朗读结束后恢复 | 0.5-0.7 或不触发 | 1.0 |
| 胜利 / 失败 | BGM fade 或 stop | 1.0 | no-op |

第一版可以不用复杂淡入淡出曲线，但必须避免突兀：

- `setVolume()` 优先于 `pause()`，因为调音量通常比重启 player 成本低。
- 恢复 BGM 音量可用 2-3 个短 timer 阶梯恢复，但必须由 `exitBattle()` 统一取消。
- 若 timer 也引起 UI 抖动，则降级为一次性恢复音量。

### 3.3 BGM 资源要求

```text
entry/src/main/resources/rawfile/sound/bgm_battle_loop.ogg
```

资源约束：

- OGG Vorbis。
- 30-45 秒。
- 首尾无缝循环，无 fade-out、无 final hit、无尾部静音。
- 22050 Hz 或 44100 Hz。
- mono 优先，48-64 kbps。
- 目标体积 100 KB 内。

如用户提供 MP3，进入仓库前转码为 OGG；源 MP3 不作为正式运行资源。

## 4. TTS 与 BGM 焦点策略

### 4.1 已知约束

V0.4.8 已验证：

- `audioInterruptMode = INDEPENDENT_MODE` 能缓解同 app 内 AVPlayer 互相打断。
- CoreSpeechKit TTS 运行在系统层，TTS 播放会把 BGM AVPlayer 强制切到 `paused`。
- 高频监听 `audioInterrupt` 或周期性 `ensureBgmPlaying()` 会让拼写题 UI 测试不稳定。

因此新方案必须避免“BGM 抢焦点”思路。

### 4.2 speakWord 流程

```text
speakWord(word)
  1. 如果 Voice disabled 或 word 为空，直接返回。
  2. voiceToken += 1，用于取消旧的延迟恢复。
  3. 标记 voiceActive = true。
  4. MusicLane.duckForVoice()，只调低音量，不主动 pause。
  5. VoiceLane.speak(word, listener)。
  6. listener.onComplete / onError / onStop 进入 finishVoice(token)。
  7. 同时设置一个 1500-2500 ms timeout 兜底进入 finishVoice(token)。
```

`finishVoice(token)`：

```text
1. 如果 token 已过期或 mixer 已 disposed，no-op。
2. voiceActive = false。
3. 清理 voice timeout。
4. 如果 BGM 仍处于 playing / prepared，恢复音量。
5. 如果 BGM 被系统暂停，最多调用一次 safeResumeAfterVoice()。
6. safeResumeAfterVoice() 失败则静默放弃，不继续重试。
```

### 4.3 禁止策略

第一版明确不做：

- 不做周期性 `ensureBgmPlaying()`。
- 不在 `audioInterrupt` 回调里立刻反复 `play()`。
- 不为了 BGM 修改 `SpellQuestionFlow` polling budget 来掩盖 flake。
- 不在每个题目切换时强制重建 BGM player。
- 不让 `BattlePage` 自己维护 `bgmRescueTimer`。

## 5. 状态机

### 5.1 MusicLane 状态

```text
Idle
  -> Loading
  -> Ready
  -> Playing
  -> Ducking
  -> PausedByVoice
  -> Stopping
  -> Released
```

状态说明：

- `Idle`: 尚未 preload。
- `Loading`: 正在读取 rawfile / 创建 player。
- `Ready`: player prepared，但尚未播放。
- `Playing`: 正常循环。
- `Ducking`: 音量被 combo 或 voice 临时降低。
- `PausedByVoice`: TTS 导致系统暂停，等待一次性恢复。
- `Stopping`: 页面退出或战斗结束，正在 pause / release。
- `Released`: 已释放；所有异步回调必须 no-op。

### 5.2 Mixer 状态

```text
NotEntered
  -> Entering
  -> Active
  -> Ending
  -> Disposed
```

`exitBattle()` 必须：

- 切到 `Disposed` 或 `Ending`。
- 清理所有 volume restore timer。
- 清理 voice timeout。
- 停止 / 释放 MusicLane。
- dispose SfxLane / VoiceLane。
- 让之后的回调全部检查 token + disposed 标志。

## 6. API 设计

### 6.1 `BattleAudioMixer`

建议新增：

```text
entry/src/main/ets/services/BattleAudioMixer.ets
```

公开 API：

```text
class BattleAudioMixer {
  async enterBattle(ctx: common.UIAbilityContext): Promise<void>
  async exitBattle(): Promise<void>

  startBattleBgm(): void
  stopBattleBgm(): void

  playNormalAttack(): void
  playComboAttack(): void
  playPlayerHurt(): void
  playMonsterDefeat(): void
  playVictory(): void
  playDefeat(): void

  speakWord(word: string): void

  setMusicEnabled(enabled: boolean): void
  setSfxEnabled(enabled: boolean): void
  setVoiceEnabled(enabled: boolean): void
  setMasterVolume(value: number): void
}
```

第一版配置可以先常量化；后续接入 `GameConfig`：

```text
musicEnabled: boolean
sfxEnabled: boolean
voiceEnabled: boolean
masterVolume: number
musicVolume: number
sfxVolume: number
voiceVolume: number
```

### 6.2 `PronunciationService` 扩展

现有 `speak(word: string): void` 保留，避免破坏旧调用。

新增可选 listener 形态：

```text
speak(word: string, listener?: PronunciationListener): void
```

监听接口建议：

```text
class PronunciationListener {
  onStart?: () => void
  onComplete?: () => void
  onError?: () => void
  onStop?: () => void
}
```

如果 CoreSpeechKit listener 在 ArkTS 侧成本过高或造成 flake，则 `BattleAudioMixer` 第一版可以只用 timeout 兜底，不注册底层 listener。该取舍以 `SpellQuestionFlow` 连跑结果为准。

### 6.3 `AudioService` 扩展边界

第一版尽量少动 `AudioService`：

- 保留现有短音效 key。
- 新增 `COMBO_ATTACK` key。
- 可新增 `setVolume(key, value)`，但只用于 SFX 微调。
- 不把 BGM loop 逻辑塞回 `AudioService`，除非最终确认该抽象仍然足够简单。

若切换到 SoundPool，建议新建 `SfxLane` 内部实现，不要求 `BattlePage` 感知。

## 7. BattlePage 接入点

### 7.1 生命周期

当前：

```text
private audio: AudioService = new AudioService()
private tts: PronunciationService = new PronunciationService()
```

目标：

```text
private audioMixer: BattleAudioMixer = new BattleAudioMixer()
```

生命周期：

```text
aboutToAppear:
  await audioMixer.enterBattle(ctx)
  audioMixer.startBattleBgm()

aboutToDisappear:
  await audioMixer.exitBattle()
```

### 7.2 战斗事件映射

| BattlePage 事件 | Mixer 调用 |
| --- | --- |
| 正确普通攻击 | `playNormalAttack()` |
| combo / crit 触发 | `playComboAttack()` |
| 答错反击命中玩家 | `playPlayerHurt()` |
| 怪物击败 | `playMonsterDefeat()` |
| 胜利结算前 | `playVictory()` |
| 失败结算前 | `playDefeat()` |
| 自动发音 / 手动喇叭 | `speakWord(lastAnswerWord)` |

`BattlePage` 不再直接调用 `audio.play(SoundKeys.X)` 或 `tts.speak(word)`；过渡期可以先保留旧字段，但最终要收敛到 Mixer。

## 8. 降级策略

### 8.1 BGM 加载失败

- `enterBattle()` 不抛出。
- `startBattleBgm()` no-op。
- SFX 与 TTS 继续工作。
- 记录 `console.error` 便于真机调试。

### 8.2 TTS 不可用

- `speakWord()` no-op。
- 不影响 BGM 或 SFX。
- 自动发音按钮沿用现有不可用逻辑。

### 8.3 系统暂停 BGM 后恢复失败

- `safeResumeAfterVoice()` 最多尝试一次。
- 失败后保持静默，不继续救。
- 下一次 `startBattleBgm()` 或重新进入战斗时再尝试恢复。

### 8.4 资源缺失

- 缺短音效：对应 key muted，其他声音继续。
- 缺 BGM：只禁用 MusicLane。
- 缺 combo SFX：可临时回退 `HIT_CRIT`，但需要 log。

## 9. 测试计划

### 9.1 单元测试

新增或扩展本地单测：

- `BattleAudioMixer.enterBattle` 会 preload SFX 和 BGM。
- `playComboAttack()` 会触发 combo SFX，并对 BGM 做短 duck。
- `speakWord()` 会 duck BGM。
- TTS complete 后恢复音量。
- TTS complete 后如果 BGM paused，只恢复一次。
- `exitBattle()` 后所有 timeout / listener 回调 no-op。
- BGM preload 失败不影响 SFX。
- `setMusicEnabled(false)` 不影响 SFX / Voice。
- `setSfxEnabled(false)` 不影响 BGM / Voice。
- `setVoiceEnabled(false)` 不触发 BGM duck。

需要用 fake player / fake TTS 注入，避免单测依赖真实 media API。

### 9.2 UI / 集成验证

必须验证：

```text
hvigorw assembleHap
codelinter -c ./code-linter.json5 . --fix
```

按 `.cursor/dev-commands.md` 执行对应 ohosTest。

重点 UI 套件：

- `SpellQuestionFlow.ui.test.ets` 连跑 5 次。
- 战斗页从 Home 进入、答题、拼写、结算、返回，再进入，确认无残留 BGM。
- 自动发音开启：BGM 不盖住单词朗读。
- 自动发音关闭：BGM + SFX 正常。
- 快速连续答题：SFX 不阻塞点击，combo 能听到。

### 9.3 真机验收

至少在一台 HarmonyOS NEXT 真机 / 平板上验证：

- 系统媒体音量可以控制 BGM / SFX。
- TTS 声音清晰。
- 锁屏 / 切后台时 BattlePage 退出后 BGM 停止。
- 戴耳机与外放无明显差异。

## 10. 实施顺序

### Phase 1: Mixer 空壳与 SFX 代理

- 新增 `BattleAudioMixer`。
- 内部先持有现有 `AudioService` 与 `PronunciationService`。
- 不加 BGM，仅把 BattlePage 的 SFX / TTS 调用迁到 Mixer。
- 目标：行为不变，测试稳定。

### Phase 2: Combo 独立音效

- 新增 `combo_attack.ogg` 与 `SoundKeys.COMBO_ATTACK`。
- `playComboAttack()` 播 combo，不再复用 `hit_crit` 或只在需要时叠加。
- 验证短音效叠加无回归。

### Phase 3: BGM MusicLane

- 新增 `bgm_battle_loop.ogg`。
- 实现 `MusicLane` 专用 `AVPlayer` loop。
- 只在 `autoSpeak=false` 场景验证 BGM 与 SFX。

### Phase 4: Voice Duck

- `speakWord()` 前降低 BGM 音量。
- TTS complete 或 timeout 后恢复音量。
- 不做 BGM resume，只做音量 duck。

### Phase 5: 单次 Resume

- 若真机 / 模拟器确认 TTS 后 BGM 被暂停，再加 `safeResumeAfterVoice()`。
- 每次 TTS 结束最多一次恢复。
- `SpellQuestionFlow` 连跑 5 次必须通过。

### Phase 6: 配置化

- 将 music / sfx / voice 开关接入 `GameConfig` 或设置页。
- 可延后到家长设置版本，不阻塞第一版 BGM 合入。

## 11. 风险与决策点

| 风险 | 影响 | 处理 |
| --- | --- | --- |
| TTS listener 本身带来 ArkTS marshal 成本 | 拼写题点击 flake | 优先 timeout 兜底；listener 只在验证稳定后启用 |
| `AVPlayer.play()` 恢复成本高 | UI thread 抖动 | 每次 TTS 最多恢复一次；失败即放弃 |
| BGM 音量恢复 timer 干扰 UI | 点击稳定性下降 | 降级为一次性 setVolume |
| SFX 多 AVPlayer 成本高 | 低端设备延迟 | 第二阶段评估 SoundPool |
| 真机与模拟器焦点行为不同 | 线上表现不一致 | 真机作为最终合入门槛 |

## 12. 明确不变量

- `BattleEngine` 不感知音频实现。
- `BattlePage` 只发送音频语义事件。
- 音频失败不阻塞答题流程。
- 页面退出必须释放所有音频资源。
- 不以放宽 UI 测试 polling 作为解决 BGM 问题的主要手段。
- BGM 体验服从学习清晰度：朗读永远比背景音乐优先。

## 13. 验收清单

- [ ] 新增 `BattleAudioMixer` 后，原有 SFX/TTS 行为不退化。
- [ ] `combo_attack.ogg` 可独立播放。
- [ ] BGM 进入战斗后循环，退出战斗后停止。
- [ ] TTS 时 BGM 降低音量，朗读后恢复。
- [ ] TTS 打断 BGM 时最多恢复一次，不轮询。
- [ ] 缺失任一音频资源不导致战斗页崩溃。
- [ ] `SpellQuestionFlow.ui.test.ets` 连跑 5 次通过。
- [ ] CodeLinter 无新增缺陷。
- [ ] 真机验收通过。
