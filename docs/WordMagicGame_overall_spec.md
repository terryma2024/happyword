# WordMagicGame 产品与架构设计规格

> 文档状态：当前版本基线（V0.5.8 家长管理后台改版）
> 适用版本：V0.1 原型 → V0.5.8 家长管理后台
> 客户端目标平台：HarmonyOS NEXT，ArkTS / ArkUI，DevEco Studio 托管工程
> 服务端：Python 3.11，FastAPI + Beanie(MongoDB)，部署在 Vercel Serverless
> 详细演进时间线见 [`WordMagicGame_roadmap.md`](WordMagicGame_roadmap.md)；本文记录"现在跑的代码长什么样"。

---

## 1. 产品定位

WordMagicGame（中文暂定名"小魔法师单词冒险"）是面向 8 岁左右儿童的英语单词学习小游戏。产品通过"魔法师对战怪物"的轻量战斗 + "今日冒险"每日剧情 + "魔法币兑换愿望单"的成长闭环，把单词练习包装成短时冒险体验：单局 3–5 分钟即可完成，正向反馈密度高，并保留家长侧的内容/账户/数据掌控点。

经过 V0.1 → V0.5 的迭代，产品已经从一个本地原型演进为：

- 设备端：完整闭环的 HarmonyOS 应用，含战斗、复习、每日冒险、愿望单、家长 PIN、本地学习报告。
- 服务端：FastAPI 应用（部署在 Vercel），管理词库 / 词包 / 类目 / 兑换池 / 家长账户 / OpenAI 辅助内容生成。
- 协同：客户端按用户主动操作从服务端拉最新词包到本地缓存，下次冷启动从缓存重建本地仓库。

---

## 2. 用户与场景

### 2.1 角色

- **儿童玩家**：8 岁左右，正在打基础英语词汇。
- **家长**：通过 6 位家长 PIN 解锁兑换、添加 / 删除自定义愿望、进入"家长管理后台"（V0.5.8 起改名，原"管理员控制台"）拍照导入课本单词 / 复核 LLM 提取结果 / 一键发布词包、设置 / 修改 PIN。
- **内容运营 / 开发者**：通过服务端 Admin Console 管理单词、生成插画与音频、发布词包、查看统计。

### 2.2 使用场景

- 平板横屏短时学习（华为 MatePad Air 为首要体验设备）。
- 手机横屏补充练习（Mate 60 Pro 等）。
- 离线优先：所有"必须在线"的功能都靠本地缓存兜底；冷启动从本地词包加载，不需要网络。
- 半在线：家长在 ConfigPage "词库同步" 行主动点击"同步词包"才会拉服务端最新词包。

### 2.3 成功标准

- 儿童 5 分钟内独立完成一局今日冒险。
- 答对/答错反馈即时、动效与音效区分明显。
- 家长能在不打扰孩子的情况下管理 PIN、愿望单、词库。
- 服务端发布新词包后，孩子下次入主页能看到新区域 / 新词，全程不需要重装应用。

---

## 3. 版本演进概览

下表是已落地的主线版本。详细子版本（V0.3.5–V0.3.10、V0.4.x、V0.5.x）参见 [`WordMagicGame_roadmap.md`](WordMagicGame_roadmap.md)。

| 版本   | 主题                | 关键交付                                                                                                |
| ---- | ----------------- | --------------------------------------------------------------------------------------------------- |
| V0.1 | 原型基线              | HomePage / BattlePage / ResultPage 闭环；30 词本地 JSON；三选一 MCQ；连击双倍伤害。                                   |
| V0.2 | 学习体验增强            | `AudioService` / `PronunciationService` / `LearningRecorder` / `WrongAnswerStore`；暴击视听五层；错题复习模式。     |
| V0.3 | 内容与关卡             | "今日冒险" `TodaySessionPlan`；Wishlist + `CoinAccount`；区域选择器；怪物图鉴；Spell / FillLetter 题型；家长 PIN 兑换闸。     |
| V0.4 | 复习与成长             | 自定义 PIN 设置页；自定义愿望（家长添加 / 删除）；今日学习计划与本地学习报告；五区主题（含 Animal Safari / Ocean Realm）；V0.3.10 暖羊皮纸图标整套。 |
| V0.5 | 服务端化              | FastAPI 服务端 + Beanie/MongoDB；JWT 管理员账户；schema 版本化的词包发布；客户端手动同步 + 本地缓存；OpenAI 课本扫描 / 例句 / 干扰项辅助。     |
| V0.5 follow-up      | 客户端化 V0.5 + 体验细节修复 | 设备端 Admin Console；ConfigPage 同步入口；HomePage 区域故事用服务端 categories 覆写；魔法币改为 1 ⭐ = 1 币；工具栏图标光栅化；UI 自动化补全。  |
| V0.5.8（当前）         | 家长管理后台改版         | "管理员控制台"重命名为"家长管理后台"；进入即锁定竖屏；移除用户名 / 密码登录闸（V0.6 改为家长账户隔离）；以"拍照 / 从相册"上传课本图替代手填发布流，照片走 OpenAI vision 提单词草稿，家长复核后才入库；新增独立 `LessonDraftReviewPage` 复核页。 |

---

## 4. 游戏规则

### 4.1 战斗参数（默认 / 可配置上下界）

| 项目        | 默认                           | 可配范围 / 备注                                          |
| --------- | ---------------------------- | -------------------------------------------------- |
| 玩家 HP     | 5                            | 1 – 10（ConfigPage 步进）                              |
| 怪物 HP     | 3                            | 1 – 10                                             |
| 单局怪物数     | 5                            | 1 – 10                                             |
| 单局倒计时     | 300 s                        | 来自 `TIMER_CHOICES = [3, 15, 30, 60, 120, 300, 600]` |
| 每次正确伤害    | 1                            | 固定                                                 |
| 连击奖励      | 连续答对 3 题 → 当次伤害 2，触发"魔法爆发"反馈 | 固定；暴击视听见 §4.4                                      |
| 失败条件      | 玩家 HP = 0 或倒计时归零             | 任一即结束                                              |
| 胜利条件      | 怪物全数被击败                      |                                                    |
| 选项数量（MCQ） | 3                            | `QuestionGenerator.MIN_REPO_SIZE = 3`              |

> 默认值与 `entry/src/main/ets/models/GameConfig.ets`、`BattleEngine.ets` 中的常量保持一致，单测 `defaultsMatchEngineDefaults` 守住一致性。

### 4.2 答题循环

1. BattlePage `aboutToAppear` 根据 `GameConfig.mode` / `TodaySessionPlan` 构造对应的 `IQuestionSource`。
2. `BattleEngine.start()` 创建初始 `BattleState` 并产出第一题。
3. UI 渲染中文提示、题型对应控件（MCQ / FillLetter / Spell）、双方 HP、当前怪序号、剩余时间。
4. 用户提交答案 → `BattleEngine.submitAnswer(option)` 返回 `AnswerOutcome`：
   - 正确：`comboCount += 1`；当次伤害 = `comboTriggered ? 2 : 1`；扣怪 HP；记录学习数据。
   - 错误：`comboCount = 0`，玩家 HP -1，短暂显示正确答案。
5. 怪物 HP = 0 时 `defeatedMonsters += 1`，未达 `monstersTotal` 则推下一只。
6. 任一终止条件成立时 `engine.buildSessionResult()` → `BattlePage.navigateToResult()` → `replaceUrl('pages/ResultPage')`。

### 4.3 题型矩阵

| 题型枚举                      | 何时出现                  | 控件                                              |
| ------------------------- | --------------------- | ----------------------------------------------- |
| `Choice`                  | 普通槽 / 复习槽 / 兜底        | 三个 `ChoiceButton`                               |
| `FillLetter`              | Spelling 槽位（缺 1 个字母）  | 字母模板 + 三个字母 `ChoiceButton`                      |
| `FillLetterMedium`        | Elite 槽位（缺 2 个字母，两步）  | 字母模板 + 三个字母 `ChoiceButton`，分两步                  |
| `Spell`                   | Boss 槽位               | `SpellingArea`：从打乱字母池里按序点齐                      |

`PlanQuestionSource` 决定每个怪槽位优先尝试哪种题型，词库不够时降级到下一档。

### 4.4 暴击视听五层（`AnswerOutcome.comboTriggered === true`）

1. **全屏金色闪光** `CritGoldFlash` (`#FFB400`，opacity 0 → 0.55 → 0，~450 ms)。
2. **巨型浮动伤害数字** `CritDamageNumber` 72 vp，`-${damage}!`，translateY + opacity + scale，~700 ms。
3. **怪物 zoomPulse** 220 ms ease-out × 1.12 → 持续 120 ms → 160 ms 复位。
4. **独立爆发音效** `AudioService.play('hit_crit')`；普通命中走 `hit_normal`。
5. **加长玩家施法动画** `castPulse` 500 ms 旋转 + 缩放 + 金色光环（普通仅 120 ms `nudgePulse`）。

`FEEDBACK_MS = 650 ms` 同时控制反馈窗口；五层动效都在该窗口内完成。

### 4.5 星级奖励

`BattleEngine.computeStars()`：

| 星级 | 条件                       |
| -- | ------------------------ |
| 3 ⭐ | 胜利且正确率 ≥ 80%             |
| 2 ⭐ | 胜利（正确率 < 80%）或击破 ≥ 3 只怪 |
| 1 ⭐ | 击破 ≥ 1 只怪                |
| 0 ⭐ | 上述都不满足                   |

### 4.6 魔法币（V0.5 follow-up 起：1 星 = 1 币）

仅 **今日冒险** 模式产生魔法币（其他模式只有星星反馈）：

```
coinsEarned = result.stars   // 0..3
```

- 当日首次完成今日冒险 + 胜利：通过 `COIN_REASON_TODAY_FIRST` 计入，触发 HomePage "已完成"徽章；即使 `DAILY_CAP` 截到 0 币，徽章仍翻起。
- 其他完成（重玩 / 失败但有击破）：通过 `'stars'` 这个 txn reason 计入。
- `DAILY_CAP = 20`，单局上限 3 币，理论上单日打满需要 7 局以上，正常使用不会触顶。

---

## 5. 内容设计

### 5.1 词库来源

按优先级：

1. **远端词包缓存**（`WordPackCache.read()`）— 用户在 ConfigPage 主动同步过且未失效。
2. **设备端 rawfile** `entry/src/main/resources/rawfile/data/words_v1.json` — 兜底，App 安装后即可用。
3. **自定义词** — `GameConfig.customWordsRaw`，按 `中文:英文` / `中文：英文` 解析（支持半角/全角冒号），仅在用户勾选 `custom` 类目时拼入战斗池。

战斗池由 `computeFinalPool(allBuiltin, enabledCategories, customWordsRaw)` 在 BattlePage 启动时计算。

### 5.2 词条字段

```ts
class WordEntry {
  id: string = '';
  word: string = '';
  meaningZh: string = '';
  category: string = '';
  difficulty: number = 1;
  image?: string;
  audio?: string;
  // V0.5 服务端拓展
  distractors?: string[];        // 服务端 LLM 预生成的同类干扰项
  example?: ExampleSentence;     // { en, zh }
  illustrationUrl?: string;      // 服务端 Blob URL
  audioUrl?: string;             // 服务端 Blob URL
}
```

### 5.3 类目（Categories）

| Category id | 中文标签（默认）| 关联区域 |
| ----------- | ----------- | -------- |
| `fruit`     | 水果         | Fruit Forest |
| `place`     | 日常地点     | School Castle |
| `home`      | 家居物品     | Home Cottage |
| `animal`    | 动物         | Animal Safari |
| `ocean`     | 海洋         | Ocean Realm |
| `custom`    | 自定义       | （仅 free-play 战斗池） |

服务端发布的词包若 `schema_version >= 4` 会带 `categories[]`，包含 `id / label_en / label_zh / story_zh / source_image_url`。客户端 `CategoryCatalog` 用作覆写：HomePage 的区域副标题与故事文本优先取服务端值，否则回退到设备端 `AdventureCatalog`。

### 5.4 题目生成原则

- 正确答案来自当前题目的 `word`。
- 提示用 `meaningZh`（中文释义）。
- 干扰项策略：服务端 `distractors` 字段 > 同类目同难度同步随机 > 全局兜底；同题三个选项不重复且包含答案。
- 不连续两题命中同一正确单词（`QuestionGenerator` 维护 `lastAnswerWordId`）。
- 词库不足以生成 3 个独特选项时，降级到全局补足而不是抛错。

---

## 6. 信息架构

### 6.1 路由表

`entry/src/main/resources/base/profile/main_pages.json` 注册了 12 个页面（顺序）：

```
pages/HomePage              入口
pages/BattlePage            战斗
pages/ResultPage            结算
pages/ConfigPage            设置
pages/CustomWordsPage       自定义词列表编辑
pages/WishlistPage          愿望单
pages/MonsterCodexPage      怪物图鉴
pages/ParentPinSetupPage    家长 PIN 设置 / 修改
pages/RedemptionHistoryPage 兑换历史
pages/TodayPlanPage         今日学习计划预览
pages/LearningReportPage    学习报告
pages/ParentAdminPage       家长管理后台（V0.5.8 重命名自 AdminConsolePage，去登录闸）
pages/LessonDraftReviewPage V0.5.8 课本图复核页（vision 提取 → 家长复核）
```

### 6.2 页面流

```text
HomePage ─┬─ HomeStartButton ─→ BattlePage(today) ─→ ResultPage ─┬─ HomePage
          │                                                       └─ WishlistPage
          ├─ HomeReviewButton ─→ BattlePage(review) ─→ ResultPage ─→ HomePage / BattlePage
          ├─ HomeCodexButton ─→ MonsterCodexPage
          ├─ HomePlanButton  ─→ TodayPlanPage ─→ LearningReportPage
          ├─ HomeWishlistButton ─→ WishlistPage ─┬─ +添加 / ✕（PIN）─→ AddCustomWishDialog
          │                                       ├─ 申请兑换（PIN）─→ GiftBox 模态
          │                                       └─ 📜 历史 ─→ RedemptionHistoryPage
          └─ HomeConfigButton ─→ ConfigPage ─┬─ 自定义词 ─→ CustomWordsPage
                                              ├─ 家长密码 ─→ ParentPinSetupPage
                                              ├─ 立即同步（HTTP）
                                              └─ 家长管理后台（PIN）─→ ParentAdminPage ─┬─ 📷拍照 / 🖼️从相册 ─→ /lessons/import ─→ LessonDraftReviewPage
                                                                                       ├─ 待复核草稿列表 ─→ LessonDraftReviewPage
                                                                                       └─ 一键发布词包 ─→ /api/v1/admin/packs/publish
```

> V0.5.8 起 ParentAdminPage 进入即锁定竖屏（`window.setPreferredOrientation` PORTRAIT），离开时恢复 AUTO_ROTATION_LANDSCAPE；LessonDraftReviewPage 复用同一竖屏，让 ParentAdminPage 在 back-pop 时统一恢复横屏。

### 6.3 各页职责（高层）

| 页面                  | 主要职责                                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| HomePage            | 主入口；展示金币 / 复习 / 图鉴 / 计划 / 愿望单 / 设置六颗工具栏按钮 + 大尺寸 AdventureCard + 区域 chip 选择器 + HomeStartButton。 |
| BattlePage          | 战斗主舞台。处理三种题型、HP / 倒计时 / 连击 / 暴击视听 / 反馈、动画、音效。                                                  |
| ResultPage          | 单局总结（胜负标题 + 三星 + 击破/正确率/学习词数 + 今日模式专属的 +N ✨ 与累计余额）。                                            |
| ConfigPage          | 战斗参数 + 类目勾选 + 自动发音开关 + 自定义词入口 + 家长 PIN 入口 + 词包同步入口 + 家长管理后台入口；含 ConfigValidationHint 阻止非法保存。 |
| CustomWordsPage     | 单一 TextArea 编辑 `customWordsRaw`，保存校验非空 + 至少一行可解析。                                                |
| WishlistPage        | 愿望卡片列表（默认 + 自定义）；显示余额；申请兑换 / 添加 / 删除均经家长 PIN；兑换成功展示 GiftBox 模态。                                |
| RedemptionHistoryPage | 倒序展示 `RedemptionRecord` 列表，最多 50 条滚动保留。                                                          |
| MonsterCodexPage    | 横向翻页查看 `MONSTER_CODEX` 中所有怪物 / boss 立绘 + 描述。                                                     |
| TodayPlanPage       | 只读预览今日 10 个词的"复习 / 学习中 / 新词"分桶 + 完成进度（每个 wordId 一行）。                                            |
| LearningReportPage  | 全量统计：正确率、已掌握词、新词数、复习词数、薄弱单词分组、按类目正确率分布。                                                       |
| ParentPinSetupPage  | 6 位 PIN 两步一致校验，写回 `GameConfig.parentPin`。                                                        |
| ParentAdminPage     | V0.5.8 家长管理后台（PIN 闸后入）：竖屏概览（用户数 / 词条数 / 类别数 / 已发布版本数 / 最新版本 / 待审 LLM 草稿 / 待审课本图）；📷 拍照 / 🖼️ 从相册导入课本图；待复核草稿列表；一键发布新词包。**已下线 JWT 登录卡片**，V0.6 以家长账户做数据隔离。 |
| LessonDraftReviewPage | V0.5.8 课本单词复核页（PIN 后续传）：展示原图 + 可改主题标签 + 候选词列表（保留 / 编辑 / 弃用），编辑弹窗校验非空 trim，"全部确认"先 PATCH 再 /approve、"全部拒绝" /reject；409 ALREADY_REVIEWED 自动 back。 |

---

## 7. 系统架构（客户端）

### 7.1 架构原则

- 页面只负责渲染 + 路由 + 用户输入；规则全部进 `models/` + `services/`。
- AppStorage 只放跨页临时 handoff（GameConfig、TodaySessionPlan、TodayLastCompletedDayKey、TodayRegionId）。V0.5.8 起 ParentAdminPage 不再写 admin_jwt，待 V0.6 家长账户重新接入。
- 持久化数据全部走 `@ohos.data.preferences`，每个领域一个 namespace（见 §9 表）。
- 网络访问全部经 `RemoteWordPackService` / `ParentApiClient` 两个 facade，UI 不直接调用 `@kit.NetworkKit`。`ParentApiClient`（V0.5.8 重命名自 `AdminApiClient`，去掉 JWT 头）额外暴露 `importLesson(PickedImage)` 走 `multipart/form-data` 上传。
- 主线 UI 路径必须在没有网络、没有缓存、没有家长 PIN 的情况下也能跑（rawfile 兜底）。

### 7.2 目录结构（实际）

```text
entry/src/main/ets/
  pages/                                    12 个页面（见 §6.1）
  components/
    HpBar.ets                               HP 条
    ChoiceButton.ets                        答案按钮，4 态
    CharacterCard.ets                       角色卡 + 4 个脉冲动画入口
    SpellingArea.ets                        Spell 题型字母池
    AddCustomWishDialog.ets                 自定义愿望表单
    ParentPinDialog.ets                     6 位 PIN 输入弹窗
    GiftBox.ets                             兑换成功庆祝动画
    CritOverlay.ets                         暴击金闪 / 浮动伤害 / 施法光环
    MagicProjectile.ets                     法术投射动画
    ParentLongPressGate.ets                 V0.3.9 之前的旧家长长按闸；当前已无引用，仅保留作历史代码
  models/                                   见 §8
  services/                                 见 §10
  data/
    AdventureCatalog.ets                    5 个区域元数据
    MonsterCatalog.ets                      10 个怪物 / boss 元数据
    CharacterAssets.ets                     角色 → svg 路径
entry/src/main/resources/
  rawfile/
    data/words_v1.json                      内置词库
    icons/{review,codex,wishlist,gear,scroll}.png   工具栏 PNG（V0.5 follow-up 替换）
    character/*.svg                         玩家 + 怪物 + 7 个 boss 立绘
    sound/*.ogg, battle_bgm.mp3
  base/profile/main_pages.json              路由
  base/element/*                            字符串 / 颜色资源
```

> `Index.ets`（V0.1 时期的 GiftBox 演示页）已在 V0.5 follow-up 中移除；启动直接进 HomePage。

### 7.3 状态流

```text
ChoiceButton(tap)
  ─→ BattlePage.onAnswer
       ├─ BattleEngine.submitAnswer(option) → AnswerOutcome
       │     └─ 内部更新 BattleState（HP / combo / monsters / answers）
       ├─ AudioService.play('hit_normal'|'hit_crit'|'answer_wrong')
       ├─ CharacterCard.{hurtPulse|nudgePulse|zoomPulse|castPulse}
       └─ LearningRecorder.recordAnswer(wordId, correct)
  ─→ BattleEngine.buildSessionResult()  // 终止条件
       └─ BattlePage.navigateToResult
            ├─ applyTodayAdventureRewards(result, plan)  // today 模式
            │     ├─ result.stars → CoinAccount.earn
            │     └─ AppStorage[todayLastCompletedDayKey] = today
            └─ replaceUrl('pages/ResultPage', { params: result })
```

页面永远不直接改 `playerHp` / `monsterHp` / `comboCount`，所有写入都走 `BattleEngine.submitAnswer` 或 `tick`。

---

## 8. 数据模型

仅列对外/跨页暴露的字段。完整签名见 `entry/src/main/ets/models/`。

### 8.1 核心战斗

```ts
class WordEntry { id; word; meaningZh; category; difficulty;
                  image?; audio?; distractors?; example?; illustrationUrl?; audioUrl? }
class ExampleSentence { en; zh }

enum QuestionKind { Choice, FillLetter, FillLetterMedium, Spell }
class Question {
  promptZh; answer; options[]; wordId; kind;
  // FillLetter / FillLetterMedium
  letterTemplate; missingIndex; letterOptions[]; letterAnswer;
  // Spell
  spellLetters[]; spellRevealedMask[]; spellPool[];
}

enum BattleStatus { Ready, Playing, Won, Lost }
class BattleState {
  playerHp; monsterHp; monsterIndex; monstersTotal;
  comboCount; remainingSeconds;
  totalAnswers; correctAnswers; defeatedMonsters;
  learnedWordIds[]; currentQuestion?; status;
}

class SessionResult {
  status; defeatedMonsters; monstersTotal;
  totalAnswers; correctAnswers; correctRate;
  learnedWordCount; stars;
  newlyLearnedCount; totalLearnedCount;
  // V0.3 today adventure 字段
  isTodayAdventure; regionId; bossName;
  reviewWordCount; newWordCount;
  coinsEarned; coinsTotal; dailyCapHit;
}
```

### 8.2 配置

```ts
class GameConfig {
  playerMaxHp = 5; monsterMaxHp = 3; monstersTotal = 5;
  startingSeconds = 300;
  enabledCategories = ['fruit','place','home'];
  customWordsRaw = '';
  autoSpeak = true;
  mode = 'normal';   // 'normal' | 'review' | 'today'
  parentPin = '';    // 空字符串 = 未配置
}
```

### 8.3 经济与愿望

```ts
class CoinTxn { ts; delta; reason; balanceAfter }
class CoinSnapshot {
  version; totalCoins; spentCoins;
  todayDayKey; todayCoinsEarned; todayAdventureCompleted;
  txns[];
}

enum WishState { Idle, Confirmed }   // V0.3.9 起 Pending 退役
class MagicWish { id; displayName; costCoins; iconEmoji; state;
                  requestedAt; confirmedAt; isCustom }
class WishlistSnapshot { version; wishes[] }

class RedemptionRecord { id; ts; wishId; displayName; iconEmoji; costCoins }
class RedemptionHistorySnapshot { version; records[] }
```

### 8.4 今日冒险

```ts
enum WordSource { Review, Learning, New }
class WordSlot { wordId; source }
class MonsterSlot { kind; catalogIndex }     // kind: 'normal'|'spelling'|'review'|'elite'|'boss'
class MonsterPlan { slots[] }                // 长度恒等于 MONSTER_PLAN_SLOT_COUNT = 5

class AdventureRegion {
  id; displayName;
  themeWordCategories[];          // ['fruit'] / ['place'] / ...
  bgPrimary; bgAccent;            // 主题色
  bossName;
  monsterPlan;                    // 模板：Normal → Spelling → Review → Elite → Boss
  bossCandidates[];               // 1..n 个 boss 元数据
}

class TodaySessionPlan {
  regionId; monsterSlots[];        // 5 个怪槽，最后一个是当日轮换的 boss
  wordPlan[];                      // 10 个词槽（5 怪 × 2）
  bossWordIds[];                   // boss 槽优先消费的两个词 id
  isFirstToday;                    // 当日首次进入战斗
}
```

---

## 9. 持久化布局

### 9.1 `@ohos.data.preferences` 命名空间

| 领域       | 文件名                              | 主键                    | 内容                         |
| -------- | -------------------------------- | --------------------- | -------------------------- |
| 魔法币       | `wordmagic_coins`               | `snapshot_v1`         | `CoinSnapshot` (JSON)      |
| 学习记录     | `wordmagic_learning`            | `snapshot_v1`         | `LearningSnapshot` (JSON)  |
| 愿望单       | `wordmagic_wishlist`            | `snapshot_v1`         | `WishlistSnapshot` (JSON)  |
| 兑换历史     | `wordmagic_redemption_history`  | `snapshot_v1`         | `RedemptionHistorySnapshot` |
| 今日设置     | `today_settings`                | `region_id`           | 选中的区域 id                   |
| 服务端词包缓存  | `word_pack_cache`               | `pack_v2`             | `{ body, etag, schemaVersion, fetchedAt }` |

所有领域写入都用 100 ms 去抖 + fire-and-forget；进入 ResultPage / 退出战斗等关键节点显式 `flushNow()`。

### 9.2 AppStorage（跨页 handoff）

| Key                          | 值                  | 写入方                                | 读取方                               |
| ---------------------------- | ------------------ | ---------------------------------- | --------------------------------- |
| `gameConfig`                 | `GameConfig`       | ConfigPage / ParentPinSetupPage    | HomePage / BattlePage / WishlistPage |
| `todayPlan`                  | `TodaySessionPlan` | HomePage（点击 HomeStartButton）       | BattlePage                        |
| `todayLastCompletedDayKey`   | `YYYY-MM-DD`       | BattlePage（applyTodayAdventureRewards） | HomePage（已完成徽章）              |
| `todayRegionId`              | 区域 id              | HomePage（区域 chip 切换）              | HomePage                          |

---

## 10. 服务模块（客户端）

### 10.1 战斗 / 学习

| 模块                     | 公开 API                                                                                   | 职责                            |
| ---------------------- | ---------------------------------------------------------------------------------------- | ----------------------------- |
| `WordRepository`       | `loadFromRawfile() / setEntries() / size() / all() / byCategory() / findById()`         | 内存词库；泛包 / rawfile / custom 三源同形 |
| `IQuestionSource`      | `nextQuestion()`                                                                         | BattleEngine 喂料口              |
| `QuestionGenerator`    | `nextQuestion() / nextQuestionForWord(wordId)`                                           | 三选一 MCQ                       |
| `FillLetterGenerator`  | `generate() / generateMedium()`                                                          | FillLetter / FillLetterMedium |
| `SpellGenerator`       | `generate()`                                                                             | Boss 拼写题                      |
| `PlanQuestionSource`   | `nextQuestion() / setMonsterIndexProvider(...)`                                          | 把 TodaySessionPlan + 当前怪 kind 映射到题型链 |
| `BattleEngine`         | `start() / submitAnswer() / tick() / getState() / buildSessionResult()`                  | 规则引擎；唯一可改 BattleState 的入口     |
| `AudioService`         | `preload() / play() / dispose()`，`SoundKeys` 枚举                                          | 6 类 SFX + 战斗 BGM              |
| `PronunciationService` | `init() / speak() / dispose()` + 模块级 `shouldAutoSpeak()`                                 | TTS（CoreSpeechKit）            |
| `LearningRecorder`     | `init() / beginSession() / recordAnswer() / flushNow() / newlyLearnedCount / recentWrongIds(n) / totalLearnedCount` | per-word 统计 + 错题集 |
| `WrongAnswerStore`     | `open() / load() / save()`                                                                 | 上一项的持久化适配层             |
| `MemoryScheduler`      | `classify(stat)`                                                                         | 单词 → MemoryState（New/Learning/Review） |

### 10.2 经济 / 愿望

| 模块                       | 公开 API                                                                                                    | 职责                            |
| ------------------------ | --------------------------------------------------------------------------------------------------------- | ----------------------------- |
| `CoinAccount`            | `init() / beginToday() / earn(reason, amount, nowMs) / redeem(wishId, cost) / balance() / snapshot() / flushNow()` | 钱包 + 每日封顶 + txn 日志 |
| `WishlistStore`          | `init() / list() / markConfirmed() / acknowledge() / addCustomWish() / removeCustomWish()`                | 愿望单 CRUD                      |
| `RedemptionHistoryStore` | `init() / list() / add() / loadSnapshotForTest()`                                                          | 兑换历史滚动保留 50 条                 |

### 10.3 今日冒险 / 学习报告

| 模块                       | 公开 API                                                                  | 职责                            |
| ------------------------ | ----------------------------------------------------------------------- | ----------------------------- |
| `TodayPreferences`       | `init() / loadRegionId() / saveRegionId()`                              | 区域 id 持久化                     |
| `TodayAdventureBuilder`  | `build(region, repo, recorder, nowMs, isFirstToday) → TodaySessionPlan` | 主算法见 §11                      |
| `TodayPlanService`       | `build()`                                                               | TodayPlanPage 的只读视图模型         |
| `LearningReportBuilder`  | `build()`                                                               | LearningReportPage 的只读视图模型    |

### 10.4 服务端协同（V0.5）

| 模块                       | 公开 API                                                                                | 职责                                     |
| ------------------------ | ------------------------------------------------------------------------------------- | -------------------------------------- |
| `RemoteWordPackConfig`   | `SERVER_BASE_URL`、`pickServerBaseUrl()`、`latestPackUrl()`                              | 默认 `https://happyword.vercel.app`     |
| `RemoteWordPackService`  | `fetchLatest(url, ifNoneMatch?)`                                                      | HTTP GET + ETag                        |
| `WordPackCache`          | `init() / read() / readRecord() / write() / writeRecord() / touchFetchedAt()`         | 词包本地缓存 + ETag                          |
| `WordPackBootstrapper`   | static `forContext(ctx)` + `bootstrap()`                                              | 冷启动：cache 优先，fallback rawfile，**不发网络** |
| `WordPackSyncService`    | `syncOnce()`                                                                          | ConfigPage 手动同步入口；返回 outcome 枚举 + 拒收最小词数判断 |
| `RemoteAssetCache`       | static `forContext(ctx)` + `resolve(url, kind)`                                       | 远端图片 / 音频的设备端 LRU                      |
| `CategoryCatalog`        | `setRows() / getById() / size()`                                                      | 服务端 categories 覆写                      |
| `ParentApiClient`        | `withRealHttp(baseUrl)` + `getStats() / listPacks() / publishPack(notes?)` + V0.5.8 课本流：`importLesson(PickedImage) / getLessonDraft(id) / patchLessonDraft(id, edited) / approveLessonDraft(id) / rejectLessonDraft(id) / listPendingLessonDrafts(page, size)` | 家长管理后台 HTTP，无 JWT 头（V0.5.8） |
| `LessonImagePicker`      | `pickFromGallery() / pickFromCamera()`                                                | 包装 `picker.PhotoViewPicker` + `cameraPicker.pick`，按扩展名嗅 MIME，返回 `PickedImage` 或 `null`（用户取消 / 不支持类型） |
| `MultipartBuilder`       | `buildSingleImageMultipart(field, filename, mime, bytes)` + `escapeFilename(name)`    | RFC-7578 单图片上传体，逐字符替换 `"` / CR / LF 防头注入 |
| `orientation` 工具         | `lockPortrait(adapter) / restoreAutoLandscape(adapter)`                                | 包 `window.setPreferredOrientation`，给 ParentAdminPage / LessonDraftReviewPage 用 |

---

## 11. 今日冒险算法

### 11.1 Plan 构建

入口：`HomePage.handleStartToday()` → `TodayAdventureBuilder.build(region, repo, recorder, nowMs, isFirstToday)`。

1. `MonsterPlan` 模板从 `region.monsterPlan.slots` 复制，长度恒为 `MONSTER_PLAN_SLOT_COUNT = 5`，模板是 Normal → Spelling → Review → Elite → Boss。
2. **Boss 轮换**：`hashDjb2('${region.id}:${localDayKey(nowMs)}') mod region.bossCandidates.length` → 选定当日 boss → 写回最后一槽的 `catalogIndex`。同区同日总是同一 boss。
3. **Word slot 数**：`MONSTER_PLAN_SLOT_COUNT * WORD_PLAN_MULTIPLIER = 5 × 2 = 10` 个。
4. **Word 分桶**：从 `region.themeWordCategories` 圈词，按 `MemoryScheduler.classify` 分 Review / Learning / New 三桶；目标比例 ≈ **5 复习 / 3 学习中 / 2 新词**，桶不够就轮转后续桶。
5. **Boss words**：`pickBossWords(plan, 2)` 优先取 review + learning 中难度高的，不够则取最难的 new；写入 `plan.bossWordIds`，BattlePage 走到 boss 槽位时 `PlanQuestionSource` 优先吐这两个。
6. **isFirstToday**：HomePage 入战前从 `CoinAccount.todayAdventureCompleted()` 反推。

### 11.2 区域目录

`entry/src/main/ets/data/AdventureCatalog.ets` 中的 5 个区域：

| id              | displayName    | themeWordCategories | bossName       |
| --------------- | -------------- | ------------------- | -------------- |
| `fruit-forest`  | Fruit Forest   | `['fruit']`         | Witch / Phoenix / Pumpkin King 等 |
| `school-castle` | School Castle  | `['place']`         | Imp King 等     |
| `home-cottage`  | Home Cottage   | `['home']`          | Snow Queen 等   |
| `animal-safari` | Animal Safari  | `['animal']`        | Unicorn 等      |
| `ocean-realm`   | Ocean Realm    | `['ocean']`         | Kraken 等       |

> 区域 displayName / story / 主题色由 V0.5.E 起被服务端 `categories[]` 覆写（schema_version ≥ 4 时生效）。

### 11.3 怪物图鉴

`MonsterCatalog` 共 **10** 条 = 3 archetype（Slime / Zombie / Dragon，按难度桶 Normal / Spelling / Review / Elite / Boss-fallback）+ 7 童话 boss（Witch / Phoenix / Unicorn / Kraken / Pumpkin King / Snow Queen / Imp King）。`MonsterEntry` 上有 `assetPath` 字段；`assetPathForEntry()` 优先读 entry 自带路径，空时回退到 `characterAssetForKind(kind)`。

---

## 12. 愿望单与家长 PIN

### 12.1 PIN 流程

- 设置 / 修改：HomePage → ConfigPage → "家长密码" → ParentPinSetupPage → 两步一致 → 写入 `GameConfig.parentPin`（明文，本地家庭设备）。
- 校验：`ParentPinDialog` 自绘 3×4 数字键盘，输错抖动 + 清空，无锁定 / 无次数限制。
- 取消：ConfigPage 的"家长管理后台"按钮（V0.5.8 起改名）、WishlistPage 的"申请兑换 / + 添加 / ✕"都先校验 PIN；PIN 为空时弹"尚未设置家长密码"提示。

### 12.2 兑换流程（`MagicWish.state` 单段链路）

```
Idle ──[家长 PIN 通过]──> Confirmed
       │
       └─ CoinAccount.redeem(wishId, cost) 扣款
       └─ RedemptionHistoryStore.add(record)
       └─ WishlistPage 顶层 Stack 盖 50% 黑底 modal
       └─ GiftBox 动画（~1.68s 展开 + 1.5s hold = 3.18s 阻塞，期间 onBackPress 拦截）
       └─ store.acknowledge(wishId) 把状态归位
```

### 12.3 自定义愿望

- 添加：WishlistPage 头部 "+ 添加" → ParentPinDialog → AddCustomWishDialog（name / cost / emoji 三输入 + Submit / Cancel）。校验规则：
  - name 长度 1–12 字（trim 后）
  - cost 整数 5 – 200
  - emoji 留空则用默认 ⭐，最多 4 字符
- 删除：仅 `isCustom = true` 的愿望卡片右侧出现 ✕；点击 → ParentPinDialog → 系统 AlertDialog 二次确认 → `WishlistStore.removeCustomWish`。

---

## 13. 服务端架构（V0.5）

### 13.1 应用形状

- 语言/框架：Python 3.11 + FastAPI（ASGI），Beanie ODM 跑在 Motor 之上。
- 数据库：MongoDB（生产用 Atlas，单测用 `mongomock-motor`）。
- 部署：Vercel Serverless Python，入口 `server/api/index.py` 重新导出 `app.main:app`，`server/vercel.json` 把所有 path 转发给 `api/index.py`，函数 `maxDuration = 60s`。
- LLM：`openai`（`AsyncOpenAI`），用模型 `openai_model_text` 与 `openai_model_vision`。

### 13.2 文档模型（`init_beanie` 注册顺序）

| Document      | 集合                  | 关键字段                                                          |
| ------------- | -------------------- | ------------------------------------------------------------- |
| `User`        | `users`              | `username` (unique) / `password_hash` / `role` / `last_login_at` |
| `Word`        | `words`              | `id` (string) / `word` / `meaningZh` / `category` / `difficulty` / `distractors?` / `example_sentence_*` / `illustration_url?` / `audio_url?` / `deleted_at?` |
| `WordPack`    | `word_packs`         | `version` (unique idx) / `schema_version` / `words[]` / `categories?` / `published_at` / `published_by` / `notes` |
| `PackPointer` | `pack_pointers`      | 单例 `singleton_key='main'` / `current_version` / `previous_version` |
| `Category`    | `categories`         | `id` / `label_en` / `label_zh` / `story_zh` / `source_image_url` / `source` |
| `LlmDraft`    | `llm_drafts`         | LLM 生成的干扰项 / 例句草稿，需人工 approve 后写入 `Word`                     |
| `LessonImportDraft` | `lesson_drafts`| OpenAI vision 课本扫描批量导入草稿                                      |

### 13.3 路由表

| Router 文件             | Prefix                       | 路由                                                                                  |
| --------------------- | ---------------------------- | ----------------------------------------------------------------------------------- |
| `auth.py`             | `/api/v1/auth`               | `POST /login` / `GET /me`                                                           |
| `public_packs.py`     | `/api/v1`                    | `GET /health` / `GET /packs/latest.json`                                            |
| `admin_words.py`      | `/api/v1/admin/words`        | `GET ""` / `GET /{id}` / `POST ""` / `PUT /{id}` / `DELETE /{id}`                   |
| `admin_assets.py`     | `/api/v1/admin/words`        | `POST /{id}/illustration` + `DELETE` / `POST /{id}/audio` + `DELETE`                |
| `admin_packs.py`      | `/api/v1/admin/packs`        | `GET ""` / `GET /current` / `GET /{version}` / `POST /publish` / `POST /rollback`   |
| `admin_drafts.py`     | `/api/v1/admin`              | `POST /words/{id}/generate-distractors` / `…/generate-example` / `GET /drafts` / `GET /drafts/{id}` / `PATCH /drafts/{id}` / `POST /drafts/{id}/approve` / `POST /drafts/{id}/reject` |
| `admin_categories.py` | `/api/v1/admin/categories`   | `GET ""` / `GET /{id}` / `POST ""` / `PUT /{id}` / `DELETE /{id}`                   |
| `admin_lessons.py`    | `/api/v1/admin`              | `POST /lessons/import`（vision）/ `GET /lesson-drafts` / `GET /lesson-drafts/{id}` / `PATCH /lesson-drafts/{id}` / `POST /lesson-drafts/{id}/approve` / `POST /lesson-drafts/{id}/reject` |
| `admin_llm.py`        | `/api/v1/admin/llm`          | `POST /scan-words`（OpenAI vision 提取课本单词）                                            |
| `admin_stats.py`      | `/api/v1/admin`              | `GET /stats`                                                                        |

> **V0.5.8 起所有 `admin_*` 路由不再要求 JWT bearer**：`Depends(current_admin_user)` 统一移除，家长设备直接调用。代价是单个家庭的设备目前都看到全局数据；V0.6 计划重新引入家长账户做行级隔离。

### 13.4 词包发布（`/api/v1/packs/latest.json`）

公开端点。`pack_service.get_current_pack_payload()`：

1. `PackPointer.singleton('main').current_version` 指向已发布版本 → 返回 `{ version, schema_version, published_at, words[], categories? }`，`ETag = "${version}"`，命中 `If-None-Match` 返回 304。
2. 没有发布过 → 返回 **synthetic** payload `version=0, schema_version=1, words=` 当前 DB 实时 dump，方便客户端冷启动也能跑通。

`schema_version` 由 `derive_schema_version` 推断：

| 值 | 触发条件                                                  |
| - | ----------------------------------------------------- |
| 1 | 仅基础词字段                                                |
| 2 | 任一 word 含 `distractors` / `example`                   |
| 4 | 词包顶层带非空 `categories`                                  |
| 5 | 任一 word 含 `illustrationUrl` / `audioUrl`              |

> 跳过 3 是历史原因。

### 13.5 同步流程（客户端视角）

ConfigPage "词库同步" 行 → "同步词包" 按钮（id `ConfigSyncButton`）：

1. `WordPackSyncService.syncOnce(remote, cache)` 取出本地 `WordPackCacheRecord`。
2. 用 `record.etag` 作为 `If-None-Match` 调 `RemoteWordPackService.fetchLatest(url, etag)`。
3. 翻译为 `SyncStatus` 枚举：
   - **304 Not Modified** → `UpToDate`，`touchFetchedAt`，cache 不动。
   - **200 + body** → 解析后 wordsLength `< MIN_WORDS_PER_PACK (= 3)` → `RejectedTooSmall`；否则 `cache.writeRecord(body, etag, schemaVersion)` 后 `Updated`。
   - HTTP 非 2xx/304 → `HttpError(httpStatus)`。
   - 网络异常 / 解析失败 → `NetworkError`。
4. ConfigPage `toastForOutcome` 把 `SyncOutcome` 翻成中文（id `ConfigSyncToast`，2.4 s 自动消失）：
   - `已同步至 v{cachedVersion}`
   - `已是最新 v{cachedVersion}` 或 `已是最新`（cache 还没拿到 version 时）
   - `同步失败 (HTTP {httpStatus})`
   - `同步失败 (服务端词包过小)`
   - `同步失败 (网络错误)`
5. ConfigSyncStatus 行（id `ConfigSyncStatus`）显示 `已缓存 schema v{schemaVersion}` 或 `尚未同步`。
6. 同步成功后**不会立即刷新 HomePage** —— 下次进 HomePage 时 `WordPackBootstrapper.bootstrap()` 重新读 cache，新词包才生效。这是有意为之，避免战斗中途词库换底；UI 自动化测试也基于这个时序断言。

### 13.6 设备端家长管理后台（V0.5.8）

`ParentAdminPage` 是家长在自家设备上的运维入口：

- **入口**：ConfigPage → "家长管理后台"按钮，家长 PIN 校验后 push。进入即调 `lockPortrait`，离开 `restoreAutoLandscape`。
- **统计卡**：`/api/v1/admin/stats` → `userCount / wordCount / categoryCount / packCount / latestVersion / lastPublishedAt / llmDraftPending / lessonImportDraftPending`。
- **课本导入卡**（V0.5.8 替代旧的"发布新版词包"流）：
  - 📷 拍照（`@kit.CameraKit.cameraPicker`）/ 🖼️ 从相册（`@kit.CoreFileKit.picker.PhotoViewPicker`）任一通道返回 URI。
  - 客户端用 `LessonImagePicker` 嗅 MIME（jpg/jpeg/png/webp 白名单）+ 读字节，组装 `PickedImage` 后 `ParentApiClient.importLesson(image)` 走 `multipart/form-data` POST `/api/v1/admin/lessons/import`。
  - 服务端 `admin_lessons.import_lesson()` 调 OpenAI vision，落 `LessonImportDraft` 文档，返回 `LessonDraftDto`。客户端把 `id` + `extracted.words.length` 暂存，点 "去复核 →" push `LessonDraftReviewPage`。
  - 8 MB / 非白名单 MIME / 网络异常 / 非 2xx 都映射到友好文案（"图片超过 8 MB" / "仅支持 JPG / PNG / WebP" / "网络异常" / "服务异常 (HTTP …)"）。
- **待复核草稿列表**：`/api/v1/admin/lesson-drafts?status=pending` → 时间戳行 + "复核 →" 按钮直跳 `LessonDraftReviewPage`。`onPageShow` 触发 refresh，所以从复核页 back 之后已 approve / reject 的草稿会立刻从列表里消失。
- **发布新版本词包**：`POST /api/v1/admin/packs/publish` + 可选 notes 单独保留，让家长可以把多张课本图都复核入库后一次性发布。

`LessonDraftReviewPage` 单独承担课本复核：

- 路由参数 `{ draftId: string }`，`getLessonDraft` 拉到草稿后渲染原图缩略 + 可改主题标签 + 候选词列表。
- 每行三件套：✓ 保留、`编辑` 弹窗（英文 / 中文双输入，trim 校验非空）、✎ 已编辑标记。
- "全部确认"先 `PATCH /api/v1/admin/lesson-drafts/{id}` 提交 edited extraction，再 `POST /approve`；"全部拒绝"`POST /reject`。两条路径都在 toast 后 back 到 ParentAdminPage；HTTP 409 ALREADY_REVIEWED 自动 back，避免家长在已处理的草稿上反复点。

> **V0.5.8 已下线 JWT 登录卡片**。`auth.py` 仍保留 `/login` 给将来的 Web 后台用，但所有 `admin_*` 路由都不要求 token。代价是同一家庭里所有家长设备共享全局视图；V0.6 会以家长账户做行级隔离。

---

## 14. UI / 交互约束

### 14.1 横屏布局（BattlePage）

- 左：玩家角色卡（CharacterCard）+ HpBar + 当前怪剩余 / 总数。
- 中：题目区域（中文 prompt + 自动播音按钮 + 倒计时 + 反馈条）。
- 右：怪物角色卡 + HpBar + 怪物名 + 当前击破数。
- 下：题型对应控件（三个 ChoiceButton / 字母模板 + 字母按钮 / SpellingArea）。

布局走 Row + Column + Flex + 百分比，禁止固定像素；字号给 14–18 vp 区间，按钮高度 ≥ 44 vp（儿童手指）。

### 14.2 工具栏图标

V0.5 follow-up 把工具栏 5 个图标（review / codex / wishlist / gear + WishlistPage 的 scroll）从 SVG 光栅化为 96×96 PNG，配合 `.syncLoad(true)` 解决 SVG 复杂路径在 back-nav 重挂时偶尔闪占位符（被孩子家长描述为"图标变 emoji"）的问题。Plan 按钮（📋）保留 emoji 字样。

### 14.3 反馈与无障碍

- 答对：按钮高亮正向色 + 怪物 HP 下降 + 动画 + SFX。
- 答错：错误按钮高亮 + 正确答案高亮 + 玩家 HP 下降 + SFX。
- 连击爆发：暴击五层（§4.4）。
- 怪物死亡：MagicProjectile + zoomPulse + monster_defeat SFX。
- 文案短句化、对比度高；关键反馈同时通过颜色 + 文字/动画双通道，不只靠颜色。
- 反馈期间 `FEEDBACK_MS = 650 ms` 禁用所有交互按钮，防止重复结算。

---

## 15. 测试策略

### 15.1 设备无关单测（`entry/src/test/`）

30 个测试文件，覆盖：

- 纯算法：`shuffle` 不丢元素；`QuestionGenerator` 三选一不重复且包含答案；`PlanQuestionSource` 题型链；`MemoryScheduler.classify` 分桶。
- BattleEngine：答对 / 答错 / 连击双倍 / 怪物切换 / 胜负条件 / `computeStars`。
- CoinAccount：`earn` 上限截断、`today-first` 即使被截到 0 也翻 `todayAdventureCompleted`、`beginToday` 跨天重置、`redeem` 不受日封顶限制、txn 历史滚动 cap。
- 持久化：WrongAnswerStore / WishlistStore / RedemptionHistoryStore 的 round-trip + 兼容老 schema 反序列化。
- 解析：`parseCustomWords`（半角/全角冒号、空行、错行）、`computeFinalPool`、`parsePackCategories`。
- 家长管理后台 HTTP（V0.5.8）：`ParentApiClient` 课本导入流（pre-flight 大小 / MIME 校验、`multipart/form-data` POST、JSON 解析、HTTP 错误映射）、`MultipartBuilder` 字节级 round-trip + `escapeFilename` 头注入防护、`LessonImagePicker` 取消 / MIME 嗅探。

跑法：`hvigorw -p module=entry@default test`，BUILD SUCCESSFUL = 全部通过（hvigor 在任一断言失败时返回非 0）。

### 15.2 设备 UI 测试（`entry/src/ohosTest/ets/test/`）

19 个 Hypium UI 测试文件（含 V0.5.8 新增的 `LessonDraftReviewFlow.ui.test.ets`）。覆盖：

- 路由：`RoutingFlow.ui.test.ets`（首页 → 战斗 → 结算 → 重玩 / 返回的全闭环）。
- 战斗题型：`SpellQuestionFlow / FillLetterFlow`。
- 暴击 / 命中：`MagicAttack / CritSpectacle`。
- 复习模式：`ReviewMode.ui.test.ets`。
- 今日冒险 / 区域 / 计划：`V03Adventure / RegionPickerFlow / TodayPlanFlow`。
- 学习报告：`LearningReportFlow.ui.test.ets`。
- 愿望单（默认 + 自定义）：`WishlistFlow / CustomWishlistFlow`，含 PIN 闸 + 验证错误 + 端到端添加。
- 设置 / 同步 / 家长管理后台：`ConfigFlow / ConfigSyncFlow / ParentAdminFlow / LessonDraftReviewFlow`（后两者 V0.5.8 起取代 `AdminConsoleFlow`），含 PIN 闸 + 同步成功断言 + 缓存状态跨页持久 + 课本导入按钮 / 待复核列表 / 路由注册的烟雾测试。
- 图鉴：`MonsterCodexFlow.ui.test.ets`。

入口 `entry/src/ohosTest/ets/test/List.test.ets`。跑法：

```bash
hvigorw --mode module -p module=entry@ohosTest assembleHap
hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc shell aa test -b com.terryma.wordmagicgame -m entry_test \
  -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 1500
```

成功标志：`OHOS_REPORT_RESULT: stream=Tests run: N, Failure: 0, Error: 0`。

### 15.3 服务端测试（`server/tests/`）

28 个文件（含 `conftest.py` / `__init__.py`，26 个 `test_*.py`）。覆盖：

- 路由层：auth / public_packs / admin_words / admin_packs / admin_drafts / admin_categories / admin_lessons / admin_stats。
- 服务层：`pack_service.derive_schema_version` 全分支、`llm_service` 解析、`asset_service` 上传链路（mock httpx）。
- 模型：`Word` / `WordPack` / `User` 的字段约束。
- 工具：`seed_from_rawfile` 命令行行为。
- 可选：`test_llm_live_smoke.py` 是真正打 OpenAI 的 smoke 测试，CI 不跑。

`AGENTS.md` 强制：每个改 `server/` 的 commit 必须 `uv run pytest` 全绿（含 0 warning，warnings filter 配在 `pyproject.toml`）。

### 15.4 手工验收

- 平板 + 手机分别横屏跑一局今日冒险。
- 快速连点选项 → 不重复扣血 / 不重复结算。
- 战斗中切出 App 再切回 → 倒计时不应该继续累计。
- 飞行模式开 → 进入主页 / 战斗 / 愿望单 / ConfigPage 都应正常（同步按钮会 toast 网络异常但不崩）。

---

## 16. 风险与决策

| 风险                         | 影响                  | 应对                                                                  |
| -------------------------- | ------------------- | ------------------------------------------------------------------- |
| 儿童误触 / 连点                  | 状态重复结算              | 反馈期间禁用选项 + `battleEndHandled` 单航闸。                                  |
| 横屏手机空间不足                   | 按钮 / 角色裁切           | 弹性布局 + ChoiceButton 拉满宽。                                            |
| 词库过少                        | 干扰项重复 / 题目过易        | 全局补足 + 自动降级题型。                                                     |
| UI 与规则耦合                    | 后续难维护               | 战斗规则全部进 `BattleEngine` / `BattleState`，页面只调接口。                     |
| 服务端冷启动慢（Vercel）             | "同步词包"首次延迟 5–10s     | UI 同步 toast 提示；UI 自动化 retry 1 次，但不掩盖真实 regression。                  |
| SVG 图标在 back-nav 偶尔闪占位符      | 用户感知"图标变 emoji"      | V0.5 follow-up 改用 96×96 PNG + `syncLoad(true)`。                     |
| 家长 PIN 明文                   | 设备被借用时 PIN 可能被读出     | V0.6 计划评估哈希 + 系统密钥环。                                               |
| 词包大小爆炸                     | 缓存过大 + 同步带宽         | `WordPackCache` 只存最新一份；`MIN_WORDS_PER_PACK` 拒收过小词包做防御。            |
| 服务端 schema 演进破坏老客户端         | 老设备崩溃               | 客户端解析器对未知字段 ignore，新字段都加 `?`；`schema_version` 单调向上递增。            |

---

## 17. 后续路线图

> 详细子版本路线见 [`WordMagicGame_roadmap.md`](WordMagicGame_roadmap.md)。本节只列方向。

### V0.6 候选（未启动）

- 服务端发起 push（推送式新词包），客户端 silent refresh。
- 家长 PIN 哈希存储，跨设备共用一个 family code。
- 多账户 / 学习进度跨设备同步（评估是否需要登录态）。
- 课本扫描 → 自动建议自定义词列表（接 V0.5 已有的 `admin_lessons` 草稿流）。

### V1.0 候选

- 完整美术替换（角色 / 怪物 / 背景 / UI 全套）。
- 学习报告导出 PDF / 邮件给家长。
- 评估云端学习记录、家长侧成长曲线、跨设备进度。
- 评估正式商业化：内容订阅 / 家长账号 / 商城。

---

## 18. 关联文档与代码索引

- [`docs/WordMagicGame_roadmap.md`](WordMagicGame_roadmap.md)：所有子版本的时间线 + 验收。
- [`docs/superpowers/specs/`](superpowers/specs/)：每个版本的设计文档（V0.2 / V0.3 / V0.3.5 / V0.3.6 / V0.3.7 / V0.3.8 / V0.3.9 / V0.3.10 / V0.4.x / V0.5 / V0.5 follow-up）。
- [`docs/superpowers/plans/`](superpowers/plans/)：对应实现计划与 checklist。
- [`docs/arkts-references/`](arkts-references/)：HarmonyOS / ArkTS / hvigor 相关命令与 API 速查。
- [`server/README.md`](../server/README.md) / [`server/pyproject.toml`](../server/pyproject.toml)：服务端依赖与启动。
- [`AGENTS.md`](../AGENTS.md) / [`CLAUDE.md`](../CLAUDE.md)：项目内 AI 代理工作约定（包括 server 全绿要求）。
- [`.cursor/dev-commands.md`](../.cursor/dev-commands.md)：HarmonyOS 构建 / lint / 测试命令的真源。

每次新增大功能时先看本文档是否仍符合架构边界；若引入账号、长连接、或服务端结构性变化，必须新增专项设计文档并更新本文 §3 / §13 / §17。
