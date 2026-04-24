# WordMagicGame 产品与架构设计规格

> 文档状态：正式产品架构设计  
> 适用版本：V0.1 原型及后续迭代基线  
> 初始需求来源：`docs/鸿蒙背单词游戏开发.pdf`  
> 目标平台：HarmonyOS NEXT，ArkTS，ArkUI，DevEco Studio 托管工程

## 1. 产品定位

WordMagicGame，中文暂定名“小魔法师单词冒险”，是一款面向儿童的英语单词学习小游戏。产品通过“魔法公主对战史莱姆”的轻量战斗包装，将单词选择题转化为短时冒险体验，降低机械背诵的枯燥感，并帮助 8 岁左右儿童建立中文含义、英文单词与即时反馈之间的记忆连接。

V0.1 的目标不是构建完整商业化游戏，而是交付一个可运行、可扩展、可验证的离线原型。该原型应能稳定运行在华为平板和手机上，完成从首页、战斗、答题、结算到重新开始的基础闭环，为后续加入动画、音效、发音、关卡、学习记录和内容扩展留下清晰边界。

## 2. 用户与场景

### 2.1 目标用户

- 核心用户：8 岁左右、正在学习英语基础词汇的儿童。
- 使用陪伴者：家长或开发者本人，用于配置词库、观察学习效果和后续迭代内容。
- 学习阶段：从中文释义或图片/语音提示识别英文单词，优先覆盖常见名词。

### 2.2 使用场景

- 平板横屏短时学习：以华为 MatePad Air 为首要体验设备。
- 手机横屏补充练习：兼容 Mate 60 Pro 及其他支持 HarmonyOS NEXT 的手机。
- 离线使用：首版不依赖网络、账号、服务端或云同步，所有词库和资源本地打包。

### 2.3 产品成功标准

- 儿童可以在 5 分钟内独立完成一局游戏。
- 答题反馈足够及时，能清楚知道“答对造成伤害、答错自己扣血”。
- 视觉和交互足够游戏化，但规则简单到不需要额外教学。
- 架构上能支持后续添加更多词库、题型、角色、音效和学习统计。

## 3. 版本范围

### 3.1 V0.1 必须包含

- 首页：展示游戏名、开始游戏入口和基础说明。
- 战斗页：横屏战斗布局，左侧玩家角色，右侧怪物，中间或下方显示题目与三项英文选项。
- 答题流程：每题显示中文提示，用户从三个英文选项中选择答案。
- 战斗规则：正确答案攻击怪物，错误答案扣除玩家 HP。
- 连击规则：连续答对 3 题后触发一次双倍伤害。
- 结算页：展示本局胜负、击败怪物数、正确率、学习词数和星级奖励。
- 本地词库：首批约 30 个词，分为水果、日常地点、家居物品三类。
- 响应式横屏：适配平板与手机横屏，不出现主要内容裁切。

### 3.2 V0.1 明确不包含

- 用户账号、登录、云同步和排行榜。
- 在线词库、服务端内容管理和远程配置。
- 复杂养成系统、装备系统、商城或内购。
- 强依赖图片识别、语音识别或 AI 生成题目。
- 竖屏模式完整适配。

## 4. 游戏规则设计

### 4.1 基础参数


| 项目     | V0.1 设定                |
| ------ | ---------------------- |
| 单局时长   | 5 分钟                   |
| 每局怪物数  | 5 个                    |
| 玩家 HP  | 5                      |
| 怪物 HP  | 3                      |
| 每次正确伤害 | 1                      |
| 连击奖励   | 连续答对 3 题后，本次攻击造成 2 点伤害 |
| 选项数量   | 3 个英文选项                |
| 失败条件   | 玩家 HP 为 0，或倒计时结束       |
| 胜利条件   | 5 个怪物全部被击败             |


### 4.2 答题循环

1. 战斗开始后创建初始 `BattleState`，加载本局词库并生成第一题。
2. 页面显示中文提示词、三个英文选项、双方 HP、当前怪物和剩余时间。
3. 用户点击选项后，系统判断是否正确。
4. 正确时增加连击计数，并按普通或连击伤害扣除怪物 HP。
5. 错误时重置连击计数，玩家 HP 减 1，并短暂显示正确答案。
6. 怪物 HP 为 0 时记录击败数，若未击败 5 个怪物则生成下一个怪物。
7. 玩家 HP 为 0、倒计时归零或击败全部怪物时结束战斗并进入结算页。

### 4.3 连击规则

连击采用“第三次连续答对即触发奖励”的规则。每次答对后 `comboCount` 加 1；当 `comboCount` 达到 3 时，本次伤害为 2，触发魔法爆发反馈，并将 `comboCount` 重置为 0。答错会立即将 `comboCount` 重置为 0。

该规则简单、可感知，并能在短局内频繁触发奖励。后续版本可扩展为更长连击条、技能槽或角色技能，但 V0.1 不引入额外复杂度。

**V0.2 暴击视听分层 (crit spectacle).** 当 `AnswerOutcome.comboTriggered === true` 时，`BattlePage` 叠放以下五层反馈（详见 [2026-04-24-v0.2-design.md](superpowers/specs/2026-04-24-v0.2-design.md) §4），以让暴击明显强于普通攻击：

1. **全屏金色闪光**：`CritOverlay` 中的 `CritGoldFlash`，`#FFB400` opacity `0 → 0.55 → 0`，约 450 ms。
2. **巨型浮动伤害数字**：`CritDamageNumber` 72 vp，`-${outcome.damage}!` 悬浮于怪物卡片上方，联合 `translateY / opacity / scale` 约 700 ms。
3. **怪物缓慢放大**：`CharacterCard.zoomPulse` 驱动 220 ms ease-out 放大至 1.12，保持 120 ms 后在 160 ms 内复位。
4. **独立爆发音效**：`AudioService.play('hit_crit')`；普通攻击仍然使用 `hit_normal`。
5. **延长的玩家施法动画**：`CharacterCard.castPulse` 触发 500 ms 旋转 + 缩放 + 金色光环，明显长于普通命中的 120 ms 轻推。

普通命中走 `hurtPulse / nudgePulse`（150 ms / 120 ms），两条路径在 `onOptionTap` 里二选一触发，避免视觉叠加。`FEEDBACK_MS` 保持 650 ms，五层动画均在该窗口内完成。

### 4.4 星级奖励

V0.1 采用轻量星级反馈，不涉及持久化货币。建议规则如下：


| 星级  | 条件                       |
| --- | ------------------------ |
| 3 星 | 胜利且正确率不低于 80%            |
| 2 星 | 胜利但正确率低于 80%，或击败至少 3 个怪物 |
| 1 星 | 击败至少 1 个怪物               |
| 0 星 | 未击败怪物                    |


## 5. 内容设计

### 5.1 首批词库

首版包含约 30 个高频、短词、具象名词，优先降低儿童阅读负担。


| 分类   | 示例                                  |
| ---- | ----------------------------------- |
| 常见水果 | apple, banana, orange, grape, pear  |
| 日常地点 | school, hospital, park, supermarket |
| 家居物品 | TV, chair, bed, table               |


首版应避免过长或罕见单词，例如 `refrigerator`。若必须包含长词，应放入后续难度分层，而非 V0.1 默认词库。

### 5.2 题目生成原则

- 正确答案来自当前题目的 `word` 字段。
- 提示优先使用 `meaningZh`，即中文释义。
- 干扰项从同一或相近难度词库中选择，避免明显不属于同类导致题目过易。
- 三个选项顺序必须随机化。
- 不应连续两题出现同一个正确单词。
- 当词库数量不足以生成两个干扰项时，应降级到全局词库补足，而不是崩溃。

### 5.3 后续内容扩展

后续版本可加入图片提示、英文发音、拼写题、听音选词、错题复习和难度等级。所有扩展应优先通过 `WordEntry` 数据字段和 `QuestionGenerator` 策略扩展，而不是把题型逻辑写死在 UI 页面中。

## 6. 信息架构与页面流

### 6.1 页面结构

```text
HomePage
  -> BattlePage
      -> ResultPage
          -> HomePage 或 BattlePage
```

### 6.2 首页 HomePage

职责：

- 展示产品标题、角色主题和开始游戏按钮。
- 可展示当前词库分类入口，V0.1 可先默认使用全部首批词库。
- 不承载战斗状态和题目生成逻辑。

### 6.3 战斗页 BattlePage

职责：

- 呈现玩家、怪物、HP、倒计时、题目和选项。
- 接收用户答题输入并转发给 `BattleState` 或战斗控制器。
- 根据状态展示普通攻击、错误反馈、连击反馈和怪物切换。
- 在战斗结束时导航到结算页。

### 6.4 结算页 ResultPage

职责：

- 展示本局结果：胜负、击败怪物数、答题数、正确数、正确率、学习词数、星级。
- 提供“再来一局”和“返回首页”入口。
- 不重新计算战斗过程，只消费战斗结束时生成的 `SessionResult`。

## 7. 系统架构

### 7.1 架构原则

- 页面只负责展示和用户输入，核心规则放在模型或服务中。
- 游戏状态集中管理，避免 UI 组件各自维护不一致的血量、连击或计时。
- 词库、题目生成、战斗规则、音频播放相互解耦，便于独立测试。
- 所有 V0.1 数据和资源本地打包，确保离线可用。
- 组件小而清晰，优先保证儿童交互稳定和开发迭代效率。

### 7.2 推荐目录结构

```text
entry/src/main/ets/
  pages/
    HomePage.ets
    BattlePage.ets
    ResultPage.ets
  components/
    HpBar.ets
    ChoiceButton.ets
    CharacterCard.ets
    CountdownBadge.ets
    ComboBadge.ets
  models/
    WordEntry.ets
    Question.ets
    BattleState.ets
    SessionResult.ets
  services/
    WordRepository.ets
    QuestionGenerator.ets
    BattleEngine.ets
    AudioService.ets
  utils/
    shuffle.ets
    timer.ets
entry/src/main/resources/
  rawfile/
    data/words_v1.json
    sound/
  base/media/
  base/element/
```

当前工程仍以 `Index.ets` 作为入口页面，并已存在 `GiftBox.ets` 动画组件。后续实现时可以保留 `Index.ets` 作为临时入口，也可以将其改造为 `HomePage` 并同步更新 `main_pages.json`。已有礼盒动画和本地音频播放代码可作为后续奖励反馈、连击反馈或结算反馈的参考资产，但不应与战斗核心规则耦合。

### 7.3 模块职责


| 模块                     | 职责                                                                                                             | 依赖                                 |
| ---------------------- | -------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `WordEntry`            | 定义单词数据结构                                                                                                       | 无                                  |
| `Question`             | 定义单题提示、选项、答案                                                                                                   | `WordEntry`                        |
| `SessionResult`        | 定义结算数据                                                                                                         | `BattleState` 输出                   |
| `WordRepository`       | 加载本地 JSON 词库，按分类/难度筛选                                                                                          | 资源管理器                              |
| `QuestionGenerator`    | 从词库生成题目和干扰项                                                                                                    | `WordRepository`, `shuffle`        |
| `BattleState`          | 保存当前血量、连击、怪物序号、统计数据                                                                                            | 纯状态模型                              |
| `BattleEngine`         | 执行答题判定、伤害、胜负和结算转换                                                                                              | `BattleState`, `QuestionGenerator` |
| `AudioService`         | 播放本地音效，封装 AVPlayer 细节；单键预加载 + 失败静音回退                                                                           | HarmonyOS media API                |
| `PronunciationService` | 封装 `@kit.CoreSpeechKit` TTS，`speak(word)` 取消前一条，引擎不可用时静默 no-op (V0.2)                                          | CoreSpeechKit                      |
| `LearningRecorder`     | 维护 per-word 学习统计，100 ms 去抖写盘，暴露 `recordAnswer / recentWrongIds / newlyLearnedCount / totalLearnedCount` (V0.2) | `WrongAnswerStore`                 |
| `WrongAnswerStore`     | `@ohos.data.preferences` 封装，`wordmagic_learning` JSON 持久化 `LearningSnapshot` (V0.2)                            | `@ohos.data.preferences`           |
| `HpBar`                | 展示血量百分比                                                                                                        | UI 入参                              |
| `ChoiceButton`         | 统一答案按钮样式与禁用态                                                                                                   | UI 入参                              |
| `CharacterCard`        | 展示玩家或怪物形象和 HP；V0.2 新增 `hurtPulse / nudgePulse / zoomPulse / castPulse` 四个脉冲动画入口                                | `HpBar`                            |
| `CritOverlay`          | 暴击视觉三层：`CritGoldFlash` 全屏金闪 + `CritDamageNumber` 浮动伤害数字 + `CritCastGlow` 玩家施法光环 (V0.2)                         | `@Prop critPulse`                  |


### 7.4 状态流

```text
BattlePage
  -> 用户点击 ChoiceButton
  -> BattleEngine.submitAnswer(option)
  -> BattleState 更新
  -> QuestionGenerator 生成下一题或 BattleEngine 生成 SessionResult
  -> BattlePage 重新渲染
  -> 结束时路由到 ResultPage
```

页面不直接修改怪物 HP、玩家 HP 或连击数；所有用户动作必须通过战斗状态接口完成。这样可以在单元测试中不启动 UI，即验证核心规则。

## 8. 数据模型

### 8.1 WordEntry

```ts
export class WordEntry {
  id: string = '';
  word: string = '';
  meaningZh: string = '';
  category: string = '';
  difficulty: number = 1;
  image?: string;
  audio?: string;
}
```

字段说明：

- `id`：稳定唯一标识，避免直接用英文单词作为业务 ID。
- `word`：英文答案。
- `meaningZh`：中文提示。
- `category`：词库分类，例如 `fruit`、`place`、`home`。
- `difficulty`：难度等级，V0.1 默认 1。
- `image`：后续图片提示预留字段。
- `audio`：后续发音或听力题预留字段。

### 8.2 Question

```ts
export class Question {
  promptZh: string = '';
  answer: string = '';
  options: string[] = [];
  wordId: string = '';
}
```

约束：

- `options.length` 必须等于 3。
- `options` 必须包含 `answer`。
- 同一题内选项不能重复。

### 8.3 BattleState

```ts
export class BattleState {
  playerHp: number = 5;
  monsterHp: number = 3;
  monsterIndex: number = 1;
  monstersTotal: number = 5;
  comboCount: number = 0;
  remainingSeconds: number = 300;
  totalAnswers: number = 0;
  correctAnswers: number = 0;
  defeatedMonsters: number = 0;
  currentQuestion?: Question;
  status: BattleStatus = BattleStatus.Playing;
}
```

建议状态枚举：

```ts
export enum BattleStatus {
  Ready = 'ready',
  Playing = 'playing',
  Won = 'won',
  Lost = 'lost'
}
```

### 8.4 SessionResult

```ts
export class SessionResult {
  isWin: boolean = false;
  defeatedMonsters: number = 0;
  totalAnswers: number = 0;
  correctAnswers: number = 0;
  accuracy: number = 0;
  learnedWordCount: number = 0;
  stars: number = 0;
  elapsedSeconds: number = 0;
}
```

## 9. UI 与交互设计

### 9.1 横屏布局

BattlePage 建议采用三段式横屏布局：

- 左侧：玩家角色卡，显示小魔法师、公主状态和玩家 HP。
- 中央：题目区域，显示中文提示、连击状态、反馈文本和倒计时。
- 右侧：怪物角色卡，显示史莱姆、怪物 HP 和当前第几个怪物。
- 底部或中央下方：三个大尺寸答案按钮。

布局应使用 Row、Column、Flex、百分比宽度、权重和 vp 单位组合，不应依赖固定像素。按钮需要足够大，适合儿童点击。

### 9.2 反馈规则

- 答对：按钮短暂高亮为正向颜色，玩家播放攻击或魔法反馈，怪物 HP 下降。
- 答错：错误按钮短暂高亮，正确答案显示为正向颜色，玩家 HP 下降。
- 连击：第三次连续答对时展示“魔法爆发”或类似提示，并播放更明显的动画或音效。
- 怪物击败：怪物消失或淡出，下一个史莱姆出现。
- 结束：禁止继续答题，进入结算页。

### 9.3 可访问性与儿童体验

- 文案短句化，避免复杂说明。
- 选项按钮字体大、对比度高。
- 关键反馈同时通过颜色和文字/动画表达，避免只依赖颜色。
- 点击后应短暂禁用选项，防止连续点击造成重复结算。

## 10. 技术实现约束

### 10.1 HarmonyOS / ArkTS

- 使用 ArkTS 和 ArkUI 声明式 UI。
- 优先修改 `entry/src/main/ets` 下的页面、组件、模型和服务。
- 保持 DevEco Studio 管理的工程结构，不进行无必要的工程重排。
- 资源放入 `entry/src/main/resources`，词库建议放入 `rawfile/data/words_v1.json`。

### 10.2 状态管理

V0.1 可采用页面持有状态对象的轻量方案，避免过早引入复杂全局状态。随着功能增加，可再抽象为更明确的 Store 或 AppStorage 方案。无论采用哪种方式，战斗规则都应能在非 UI 环境中测试。

### 10.3 计时器

倒计时由 BattlePage 生命周期启动和释放，或封装进 `timer.ets` 工具。页面退出、战斗结束或重新开始时必须清理计时器，避免后台继续扣时或内存泄漏。

### 10.4 音频

音频播放通过 `AudioService` 封装。V0.1 可以只提供接口或少量本地音效，不要求完整音频系统。已有 `Index.ets` 中的本地 OGG 播放实践可作为实现参考。

## 11. 迭代里程碑


| 里程碑        | 内容                           | 验收产物          |
| ---------- | ---------------------------- | ------------- |
| T1 工程基线    | 确认 HarmonyOS ArkTS 工程可构建运行   | 空白或现有入口页在设备运行 |
| T2 页面路由    | 建立首页、战斗页、结算页的导航闭环            | 可从首页进入战斗并到结算  |
| T3 词库模型    | 定义 `WordEntry` 并创建本地 JSON 词库 | 可读取约 30 个词    |
| T4 题目生成    | 实现正确答案、干扰项和随机顺序              | 单元测试覆盖题目生成    |
| T5 战斗静态 UI | 完成横屏战斗页骨架                    | 平板和手机横屏布局正常   |
| T6 基础战斗    | 接入答题、血量、下一题和怪物切换             | 可完成一局基础流程     |
| T7 连击与反馈   | 实现三连击双倍伤害和提示                 | 连击行为可验证       |
| T8 结算页     | 展示本局统计和星级                    | 可重新开始或返回首页    |


## 12. 验收标准

V0.1 版本通过验收需满足以下条件：

- 构建部署：应用可编译，并可在 MatePad Air 和 Mate 60 Pro 或对应模拟/真机环境横屏运行。
- 基础玩法：玩家可在 5 分钟内通过三选一题目攻击 5 个怪物。
- 规则正确：答对扣怪物 HP，答错扣玩家 HP，三连击触发 2 点伤害。
- 结束闭环：胜利、玩家 HP 归零或时间耗尽时进入结算页。
- 统计准确：结算页正确显示击败数、答题数、正确率、学习词数和星级。
- 响应式布局：横屏平板和手机上 HP、角色、题目和按钮不裁切、不重叠。
- 稳定性：正常导航、答题、重开游戏过程中不崩溃；异常被记录并合理降级。

## 13. 测试策略

### 13.1 单元测试

优先覆盖纯逻辑：

- `shuffle` 不丢失元素。
- `QuestionGenerator` 生成 3 个不重复选项且包含正确答案。
- `QuestionGenerator` 不连续重复同一正确单词。
- `BattleEngine` 正确处理答对、答错、连击、怪物死亡、胜负条件。
- `SessionResult` 正确计算正确率和星级。

### 13.2 UI 测试

覆盖关键流程：

- 首页点击开始进入战斗页。
- 战斗页点击答案后状态变化。
- 玩家失败进入结算页。
- 击败 5 个怪物进入胜利结算页。
- 结算页点击再来一局重置状态。

### 13.3 手工验收

- 在平板和手机横屏分别检查布局。
- 快速连续点击答案，确认不会重复扣血或重复结算。
- 切出页面或返回首页，确认倒计时不会继续影响新局。
- 音效不可用时，确认游戏仍可正常进行。

## 14. 风险与决策


| 风险            | 影响         | 应对                                    |
| ------------- | ---------- | ------------------------------------- |
| 儿童误触或连点       | 状态重复结算     | 答题反馈期间禁用选项                            |
| 横屏手机空间不足      | 按钮或角色裁切    | 使用弹性布局，必要时压缩角色区域                      |
| 词库过少          | 干扰项重复或题目过易 | 全局补足干扰项，后续扩展词库                        |
| UI 与规则耦合      | 后续难维护      | 战斗规则放入 `BattleEngine` / `BattleState` |
| 音频 API 生命周期复杂 | 播放失败或资源泄漏  | 用 `AudioService` 封装并在页面销毁时释放          |


## 15. 后续路线图

### V0.2 学习体验增强（当前）

已落地，详见 [2026-04-24-v0.2-design.md](superpowers/specs/2026-04-24-v0.2-design.md)：

- **Track A · 反馈打磨与暴击视听.** `AudioService` 统一音效派发（`hit_normal / hit_crit / answer_wrong / monster_defeat / victory / defeat`）；`CharacterCard` 增加 `hurtPulse / nudgePulse` 普通命中脉冲；`CritOverlay` 叠加 `CritGoldFlash` + `CritDamageNumber` + `CritCastGlow`，配合 `zoomPulse / castPulse` 让暴击显著强于普通攻击（见 §4.3）。相关任务：T9 / T10 / T11。
- **Track B · 英文发音.** `PronunciationService` 封装 `@kit.CoreSpeechKit` TTS，`BattlePage.questionArea` 新增 `BattleSpeakerButton`；`GameConfig.autoSpeak` 由 `ConfigPage` 的 `ConfigAutoSpeakToggle` 切换。相关任务：T12。
- **Track C · 本地学习记录.** `WrongAnswerStore` + `LearningRecorder` 通过 `@ohos.data.preferences` 持久化每词统计（100 ms 去抖），`ResultPage` 展示 `本局新学 N / 累计 M`。相关任务：T13。
- **Track D · 错题复习模式.** `GameConfig.mode` 新增 `normal / review`；`HomePage.HomeReviewButton` 在 `recentWrongIds(12).length ≥ 3` 时启用；`BattlePage.aboutToAppear` 在复习模式下以错题池构建题目并覆盖 3 怪 / 120 s 参数；`BattlePage.navigateToResult` 结束时复位 `mode=normal`。相关任务：T14。
- **Track E · 验证与文档.** 新增 UI 测试 `CritSpectacleUiTest / SpeakerButtonUiTest / ReviewModeUiTest` 与单测 `WrongAnswerStore / LearningRecorder`，并在 `RoutingFlow.ui.test.ets` 中导出 `resetToDefaultConfigShared` 作为共享测试夹具。相关任务：T15 / T16。

### V0.3 内容与关卡

- 增加更多词库分类和难度等级。
- 支持按分类选择关卡。
- 增加更多怪物和背景主题。

### V0.4 复习与成长

- 引入本地进度、连续学习天数和掌握度。
- 根据错题频率调整出现概率。
- 加入简单角色成长或奖励展示。

### V1.0 产品化方向

- 完整视觉资源替换。
- 更系统的家长配置和学习报告。
- 评估是否需要云同步、账号和多设备进度。

## 16. 当前项目落地建议

当前代码仍是较早期的 HarmonyOS 示例形态，入口为 `Index.ets`，包含基础按钮、礼盒动画和本地音效播放实验。推荐后续实现时采用渐进式替换：

1. 保留现有工程配置，先新增模型、服务和单元测试。
2. 将 `Index.ets` 改造成首页，或新增 `HomePage.ets` 后更新路由配置。
3. 先完成无美术资源依赖的战斗闭环，再替换角色、怪物和背景资源。
4. 将已有 `GiftBox` 动画改造成奖励反馈时，保持其作为独立组件，不直接读写战斗状态。

这份文档作为后续迭代的产品与架构基线。每次新增大功能时，应先确认是否仍符合本规格中的架构边界；若引入账号、联网、持久化学习记录或新题型，应新增对应的专项设计文档。