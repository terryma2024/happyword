# WordMagicGame 产品路线图

> 文档状态：路线图基线  
> 关联基线：[WordMagicGame_overall_spec.md](WordMagicGame_overall_spec.md)  
> 当前路线选择：趣味学习与长期学习系统平衡推进  
> 最近更新：2026-04-30（V0.4.5 本地学习报告：新增 `LearningReportBuilder` + `pages/LearningReportPage`，TodayPlanPage 顶栏 📊 入口跳转；展示总正确率 / 4 态计数（掌握/熟悉/学习中/新词） / 今日复习进度条 / 最薄弱 1-3 个分类 + 全部分类详情；薄弱分类按正确率升序、跳过 seenCount = 0 的分类；review-bar id 落在外层 Stack 上，避免 0% 时内层 Row 折叠失踪；UI 测试用 swipe(1400→300) 滚一次后再 findComponent 折叠下方组件；V0.4.4 每日学习计划页：HomePage 📋 入口 + `TodayPlanService`）

## 1. 产品愿景

WordMagicGame 的长期目标不是把单词题包装成一个短期小游戏，而是做成一个儿童愿意持续打开、家长能够理解学习价值、后续可以通过内容后台持续扩展的英语学习冒险产品。

产品需要同时满足两条主线：

- **游戏更好玩**：通过怪物差异、主题关卡、战斗反馈、奖励愿望单和未来剧情，让孩子觉得自己在冒险。
- **学习更有效**：通过题型阶梯、错词复习、遗忘曲线、词库分级和未来句子语境，让孩子真正理解并记住单词。

路线图的核心原则是：客户端先把学习游戏内核做扎实，服务端随后作为内容生产、词库发布、家长管理和 AI 能力的支撑层逐步进入。

## 2. 当前实现状态摘要

当前工程已经超过最初 V0.1 的离线原型范围，具备了继续产品化的基础：

- 页面闭环：已有 `HomePage`、`BattlePage`、`ResultPage`，并保留 `Index.ets` 作为入口相关页面。
- 配置能力：已有 `ConfigPage` 和 `CustomWordsPage`，支持本地战斗参数和自定义单词输入。
- 战斗模型：已有 `WordEntry`、`Question`、`BattleState`、`SessionResult`、`GameConfig` 等基础模型。
- 战斗服务：已有 `WordRepository`、`QuestionGenerator`、`BattleEngine`、`AudioService`、`PronunciationService`。
- 学习记录：已有 `LearningRecorder` 和 `WrongAnswerStore`，支持本地答题统计与错题复习基础。
- 怪物基础：已有 `MonsterCatalog`，V0.3.8 收紧到 10 条（3 archetype + 7 boss），战斗按 catalog 1-based 索引循环。
- 体验增强：已有暴击反馈、音效、TTS、复习模式和相关 UI/单元测试雏形。

因此后续路线不应回到“从零搭原型”，而应围绕“今日冒险、题型扩展、复习调度、奖励愿望单、内容后台”逐步演进。

## 3. 路线图总览


| 版本     | 主题               | 核心目标                                                      | 服务端依赖    |
| ------ | ---------------- | --------------------------------------------------------- | -------- |
| V0.3   | 趣味学习内核版          | 今日冒险、主题关卡包装、怪物题型差异、补字母题、轻量遗忘曲线、本地魔法愿望单                    | 无        |
| V0.3.5 | 区域与拼写难度补完版       | 新增学校城堡与家庭小屋两个主题区域、补字母题中级难度（双空两步选择）、今日冒险区域切换               | 无        |
| V0.3.6 | 首页入口合并版          | 合并“开始游戏”与“今日冒险”为单一主入口；首页不再显示右侧开始游戏区域；保留复习入口并迁移到顶部工具栏/卡片入口 | 无        |
| V0.3.7 | 怪物图鉴页            | 新增怪物图鉴页，左右箭头翻看 3 张难度形象（Slime / Zombie / Dragon）与童话风简介；首页工具栏提供入口        | 无        |
| V0.3.8 | 怪物图鉴扩展（7 boss 上线 + V0.2 颜色变种 Slime 退役） | 怪物图鉴扩到 10 张（3 archetype + 7 童话风 boss）；3 个 region 各持有 2-3 只 boss 候选，每天按 hash(regionId+date) 确定性轮换战斗中的 boss SVG；同时退役 V0.2 的 10 条 colored slime 变种（`Lava Imp` / `Frost Wisp` 等），catalog 收紧到 10 条，boss 索引由 14-20 重排为 4-10 | 无 |
| V0.3.9 | 魔法愿望单兑换流程重构      | 用 6 位家长 PIN 弹窗替代 3 秒长按门；兑换成功播放 GiftBox 庆祝动画（~1.68s 播 + 1.5s 停），期间遮罩 + HitTestMode.Block 屏蔽所有交互；新增持久化兑换记录页（cap 50，最新在前），从愿望单头部 📜 入口进入；卡片版式改为最左 emoji + 中间名+价 + 右侧申请兑换按钮的三段式；Pending 中间态退役（reader 兼容旧持久化）；ConfigPage 加家长密码入口行 | 无 |
| V0.3.10 | App 图标与按钮图标重构 | 用 Recraft V4 vector 生成 8 个统一「童话魔法羊皮纸」风格 SVG：app 启动图标（前景 magician 1024 + 背景紫粉金渐变魔法夜空 1024 + startIcon 尖帽金星 216）+ HomePage 顶部工具栏 4 个圆形按钮（📚📖🪄⚙ → review/codex/wand/gear）+ WishlistPage 头部 📜 按钮（→ scroll）；新增 `tools/recraft/{generate-icons.sh, svg-to-png.mjs, icons-to-launcher.sh}` 工具链；UI 测试改为 by-id 断言；不动战斗页 / 不做密度限定多 PNG / 不做深色主题变体 | 无 |
| V0.4.1 | 完整拼写题（Boss 限定）      | 新增 `QuestionKind.Spell` + `SpellGenerator`（4-9 字母门）+ `SpellingArea` 点选式字母板组件；首字母预亮，剩余字母按生成器 RNG 打乱成池；错点不扣血、不消耗、仅红色抖动；PlanQuestionSource 拆分 Boss/Elite，Boss 回退链 Spell→Medium→Beginner→Choice；BattleEngine.submitAnswer 接受 Spell 全词为合法选项；不动 LearningRecorder 写入 / 不接系统键盘 / 不做听写模式 | 无 |
| V0.4.2 | 多空补字母升级（已并入 V0.4.1） | 原计划「FillLetterMedium 升级到 3+ 空 + 撤销 + 错误反馈」与 V0.4.1 的完整拼写题在难度曲线上重复；点选式 Spell 已经覆盖「更长字符串的主动回忆」场景，故不再单独立项 | 无 |
| V0.4.3 | 精细记忆状态（已完成）       | `WordStat` 新增连续正/错次数 + `mastery`；`MemoryScheduler` 用连胜阈值促升 Familiar(2)/Mastered(5)，旧 `correctCount` 阈值（4/10）降级为 v2-snapshot 兼容回退；快照升级到 v3，老 blob 用 correct/seen 回填 mastery | 无 |
| V0.4.4 | 每日学习计划（已完成）       | HomePage 工具栏 📋 入口跳 `TodayPlanPage`；`TodayPlanService` 用 (regionId+dayKey) 哈希种子复用 `TodayAdventureBuilder`，按 Review/Learning/New 拆 3 段展示当日单词；行内显示 `MemoryState` 徽章 + ✓ 已完成（基于 V0.4.3 streak 数据派生）；read-only，不接入战斗或编辑 | 无 |
| V0.4.5 | 本地学习报告（已完成）       | `LearningReportBuilder` 计算总正确率 / 4 态计数 / 今日复习完成率 / 薄弱分类（按正确率升序，skip seen=0）；`pages/LearningReportPage` 4 卡片渲染 + 全分类详情；TodayPlanPage 顶栏 📊 入口；不接入趋势图 / 不做云端同步 | 无 |
| V0.4.6 | 更多主题区域（计划中）       | 新增更多主题区域和关卡数据，让今日冒险有持续变化                                      | 无 |
| V0.4.7 | 自定义愿望单条目（计划中）   | 奖励愿望单加入本地自定义兑换项，但仍不接真实支付                                      | 无 |
| V0.5   | 内容后台与 LLM 题库版    | Node.js 内容后台、词库管理、LLM 生成题目草稿、人工审核、词包发布                    | 必需       |
| V0.6   | 家长账户与设备绑定版       | 家长账号、孩子档案、二维码绑定设备、云端学习同步、云端愿望单                            | 必需       |
| V0.7   | AI 剧情与语境学习版      | 句子填词、主题剧情、LLM 生成剧情草稿、个性化冒险                                | 必需       |
| V0.8   | Cocos2D 战斗美术化重构版 | 用 Cocos Creator 重写战斗表现层，支持更完整的角色、怪物、动画、特效和多美术主题           | 可选       |


## 4. V0.3 趣味学习内核版

### 4.1 产品目标

V0.3 的目标是把当前战斗闭环升级为“孩子愿意每天玩一局，系统能逐步安排复习”的学习游戏内核。它需要同时带来游戏感和学习效率，但不引入账号、服务端、真实支付或复杂后台。

V0.3 的一句话定义：

```text
今日冒险 + 主题关卡包装
+ 怪物题型差异
+ 三选一与选择缺失字母
+ 轻量遗忘曲线
+ 本地魔法愿望单
```

### 4.2 今日冒险

首页增加“今日冒险”作为主入口。孩子看到的是一次主题冒险，例如“水果森林”，系统实际做的是根据学习记录生成当天的一局练习。

今日冒险建议规则：

- 每天默认推荐 1 局。
- 一局仍保持短时体验，优先沿用当前 5 怪战斗结构。
- 战斗词池由“待复习词、学习中词、新词”混合生成。
- 今日首次完成给额外奖励，重复游玩仍可练习但奖励递减或受每日上限限制。
- 暂不做完整地图大 UI，先用一个主题关卡入口和简单章节数据承载。

### 4.3 主题关卡包装

V0.3 先使用章节/区域数据，而不是制作复杂地图系统。推荐初始主题：


| 区域   | 主题词                 | 视觉方向      | Boss           | 主要题型      |
| ---- | ------------------- | --------- | -------------- | --------- |
| 水果森林 | `fruit`             | 自然、藤蔓、果冻怪 | Fruit Guardian | 三选一 + 补字母 |
| 学校城堡 | `place` / school 相关 | 书本、铅笔、钟表  | Clock Wizard   | 补字母 + 复习题 |
| 家庭小屋 | `home`              | 家具、玩具、影子怪 | Toy Knight     | 混合题型      |


V0.3 只实现"水果森林"一个区域，数据结构设计成可扩展的 `AdventureRegion`，"学校城堡"和"家庭小屋"两个区域以及今日冒险的区域切换 UI 延后到 V0.3.5 补完。

### 4.4 怪物多样性

怪物多样性不应只是换名字和颜色，而应影响题型和学习目标。推荐 V0.3 怪物类型：


| 怪物类型 | 学习作用     | 题型行为             |
| ---- | -------- | ---------------- |
| 普通怪  | 维持基础识别训练 | 三选一              |
| 拼写怪  | 引入轻量拼写训练 | 选择缺失字母           |
| 复习怪  | 强化最近错词   | 优先抽取错词/待复习词      |
| 精英怪  | 检查阶段掌握   | 三选一与补字母混合        |
| Boss | 综合考察本局词汇 | 混合题型，优先使用本局出现过的词 |


这样孩子会感到“怪物不一样”，同时每种怪物都对应一种明确学习目的。

### 4.5 题型系统

V0.3 正式支持两类题型：

- **三选一识别题**：沿用当前中文提示、三个英文选项的基础题型。
- **选择缺失字母题**：给出带空格的英文单词和 3 个候选字母，让孩子点选缺失字母。

补字母题示例：

```text
中文提示：苹果
英文提示：a _ p l e
选项：p / b / t
```

难度建议：

- 初级（V0.3 落地）：缺 1 个字母，例如 `a _ p l e`，3 选 1。
- 中级（延后到 V0.3.5）：缺 2 个字母，但分两步选择，例如 `s _ h _ o l`。
- 高级（延后到 V0.4）：连续隐藏字母或完整拼写。

V0.3 暂不做系统键盘输入。原因是横屏键盘容易遮挡战斗 UI，儿童误输入成本高，并且会引入焦点、撤销、大小写和输入法兼容问题。V0.3 先做点选式初级补字母，V0.3.5 引入中级双空版本，V0.4 再进入完整写单词。

### 4.6 轻量遗忘曲线

V0.3 需要把当前学习记录升级为更明确的词状态。推荐每个单词进入以下状态：

```text
new -> learning -> review -> familiar -> mastered
```

含义：

- `new`：从未出现或很少出现。
- `learning`：已经出现但尚不稳定。
- `review`：最近答错、到期需要复习，或正确率偏低。
- `familiar`：近期表现稳定，但仍需低频复习。
- `mastered`：长期表现稳定，只需极低频抽查。

今日冒险出题池建议比例：


| 来源     | 建议比例 | 目的           |
| ------ | ---- | ------------ |
| 待复习/错词 | 50%  | 把遗忘风险最高的词拉回来 |
| 学习中词   | 30%  | 巩固正在建立记忆的词   |
| 新词     | 20%  | 保持新鲜感和进度感    |


V0.3 不需要实现完整 SM-2 算法，可以先采用简单字段：

- `seenCount`
- `correctCount`
- `wrongCount`
- `lastAnsweredMs`
- `lastCorrectMs`
- `nextReviewMs`
- `memoryState`

规则要足够可解释，便于后续家长报告展示。

### 4.7 魔法愿望单

V0.3 奖励系统采用“轻量家长承诺奖励雏形”，命名建议为“魔法愿望单”。它不是商城，也不接真实金钱，而是帮助孩子理解“认真学习可以积累愿望”。

奖励类型：

- **星星**：表示本局学习表现。
- **魔法币**：表示可累计兑换积分。
- **勋章/贴纸**：表示阶段性成就，V0.3 可先预留。

基础奖励规则建议：


| 行为            | 魔法币 |
| ------------- | --- |
| 完成今日冒险        | +5  |
| 每击败 1 个怪物     | +1  |
| 正确率不低于 80%    | +3  |
| 复习词完成率不低于 80% | +2  |
| 每日首次完成额外奖励    | +5  |


保护规则：

- 每日魔法币上限建议先设为 `20`。
- 重复刷同一局可以练习，但不能无限刷奖励。
- V0.3 不接支付宝、真实零钱、内购或任何支付能力。

愿望单本地流程：

```text
孩子完成今日冒险
  -> 获得魔法币
  -> 首页显示累计魔法币
  -> 奖励页展示本地兑换项
  -> 孩子点击申请兑换
  -> 状态变为等待家长确认
  -> 家长在本机点击确认
```

V0.3 兑换项可以先本地内置 2-3 个，例如“睡前故事一次”“周末冰淇淋”“10 分钟动画时间”。V0.6 再升级为家长账号下的云端可配置愿望单。

### 4.8 句子填词预留

V0.3 不把句子填词放入正式 UI，但需要在架构上预留数据方向。原因是句子填词依赖高质量例句、语境控制、难度分级和内容审核，更适合与 V0.5 的内容后台及 LLM 题库生成结合。

建议预留字段方向：

- `exampleSentence`
- `sentenceMeaningZh`
- `sentenceBlank`
- `sentenceAnswer`
- `sentenceDifficulty`
- `source`
- `reviewStatus`

这些字段可以先出现在后续 `QuestionTemplate` 或服务端题库模型中，不必立即写入客户端主流程。

### 4.9 V0.3 明确不做

- 不做 Node.js 后台。
- 不做账号登录。
- 不做二维码绑定。
- 不做真实支付宝、零钱、内购或支付。
- 不做完整键盘拼写。
- 不做正式句子填词 UI。
- 不做 LLM 实时生成剧情。
- 不做复杂地图大界面。
- 不做面向多孩子/多设备的云同步。

### 4.10 V0.3 建议开发拆分

推荐按以下顺序拆分后续开发任务：

1. **题型抽象**：让 `Question` 能表达三选一和补字母两类题，而不是只隐含选择题。
2. **补字母题生成器**：基于 `WordEntry.word` 生成缺失字母、展示文本和候选字母。
3. **怪物类型数据**：扩展 `MonsterCatalog` 或新增怪物战斗配置，让怪物决定题型偏好。
4. **今日冒险生成器**：根据主题、词状态和怪物序列生成一局冒险。
5. **轻量记忆状态**：在现有学习记录基础上增加 `memoryState` 与 `nextReviewMs`。
6. **奖励账户**：本地保存魔法币、每日获得值和简单交易记录。
7. **魔法愿望单页面**：展示可兑换项、申请状态和本地家长确认按钮。
8. **结算页升级**：展示今日新学词、复习词、魔法币、星星和愿望进度。
9. **测试与验收**：覆盖补字母判定、出题比例、奖励上限、愿望单状态流。

V0.3 开始需要保持战斗逻辑与表现层分离。题目生成、答题判定、学习记录和奖励结算应继续留在可测试的逻辑层，ArkUI 当前只作为表现与交互承载。这样后续迁移到 Cocos2D 战斗场景时，可以替换战斗表现层而不重写学习系统。

## 5. V0.3.5 区域与拼写难度补完版

V0.3.5 是 V0.3 的延伸版本，目标只有两个：把 V0.3 实施时显式延后的内容补回来，让今日冒险拥有更多可换的主题与更高的拼写挑战上限。它不引入新的服务端能力，也不调整奖励规则或学习记录字段。

### 5.1 范围

- **新增主题区域**：在已上线的"水果森林"基础上，继续完成"学校城堡（`Clock Wizard`）"和"家庭小屋（`Toy Knight`）"两个 `AdventureRegion`，每个区域配套自己的词类映射、关卡背景色 token、Boss 名称与提示语。
- **补字母题中级难度**：在 V0.3 的初级（缺 1 字母 / 3 选 1）之上加入中级模式（缺 2 字母，分两步顺序选择），供精英怪和 Boss 抽题时使用。中级题需要 UI 支持两步状态、错选撤销和"差一步"提示。
- **今日冒险区域切换**：首页今日冒险卡片支持在三个区域之间切换（轻量主题选择，而不是完整地图）。词池仍按今日冒险的 50 / 30 / 20 比例规则生成，只有底色和 Boss 不同。
- **Combo 爆发音效升级**：连击触发魔法爆发（Combo Burst）时，替换当前过于单调的提示音为更有“爆炸/冲击”效果的音效（只改音效与混音参数，不改连击规则与伤害数值）。
- **怪物种类补充（按难度）**：补齐基础“难度→怪物形象”映射，让孩子对难度变化更直观：
  - 简单：史莱姆（Slime）
  - 中等：僵尸（Zombie）
  - 困难：龙（Dragon）

### 5.2 V0.3.5 明确不做

- 不做完整地图大 UI。
- 不做正式句子填词 UI。
- 不做完整键盘拼写，仍然是点选式。
- 不调整魔法币上限或愿望单兑换流程。
- 不引入服务端、账号或云同步。

### 5.3 进入条件

- V0.3 的题型抽象、轻量遗忘曲线、奖励账户和愿望单已稳定运行。
- `AdventureRegion` 与 `FillLetterGenerator` 在 V0.3 已预留扩展点；V0.3.5 只增加数据与新难度分支，不重写既有逻辑。

## 6. V0.3.6 首页入口合并版

V0.3.6 的目标是把首页“开始游戏”旧入口与 V0.3 的“今日冒险”新入口合并成一个更清晰、更少干扰的主路径：**孩子只需要点一个入口就能开始今天的冒险**。同时，为了不丢失既有“复习错题”价值，本版本保留复习入口，但把它从首页右侧大按钮区域迁移到更轻量的位置（例如顶部工具栏或冒险卡片上的辅助入口）。

### 6.1 范围

- **主入口合并**：
  - 首页不再提供“普通开始游戏（自由练习）”作为主路径。
  - 原“开始游戏”的玩法并入“今日冒险”：主入口点击后直接进入“今日冒险”（即 `today` 模式，由 `TodaySessionPlan` 驱动怪物与题型）。
- **首页布局收敛**：
  - 首页不再显示当前右侧的“开始游戏/复习按钮”竖列区域（减少视觉噪音、避免两个入口让孩子困惑）。
  - 首页的关键信息保留：标题、副标题、今日冒险卡片、金币显示、愿望单入口、配置入口等。
- **保留复习入口（迁移）**：
  - “复习错题”入口继续存在，但不再占据右侧大区域；迁移到**顶部工具栏**：与金币/愿望单/配置同一行的一个小按钮入口。
  - 复习入口的 gating 规则（例如错题数阈值）沿用现有逻辑；按钮可在不可用时置灰或隐藏，但不引入新的学习策略变更。

### 6.2 验收标准建议

- 首页只存在一个显著主 CTA（今日冒险），点击即可进入战斗。
- 首页不再出现右侧“开始游戏/复习按钮”竖列区域。
- 复习入口可达（在顶部工具栏或冒险卡片内），且在满足阈值时可进入复习战斗；不满足阈值时表现为禁用或隐藏（需保持一致且可解释）。
- 现有 V0.3“今日冒险”奖励与“今日完成”展示不回归；愿望单入口、金币显示不回归。

### 6.3 V0.3.6 明确不做

- 不改变今日冒险的出题比例、怪物槽位、奖励规则（这些仍由 V0.3/V0.3.5 定义）。
- 不新增区域、不新增拼写难度（这些属于 V0.3.5）。
- 不引入账号/服务端/云同步。

## 7. V0.3.7 怪物图鉴页

V0.3.7 在 V0.3.6 收敛主入口之后，给孩子补一个“非战斗、可慢慢翻看”的内容页，让他们在战斗外也能与怪物互动、加深角色记忆。本版本不引入新的怪物美术、不调整战斗规则，只把当前 3 套真实美术对应的难度形象以图鉴形式展示出来，每只怪物配一段儿童向简介。

### 7.1 范围

- **新增页面 `MonsterCodexPage`**：
  - 一次只展示一只怪物：大尺寸形象（直接用 `character/slime.svg` / `character/zombie.svg` / `character/dragon.svg` 对应资源）+ 英文名 + 中文角色定位（普通怪物 / 拼写专家 / 精英挑战者）+ 童话风简介段。
  - 两侧提供左右圆形箭头按钮，逐只翻看；当前位置显示为 `n / 3`，到首末两端时对应箭头置灰禁用，不做循环跳转，避免孩子误以为翻完了一圈。
  - 顶部保留返回首页按钮；不与战斗页/复习页共享导航。
- **怪物简介数据**：
  - 新增独立的 `data/MonsterCodex.ets`（与战斗用的 `MonsterCatalog` 解耦），导出 `MONSTER_CODEX` 数组，长度固定为 3，每条含 `key / nameEn / kindLabelZh / descriptionZh / assetPath` 字段。
  - 简介为儿童向童话风世界观文案（每段约 80–120 字、3–4 句），不提玩法、不提关卡，仅描述怪物本身；可由产品/文案在 PR 中一次性补齐。
- **入口位置**：
  - 在首页顶部工具栏新增图鉴入口按钮 `HomeCodexButton`（📖 emoji），插入位置在 `📚 HomeReviewButton` 与 `🪄 HomeWishlistButton` 之间，工具栏顺序变为 `✨ 📚 📖 🪄 ⚙`。
  - 视觉沿用 `HomeWishlistButton` 配色（红字 `#E63946` / 白底 `#FCEAEA` / 56×56 圆形）。
  - 入口点击后通过 `router.pushUrl` 进入图鉴页，返回时落回首页（与现有愿望单页一致）。

### 7.2 验收标准建议

- 首页工具栏出现图鉴入口按钮 `HomeCodexButton`，点击进入 `MonsterCodexPage`。
- 图鉴页首次进入时永远停在 Slime（index 0），无任何持久化记忆，并展示形象、名称、角色定位、简介与位置指示器 `1 / 3`。
- 左右箭头能正确翻页：右箭头到 Dragon (`3 / 3`) 后置灰，左箭头到 Slime (`1 / 3`) 时置灰；不做循环跳转，再点同一边箭头为 no-op。
- 3 段简介文案均不为空、童话风、不提玩法/关卡，且能在屏幕内完整显示，不依赖滚动。
- UI 测试覆盖：图鉴入口可达、Next/Prev 翻完 3 只 + 边界禁用、返回首页。
- 战斗、复习、愿望单、配置等既有入口和体验不发生回归。

### 7.3 V0.3.7 明确不做

- 不新增任何怪物形象/资产；图鉴永远 3 张（Slime / Zombie / Dragon），与现有美术资源 1:1 对应。
- 不让 V0.2 catalog 的 10 条 (`Lava Imp` / `Frost Wisp` 等) 进入图鉴；它们在战斗中复用同一个 slime 资产，进入图鉴会出现 10 张几乎相同的卡片。（注：这 10 条 colored slime 变种已在 V0.3.8 §8 中正式退役，由 7 只 boss 的视觉多样性接管。）
- 不引入“解锁”机制（不按学习进度逐步解锁怪物），所有怪物默认全部可见。
- 不在图鉴页内提供战斗、出题或音效预览功能；不接 TTS、不播任何音效。
- 不持久化 `currentCodexIndex`（每次进入永远从 Slime 开始）。
- 不做 swipe / 长按 / 缩放手势。
- 不改动战斗中怪物轮转、`MonsterKind` 行为或区域 `monsterPlan`。
- 不引入账号/服务端/云同步；简介文案随客户端一起发布。

## 8. V0.3.8 怪物图鉴扩展（7 boss 上线 + V0.2 颜色变种 Slime 退役）

V0.3.8 在 V0.3.7 收敛到 3 张难度形象之后，把怪物图鉴扩到 10 张：3 个 archetype（Slime / Zombie / Dragon）保留不动，再追加 7 只用 Recraft V4 vector 生成的童话风 boss（Witch / Phoenix / Unicorn / Kraken / Pumpkin King / Snow Queen / Imp King）；同时把这 7 只 boss 接入战斗 —— 3 个 region 各持有 2-3 只 boss 候选，TodayAdventureBuilder 用 `hash(regionId + localDayKey)` 哈希确定性挑一只覆盖 slot 5 的 catalogIndex，让玩家每天进同一区域都能见到不同 boss SVG。

同版本顺手把 V0.2 时代留下的 10 条**颜色变种 Slime**（`Lava Imp` / `Frost Wisp` / `Thorn Goblin` / `Sand Beetle` / `Storm Sprite` / `Coral Slime` / `Moss Hopper` / `Ash Imp` / `Sea Drop` / `Ember Tail`）从 `MonsterCatalog` 中**移除**——所有变种共用同一张 slime SVG，只是 fill/stroke 不同；boss 视觉多样性已经足够，单一 slime SVG 配上 archetype + boss 名册就是更紧凑、更易维护的怪物体系。Catalog 由 20 条收紧到 10 条（archetype 1-3、boss 4-10），`monsterIndexForKind(Normal/Spelling/Review/Elite/Boss) = 1/2/2/3/3` 同步重排。

### 8.1 范围

- **新增 7 张怪物美术资源**：
  - `entry/src/main/resources/rawfile/character/{witch,phoenix,unicorn,kraken,pumpkin-king,snow-queen,imp-king}.svg`，全部由 `tools/recraft/generate-bosses.sh` 经 Recraft V4 vector 生成；7 张原始响应 JSON 落盘到 `generated/recraft/` 留作可复现证据。
- **数据层扩展**：
  - `MonsterEntry` 增加 `assetPath: string` 字段（archetype 3 条留空字符串触发 fallback）；新增 `makeBossEntry` 工厂；`MONSTER_CATALOG` 由 20 条收紧到 **10 条**——3 archetype（Slime / Zombie / Dragon）+ 7 boss（catalog idx 4-10，全部 `kind=Boss`）。V0.2 的 10 条 colored slime 变种（`makeEntry` 出来的旧条目）一并移除；`monsterIndexForKind` 重排为 1/2/2/3/3 指向 archetype。
  - `CharacterAssets` 新增 `assetPathForEntry(entry)` resolver，优先返回 `entry.assetPath`，空时 fallback 到 `characterAssetForKind(entry.kind)`。
  - `AdventureRegion` 增加 `bossCandidates: number[]`；`AdventureCatalog` 把 Forest 设为 `[4,5,6]`、Castle 设为 `[7,8]`、Cottage 设为 `[9,10]`。
- **战斗集成**：
  - `TodayAdventureBuilder.applyBossRotation` 用 djb2 哈希 `${region.id}:${localDayKey(nowMs)}` 确定 candidates 索引，覆盖 `plan.monsterSlots` 末尾槽位的 `catalogIndex`；word-pick RNG 不动，确定性契约保留。
  - `BattlePage` 把 `characterAssetForKind(this.currentMonster.kind)` 改为 `assetPathForEntry(this.currentMonster)`，单点改造。
- **图鉴扩展**：
  - `MONSTER_CODEX` 长度 3 → 10；旧 3 条不动；新增 7 条按"region 出现顺序"（Forest 3 / Castle 2 / Cottage 2）排列；每条配 65-85 字童话风简介。
  - `MonsterCodexPage` 代码 0 行改动 —— 长度驱动，position indicator 自动从 `1 / 3` 变 `1 / 10`。

### 8.2 验收标准建议

- 战斗：进入 Fruit Forest 区域多日，slot 5 出现的 boss SVG 在 {Pumpkin King, Imp King, Phoenix} 中确定性轮换；同一天同一区域稳定同一只；不同区域当天可能不同。
- 图鉴：左右箭头能完整翻完 10 张；boss 卡片显示对应童话风英文名 + 中文副标题（如 `Witch` / `「夜空魔法师」`）+ 65-85 字简介 + 对应 SVG。
- 单测：MonsterCatalog（恰好 10 条、boss idx 4-10、kind=Boss、assetPath 唯一、archetype 3 条 assetPath 为空）/ CharacterAssets（assetPathForEntry 显式与 fallback 双路径）/ AdventureCatalog（3 region candidate 范围 4-6 / 7-8 / 9-10 + 7 个索引并集）/ TodayAdventureBuilder（同日同 region 稳定、空 candidates 走 fallback、override 仅触末槽、14 天哈希分布≥2）/ MonsterCodex（长度 10、顺序、boss 标签非 archetype）全过。
- UI：MonsterCodexFlow 用例 next ×9 + prev ×9 走完全程，中间采样 Pumpkin King `4 / 10` / Witch `7 / 10`。
- V0.2 颜色变种 Slime 已退役，free-play 模式下战斗轮播怪物为 Slime → Zombie → Dragon → boss 序列；archetype 3 条行为不变；现有 11 个 UI 套件 0 回归。

### 8.3 V0.3.8 明确不做

- 不新增 region（4 个候选 boss 完全在战斗里"安家"是 v0.4 的事；当前 7 只全部塞进 3 个老 region 的 candidates）。
- 不引入 Boss Rush、boss 解锁、boss 专属技能、boss 专属伤害公式、boss 专属对白。
- 不让 boss 出现在非末槽，不改 `MonsterPlan.slots.length === 5` 与 slot kind 模板。
- 不做 boss 名朗读 TTS / boss 专属音效。
- 不持久化 codex 当前索引，每次进图鉴仍从 Slime 开始。
- 不引入"今日 boss 是谁"的 HomePage 预览。
- 不动 v0.3.7 已有 3 archetype 的 nameEn / kindLabelZh / descriptionZh / assetPath。
- 不引入账号/服务端/云同步；7 boss 美术随客户端发布。

## 9. V0.3.9 魔法愿望单兑换流程重构

V0.3.9 把 V0.3 时代「家长长按 3 秒环」的魔法愿望单兑换流程整体重构，目标是让兑换体验更明确、更仪式感、并把"已兑换什么"沉淀成可回溯的记录。

具体做三件事：

1. **6 位家长 PIN 替代长按门**：`GameConfig` 新增 `parentPin: string` 字段（默认空），家长在 ConfigPage 的「家长密码」入口走两步一致才能落盘到 AppStorage。孩子点「申请兑换」时弹出全屏 `ParentPinDialog`（自绘 3×4 数字键盘 + 6 个圆点占位），输错抖动+清空（无锁定无计数），输对自动 dismiss 并触发 `CoinAccount.redeem`。未设 PIN 时点申请兑换会弹 AlertDialog 引导家长去配置页设置，**不**进入 PIN 输入框。
2. **GiftBox 庆祝动画**：兑换成功后在 WishlistPage 顶层 `Stack` 盖一个全屏 50% 黑底遮罩 + `HitTestMode.Block` 屏蔽点击 + `onBackPress` 拦截系统返回，里面播放复用现有 `GiftBox` 组件（盖子弹起 + 10 条彩带飞散 + 1.5s 自动盖回，总长 ~1.68s），动画结束后再停 1.5s 然后 modal 整体消失；之后卡片右槽闪现「已兑换 ✓」1.5s 自动 recycle 回 Idle。从 redeem 到 wish 回 Idle 总时长 ≈ 4.68s。
3. **持久化兑换记录页**：新增 `RedemptionHistoryStore` 服务（preferences 持久化、cap 50、超出丢最早一条），每笔兑换写一条 `RedemptionRecord{ id, ts, wishId, displayName, iconEmoji, costCoins }`。新页 `RedemptionHistoryPage` 按 `ts desc` 渲染卡片列表（emoji + 名字 + `YYYY-MM-DD HH:mm` 时间戳 + `-N ✨` 红字花费），空态文案「还没有兑换记录」；从愿望单头部魔法币左侧的 📜 按钮进入。

同步把卡片版式改成 **左侧 name + cost、右侧 prize emoji + 申请兑换按钮并排靠右**，emoji 不再贴在名字左边；旧 `Pending` 中间态退役但枚举保留（`coerceState` 把旧持久化里的 `'pending'` 归一为 `Idle`，避免升级时卡死）；`ParentLongPressGate` 组件文件保留但 wishlist 不再 import，等 v0.4 cleanup pass 再处理。

### 9.1 范围

- **数据模型**：
  - `models/GameConfig.ets` 加 `parentPin: string`（默认 `''`），`cloneGameConfig` 同步并对 `undefined` 容错（旧持久化）。
  - 新增 `models/RedemptionRecord.ets`：`RedemptionRecord` 值对象 + `RedemptionHistorySnapshot` envelope + `REDEMPTION_PREFS_NAME` / `REDEMPTION_PREFS_KEY` / `REDEMPTION_HISTORY_CAP=50` 常量 + 纯函数 `formatLocalTimestamp(ms): string` 输出 `YYYY-MM-DD HH:mm`（本地时区，两位补零）。
- **服务层**：
  - 新增 `services/RedemptionHistoryStore.ets`：mirror `WishlistStore` 的 preferences 模式，`init(ctx)` / `injectPreferencesForTest` / `add(r)` / `list()`（newest-first 深拷贝）/ `flushNow()` + 单例 `getRedemptionHistoryStore()`。
  - 改 `services/WishlistStore.ets`：新增 `markConfirmed(wishId, nowMs): boolean`（仅置 state=Confirmed + confirmedAt，不碰 CoinAccount），旧 `request` / `confirmByParent` 标 `@deprecated` 留一个版本；`coerceState` 把 `'pending'` 归一为 `Idle`。
- **组件**：
  - 新增 `components/ParentPinDialog.ets`：`@CustomDialog` + 纯函数 `validatePin / pushDigit / popDigit` + `PIN_LENGTH=6`；输入完整 6 位自动校验，错则抖 -8 / +8 / 0 三段动画。
  - `components/GiftBox.ets` **0 行改动**——既有 trigger-driven 行为已能匹配 modal 时间轴，外层 modal 通过额外 `setTimeout` 控制 1.5s hold。
  - `components/ParentLongPressGate.ets` 文件保留、wishlist 不再使用。
- **页面**：
  - 重写 `pages/WishlistPage.ets`：卡片版式右移、头部 📜、PIN dialog 接入、顶层 Stack GiftBox modal、`onBackPress` 守卫。
  - 新增 `pages/RedemptionHistoryPage.ets` + 路由注册。
  - 新增 `pages/ParentPinSetupPage.ets`（两步一致才落盘）+ 路由注册。
  - 改 `pages/ConfigPage.ets`：在 categoryRow 之后插入「家长密码」入口行，已设态显示 `修改 (•••••• 已设置)`，未设态显示 `设置`。
- **测试**：
  - 单测：`LocalUnit.test.ets` 追加 GameConfig.parentPin / formatLocalTimestamp 用例；新增 `RedemptionHistoryStore.test.ets`（add / list / cap50 / persist / singleton）、`ParentPinDialog.test.ets`（validatePin / pushDigit / popDigit）；改 `WishlistStore.test.ets` 删旧链测加 markConfirmed + 'pending'→Idle 迁移。
  - UI 测：新增 `WishlistFlow.ui.test.ets`（5 case：未设 PIN 提示、输错抖动、输对 → GiftBox → 历史 +1、历史页时间格式、头部按钮往返）；改/新 `ConfigFlow.ui.test.ets`（2 case：PIN 入口跳转、两步一致落盘）。

### 9.2 验收标准建议

- **PIN 配置**：⚙ → 家长密码 → 设 6 位 → 返回 → ConfigParentPinButton 文字含 `修改`；二次进入 wishlist 申请兑换不再弹"未设置"提示。
- **PIN 校验**：输错的 PIN 触发圆点行抖动（-8 / +8 / 0 vp）+ 清空 + 红字「密码不正确，请重试」可见；连续输错可重试，无锁定。
- **兑换 + GiftBox**：输对 PIN 后，遮罩出现，期间点 `← 返回` / 点其他 wish 卡片 / 点 📜 按钮均无效；3.18s 后遮罩消失，卡片右槽出现「已兑换 ✓」1.5s 后自动消失，coin balance 已减；按系统返回键在 modal 期间无效。
- **历史记录**：成功一次后进 📜 看到 1 条记录，emoji + 名字 + 时间戳格式 `^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$` + `-N ✨` 红字；连续兑换 51 条后历史页只有 50 条，最早一条被丢；空态文案「还没有兑换记录」。
- **数据迁移**：用 V0.3.8 时代生成的 wishlist preferences（含 `state='pending'`）冷启 V0.3.9，旧 Pending 自动归一为 Idle，arch/coin/UI 都正常。
- **回归 0**：现有 11+ 个 UI 套件 + 所有 ArkTS 单测 + codelinter 全部 pass。

### 9.3 V0.3.9 明确不做

- 不做 PIN 加密 / 哈希落盘，PIN 是明文 plaintext（v0.6 上云再加密）；不做 PIN 找回、不做生物识别、不接系统密码 keystore。
- 不做 PIN 错误次数统计 + 锁定（家长 app 的孩子不会暴力破解，记账成本不值）。
- 不做兑换记录的搜索 / 筛选 / 编辑 / 删除 / 撤回（历史只读，cap 50 滚动）；不做导出 CSV / 同步家长后台。
- 不在 GiftBox 期间播音效（v0.4 audio-bus 整合后再说）；不让 GiftBox 期间允许返回手势。
- 不做多家长账号、不做家长 PIN 与孩子 PIN 分离。
- 不重构 `MagicWish` 模型、不动 `WishlistCatalog` 默认 7 条 wish 内容；不引入「自定义愿望」UI（v0.4 候选）。

## 10. V0.3.10 App 图标与按钮图标重构

V0.3.10 把 v0.3.9 之前的「emoji 字符 + 模板蓝色 launcher PNG」视觉拼贴整体替换成自家美术：用 Recraft V4 vector 生成 8 个统一风格的 SVG，覆盖 app 启动图标（前景 + 背景 + startIcon）和 5 个 emoji 按钮（HomePage 工具栏 4 个 + WishlistPage 头部 1 个），让全 app 视觉从「系统 emoji 拼贴」升级为「自家 SVG 资产」，同时保持现有 7 boss SVG 的同源调性（暖色羊皮纸、平面着色、童话不恐怖）。

视觉风格关键词「童话魔法羊皮纸」：暖色羊皮纸调色板（红 `#E63946` / 金 `#FFB400` / 墨 `#1D3557` / 米 `#FFF8E7` / 粉 `#FCEAEA`），平面着色 + 柔光高光，单一可读剪影，56dp 尺寸下仍清楚识别，与 v0.3.8 的 7 boss SVG（witch / phoenix / unicorn / kraken / pumpkin-king / snow-queen / imp-king）共享同一 Recraft prompt 家族。

### 10.1 范围

- **新增 8 个 SVG 资产**（Recraft V4 vector 生成 → 落 `generated/recraft/icons/<name>.svg`）：
  - `foreground.svg`（1024×1024 前景：magician 童话角色 + 发光魔法书 + 飘出 ABC 字母）
  - `background.svg`（1024×1024 背景：紫粉金渐变魔法夜空 + 散落金色五角星 + 弯月）
  - `startIcon.svg`（216×216 splash：尖帽 + 顶端大金星，简化版）
  - `review.svg` / `codex.svg` / `wand.svg` / `gear.svg` / `scroll.svg`（5 个 in-app icon，1:1）
- **launcher PNG 光栅化**：用 librsvg `rsvg-convert` 把前 3 个 SVG 转成 PNG 输出到 `entry/src/main/resources/base/media/{foreground,background,startIcon}.png`（现有 layered_image.json 不动）。
- **rawfile SVG 同步**：5 个 in-app SVG 复制到 `entry/src/main/resources/rawfile/icons/`，由 ArkUI 内置 SVG renderer 在 `Image($rawfile('icons/<name>.svg'))` 中直接渲染。
- **生成 / 转换工具链**（新增 3 个脚本）：
  - `tools/recraft/generate-icons.sh`：mirror `generate-bosses.sh` 模式（alarm 240s + skip-if-exists + summary），批量生成 8 个 SVG。
  - `tools/recraft/svg-to-png.mjs`：薄包装 `rsvg-convert`，CLI 接受 `--in / --out / --size`。
  - `tools/recraft/icons-to-launcher.sh`：3-line 入口，把 foreground / background / startIcon 一次性转 PNG 落到 base/media。
- **页面集成**（5 个 emoji Button 容器化）：
  - `HomePage.ets`：4 个 toolbar 按钮（HomeReviewButton / HomeCodexButton / HomeWishlistButton / HomeConfigButton）由 `Button('emoji')` 改为 `Button() { Image($rawfile('icons/<name>.svg')) }`，id / size / backgroundColor / onClick 全保留；review-lock 时 `opacity(0.4)` 替代原 fontColor 灰化。
  - `WishlistPage.ets`：`WishlistHistoryButton` 同模板转换，多加 `borderRadius(8)` 显式补回原 default Button 的圆角。
- **UI 测试更新**：`HomeToolbar.ui.test.ets` / `WishlistFlow.ui.test.ets` 中所有 `assertText('📚'|'📖'|'🪄'|'⚙'|'📜')` 改成 by-id 断言（`Component.id('HomeReviewButton')` 等），契约不变。

### 10.2 验收标准建议

- **App 启动图标**：手机/平板桌面看到新 launcher（紫粉金渐变夜空 + magician 前景），不再是纯蓝色块；冷启 splash 显示尖帽 + 金星 startIcon，不再是 4 方块占位。
- **HomePage 工具栏**：右上角 4 个圆形按钮显示自家 SVG 图标（review / codex / wand / gear），不再显示系统 emoji；按钮直径仍 56dp，背景色 / 圆形 / 点击 ripple 不变；review 按钮 lock 时图标变淡（opacity 0.4），点击仍弹 HomeReviewLockedToast。
- **WishlistPage 头部**：📜 history 按钮显示 scroll.svg；点击仍跳转 RedemptionHistoryPage；其它 header 元素（← 返回 / 我的魔法币 ✨）不变。
- **生成可复现性**：再次执行 `bash tools/recraft/generate-icons.sh` 时，已存在且 > 5KB 的 SVG 直接 skip；删除后能从同一 prompt 重新生成（不强制要求像素完全一致，只要风格 / 主题正确即可）。
- **回归 0**：现有 ArkTS 单测全过、现有 UI 套件（除被显式修订的 HomeToolbar / WishlistFlow 两个）全过；codelinter 0 新增 issue；hvigorw assembleHap 成功；hap install 后启动 → 进 HomePage / 战斗 / WishlistPage / RedemptionHistoryPage / MonsterCodexPage / ConfigPage 全部不崩。

### 10.3 V0.3.10 明确不做

- 不做深色主题图标变体（`resources/dark/media/...`）：launcher 背景已偏暗紫，深色桌面下也够清晰，需要分变体留 v0.3.11+。
- 不做密度限定目录的多 PNG 副本（`sdpi/mdpi/ldpi/xldpi`）：HarmonyOS 自适应足够；如未来发现高 DPI 设备模糊再补。
- 不重做 Codex 翻页箭头 `←⬅➡` / ResultPage 星星 `★☆` / ConfigPage 铅笔 `✎` / WishlistCatalog 物品 emoji `📱⌚🎁`：这些字符目前阅读性已 OK，留 v0.3.11+ 视觉清单时再说。
- 不碰战斗页（BattlePage）任何 SVG / 图像：战斗美术化是 v0.8 Cocos2D 重构范围。
- 不改 `layered_image.json` / `module.json5` / `app.json5`：资产替换走文件名，不动 manifest。
- 不做启动 splash 动画 / Lottie / 视频开屏：startIcon.png 静态即可。
- 不引入账号 / 服务端 / 云同步 / 远程图标包：所有美术资产随客户端一起发布。

## 11. V0.4 深度学习与拼写版

V0.4 的目标是把 V0.3 的学习内核做深，重点从“点选识别”进入“主动回忆和拼写”。它不是单一发布，而是按子版本顺序推进的一组能力（V0.4.1 → V0.4.7）。

子版本概览：

| 子版本 | 主题 | 状态 |
| --- | --- | --- |
| V0.4.1 | 完整拼写题（Boss 限定） | 已完成 |
| V0.4.2 | 多空补字母升级（3+ 空 / 撤销 / 错误反馈） | 已并入 V0.4.1（点选式 Spell 已覆盖此难度曲线） |
| V0.4.3 | 精细记忆状态（连续正/错次数 + 掌握度） | 已完成 |
| V0.4.4 | 每日学习计划页 | 已完成 |
| V0.4.5 | 本地学习报告 | 已完成 |
| V0.4.6 | 更多主题区域 | 计划中 |
| V0.4.7 | 自定义愿望单条目 | 计划中 |

V0.4 可以开始考虑远程词包 JSON，但不要求完整后台。若服务端尚未开始，客户端仍应保持本地可用。

### 11.1 V0.4.1 完整拼写题（Boss 限定）

V0.4.1 把 V0.3 在「主动回忆」上的进展再推一格：Boss 关卡从「双空选择 FillLetterMedium」升级为「完整点选拼写 Spell」。整个题型与既有的 Choice / FillLetter / FillLetterMedium 并列，不替换任何已有题型。

**范围**

- 新增 `QuestionKind.Spell` 与 3 个字段（`spellLetters` / `spellRevealedMask` / `spellPool`），并实现 `Question.isValidSpell()` 校验：
  - 字母数 ∈ [4, 9]
  - mask 仅首位为 true
  - `spellLetters.join('')` 等于 `answer.toLowerCase()` 的 a-z 投影
  - `spellPool` 是 `spellLetters[1..]` 的多重集
- 新增 `SpellGenerator` 服务：从 `WordEntry.word` 抽 a-z 字母，套 4-9 长度门，剩余字母按注入的 `RandomFn` 打乱成池；4-字母词与 9-字母词都接受，3 / 10+ 字母词返回 `undefined` 由路由回退。
- 拆分 `PlanQuestionSource` 中原本共用的 Elite/Boss 分支，Boss 单独回退链 `Spell → FillLetterMedium → FillLetter → Choice`，Elite 仍保持 `FillLetterMedium → FillLetter → Choice`。
- 新增 `SpellingArea` 组件：上排 slot row 渲染字母槽，下排 pool row 渲染按生成器顺序排列的字母按钮；首字母槽预亮显示，错点字母按钮闪红 ~220ms（不扣血、不消耗），点对则字母进入下一个空槽并把对应池按钮置灰。最后一个字母落入槽后等待 200ms 揭示反馈，再回调 `onSpellComplete(answer)`。
- `BattlePage` 在 `currentQuestionKind === Spell` 时挂载 `SpellingArea`，隐藏底部 3 个 ChoiceButton；`handleSpellSubmit` 复用 onOptionTap 的 correct / 暴击分支（Spell 不会 wrong，由 SpellingArea 在客户端拒绝错点）。
- `BattleEngine.submitAnswer` 增加 `isSpell` 分支，把 `[q.answer]` 视为唯一合法 option。

**验收**

- 单元测试：`Question.isValid (Spell)`、`SpellGenerator`、`PlanQuestionSource`（Boss + 4 / 5 / 6 字母词都走 Spell；3 字母回退 FillLetter；2 字母回退 Choice；10+ 字母回退 FillLetterMedium；Elite 永不走 Spell）。
- UI 测试：`SpellQuestionFlow` 在真机/模拟器走完一局水果森林冒险，到 Boss 时按字母正确顺序敲完字母池，断言中间每一槽都被填上、最终“正确！/魔法爆发”反馈出现；同样的入口验证错点不会推进字母槽。
- 无设备 + on-device 全套测试通过（28/28），CodeLinter 无新增缺陷。

**明确不做（留给 V0.4.2+）**

- 系统键盘 / 自定义字母键盘：横屏键盘遮挡战斗 UI、儿童误输入成本高，留到后续考虑。
- 「听写模式」：纯听 TTS 后拼写，听力优先。V0.4.1 仍由 prompt 中文释义引导。
- LearningRecorder 增加 Spell-only 字段：写入仍只用 wordId + correct，记忆调度器不区分题型。
- BattleEngine 接受错答的 Spell：错点已经被 SpellingArea 在客户端拦截，引擎层不增加“拼错一半的部分答案”路径。

### 11.2 V0.4.3 精细记忆状态（连续正/错次数 + 掌握度）

V0.4.3 把 V0.3 引入的 `MemoryState` 4 态（New/Learning/Familiar/Mastered，加运行时 Review）做深：之前促升 Familiar/Mastered 用的是 **累计** `correctCount`，对「答对一次马上忘记」的孩子过于宽容；本版本改成「连续答对」驱动，并引入 0-1 的 `mastery` 信任分。

**范围**

- `WordStat` 新增 3 个字段：
  - `consecutiveCorrect`：当前连续答对次数，答错重置 0；
  - `consecutiveWrong`：当前连续答错次数，答对重置 0；
  - `mastery`：0-1 信任分。每次答对 +0.1，每次答错 -0.2（不对称：错答的代价大于对答的奖励），调用 `clampMastery` 钳制到 [0, 1]。
- `LearningRecorder.recordAnswer` 维护上述 3 个字段，并把快照 version 提升到 3。
- `MemoryScheduler` 改用 streak 阈值促升：`Learning → Familiar` 当 `consecutiveCorrect ≥ 2`；`Familiar → Mastered` 当 `consecutiveCorrect ≥ 5`。同时保留兼容回退：当 `consecutiveCorrect = 0` 时（v2 老快照刚迁移完没积累 streak），仍允许用 `correctCount ≥ 4 / ≥ 10` 的旧阈值促升，避免「升级后所有已掌握词回到 Learning」。
- `LearningSnapshot` 兼容性：parseSnapshot 在缺失 streak/mastery 字段时默认 0，并用 `correctCount / seenCount` 回填一个保守 mastery（既不让升级用户回到 0 mastery，也不让没数据的新装包错估）。

**验收**

- 单元测试（`MemoryScheduler.test.ets` / `LocalUnit.test.ets`）：
  - 连续 2 次正确把 Learning 升 Familiar；连续 5 次正确把 Familiar 升 Mastered。
  - `consecutiveCorrect = 1, correctCount = 3` 不晋升（防止「右-错-右-错」假阳性）。
  - `consecutiveCorrect = 0, correctCount = 4` 仍升 Familiar（旧快照兼容）。
  - mastery 在两端正确 clamp（0.95 + 0.1 → 1；0.1 - 0.2 → 0）。
  - v2 blob → v3 解析后 mastery 回填到 `correctCount / seenCount`，streak 默认 0。
  - v3 blob 来回序列化无损；范围外的 mastery（如 2.5）被钳制。
- 全套无设备 + on-device UI 测试通过（28/28），CodeLinter 无新增缺陷。

**明确不做（留给 V0.4.4+）**

- mastery 不影响选词权重，仅作为可观测的内部分数；选词仍由 `nextReviewMs` 调度。本版本只把字段做扎实，权重接入留给 V0.4.4 学习计划页统一改造。
- 不暴露 mastery 到 UI（无进度条 / 不在 ResultPage 显示），后续 V0.4.5 学习报告再可视化。
- 不引入「掌握度过期」（mastery 不会自动衰减），衰减由 `nextReviewMs` 路径承担。

### 11.3 V0.4.4 每日学习计划页

V0.4.4 给 HomePage 加一个「📋」工具栏入口，跳 `TodayPlanPage`：让孩子（和家长）能在战斗外面，看到今天要学的单词集合、它们各自属于哪一类（复习 / 学习中 / 新词），以及哪些已经在今天做对过。

**范围**

- 新增 `TodayPlanService.build(region, repo, recorder, nowMs)`：用 `mulberry32(hashSeed(regionId + localDayKey))` 给 `TodayAdventureBuilder` 注入种子化 RNG，确保同一天同一 region 反复打开页面看到相同的单词清单（实际战斗仍走 `Math.random()`，两个视图都属于「今天的合理投影」，但页面是只读权威读取面）。
- `TodayPlanView` 把 `wordPlan` 按 `WordSource` 拆成三段（review / learning / freshNew），每行带：英文 + 中文释义 + `WordSource` 徽章 + `MemoryState` 徽章 + 「✓ 已完成」标签（基于 V0.4.3 streak 数据派生：`lastAnsweredMs >= localStartOfDay(now) && consecutiveCorrect > 0`）。
- 新增 `pages/TodayPlanPage`：read-only ArkUI 页，顶部返回栏 + 信息卡（`今天的计划：N / M 已完成`）+ 三个分段 `Column`（仅在该段非空时渲染）；空态文案「今天没有可以学习的单词，先去玩一局冒险吧！」。
- HomePage 工具栏新增 `HomePlanButton` 圆形按钮（📋 emoji），位于 `HomeCodexButton` 与 `HomeWishlistButton` 之间。
- `main_pages.json` 注册 `pages/TodayPlanPage` 路由。

**验收**

- 单元测试 `TodayPlanService.test.ets`：`todayPlanSeed` 同 region+day 稳定、跨 day / 跨 region 不同；`localStartOfDay` 在同日内幂等；`describeMemoryState` / `describeWordSource` 5 / 3 个唯一中文标签；`build()` 返回的 `total()` 等于 `MONSTER_PLAN_SLOT_COUNT * WORD_PLAN_MULTIPLIER`；同 NOW 反复构造产生完全一致的 wordIds 序列；分桶仅含对应 source；`doneToday` 在「今天 + consecutiveCorrect > 0」时为真，「昨天」/「最近一次答错」时为假；`doneCount` 跨桶累加正确。
- UI 测试 `TodayPlanFlow.ui.test`：HomePlanButton → TodayPlanPage（可见 `TodayPlanTitle` / `TodayPlanRegionName` / `TodayPlanProgressText`），全新安装至少有一个分段（新词桶为兜底），`TodayPlanBackButton` 返回 HomePage。
- 一并稳定 SpellQuestionFlow（`driveUntilSpell` 在长期 suite 串行后会偶发等不到 Spell 渲染就超 turn budget，本版本通过加 500ms 起步安顿 + 150ms 读插槽前安顿 + turns 上限 30→50 三处微调修复）。
- 全套 31 / 31 on-device UI 测试通过；no-device 单测全过；CodeLinter 无新增缺陷。

**明确不做（留给 V0.4.5+）**

- mastery 进度条 / 学习曲线图：留到 V0.4.5 学习报告统一可视化。
- 在计划页直接进入战斗：保持单一战斗入口（HomePage 「开始今日冒险」），避免在多个入口分流今日完成态。
- 编辑 / 重新洗牌今日计划：本版本是只读视图，编辑能力是 V0.4.7 自定义愿望单条目场景的延伸，不在本版本范围。
- 持久化「完成态」集合：派生自 streak 数据，不引入并行持久层。

### 11.4 V0.4.5 本地学习报告

V0.4.5 把 V0.4.3 累积的记忆数据与 V0.4.4 的「今天」视图合在一个回顾页：让孩子（和家长）能看到「我整体学得怎么样」「今天复习做完了多少」「哪个分类还没拿下」。

**范围**

- 新增 `LearningReportBuilder.build(repo, recorder, nowMs)`：纯函数，遍历 `repo.all()` 发现所有分类（确保空分类也呈现，而不是被静默丢弃），叠加 `WordStat`，输出：
  - `accuracyPct` = round(totalCorrect / totalSeen × 100)
  - 4 态计数（`new` / `learning` / `familiar` / `mastered`）来自 `MemoryScheduler.classify`，与全局选词管线一致
  - `reviewDoneTodayCount`：本日已答对的复习/学习单词数（基于 V0.4.4 「lastAnsweredMs ≥ localStartOfDay && consecutiveCorrect > 0」信号）
  - `reviewCompletionPct` = round(done / max(due, done) × 100)，永远 ≤ 100
  - `weakCategories`：按 `accuracyPct` 升序，跳过 `totalSeen === 0` 的分类，最多 3 条
- 新增 `pages/LearningReportPage`：4 张卡片（accuracy / state pills / review progress / weak）+ 分类详情列表，空数据时给「还没有学习记录」提示。
- 入口：`TodayPlanPage` 顶栏新增 📊 `TodayPlanReportButton`，避免再撑爆 HomePage 工具栏。
- review-bar 的 id 落在外层 `Stack` 上（不是只有动态宽度的内层 `Row`），保证 0% 时仍能被测试 a11y 树发现。

**验收**

- 单元测试 `LearningReportBuilder.test`：零状态、按类聚合、薄弱分类排序、跳过 seen=0、4 态计数、review-completion 在「今天复习过/没复习过」两条路径下表现、accuracy 四舍五入、unseen 不计入正确率分母（共 9 条用例）。
- UI 测试 `LearningReportFlow.ui.test`：HomePlanButton → TodayPlanReportButton → LearningReportPage（assert title + accuracy 在屏顶；swipe 一次后 findComponent 拉到 review-bar + category-section）；back 链：报告 → 今日计划 → HomePage。
- 全套 34 / 34 on-device 测试通过；no-device 单测全过；CodeLinter 无新增缺陷。

**明确不做（留给 V0.5 / 后续）**

- 7 天 / 30 天趋势图：当前没有时间序列持久化，加图前要先有 `LearningHistoryStore`；本版本只做静态快照。
- 题型维度拆分（按 Choice / FillLetter / Spell 看正确率）：孩子从不直接看到题型分布，加进来反而提升认知负担；后续可作为「家长视角」选配。
- 云端同步：留到 V0.6 家长账户与设备绑定版。
- 自定义目标线 / 提醒：本版本是只读回顾，目标设置归属设置/家长能力。

## 12. V0.5 内容后台与 LLM 题库版

V0.5 开始引入 Node.js 服务端。后台优先定位为“内容生产与发布系统”，暂不做账号和设备绑定。

### 7.1 技术方向

- Node.js 实现，优先选择容易部署到 Vercel 的架构。
- 数据库可选 Vercel Postgres、Neon、Supabase 或其他托管 PostgreSQL。
- 后台 API 输出版本化词包 JSON，客户端按版本拉取。
- LLM 调用只发生在服务端，客户端不直接请求 LLM。

### 7.2 后台能力

- 词库管理：单词、中文释义、分类、难度、音标、发音资源、例句字段。
- 题库管理：三选一题、补字母题、未来句子填词模板。
- LLM 生成：根据单词批量生成干扰项、例句、句子填词草稿和简单剧情文案。
- 人工审核：所有 LLM 内容先进入草稿，审核后才能发布。
- 词包发布：生成版本化 JSON，包含版本号、发布时间、适配客户端版本和回滚信息。
- 回滚机制：词包质量有问题时可以回退到上一版。

### 7.3 V0.5 明确不做

- 不做孩子账号。
- 不做家长登录。
- 不做设备二维码绑定。
- 不做学习记录云同步。
- 不让 LLM 内容未经审核直接进入儿童端。

## 13. V0.6 家长账户与设备绑定版

V0.6 的目标是把产品从单设备本地游戏升级为可由家长管理的长期学习工具。

建议能力：

- 家长账号，支持基础登录。
- 孩子档案，支持昵称、年龄、学习阶段和词包选择。
- 设备二维码绑定，客户端展示二维码，家长端扫码绑定设备。
- 学习记录云同步，支持更换设备或多设备查看。
- 家长端学习报告，展示完成天数、掌握词数、错词分类、复习完成率。
- 云端魔法愿望单，家长可配置兑换项、所需魔法币和确认状态。
- 简单通知能力，例如孩子申请兑换后提醒家长确认。

真实零钱或支付宝兑换仍建议保持谨慎。若后续要做，需要单独设计未成年人保护、家长审批、额度上限、支付合规和风控策略。

## 14. V0.7 AI 剧情与语境学习版

V0.7 的目标是让学习从单词识别进入语境理解，并让战斗更有故事感。

建议能力：

- 正式上线句子填词题型。
- 每个主题区域拥有短剧情、关卡目标和 Boss 对话。
- LLM 在服务端生成剧情草稿、例句草稿和主题关卡文案。
- 所有 AI 内容经过审核、过滤和版本发布后进入客户端。
- 根据孩子掌握情况生成个性化冒险推荐，例如“今天去复习学校词汇”。
- Boss 战可以组合三选一、补字母、完整拼写和句子填词。

AI 的定位应是“辅助内容生产”，而不是让儿童端实时暴露在不可控生成内容前。

## 15. V0.8 Cocos2D 战斗美术化重构版

V0.8 的目标是在玩法和业务功能打磨稳定后，把战斗场景从 ArkUI 元素拼装升级为更完整的 2D 游戏表现层。ArkUI 继续承担应用外壳和业务页面，Cocos Creator / Cocos2D 负责战斗场景、角色、怪物、动画、特效和美术主题。

推荐架构边界：

```text
HarmonyOS ArkUI App
  - 首页
  - 今日冒险入口
  - 配置页
  - 词库与奖励页面
  - 家长功能与学习报告
  - 学习记录、奖励、服务端同步

Cocos2D Battle Scene
  - 角色与怪物表现
  - 战斗背景与场景层次
  - 攻击动画、受击动画、粒子特效
  - 题目展示与战斗内交互
  - Boss 表现和主题美术
```

关键原则：

- **Cocos 负责表现和输入**：角色、怪物、背景、技能、动画、粒子、战斗内按钮和点击反馈。
- **学习逻辑留在核心层**：题目生成、答题判定、遗忘曲线、学习记录、奖励结算和服务端同步不写死在 Cocos 场景脚本里。
- **ArkUI 保持产品外壳**：首页、配置、愿望单、家长绑定、学习报告等仍然用 ArkUI 实现。
- **数据接口先行**：在 V0.3-V0.7 中逐步形成可序列化的 `BattleSession`、`Question`、`AnswerOutcome`、`SessionResult` 等边界对象。
- **美术资源规范化**：提前规划角色序列帧或 Spine、怪物图集、背景分层、特效图集、UI 皮肤和主题资源目录。

V0.8 建议能力：

- 用 Cocos Creator 3.x 和 TypeScript 实现战斗场景。
- 支持多个美术主题，例如水果森林、学校城堡、家庭小屋。
- 支持角色待机、施法、受击、胜利、失败动画。
- 支持怪物待机、攻击、受击、死亡和 Boss 登场动画。
- 支持普通攻击、暴击、补字母成功、复习怪、Boss 技能等专属特效。
- 支持移动端性能优化，包括图集、对象池、粒子数量控制和资源预加载。

V0.8 不建议重写全部 App。它是战斗表现层重构，不是产品业务层重构。等 V0.3-V0.7 的题型、学习状态、奖励和后台模型稳定后再做，可以减少跨引擎迁移返工。

## 16. 长期能力地图

长期产品可以分为五个能力域：


| 能力域   | 近期目标            | 长期目标                            |
| ----- | --------------- | ------------------------------- |
| 游戏战斗  | 怪物题型差异、Boss 混合题 | Cocos2D 战斗场景、技能、装备、剧情、地图冒险      |
| 学习系统  | 错词复习、轻量遗忘曲线     | 个性化学习计划、长期掌握度模型                 |
| 内容系统  | 本地词库、远程词包       | 后台 CMS、LLM 题库生成、审核发布            |
| 家长系统  | 本地愿望单           | 家长账号、设备绑定、学习报告、云端兑换             |
| AI 能力 | 后台生成题目草稿        | 剧情生成、例句生成、个性化关卡推荐               |
| 美术表现  | ArkUI 战斗原型      | Cocos2D 场景、角色动画、怪物图集、粒子特效、多主题皮肤 |


## 17. 开发优先级建议

短期优先级建议如下：

1. **先做 V0.3 题型与怪物差异**：这是孩子最容易感知的升级。
2. **再做轻量遗忘曲线**：让游戏开始承担真实复习价值。
3. **接着做魔法愿望单**：为持续动机和后续家长端打基础。
4. **整理 V0.3 验收与测试**：确保补字母、出题、奖励和复习不会破坏现有战斗。
5. **V0.3 稳定后做 V0.3.5 补完**：先把另两个主题区域和中级补字母题加上，让今日冒险的区域切换和拼写挑战完整起来。
6. **V0.3.5 之后再启动服务端**：避免客户端模型未稳定时过早设计后台字段。
7. **玩法和业务稳定后再启动 Cocos2D 重构**：先保留 ArkUI 战斗原型，等战斗规则、题型和学习数据边界稳定后再迁移表现层。

推荐近期第一批实施计划围绕 V0.3，不要同时启动 Node.js 后台。后台等客户端题型、词状态和奖励模型跑通后再做，字段会更稳定。

## 18. 验收标准建议

V0.3 完成时建议满足：

- 孩子可以从首页进入“今日冒险”并完成一局主题战斗。
- 一局中至少出现三选一和选择缺失字母两类题。
- 不同怪物能体现不同题型或学习行为。
- 错词或待复习词在今日冒险中有更高出现概率。
- 结算页能展示星星、魔法币、本局新学词和复习词。
- 魔法币能本地累计，并受每日上限约束。
- 魔法愿望单能展示兑换项、申请兑换和本地家长确认状态。
- 当前离线游戏能力不依赖服务端。
- 原有三选一战斗、音效、TTS、复习模式不发生明显回归。

## 19. 关键风险


| 风险         | 影响          | 应对                             |
| ---------- | ----------- | ------------------------------ |
| V0.3 范围过大  | 开发周期失控      | 严格不做服务端、账号、真实支付和完整地图           |
| 补字母题过难     | 孩子挫败        | V0.3 只做点选缺失字母，不做键盘输入           |
| 奖励变成刷分     | 学习目标偏移      | 设置每日魔法币上限和首次完成奖励               |
| 遗忘曲线过复杂    | 难以解释和测试     | 先做轻量状态机，不上复杂算法                 |
| LLM 内容不可控  | 儿童内容安全风险    | LLM 只在服务端生成草稿，必须人工审核发布         |
| 后台过早进入     | 客户端模型反复变化   | V0.5 再做内容后台，V0.6 再做账号绑定        |
| Cocos 迁移过早 | 玩法未定导致表现层返工 | V0.8 再做战斗美术化重构，V0.3 起保持逻辑与表现分离 |


## 20. 近期建议结论

下一步最适合进入的开发主题是：

```text
V0.3 趣味学习内核版
```

优先实施顺序建议为：

```text
题型抽象
  -> 补字母题
  -> 怪物类型与今日冒险
  -> 轻量遗忘曲线
  -> 本地魔法币与愿望单
  -> 结算页与测试完善
```

这条路线能让游戏更完整，也为未来 Node.js 后台、LLM 题库、家长账号、二维码绑定和 AI 剧情留下稳定演进空间。