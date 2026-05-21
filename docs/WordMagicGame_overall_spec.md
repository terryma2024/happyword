# WordMagicGame 产品与架构设计规格

> 文档状态：当前版本基线（Monorepo 四模块 + **三端 bootstrap parity V0.7.1** + 服务端 **V0.8.1 / V0.8.2** 后台）
> 适用版本：V0.1 原型 → V0.7.1 三端对齐 → V0.8 家长词库与系统管理员控制台（已交付）
> 客户端目标平台：HarmonyOS NEXT（`harmonyos/`，设计与 ohosTest 权威参考）、iOS（`ios/WordMagicGame/`，Swift / SwiftUI）、Android（`android/`，Kotlin / Jetpack Compose）
> 服务端：Python 3.12，FastAPI + Beanie(MongoDB)，部署在 Vercel Serverless（项目 Root Directory = `server`）
> 工程结构：`harmonyos/`、`ios/`、`android/`、`server/` 四个一等模块并列；`shared/` 仅放 contracts / schemas / fixtures
> 详细演进时间线见 [`WordMagicGame_roadmap.md`](WordMagicGame_roadmap.md)；V0.8 设计见 [`superpowers/specs/2026-05-08-v0.8-backoffice-and-vocabulary-management-design.md`](superpowers/specs/2026-05-08-v0.8-backoffice-and-vocabulary-management-design.md)。**V0.8.3 / V0.8.4** 战斗线设计见 [`docs/features/2026-05-18-battle-polish-v0-8-3/00-design.md`](features/2026-05-18-battle-polish-v0-8-3/00-design.md)、[`docs/features/2026-05-18-battle-balance-v0-8-4/00-design.md`](features/2026-05-18-battle-balance-v0-8-4/00-design.md)。本文记录"现在跑的代码长什么样"（**V0.8.4 条目为已批准目标态**，实现落地前代码可能仍为旧默认）。

---

## 1. 产品定位

WordMagicGame（中文暂定名"小魔法师单词冒险"）是面向 8 岁左右儿童的英语单词学习小游戏。产品通过"魔法师对战怪物"的轻量战斗 + "今日冒险"每日剧情 + "魔法币兑换愿望单"的成长闭环，把单词练习包装成短时冒险体验：单局 3–5 分钟即可完成，正向反馈密度高，并保留家长侧的内容/账户/数据掌控点。

经过 V0.1 → V0.7.1 的迭代，产品已经从一个本地原型演进为 **三端原生 + 服务端** 的 monorepo 产品工程：

- **HarmonyOS 客户端**（`harmonyos/`，app `0.7.0`）：完整闭环，17 页路由；战斗、复习、每日冒险、愿望单、家长 PIN、按词包本地学习报告；V0.6.5+ 三层词包（built-in / global / family）+ 设备级 pack 选择器；ohosTest 为自动化权威参考。
- **iOS 客户端**（`ios/WordMagicGame/`，`0.7.0` / build `1007004` TestFlight 已验证）：与 Harmony **bootstrap 矩阵对齐**（17 页、V0.6.7.8 语义）；索引见 [`docs/ios-replica/00-index.md`](ios-replica/00-index.md)、发布门禁 [`ios/release-pre.md`](../ios/release-pre.md)。
- **Android 客户端**（`android/`）：与 Harmony **bootstrap 矩阵对齐**（17 页均已实现）；索引见 [`docs/android-replica/00-index.md`](android-replica/00-index.md)、Phase 5 门禁 [`docs/android-replica/07-release-readiness-checklist.md`](android-replica/07-release-readiness-checklist.md)。
- **服务端**：FastAPI（Vercel），词库 / 词包 / 类目 / 家长账户 / 设备绑定 / OpenAI 辅助；**V0.8.1** 家长 Web 词库工作台 `/family/{family_id}/packs/*` + 子端 **global+family 合并** `GET /api/v1/family/{family_id}/packs/latest.json`；**V0.8.2** 系统管理员 HTML `/admin/*`（会话 cookie + `admin_audit_service`）。自 V0.6.5 起 `FamilyPackDefinition` + `GLOBAL_PACK_FAMILY_ID` 承载 global / family 两层。
- **共享契约**：`shared/` 仅 OpenAPI / JSON Schema / 错误码 / 同步协议 / golden fixtures；三端各自原生实现业务逻辑。
- **端云协同**：三端按用户主动同步拉 global / family 词包到本地缓存，冷启动从缓存重建词包库；HarmonyOS 侧为 `PackLibrary` / `GlobalPackService` / `FamilyPackService`，iOS / Android 复刻同一语义与本端命名。
- **V0.7.1 之后新功能**：走 [`docs/sop/00-three-platform-feature-sop.md`](sop/00-three-platform-feature-sop.md)（Harmony 先实现 → 复制触发签字 → iOS / Android 并行复制），不再扩写一次性 replica 计划。

---

## 2. 用户与场景

### 2.1 角色

- **儿童玩家**：8 岁左右，正在打基础英语词汇。
- **家长**：通过 6 位家长 PIN 解锁兑换、添加 / 删除自定义愿望、进入"家长管理后台"（V0.5.8 起改名，原"管理员控制台"）拍照导入课本单词 / 复核 LLM 提取结果 / 一键发布词包、设置 / 修改 PIN。
- **内容运营 / 开发者**：通过服务端 Admin Console 管理单词、生成插画与音频、发布词包、查看统计。

### 2.2 使用场景

- 平板横屏短时学习（当前以 HarmonyOS / 华为 MatePad Air 为首要体验设备）。
- 手机横屏补充练习（HarmonyOS / iOS / Android 儿童流均为横屏优先）。
- 离线优先：所有"必须在线"的功能都靠本地缓存兜底；冷启动从本地词包加载，不需要网络。
- 半在线：家长在 PackManagerPage（📦 我的词包，从 ConfigPage 进入）顶部主动点击 `🔄 同步词包` 才会拉服务端最新三层词包；冷启动只读本地缓存。

### 2.3 成功标准

- 儿童 5 分钟内独立完成一局今日冒险。
- 答对/答错反馈即时、动效与音效区分明显。
- 家长能在不打扰孩子的情况下管理 PIN、愿望单、词库。
- 服务端发布新词包后，任一已接入的原生客户端下次入主页能看到新区域 / 新词，全程不需要重装应用；三端 bootstrap 均已落地同步路径（PackManager「同步词包」+ 合并/分层拉取）。

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
| V0.5.8                | 家长管理后台改版         | "管理员控制台"重命名为"家长管理后台"；进入即锁定竖屏；移除用户名 / 密码登录闸（V0.6 改为家长账户隔离）；以"拍照 / 从相册"上传课本图替代手填发布流，照片走 OpenAI vision 提单词草稿，家长复核后才入库；新增独立 `LessonDraftReviewPage` 复核页。 |
| V0.6.5         | 三层词包模型（服务端 + 客户端 foundation）| **三层词包模型上线**：built-in（rawfile，5 包不可删）/ global（管理员维护，所有 family 可见，匿名只读）/ family（家长上传，`family_id`-scoped）。**服务端复用** `FamilyPackDefinition` + `GLOBAL_PACK_FAMILY_ID` 哨兵：新增 `app/services/global_pack_service.py` 薄包装、`/api/v1/admin/global-packs/**` 管理路由、`/api/v1/public/global-packs/latest.json` 匿名只读路由（含 ETag/HEAD）、`scripts/migrate_global_packs_v0_6_5.py` 默认 seed 5 个 global pack；publish 阶段过滤 `category=="test"` 词，避免污染公共词库。**API 路由约定**：通过 `.cursor/rules/api-route-pattern.mdc` 沉淀 `/api/v1/{admin,public,family/{family_id}}/**` 三段式约束，`legacy_route_aliases.py` 提供向前兼容期的路径别名层（`include_in_schema=False`），保留旧 URL 给现有客户端，新 URL 给新客户端。**客户端 foundation**：`Pack` + `SceneMetadata` 模型、`BuiltinPackLoader`（5 个 per-pack rawfile + scene 元数据）、`GlobalPackService`（匿名 ETag 客户端 + prefs slot `wordmagic_global_packs`）、`PackLibrary`（builtin/global/family 三层 union + scene fallback）、`PackSelectionService`（设备级最多 5 包 + pin + perfect-rotation，`wordmagic_pack_selection`）。UI 集成留到 V0.6.5.1；本版本 runtime 行为不变，新服务以 foundation 形式落地。 |
| V0.6.5.1       | 三层词包模型 UI 全量集成 | **HomePage / ConfigPage / BattlePage 接入 PackLibrary**：HomePage 区域 chip row 改读 `PackLibrary` + `PackSelectionService.getActiveIds()`，每个 chip 都是真实 `Pack`，点击即切换今日冒险词源；ConfigPage 新增「📦 我的词包」picker（最多激活 5 个 + 📌 pin 防轮换 + 🔄 同步词包），同步按钮一键拉 global + family；BattlePage 在 today 模式直接消费 `Pack.words` 作为 bundleRepo（通过 AppStorage `todayActivePack` 跨页 handoff），完美战斗（3 ⭐）触发 `PackSelectionService.recordPerfectAdventure()` 调用 `LibraryCandidateProvider` 自动轮换非 pinned 包。**新增**：`PackNetworkFetchAdapter`（包级 NetworkKit 适配，支持 HEAD + ETag 捕获 + preview bypass header）、`PackHomeIntegration`（`HomeIntegrationBundle` + `loadHomeIntegration` + `resolveActivePacks` + `LibraryCandidateProvider` 共享逻辑）、`WordPackBootstrapper.bootstrapPackLibrary()`（冷启动从 prefs 缓存重建 PackLibrary，不发网络）、`TodayAdventureBuilder.buildFromPack()`（直接从 `Pack` 合成 region + repo）。**软兼容**：CustomWordsPage 顶端贴软弃用横幅，旧 AppStorage 中的 `customWordsRaw` 仍可保存。 |
| V0.6.6   | GameConfig 旧词库字段清理 | **删除 GameConfig 旧字段**：`enabledCategories` / `customWordsRaw` 与配套的 `KNOWN_CATEGORIES` / `CUSTOM_CATEGORY_KEY` / `parseCustomWords` / `computeFinalPool` 全部下线；`MIN_POOL_SIZE` 仅作为 review-mode 池子兜底常量保留。**ConfigPage 简化**：删除「词库类别」chip 行（含 ConfigCategoryFruit/Place/Home/Custom）、「自定义」入口与 ConfigValidationHint，pack picker 成为唯一词源选择入口；保存路径不再做 finalPool 校验。**CustomWordsPage 删除**：从 `main_pages.json` 路由表与代码中移除（旧设备升级时遗留的 `customWordsRaw` AppStorage 字段被静默忽略）。**BattlePage 简化**：normal / review 模式 universe 直接用 `repo.all()`，不再做 category filter。**测试清理**：`LocalUnit.test.ets` 删除 `parseCustomWords` / `computeFinalPool` / `defaultsMatchEngineDefaults` 中的旧字段断言；`RoutingFlow.ui.test.ets` 删除 `openConfigAndApply` / `openCustomWordsAndSave` / `setChipSelected` / `categoryChipId` / `TestGameConfig` 等已死帮助函数。 |
| V0.6.7   | 词包管理独立成页 | **`pages/PackManagerPage` 新增**：把 V0.6.5.1 的 `📦 我的词包` 卡从 ConfigPage 抽出来独立成页，进入入口为 ConfigPage 的 `ConfigPackManagerEntry` 行（"已激活 X/5 管理 ›"）；新页 UI 用 `Toggle({ type: ToggleType.Switch })` 替换原来的 ✓ 按钮，源标签（"内置 / 官方 / 家庭"）渲染为彩色 pill 贴在英文 pack 名左侧，pinned/未 pinned 的 📌 状态保留。**ConfigPage 重构**：删除 inline picker 的所有状态 / 方法 / @Builder（`availablePacks` / `activePackIds` / `pinnedPackIds` / `togglePackActive` / `togglePackPin` / `onPackSyncTap` / `packRow` 等），仅留 `activePackCount` + `loadHomeIntegration` 在 `aboutToAppear` / `onPageShow` 同步入口行的状态。 |
| V0.6.7.1 | 移除 ConfigPage 词库同步行 | **删除 `syncRow`**：原 V0.5 时代的「词库同步 / `ConfigSyncButton` / `ConfigSyncStatus` / `ConfigSyncToast`」整行从 ConfigPage 下线（同时删 `WordPackCache` / `RemoteWordPackService` / `WordPackSyncService` 的页面级 import / @State / handler / @Builder），统一到 PackManagerPage 顶部的 `🔄 同步词包` 按钮。**测试清理**：`ConfigSyncFlow.ui.test.ets` 整文件删除，`List.test.ets` 同步去掉 `configSyncFlowUiTest` 注册。**保留**：`WordPackBootstrapper.bootstrap()` 在 app 启动期通过 `WordPackSyncService` 后台刷新 `WordPackCache` 给 HomePage 类别 overlay 用，没有 UI 入口。 |
| V0.6.7.2 | 解除设备绑定迁移到孩子档案页 | **ConfigPage 删除「解除设备绑定」行**：`ConfigUnbindBindingButton` / `ConfigUnbindToast` 整体下线，`@State unbindBusy / unbindToastText`、`private unbindToastTimer`、`onUnbindTap` / `runUnbind` / `showUnbindToast` 与 `DeviceUnbindClient` / `RealParentFetchAdapter` / `effectiveServerBaseUrl` 的 ConfigPage 级 import 一并删除。**BoundDeviceInfoPage 升级为完整服务端 unbind**：原本只调 `CloudCredentials.clearBinding()` 的本地 `onUnbind()`（按钮文案 "解除绑定 (本地)" + 提示行 "V0.6.2 仅在本机清除凭据，需在家长网页 → 设备列表 中删除以撤销"）替换为 `onUnbindTap()` + `runUnbind()` 两段：先 `ParentPinDialog` 校验 6 位家长 PIN，再 `DeviceUnbindClient.unbind()` 调 `POST /api/v1/family/{family_id}/unbind`，成功后 `recorder.attachCloudSync(undefined)` + `BoundDeviceInfoUnbindToast` 弹「已解除设备绑定」+ 600 ms 后 `router.back()` 自动回到 ConfigPage（其 `onPageShow` 重新跑 `refreshBindingState` 翻回未绑定）。按钮文案改为 `解除设备绑定` / `正在解除…`，去掉 "(本地)" 后缀和提示行；新加 `BoundDeviceInfoUnbindButton` / `BoundDeviceInfoUnbindToast` 两个 id。**测试**：`ParentBindingFlowV06UiTest` 重写 `unbindWithPinFlipsBackToUnbound → unbindFromBoundDeviceInfoPageFlipsBackToUnbound`，新路径是 `ConfigBoundDeviceInfoButton → BoundDeviceInfoUnbindButton → ParentPinDialog → BoundDeviceInfoUnbindToast → 自动 back → ConfigBindParentButton`。 |
| V0.6.7.4 | HomePage 词包激活跨页传播修复 | **`pages/HomePage.ets` `onPageShow` 重载 `homeIntegration`**：之前 `onPageShow` 只调 `applyActivePacks()`，但读的是 `aboutToAppear` 缓存的 `homeIntegration.selection: PackSelectionService` 实例 —— PackManagerPage / ConfigPage 的开关变化是写到它们自己 `loadHomeIntegration()` 出来的另一份实例 + 持久化到 preferences，不会反映到 HomePage 的内存视图，所以 chip row 切完不刷新（V0.6.5.1 注释说「chip row reflects the latest selection without a full reload」其实从未生效）。修复：`onPageShow` 重新跑 `loadHomeIntegration(ctxShow).then(b => { this.homeIntegration = b; this.applyActivePacks(); })`，让 `chipPacks` / `todayPack` / `todayRegion` 都基于 PackManagerPage 提交后的最新 `selection.getActiveIds()` 解析。**测试**：`PackManagerFlow.ui.test.ets` 新增两个 V0.6.7.4 用例 —— `togglingNonSelectedPackOffRemovesItsHomeRegionChip` 把 `home-cottage` 切关后断言 `RegionChip_home-cottage === null` 且其他 4 chip 仍在 + `AdventureCardTitle` 不变；`togglingSelectedPackOffSwapsAdventureCardThenRestores` 切 `fruit-forest` 关掉后断言 `chipPacks[0]` fallback 触发 + 标题切到 `school-castle` 的标签，再切回时 `TODAY_REGION_ID_KEY` 自动复位。两用例都 `try/finally` 兜底（assertion 挂时翻回 ON）防止失败污染设备 prefs。 |
| V0.6.7.5 | HomePage 标签英文统一 | 用户报「在词包激活切换以后，标题变成了中文」：`pages/HomePage.ets` `packChipLabel` 之前优先 `pack.labelZh` → `categoryCatalog.getById(...).labelZh` → `pack.name`，对 builtins 全部回中文，但若同 id 的 global pack override 有空 `description`，`PackLibrary.applySceneFallback` 只 fallback `scene` 不 fallback `labelZh`，致那个 pack `labelZh = ''` chip 兜底英文，5 个 chip 出现「3 中 + 2 英」混排。**修复方向**：与用户确认后选 `all_english`（chip + 大标题都对齐 PackManagerPage 的英文命名习惯）：`packChipLabel` 收紧成只看 `p.name` → `p.id` 兜底，去掉两条中文分支；`regionLabel` 收紧成直接返回 `region.displayName`（`regionFromPack(pack)` 从 `pack.name` 取）。`regionStory` / `categoryCatalog` overlay 体系保留给将来的 storyZh 长文用，不影响 chip / 标题。**未做**：`PackLibrary.applySceneFallback` 没扩成 labelZh 级 fallback —— labelZh 路径在 chip / title 上都不再被消费，没必要替换 merge 逻辑。**测试**：`PackManagerFlow.ui.test.ets` 新增 `homeRegionChipsRenderEnglishPackNames` 用例烟测 5 个 builtin chip 的 `getText()` 严格等于 `Fruit Forest / School Castle / Home Cottage / Animal Safari / Ocean Realm`；回归到中文会立刻挂掉。 |
| V0.6.7.3 | PackManagerPage 固定按钮可读性修复 | **`packRow` 重写**：原 `Button(this.isPinned(p.id) ? '📌' : '·')` 在 36×36 vp 方框里渲染单字符 emoji，未 pin 的 `·` 中点像无意义的占位符，已 pin 的 📌 在 fontSize 16 下也几乎看不清。新版按钮内文为 `📌 固定` / `已固定`：未 pin 时灰底 `#F3F4F6` + `#6B7280` 中性字，已 pin 时黄底 `#FEF3C7` + `#B45309` 深橙字，宽度由 padding 自适应（删除固定 `.width(36)` 改为 `.padding({ left: 10, right: 10 })`），`fontSize` 13。**条件渲染**：固定按钮只对当前已激活的词包渲染（`if (this.isActive(p.id)) ...`）；未激活的词包行用 `Blank().height(36)` 占位维持 Toggle 列对齐 —— 旧版无论是否激活都画 `·`，但 `togglePackPin` 在未激活时直接 `showPackToast('只有已激活的词包才能 📌 固定')` 早退，按钮其实是死区。`togglePackPin` 的早退分支保留作为 defensive guard（注释更新到 V0.6.7.3）。**`statusRow` 文案同步**：`点击右侧开关切换激活；📌 防止满分自动轮换` → `开关：切换激活 · 固定：防止满分自动轮换`，避免 emoji 提示与按钮文案不一致。**测试**：未触动 ohosTest —— `PackPin_<id>` button id 与 `togglePackPin` 行为契约不变；`cd harmonyos && hvigorw assembleHap` + `hvigorw test` 双绿，模拟器实跑确认 `Active+unpinned/Active+pinned/Inactive` 三态视觉差异清晰。 |
| V0.6.7.7 | ConfigPage 倒计时自定义 + 我的词包行精简 | **目的**：把开发者向的 3s/15s/1m/2m chip 从家长视图移走，并为家长 + UI 测试保留任意秒数入口。**改动**：① `models/GameConfig.ets` 把 `TIMER_CHOICES` 从 `[3, 15, 30, 60, 120, 300, 600]` 砍到 `[30, 180, 300, 600]`（30s / 3m / 5m / 10m），并新增 `TIMER_CUSTOM_MIN = 1` / `TIMER_CUSTOM_MAX = 3600` 边界常量。② 新组件 `components/CustomTimerDialog.ets`：`@CustomDialog` + 数字 `TextInput`，导出纯函数 `validateCustomTimerSeconds(input)`（trim → 仅数字 → 边界检查），单测 `harmonyos/entry/src/test/CustomTimerDialog.test.ets`（10 个用例覆盖空/空白/非数字/负数/小数/0/超上限/3s/MIN/MAX）。③ `pages/ConfigPage.ets` 新增 `ConfigTimerCustom` 按钮：未激活时显示 `自定义`，激活时显示 `✓自定义 (Xs)` 与 chip 选中样式（`#FFB400` 背景），点击打开 `CustomTimerDialog`；同时把「我的词包」行的 📦 emoji 去掉（与 `玩家血量 / 怪物血量 / 怪物数量 / 倒计时 / 发音播放 / 家长密码 / 家长账户 / 学习记录 / 家长` 其它行保持一致，无 leading emoji）。④ `services/GameConfigPersistence.ets` 的 `sanitizeTimer` 不再 snap-round 到最近 chip（旧行为会把 3s 自定义值在 rehydrate 时偷偷改成 30s），改为只 clamp 到 `[TIMER_CUSTOM_MIN, TIMER_CUSTOM_MAX]`，让 `自定义 3s` 在 ohosTest 进程之间稳定存活。**测试**：`ConfigFlow.ui.test.ets` 新增两个用例：`customTimerDialogAcceptsThreeSecondsAndUpdatesChip`（开 dialog → 输入 `3` → 确定 → 断言 `ConfigTimerCustom` 文案含 `✓自定义` 和 `3s` + `ConfigTimer30s` 不带 `✓` → 保存 → 回首页 → 重开 ConfigPage 验证 3s 持久化没被重写到 chip → finally 用 `restoreDefaultTimerChip` 回 5m）；`customTimerDialogRejectsZeroAndKeepsDialogOpen`（输入 `0` → 确定 → 断言 dialog 仍在 + `CustomTimerDialogError` 显示 → 取消 dialog → 取消 ConfigPage 不持久化）。同步把 `LocalUnit.test.ets::defaultsMatchEngineDefaults` 的 `TIMER_CHOICES.indexOf(3) >= 0` 断言换成 `length === 4` + `[30, 180, 300, 600]` 都在 / `[3, 15, 60, 120]` 都不在的精确对比。**ohosTest 副作用**：把 `scrollToParentPinButton` 从「`findComponent` 非空就退出」加固为「button 报告高度 ≥ 100px 才退出」—— 旧版会在 `ConfigParentPinButton` 处于 `Y∈[1235,1260]` 这种 25px clipped slice 时立即退出，导致后续 `clickByIdShared` 落在 viewport 边缘被系统当作非 hit-test，三个 PIN setup 用例都 fail；新版强制 swipe 到按钮全可见。 |
| V0.6.7.6 | 三层词包 UI 自动化测试覆盖 | **`server/mock_ui_server.py` 扩成全三层**：之前 ohosTest 的 PackManagerFlow 只有 5 个 builtin pack 在场，缺 global / family 两层在 PackManagerPage 同步、激活、HomePage chip 传播的 round-trip 验证。新增 `FIXTURE_GLOBAL_PACK_PAYLOAD`（`space-station` / "Space Station" 3 词，匹配 `services/GlobalPackService.ets` 期望的 schema_v1 envelope）+ 匿名只读 `GET /api/v1/public/global-packs/latest.json`（含 `If-None-Match` 304 + `HEAD`）；把 V0.6.3 时代的 `GET /api/v1/family/{family_id}/family-packs/active.json`（固定空 packs）替换为与生产一致的 `GET /api/v1/family/{family_id}/family-packs/latest.json`（Bearer 闸 + ETag + HEAD），返回 `FIXTURE_FAMILY_PACK_PAYLOAD`（`family-snacks` / "Family Snacks" 3 词）。两个 fixture 的 `pack_id` 都刻意避开 5 个 builtin 名字，让 chip row 在「关 1 builtin / 开 1 新包」时能客观表现 row composition 的变化。**测试**：`PackManagerFlow.ui.test.ets` 新增两个用例：`syncedGlobalPackAppearsInListAndActivatingItGrowsHomeChipRow`（匿名 sync → 验证「官方」tag + 英文 label → 关 `home-cottage` 开 `space-station` → HomePage 验证 chip 增减）；`boundDeviceSyncPullsFamilyPackAndAffectsHomeChipRow`（先 `seedMockBinding()` 在 mock 侧挂 deterministic JWT，再客户端 UI 级 `bindViaShortCode(driver)` 走 ScanBindingPage 真实 redeem 让 `CloudCredentials` 在 live ability 上落实，再 sync → 验证「家庭」tag + 英文 label → 关 `animal-safari` 开 `family-snacks` → HomePage 验证 chip 增减；`finally` 还原激活集 + `unbindMockBinding()` + `wipeBoundDeviceState()` 清 `wordmagic_cloud` 全部绑定 keys 让随后跑的 `ParentBindingFlowV06` 还能从未绑定起步）。新增可复用 helper：`mockHttp` / `seedMockBinding` / `unbindMockBinding` / `bindViaShortCode` / `wipeBoundDeviceState` / `tapPackSyncAndWaitForToast` / `togglePackActiveInPlace`（用 `@ohos.net.http` + `@ohos.data.preferences`）。**未触动**：`pages/PackManagerPage` 的实现，本版本只是补测试 + 扩 mock。 |
| V0.7.0 | Monorepo 原生多客户端重排 | 根目录升级为 monorepo；HarmonyOS DevEco 工程整体迁入 `harmonyos/`；根目录并列 `ios/`、`android/` 原生客户端模块；`server/` 保持后端一级模块；`shared/` 只保存 contracts / schemas / fixtures。V0.7.0 不重排服务端 API，不把 `shared/` 做成跨平台 SDK。 |
| V0.7.1 | 三端 bootstrap parity | Harmony / iOS / Android **17 页矩阵**与 V0.6.7.8 词包/报告语义对齐；Harmony 仍为设计与 ohosTest 权威参考；详见 roadmap §14.1、`docs/ios-replica/`、`docs/android-replica/`。 |
| V0.8.1 | 家长词库 Web 工作台 | `/family/{family_id}/packs/*` HTML + family pack JSON API（`parent_packs_pages.py`、`parent_family_pack.py`）；子端合并拉取 `GET /api/v1/family/{family_id}/packs/latest.json`（`child_family_pack.py` + `family_pack_service.collect_child_vocabulary`）。 |
| V0.8.2 | 系统管理员 HTML 控制台 | `/admin/*` 会话登录 + 高风险操作审计（`admin_pages.py`、`admin_audit_service.py`）；与 V0.5.x 遗留 JSON `/api/v1/admin/**` 自动化 API 并存，日常人工运维走 HTML 壳。 |
| V0.8.3 | 战斗与词包体验小优化（设计 / 实施中） | 词包激活 10 槽 + 满额自动轮换；`MonsterLevel` + bonus ✨ + 50% HP-2 重击；`DamageFloaterLabel`。详见 feature `2026-05-18-battle-polish-v0-8-3`。 |
| V0.8.4 | 战斗平衡与题型节奏（设计已锁） | 魔法师默认 HP **10**；`Spell` 错点字母每次 **-1 HP**；今日战斗 intro（每词最多 1× Choice + 1× FillLetter）→ challenge（FillLetterMedium / Spell 各 **50%**）。详见 feature `2026-05-18-battle-balance-v0-8-4`。 |

---

## 3.1 三层词包模型（V0.6.5 → V0.6.6）

V0.6.5 把"词包"重构为统一的 `Pack` 对象（`harmonyos/entry/src/main/ets/models/Pack.ets`），来源分三层；V0.6.5.1 把 HomePage / ConfigPage / BattlePage 全部切到 PackLibrary；V0.6.6 删除最后一批旧 GameConfig 词库字段，pack picker 成为唯一词源入口。

| 层 | 来源 | 是否可删 | 同步路径 | 服务端集合 |
|---|---|---|---|---|
| `builtin` | rawfile（5 个，每包独立 JSON + scene 元数据） | 否 | 随安装包 | 无 |
| `global`  | 系统管理员维护 | 否（孩子端） | `/api/v1/public/global-packs/latest.json`（匿名读，ETag 304） | `FamilyPackDefinition` 中 `family_id == GLOBAL_PACK_FAMILY_ID` 的记录 |
| `family`  | 家长在家长后台上传 | 是 | 设备拉取：**合并** `GET /api/v1/family/{family_id}/packs/latest.json`（global+family）；family-only 遗留：`family-packs/latest.json` | `FamilyPackDefinition` 普通记录 |

**底层数据库复用**：global 与 family 共用同一套 `FamilyPackDefinition` / `FamilyPackDraft` / `FamilyPackPointer` / `FamilyWordPack` 集合，仅靠特殊的 `GLOBAL_PACK_FAMILY_ID = "__global__"` 哨兵区分。`server/app/services/global_pack_service.py` 是 `family_pack_service` 的薄包装，将 `family_id=GLOBAL_PACK_FAMILY_ID` 隐藏在 API 边界后。`publish` 阶段统一过滤 `category=="test"` 词，避免污染公共词库。

**API 路由约定**（沉淀在工程级 `.cursor/rules/api-route-pattern.mdc`）：

| 前缀 | 鉴权 | 用途 |
|---|---|---|
| `/api/v1/admin/**` | 管理员 token（V0.6.x 暂未启用） | 系统管理员功能（含 `admin/global-packs/**`） |
| `/api/v1/public/**` | 匿名 | 公共资源（`preview-urls.json`、`global-packs/latest.json`、ab 开关等） |
| `/api/v1/family/{family_id}/**` | 家长 / 设备账号（V0.6.x 暂未启用） | family-scoped 资源 |

`server/app/routers/legacy_route_aliases.py` 在 v0.6.5 引入向前兼容期路径别名层：把现有不合规的旧路径以 `include_in_schema=False` 别名重定向到符合新约束的新路径，保留旧 URL 给现有客户端，新 URL 给新客户端。后续版本再删除旧路径。

**客户端模型 / 服务**：

- `Pack` + `SceneMetadata` 模型（`harmonyos/entry/src/main/ets/models/Pack.ets`）— 统一描述三层词包；scene 包含 `bgPrimary` / `bgAccent` / `bossName` / `bossCandidates` / `monsterPlan`。
- `BuiltinPackLoader`（`services/BuiltinPackLoader.ets`）— 读取 5 个 per-pack rawfile（`resources/rawfile/data/builtin/{fruit-forest,school-castle,home-cottage,animal-safari,ocean-realm}.json`），每包自带 scene 元数据。
- `GlobalPackService`（`services/GlobalPackService.ets`）— 匿名 ETag 客户端，prefs slot `wordmagic_global_packs`，处理 200 / 304 / 204 / 网络异常 4 种状态。
- `FamilyPackService`（`services/FamilyPackService.ets`）— 家长设备 token 鉴权 ETag 客户端，prefs slot `wordmagic_family_packs`，处理 200 / 304 / 401 / 410（家长解绑）等状态。
- `PackLibrary`（`services/PackLibrary.ets`）— builtin / global / family 三层 union，覆盖优先级 family > global > builtin（同 id），scene fallback：自身非空 → 同 id builtin → 哈希调色板。
- `PackSelectionService`（`services/PackSelectionService.ets`）— 设备级最多 5 包 + pin + perfect-rotation，prefs slot `wordmagic_pack_selection`。3 次完美战斗后未 pin 的 active 包自动换入下一个候选（family > global > builtin，按 publishedAt DESC + id ASC），pinned 包永不轮换。
- `PackNetworkFetchAdapter`（V0.6.5.1，`services/PackNetworkFetchAdapter.ets`）— 给 GlobalPackService / FamilyPackService 用的 NetworkKit 适配器，支持 HEAD 请求 + ETag 捕获 + preview deployment 的 bypass header 注入。
- `PackHomeIntegration`（V0.6.5.1，`services/PackHomeIntegration.ets`）— 共享给 HomePage / ConfigPage 的 helper：`HomeIntegrationBundle`（PackLibrary + PackSelectionService）、`loadHomeIntegration(ctx)`（一次性冷启动）、`resolveActivePacks(bundle)`、`fallbackPackFromRegion(region)` / `fallbackPacks()`（无 pack 兜底用 AdventureCatalog 合成）、`LibraryCandidateProvider`（perfect-rotation 候选源）。
- `WordPackBootstrapper.bootstrapPackLibrary(ctx)`（V0.6.5.1）— 冷启动从 prefs 缓存重建 PackLibrary，不发网络；网络刷新由 PackManagerPage「🔄 同步词包」按钮显式触发。
- `TodayAdventureBuilder.buildFromPack(pack, recorder, nowMs, isFirstToday)`（V0.6.5.1）— 直接从 `Pack` 合成 `AdventureRegion` + `WordRepository`，再调用旧 `build()` 算法生成 `TodaySessionPlan`。

**UI 集成**（V0.6.5.1 完成）：

- HomePage：`@State chipPacks: Pack[]` + `@State todayPack: Pack`，`onPageShow` 在 V0.6.7.4 改成每次重新跑 `loadHomeIntegration(ctxShow)` 再 `applyActivePacks()` —— PackManagerPage 修改 `selection` 用的是它自己 `loadHomeIntegration` 出来的另一个 `PackSelectionService` 实例，不重载就看不到改动。chip 文案在 V0.6.7.5 改为 `packChipLabel(p)` 只看 `p.name` → `p.id` 兜底（统一英文，与 PackManagerPage 一致）；标题 `AdventureCardTitle` 同步改成直接 `region.displayName`（即 `pack.name`）。点 chip 即切换今日冒险词源；进入战斗前把 `todayPack` 写入 AppStorage `TODAY_ACTIVE_PACK_KEY`。
- ConfigPage：新增「📦 我的词包」picker section，渲染所有可用 pack（builtin / global / family），勾选 ✓ 激活 / 📌 pin / 🔄 同步全局 + 家庭包；最多 5 个激活，超出弹 toast。
- BattlePage：today 模式优先读 `TODAY_ACTIVE_PACK_KEY` 中的 `Pack.words` 作为 `bundleRepo`，缺失则回退全局 rawfile repo；3 ⭐ 完美战斗触发 `PackSelectionService.recordPerfectAdventure(activePack, LibraryCandidateProvider)`。

**V0.6.6 清理**：删除 `GameConfig.enabledCategories` / `customWordsRaw` / `KNOWN_CATEGORIES` / `CUSTOM_CATEGORY_KEY` / `parseCustomWords` / `computeFinalPool`，下线 `pages/CustomWordsPage`，BattlePage 在 normal / review 模式 universe 改用 `repo.all()`。Pack picker 成为唯一词源选择入口。

---

## 4. 游戏规则

### 4.1 战斗参数（默认 / 可配置上下界）

| 项目        | 默认                           | 可配范围 / 备注                                          |
| --------- | ---------------------------- | -------------------------------------------------- |
| 玩家 HP     | **10**（V0.8.4；此前为 5）        | 1 – 10（ConfigPage 步进）；已保存配置不自动迁移                    |
| 怪物 HP     | 3                            | 1 – 10                                             |
| 单局怪物数     | 5                            | 1 – 10                                             |
| 单局倒计时     | 300 s                        | 来自 `TIMER_CHOICES = [3, 15, 30, 60, 120, 300, 600]` |
| 每次正确伤害    | 1                            | 固定                                                 |
| 连击奖励      | 连续答对 3 题 → 当次伤害 2，触发"魔法爆发"反馈 | 固定；暴击视听见 §4.4                                      |
| 失败条件      | 玩家 HP = 0 或倒计时归零             | 任一即结束                                              |
| 胜利条件      | 怪物全数被击败                      |                                                    |
| 选项数量（MCQ） | 3                            | `QuestionGenerator.MIN_REPO_SIZE = 3`              |

> 默认值与 `harmonyos/entry/src/main/ets/models/GameConfig.ets`、`BattleEngine.ets` 中的常量保持一致，单测 `defaultsMatchEngineDefaults` 守住一致性。

### 4.2 答题循环

1. BattlePage `aboutToAppear` 根据 `GameConfig.mode` / `TodaySessionPlan` 构造对应的 `IQuestionSource`。
2. `BattleEngine.start()` 创建初始 `BattleState` 并产出第一题。
3. UI 渲染中文提示、题型对应控件（MCQ / FillLetter / Spell）、双方 HP、当前怪序号、剩余时间。
4. 用户提交答案 → `BattleEngine.submitAnswer(option)` 返回 `AnswerOutcome`：
   - 正确：`comboCount += 1`；当次伤害 = `comboTriggered ? 2 : 1`；扣怪 HP；记录学习数据。
   - 错误：`comboCount = 0`，玩家 HP -1，短暂显示正确答案。
   - **V0.8.4 — `Spell` 多字母选择：** 在拼完整个词之前，每点错一个字母池字母也 **-1 HP**（不经过 `submitAnswer`，不推进题目）；拼对后仍走正常 `submitAnswer` 对怪扣血。
5. 怪物 HP = 0 时 `defeatedMonsters += 1`，未达 `monstersTotal` 则推下一只。
6. 任一终止条件成立时 `engine.buildSessionResult()` → `BattlePage.navigateToResult()` → `replaceUrl('pages/ResultPage')`。

### 4.3 题型矩阵

| 题型枚举                      | 何时出现                  | 控件                                              |
| ------------------------- | --------------------- | ----------------------------------------------- |
| `Choice`                  | 普通槽 / 复习槽 / 兜底        | 三个 `ChoiceButton`                               |
| `FillLetter`              | Spelling 槽位（缺 1 个字母）  | 字母模板 + 三个字母 `ChoiceButton`                      |
| `FillLetterMedium`        | Elite 槽位（缺 2 个字母，两步）  | 字母模板 + 三个字母 `ChoiceButton`，分两步                  |
| `Spell`                   | Boss 槽位 / V0.8.4 challenge 池 | `SpellingArea`：从打乱字母池里按序点齐；**V0.8.4** 错点字母每次扣 1 HP |

**题型调度（V0.8.4 今日冒险 / `PlanQuestionSource`）：** 与 `GameConfig.enabledQuestionTypes` 求交，开局判定 schedule mode：

| Mode | 条件 | 行为 |
| --- | --- | --- |
| `single_type` | 只启用 1 种 | 100% 该题型 |
| `intro_only` | 只启用 Intro 类 | 整局 Intro；Intro pass 后 intro sustain，**无** Challenge |
| `challenge_only` | 只启用 Challenge 类 | 从第 1 题起 Challenge，**跳过** Intro |
| `two_phase` | 两类都有 | Intro pass（每词已启用轻题型各最多 1 次）→ Challenge（重题型 50/50 或 100%） |

Intro 类 = `choice` + `fill-letter`；Challenge 类 = `fill-letter-medium` + `spell`。

V0.8.3 的 `MonsterLevel` 仍决定 bonus ✨ 与重击，但 **不再** 作为今日战斗的出题依据（见 [`2026-05-18-battle-balance-v0-8-4/00-design.md`](features/2026-05-18-battle-balance-v0-8-4/00-design.md) §6.3）。

**历史（V0.8.3 之前）：** `PlanQuestionSource` 按怪物槽位 / `MonsterKind` 映射题型链，词库不够时降级到下一档。

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

### 5.1 词库来源（V0.6.6）

`PackLibrary` 在冷启动时从三层来源 union：

1. **built-in rawfiles**：`harmonyos/entry/src/main/resources/rawfile/data/builtin/{fruit-forest,school-castle,home-cottage,animal-safari,ocean-realm}.json`（每包独立 + scene 元数据）。这是离线兜底，App 安装即可用。
2. **global pack 缓存**：`@ohos.data.preferences/wordmagic_global_packs`，由 `GlobalPackService` 从 `/api/v1/public/global-packs/latest.json` 拉取（匿名 ETag）。
3. **family pack 缓存**：`@ohos.data.preferences/wordmagic_family_packs`，由 `FamilyPackService` 从 `/api/v1/family/{family_id}/family-packs/latest.json` 拉取（家长设备 token 鉴权）。

union 后覆盖优先级是 family > global > builtin（同 id 时高优先级覆盖低优先级）；scene fallback 顺序是「自身非空 → 同 id builtin → 哈希调色板」。

**今日冒险战斗池**：HomePage 在进入战斗前把当前 active `Pack`（PackSelectionService 的"今日选中包"）写入 AppStorage `TODAY_ACTIVE_PACK_KEY`；BattlePage 直接消费 `Pack.words` 作为 `bundleRepo`，PlanQuestionSource 由此能解析 plan 里的所有 wordId。
**普通 / 复习模式战斗池**：直接用 `WordRepository.all()`（built-in rawfile 仓）。V0.6.6 起没有 category filter / custom words 拼接环节。

**远端老词包缓存**（`WordPackCache.read()`，namespace `word_pack_cache`）仍保留，是 V0.5 时代的全局 schema-versioned 词包格式，由 `WordPackBootstrapper.bootstrap()` 在 app 启动期通过 `RemoteWordPackService` / `WordPackSyncService` 后台刷新。V0.6.7 起这条链路**没有 UI 触发入口**（原 ConfigPage 的「词库同步」行已下线）；当前版本它仅替换 BuiltinPackLoader 的 word entry 字段（rich metadata 注入），不影响 PackLibrary 的 union 结果。

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

V0.6.6 起类目仅作为 `WordEntry.category` 元数据 + 内置 pack id 的呼应字段使用，不再驱动战斗池筛选（pack picker 已经替代了这件事）：

| Category id | 中文标签（默认）| 关联内置 Pack |
| ----------- | ----------- | -------- |
| `fruit`     | 水果         | `fruit-forest` |
| `place`     | 日常地点     | `school-castle` |
| `home`      | 家居物品     | `home-cottage` |
| `animal`    | 动物         | `animal-safari` |
| `ocean`     | 海洋         | `ocean-realm` |

`custom` 类目已下线（曾用于 free-play 战斗池）。服务端发布的词包若 `schema_version >= 4` 仍会带 `categories[]`，包含 `id / label_en / label_zh / story_zh / source_image_url`；客户端 `CategoryCatalog` 用作覆写：HomePage 的区域副标题与故事文本优先取服务端值，否则回退到设备端 `AdventureCatalog`。

### 5.4 题目生成原则

- 正确答案来自当前题目的 `word`。
- 提示用 `meaningZh`（中文释义）。
- 干扰项策略：服务端 `distractors` 字段 > 同类目同难度同步随机 > 全局兜底；同题三个选项不重复且包含答案。
- 不连续两题命中同一正确单词（`QuestionGenerator` 维护 `lastAnswerWordId`）。
- 词库不足以生成 3 个独特选项时，降级到全局补足而不是抛错。

---

## 6. 信息架构

### 6.1 路由表

`harmonyos/entry/src/main/resources/base/profile/main_pages.json` 注册了 **17** 个页面（顺序）：

```
pages/HomePage              入口
pages/BattlePage            战斗
pages/ResultPage            结算
pages/ConfigPage            设置（「我的词包」入口行 → PackManagerPage）
pages/WishlistPage          愿望单
pages/MonsterCodexPage      怪物图鉴
pages/ParentPinSetupPage    家长 PIN 设置 / 修改
pages/RedemptionHistoryPage 兑换历史
pages/TodayPlanPage         今日学习计划预览
pages/LearningReportPage    学习报告（按 pack 分组，V0.6.7.8）
pages/ParentAdminPage       家长管理后台（V0.5.8 重命名，设备端竖屏入口）
pages/LessonDraftReviewPage V0.5.8 课本图复核页
pages/BypassSecretPage      preview bypass token（debug）
pages/ScanBindingPage       V0.6 扫码 / 相册 QR 绑定
pages/BoundDeviceInfoPage   V0.6 已绑定设备信息 / 服务端解绑
pages/DevMenuPage           debug 后端环境切换
pages/PackManagerPage       V0.6.7 词包管理（激活 / pin / 同步词包）
```

> V0.6.6 删除了 `pages/CustomWordsPage`（曾经的「自定义词列表编辑」页）；旧设备 AppStorage 中遗留的 `customWordsRaw` 字段在 `cloneGameConfig` / `gameConfigFromJson` rehydrate 时被静默忽略。

### 6.2 页面流

```text
HomePage ─┬─ HomeStartButton (todayPack) ─→ BattlePage(today, AppStorage TODAY_ACTIVE_PACK_KEY) ─→ ResultPage ─┬─ HomePage
          │                                                                                                   └─ WishlistPage
          ├─ pack chip row（PackSelectionService.getActiveIds → PackLibrary）
          │     └─ 点击 chip 即切换 todayPack（不直接发请求）
          ├─ HomeReviewButton ─→ BattlePage(review) ─→ ResultPage ─→ HomePage / BattlePage
          ├─ HomeCodexButton ─→ MonsterCodexPage
          ├─ HomePlanButton  ─→ TodayPlanPage ─→ LearningReportPage
          ├─ HomeWishlistButton ─→ WishlistPage ─┬─ +添加 / ✕（PIN）─→ AddCustomWishDialog
          │                                       ├─ 申请兑换（PIN）─→ GiftBox 模态
          │                                       └─ 📜 历史 ─→ RedemptionHistoryPage
          └─ HomeConfigButton ─→ ConfigPage ─┬─ 📦 我的词包 ─→ PackManagerPage（5 ✓ + 📌 pin + Toggle 开关 + 🔄 同步词包）
                                              │     └─ 🔄 同步：GlobalPackService + FamilyPackService 并行 ensureLatest
                                              ├─ 家长密码 ─→ ParentPinSetupPage
                                              ├─ 学习记录立即同步（CloudSync，仅在已绑定家长账号时显示）
                                              ├─ 家长账户：未绑定 ─→ ScanBindingPage / 已绑定 ─→ BoundDeviceInfoPage（孩子档案 + 解除设备绑定 PIN→/child/unbind）
                                              └─ 家长管理后台（PIN）─→ ParentAdminPage ─┬─ 📷拍照 / 🖼️从相册 ─→ /lessons/import ─→ LessonDraftReviewPage
                                                                                       ├─ 待复核草稿列表 ─→ LessonDraftReviewPage
                                                                                       └─ 一键发布词包 ─→ /api/v1/admin/packs/publish
```

> V0.5.8 起 ParentAdminPage 进入即锁定竖屏（`window.setPreferredOrientation` PORTRAIT），离开时恢复 AUTO_ROTATION_LANDSCAPE；LessonDraftReviewPage 复用同一竖屏，让 ParentAdminPage 在 back-pop 时统一恢复横屏。

### 6.3 各页职责（高层）

| 页面                  | 主要职责                                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| HomePage            | 主入口；展示金币 / 复习 / 图鉴 / 计划 / 愿望单 / 设置六颗工具栏按钮 + 大尺寸 AdventureCard + 三层词包驱动的 chip row（每个 chip 是一个 active `Pack`）+ HomeStartButton。冷启动调 `loadHomeIntegration` 把 `PackLibrary` + `PackSelectionService` 拉起来；进入战斗前把 `todayPack` 写入 AppStorage `TODAY_ACTIVE_PACK_KEY`。 |
| BattlePage          | 战斗主舞台。处理三种题型、HP / 倒计时 / 连击 / 暴击视听 / 反馈、动画、音效。Today 模式下 `bundleRepo` 由 `TODAY_ACTIVE_PACK_KEY` 中的 `Pack.words` 直接构造；3 ⭐ 完美战斗触发 `PackSelectionService.recordPerfectAdventure` 自动轮换非 pinned 包。 |
| ResultPage          | 单局总结（胜负标题 + 三星 + 击破/正确率/学习词数 + 今日模式专属的 +N ✨ 与累计余额）。                                            |
| ConfigPage          | 战斗参数（HP / 怪物数 / 倒计时） + 自动发音开关 + 「我的词包」入口行（`ConfigPackManagerEntry` → PackManagerPage，V0.6.7）+ 家长 PIN + 家长账户绑定 + 家长管理后台入口。V0.6.7.1 起无独立「词库同步」行。 |
| PackManagerPage     | V0.6.7：三层词包列表；Toggle 激活（最多 5）+ 📌 固定 + 顶部 `🔄 同步词包`（global + family 并行 `ensureLatest`）。HomePage chip row 在 `onPageShow` 重载 selection（V0.6.7.4）。 |
| WishlistPage        | 愿望卡片列表（默认 + 自定义）；显示余额；申请兑换 / 添加 / 删除均经家长 PIN；兑换成功展示 GiftBox 模态。                                |
| RedemptionHistoryPage | 倒序展示 `RedemptionRecord` 列表，最多 50 条滚动保留。                                                          |
| MonsterCodexPage    | 横向翻页查看 `MONSTER_CODEX` 中所有怪物 / boss 立绘 + 描述。                                                     |
| TodayPlanPage       | 只读预览今日 10 个词的"复习 / 学习中 / 新词"分桶 + 完成进度（每个 wordId 一行）。                                            |
| LearningReportPage  | 全量统计：总正确率、四态计数（掌握 / 熟悉 / 学习中 / 新词）、今日复习完成率，以及按词包（pack）分组的正确率行（V0.4.5 按 category 分组；V0.6.7.8 重写为按 pack 分组以匹配三层词包模型，活跃包按选择顺序在前、未激活但有作答的包按正确率升序在后）。 |
| ParentPinSetupPage  | 6 位 PIN 两步一致校验，写回 `GameConfig.parentPin`。                                                        |
| ParentAdminPage     | V0.5.8 家长管理后台（PIN 闸后入）：竖屏概览（用户数 / 词条数 / 类别数 / 已发布版本数 / 最新版本 / 待审 LLM 草稿 / 待审课本图）；📷 拍照 / 🖼️ 从相册导入课本图；待复核草稿列表；一键发布新词包。**已下线 JWT 登录卡片**，V0.6 以家长账户做数据隔离。 |
| LessonDraftReviewPage | V0.5.8 课本单词复核页（PIN 后续传）：展示原图 + 可改主题标签 + 候选词列表（保留 / 编辑 / 弃用），编辑弹窗校验非空 trim，"全部确认"先 PATCH 再 /approve、"全部拒绝" /reject；409 ALREADY_REVIEWED 自动 back。 |

---

## 7. 系统架构（四模块）

### 7.0 Monorepo 模块边界

当前仓库根目录是产品 monorepo，而不是某一个客户端工程根。四个一等模块职责如下：

| 模块 | 当前状态 | 技术方向 | 职责边界 |
| ---- | -------- | -------- | -------- |
| `harmonyos/` | 已实现（权威参考） | HarmonyOS NEXT / ArkTS / ArkUI | 17 页运行时 + ohosTest；产品功能线 V0.6.7.8，`app.json5` **0.7.0**。 |
| `ios/` | 已实现（bootstrap parity） | Native Swift / SwiftUI | `ios/WordMagicGame/`；17 页与 Harmony 对齐；见 `docs/ios-replica/00-index.md`。 |
| `android/` | 已实现（bootstrap parity） | Native Kotlin / Jetpack Compose | `android/` 全页落地；见 `docs/android-replica/00-index.md`。 |
| `server/` | 已实现 | Python / FastAPI / MongoDB / Vercel | 词库、词包、家长账户、设备绑定、**V0.8.1** 家长词库 Web、**V0.8.2** `/admin/` HTML 控制台、OAuth、LLM 草稿与发布。 |

`shared/` 是辅助契约目录，只能放 OpenAPI、JSON Schema、错误码、同步协议和 golden fixtures；不得放会被三端直接 import 的客户端运行时代码。跨端一致性通过契约测试和 fixtures 维持，而不是通过共享 UI / 业务 SDK 维持。

`shared/contracts/` is the contract checkpoint for API shape, sync protocols, and error semantics. A server API change is not cross-client-ready until the generated OpenAPI snapshot and the relevant domain/protocol docs have been updated.

### 7.0.1 iOS / Android（bootstrap）

- **iOS**：`ios/project.yml` + XcodeGen；领域逻辑在 `ios/WordMagicGame/`（Swift）；XCTest / XCUITest；发布清单 [`ios/release-pre.md`](../ios/release-pre.md)。
- **Android**：Gradle 工程 `android/`；Compose UI + JVM / instrumented tests；发布硬化 [`docs/android-replica/07-release-readiness-checklist.md`](android-replica/07-release-readiness-checklist.md)。
- **Parity 边界**：bootstrap 不含 V0.9 句子填词、V0.10 战斗 BGM、V0.11 Cocos；学习报告仍为 **device-local**（未上云按 pack 聚合）。

### 7.1 HarmonyOS 客户端架构原则

- 页面只负责渲染 + 路由 + 用户输入；规则全部进 `models/` + `services/`。
- AppStorage 只放跨页临时 handoff（GameConfig、TodaySessionPlan、TodayLastCompletedDayKey、TodayRegionId）。V0.5.8 起 ParentAdminPage 不再写 admin_jwt，待 V0.6 家长账户重新接入。
- 持久化数据全部走 `@ohos.data.preferences`，每个领域一个 namespace（见 §9 表）。
- 网络访问全部经 `RemoteWordPackService` / `ParentApiClient` 两个 facade，UI 不直接调用 `@kit.NetworkKit`。`ParentApiClient`（V0.5.8 重命名自 `AdminApiClient`，去掉 JWT 头）额外暴露 `importLesson(PickedImage)` 走 `multipart/form-data` 上传。
- 主线 UI 路径必须在没有网络、没有缓存、没有家长 PIN 的情况下也能跑（rawfile 兜底）。

### 7.2 HarmonyOS 目录结构（实际）

```text
harmonyos/entry/src/main/ets/
  pages/                                    17 个页面（见 §6.1）
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
    Pack.ets                                V0.6.5：Pack + SceneMetadata
  services/                                 见 §10
    BuiltinPackLoader.ets                   V0.6.5：5 个 per-pack rawfile 加载器
    GlobalPackService.ets                   V0.6.5：匿名 ETag 客户端 + prefs 缓存
    FamilyPackService.ets                   V0.6 / V0.6.5：家长设备 token ETag 客户端
    PackLibrary.ets                         V0.6.5：三层 union + scene fallback
    PackSelectionService.ets                V0.6.5：设备级最多 5 包 + pin + perfect-rotation
    PackNetworkFetchAdapter.ets             V0.6.5.1：HEAD/ETag/Bypass header 适配
    PackHomeIntegration.ets                 V0.6.5.1：HomePage / ConfigPage 共享 helper
  data/
    AdventureCatalog.ets                    5 个区域元数据（pack picker 兜底）
    MonsterCatalog.ets                      10 个怪物 / boss 元数据
    CharacterAssets.ets                     角色 → svg 路径
harmonyos/entry/src/main/resources/
  rawfile/
    data/builtin/                           V0.6.5：5 个 per-pack JSON + scene 元数据
      fruit-forest.json
      school-castle.json
      home-cottage.json
      animal-safari.json
      ocean-realm.json
    data/words_v1.json                      内置词库（V0.5 同步链路兜底，保留）
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

仅列对外/跨页暴露的字段。完整签名见 `harmonyos/entry/src/main/ets/models/`。

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
  autoSpeak = true;
  mode = 'normal';   // 'normal' | 'review' | 'today'
  parentPin = '';    // 空字符串 = 未配置
}
```

> V0.6.6 删除了 `enabledCategories` / `customWordsRaw`：词源选择已经由 `PackSelectionService`（设备级 prefs）独立承担，GameConfig 退化为纯战斗参数容器。

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
| GameConfig | `wordmagic_game_config_v1`     | `game_config_json`    | 战斗参数 + autoSpeak + mode + parentPin（V0.6.6 起不再含 enabledCategories / customWordsRaw） |
| 魔法币       | `wordmagic_coins`               | `snapshot_v1`         | `CoinSnapshot` (JSON)      |
| 学习记录     | `wordmagic_learning`            | `snapshot_v1`         | `LearningSnapshot` (JSON)  |
| 愿望单       | `wordmagic_wishlist`            | `snapshot_v1`         | `WishlistSnapshot` (JSON)  |
| 兑换历史     | `wordmagic_redemption_history`  | `snapshot_v1`         | `RedemptionHistorySnapshot` |
| 今日设置     | `today_settings`                | `region_id`           | 选中的区域 id（pack picker 兜底用）  |
| 服务端词包缓存（旧）| `word_pack_cache`             | `pack_v2`             | `{ body, etag, schemaVersion, fetchedAt }`（V0.5 链路） |
| Global packs 缓存 | `wordmagic_global_packs`   | `global_packs_blob`   | `{ packs[], etag, fetchedAt }`（V0.6.5） |
| Family packs 缓存 | `wordmagic_family_packs`   | `family_packs_blob`   | `{ packs[], etag, fetchedAt }`（V0.6 + V0.6.5） |
| Pack selection | `wordmagic_pack_selection`    | `selection_v1`        | `{ activeIds[], pinnedIds[], perfectCount }`（V0.6.5） |
| 家长账户绑定（设备 token + family_id + nickname） | `wordmagic_cloud_creds`      | `creds_v1` | V0.6 引入；V0.6.4 引入 deviceIdSource 字段 |

所有领域写入都用 100 ms 去抖 + fire-and-forget；进入 ResultPage / 退出战斗等关键节点显式 `flushNow()`。

### 9.2 AppStorage（跨页 handoff）

| Key                          | 值                  | 写入方                                | 读取方                               |
| ---------------------------- | ------------------ | ---------------------------------- | --------------------------------- |
| `gameConfig`                 | `GameConfig`       | ConfigPage / ParentPinSetupPage    | HomePage / BattlePage / WishlistPage |
| `todayPlan`                  | `TodaySessionPlan` | HomePage（点击 HomeStartButton）       | BattlePage                        |
| `todayActivePack`            | `Pack`             | HomePage（V0.6.5.1，点击 HomeStartButton） | BattlePage（V0.6.5.1 today bundleRepo 来源） |
| `todayLastCompletedDayKey`   | `YYYY-MM-DD`       | BattlePage（applyTodayAdventureRewards） | HomePage（已完成徽章）              |
| `todayRegionId`              | 区域 id              | HomePage（pack chip 切换） | HomePage（pack picker 兜底） |
| `serverBaseUrlOverride`      | http URL           | ohosTest `List.test.ets`、DevMenuPage  | `effectiveServerBaseUrl()`         |

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
| `TodayAdventureBuilder`  | `build(region, repo, recorder, nowMs, isFirstToday) → TodaySessionPlan` + `buildFromPack(pack, recorder, nowMs, isFirstToday) → TodaySessionPlan`（V0.6.5.1） | 主算法见 §11                      |
| `TodayPlanService`       | `build()`                                                               | TodayPlanPage 的只读视图模型         |
| `LearningReportBuilder`  | `build(library, activeIds, recorder, nowMs)`                            | LearningReportPage 的只读视图模型；V0.6.7.8 改为接受 `PackLibrary` + `activeIds`，输出按词包分组的 `PackReport[]` 替代旧的 `CategoryReport[]` |

### 10.4 服务端协同（V0.5）

| 模块                       | 公开 API                                                                                | 职责                                     |
| ------------------------ | ------------------------------------------------------------------------------------- | -------------------------------------- |
| `RemoteWordPackConfig`   | `SERVER_BASE_URL`、`pickServerBaseUrl()`、`latestPackUrl()`、`effectiveServerBaseUrl()`、`SERVER_BASE_URL_OVERRIDE_KEY` | 默认 `https://happyword.cool`；ohosTest 通过 AppStorage `serverBaseUrlOverride` 注入 mock 地址（V0.5.8） |
| `RemoteWordPackService`  | `fetchLatest(url, ifNoneMatch?)`                                                      | HTTP GET + ETag                        |
| `WordPackCache`          | `init() / read() / readRecord() / write() / writeRecord() / touchFetchedAt()`         | 词包本地缓存 + ETag                          |
| `WordPackBootstrapper`   | static `forContext(ctx)` + `bootstrap()` + `bootstrapPackLibrary(ctx)`（V0.6.5.1） | 冷启动：cache 优先，fallback rawfile，**不发网络**；`bootstrapPackLibrary` 用 BuiltinPackLoader + GlobalPackService / FamilyPackService 的 prefs 缓存重建 PackLibrary |
| `WordPackSyncService`    | `syncOnce()`                                                                          | ConfigPage「立即同步」按钮的 V0.5 链路；返回 outcome 枚举 + 拒收最小词数判断 |
| `RemoteAssetCache`       | static `forContext(ctx)` + `resolve(url, kind)`                                       | 远端图片 / 音频的设备端 LRU                      |
| `CategoryCatalog`        | `setRows() / getById() / size()`                                                      | 服务端 categories 覆写                      |
| `ParentApiClient`        | `withRealHttp(baseUrl)` + `getStats() / listPacks() / publishPack(notes?)` + V0.5.8 课本流：`importLesson(PickedImage) / getLessonDraft(id) / patchLessonDraft(id, edited) / approveLessonDraft(id) / rejectLessonDraft(id) / listPendingLessonDrafts(page, size)` | 家长管理后台 HTTP，无 JWT 头（V0.5.8） |
| `LessonImagePicker`      | `pickFromGallery() / pickFromCamera()`                                                | 包装 `picker.PhotoViewPicker` + `cameraPicker.pick`，按扩展名嗅 MIME，返回 `PickedImage` 或 `null`（用户取消 / 不支持类型） |
| `MultipartBuilder`       | `buildSingleImageMultipart(field, filename, mime, bytes)` + `escapeFilename(name)`    | RFC-7578 单图片上传体，逐字符替换 `"` / CR / LF 防头注入 |
| `orientation` 工具         | `lockPortrait(adapter) / restoreAutoLandscape(adapter)`                                | 包 `window.setPreferredOrientation`，给 ParentAdminPage / LessonDraftReviewPage 用 |

### 10.5 三层词包模型（V0.6.5 → V0.6.6）

| 模块 | 公开 API | 职责 |
| ---- | ------- | ---- |
| `BuiltinPackLoader` | `loadAll(ctx) → Pack[]` + `parsePackJson(json, packId) → Pack`（test only） | 读取 5 个 per-pack rawfile 并合成内置 `Pack[]` |
| `GlobalPackService` | `init(ctx)` + `ensureLatest() → GlobalPackEnsureResult` + `cachedPacks() → Pack[]` + 静态 `parsePacks(blob)` | 匿名 ETag 客户端；输出 `{ status, packs }`，状态枚举 `updated`/`up-to-date`/`http-error`/`network-error`；prefs slot `wordmagic_global_packs` |
| `FamilyPackService` | `init(ctx)` + `ensureLatest(deviceToken) → FamilyPackEnsureResult` + `cachedBlob() → FamilyPacksBlob` | 家长设备 token ETag 客户端；状态枚举 `updated`/`up-to-date`/`cleared`/`401`/`network-error`；prefs slot `wordmagic_family_packs` |
| `PackLibrary` | `setBuiltin(packs[]) / setGlobal(packs[]) / setFamily(packs[])` + `allPacks() / findById(id) / packsForIds(ids[])` | 三层 union + 覆盖优先级 family > global > builtin + scene fallback |
| `PackSelectionService` | `init(ctx, library)` + `getActiveIds() / setActiveIds(ids[])` + `pinnedIdsList() / togglePin(id)` + `recordPerfectAdventure(activePack, candidateProvider)` | 设备级最多 5 包 + pin + perfect-rotation；prefs slot `wordmagic_pack_selection` |
| `PackNetworkFetchAdapter`（V0.6.5.1） | `get(url, headers) / head(url, headers)` + `lastResponseHeader(name)` | NetworkKit 适配器；ETag 捕获 + preview deployment 的 `x-vercel-protection-bypass` 注入 |
| `PackHomeIntegration`（V0.6.5.1） | `loadHomeIntegration(ctx) → HomeIntegrationBundle` + `resolveActivePacks(bundle) → Pack[]` + `fallbackPackFromRegion(region) / fallbackPacks() / LibraryCandidateProvider` | HomePage / ConfigPage / BattlePage 共享；冷启动 + 兜底 + perfect-rotation 候选源 |

> 同步流程见 §13.5。冷启动绝不发网络（`bootstrapPackLibrary` 只读 prefs 缓存）；网络刷新由 PackManagerPage 顶部「🔄 同步词包」按钮显式触发。

---

## 11. 今日冒险算法

### 11.1 Plan 构建

入口（V0.6.5.1 起）：`HomePage.enterTodayAdventure()` 优先用 `TodayAdventureBuilder.buildFromPack(activePack, recorder, nowMs, isFirstToday)`；`Pack` 缺失时回退到旧路径 `TodayAdventureBuilder.build(region, repo, recorder, nowMs, isFirstToday)`。

`buildFromPack` 内部的步骤：

1. 从 `Pack.scene` 合成一个临时 `AdventureRegion`（`bgPrimary` / `bgAccent` / `bossName` / `bossCandidates` / `monsterPlan` 全来自 scene，`themeWordCategories = [pack.id]`）。
2. 从 `Pack.words` 直接构造一个 `WordRepository`。
3. 调用旧 `build()` 算法，下面的步骤完全一致：
   - `MonsterPlan` 模板从 `region.monsterPlan.slots` 复制，长度恒为 `MONSTER_PLAN_SLOT_COUNT = 5`，模板是 Normal → Spelling → Review → Elite → Boss。
   - **Boss 轮换**：`hashDjb2('${region.id}:${localDayKey(nowMs)}') mod region.bossCandidates.length` → 选定当日 boss → 写回最后一槽的 `catalogIndex`。同区同日总是同一 boss。
   - **Word slot 数**：`MONSTER_PLAN_SLOT_COUNT * WORD_PLAN_MULTIPLIER = 5 × 2 = 10` 个。
   - **Word 分桶**：按 `MemoryScheduler.classify` 分 Review / Learning / New 三桶；目标比例 ≈ **5 复习 / 3 学习中 / 2 新词**，桶不够就轮转后续桶。
   - **Boss words**：`pickBossWords(plan, 2)` 优先取 review + learning 中难度高的，不够则取最难的 new；写入 `plan.bossWordIds`，BattlePage 走到 boss 槽位时 `PlanQuestionSource` 优先吐这两个。
4. **isFirstToday**：HomePage 入战前从 `CoinAccount.todayAdventureCompleted()` 反推。

HomePage 在生成 plan 后会同时把 `plan` 写到 AppStorage `todayPlan`，把 `activePack` 写到 `todayActivePack`，这样 BattlePage 不需要 PackLibrary 也能直接构造 bundleRepo。

### 11.2 区域目录

`harmonyos/entry/src/main/ets/data/AdventureCatalog.ets` 中的 5 个区域：

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

| Router 文件 | Prefix | 路由（摘要） |
| --- | --- | --- |
| `auth.py` | `/api/v1/admin/auth` | `POST /login` / `GET /me` |
| `public_packs.py` | `/api/v1/public` | `GET /health` / `GET /preview-urls.json` / `GET /packs/latest.json` |
| `public_global_packs.py`（V0.6.5） | `/api/v1/public/global-packs` | `GET/HEAD /latest.json`（匿名，ETag/304） |
| `pair.py` | `/api/v1/family` + `/api/v1/public` + `/p` | cookie：`/{family_id}/pair/create|status|...`；匿名：`POST /pair/redeem`（挂载在 `/api/v1/public`）；落地页 `GET /p/{token_short}` |
| `parent_auth.py` / `parent_api.py` / `parent_inbox.py`（JSON） | `/api/v1/family` | `/{family_id}/auth/*`、`/{family_id}/devices`、`/{family_id}/children/*`、`/{family_id}/wishlist-items/*`、`/{family_id}/redemption-requests/*`、`/{family_id}/inbox/*` 等 |
| `parent_account.py`（JSON + HTML） | `/api/v1/family` + `/family` | `/{family_id}/account/*` JSON；`/family/{family_id}/account` 设置页 |
| `parent_family_pack.py` | `/api/v1/family` | `/{family_id}/family-packs/**`（CRUD / draft / publish / import-image / batch-upsert） |
| `child_family_pack.py` / `child_word_stats.py` / `child_wishlist.py` / `child_profile.py` | `/api/v1/family` | device token：`/{family_id}/family-packs/latest.json`、`/{family_id}/packs/latest.json`、`/{family_id}/word-stats/*`、`/{family_id}/wishlist/*`、`/{family_id}/redemption-requests/*`、`/{family_id}/profile`、`/{family_id}/unbind` |
| `parent_pages.py` / `parent_inbox.py`（HTML） / `parent_packs_pages.py`（V0.8.1） | `/family` | **`GET /family/login`** 为家长登录规范入口（邮箱 OTP + OAuth）。`/family/{family_id}/packs/**`：词库工作台（列表 / 草稿 / 发布 / 回滚 / 图片导入 / 批量粘贴）。其余 `/family/{family_id}/**`：设备绑定、兑换审批、inbox 等 |
| `admin_pages.py`（V0.8.2） | `/admin` | HTML 系统管理员控制台：登录会话 cookie、家长/设备/全局词包/家庭词包/审计日志/反馈等；高风险操作写 `AuditLog`（`admin_audit_service.record_admin_action`） |
| `oauth_google.py`（V0.6.8） | `/v1/oauth/google` | `GET /start` / `GET /callback`（canonical 生产）/ `GET /finish`（Preview ticket）。详见 `.cursor/rules/api-route-pattern.mdc` |
| `admin_*.py` 系列（JSON） | `/api/v1/admin/**` | 词 / 词包 / 类目 / LLM / lesson import / cron / stats 等 **遗留 JSON 自动化面**；人工运维优先 V0.8.2 `/admin/` HTML |

> **鉴权分层**：`/api/v1/family/{family_id}/**` 与家长 Web 使用家长 session / 设备 Bearer；**V0.8.2** `/admin/*` HTML 使用管理员 session cookie。设备端 `ParentAdminPage` 仍调用部分 **JSON** `/api/v1/admin/*`（stats / publish 等）——与 V0.5.8 行为一致；新系统级运维应使用 `/admin/` 控制台。JSON `admin_*` 的 `current_admin_user` 硬化为后续项。

> **兼容性别名层**：V0.6.5 曾通过 `legacy_route_aliases` 暴露旧 `/api/v1/family/{family_id}/**`、`/api/v1/family/{family_id}/**`、裸 `/api/v1/public/health` 等路径；**现已移除**。文档与客户端应以 `/api/v1/public/**`、`/api/v1/admin/**`、`/api/v1/family/{family_id}/**`、`/family/{family_id}/**` 为准（见 `.cursor/rules/api-route-pattern.mdc`）。

### 13.4 词包发布（`/api/v1/public/packs/latest.json`）

公开端点（`public_packs.py`）。`pack_service.get_current_pack_payload()`：

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

V0.6.7 起，**所有手动同步入口都集中在 `pages/PackManagerPage`**（📦 我的词包），`ConfigPage` 只保留一个 `ConfigPackManagerEntry` 行跳到该页。原 `ConfigPage` 的 `词库同步` 行（`ConfigSyncButton` / `ConfigSyncStatus` / `ConfigSyncToast`）已下线。

主同步路径：

1. PackManagerPage 顶部「🔄 同步词包」按钮（id `PackManagerSyncButton`）：并行调 `GlobalPackService.ensureLatest()` + `FamilyPackService.ensureLatest(deviceToken)`（仅在已绑定家长账号时），然后 `loadHomeIntegration` 重建 `PackLibrary`，最后弹中文 toast（id `PackManagerSyncToast`，2.4 s 自动消失）：
   - `✅ 已同步全局 + 家庭词包`
   - `✅ 已同步全局词包`（家庭无更新或未绑定）
   - `✅ 已同步家庭词包`
   - `已是最新`
   - `已是最新 (仅全局可同步，未绑定家长账号)`
2. HomePage / ConfigPage 的 chip / 入口行在 `onPageShow` 时再次 `loadHomeIntegration`，所以家长从 PackManagerPage back 之后立即反映新词包；今日冒险下次进入战斗才用新词源，避免战斗中途换底。

启动期同步（保留旧链路）：`WordPackBootstrapper.bootstrap()` 仍在 app 启动时通过 `WordPackSyncService` + `WordPackCache` 写一份**单一 pack 缓存**给 `HomePage` 的 V0.5 类别 overlay 用（旧 schema 兼容；与三层 pack 模型并行运行）。这条链路不再有 UI 触发入口，纯背景同步。

> 旧 `WordPackSyncService` 的 `SyncOutcome / SyncStatus` 枚举（`Updated / UpToDate / HttpError / RejectedTooSmall / NetworkError`）单元测试仍在 `harmonyos/entry/src/test`，启动期 bootstrap 流程没有变。

### 13.6 设备端家长管理后台（V0.5.8）

`ParentAdminPage` 是家长在自家设备上的运维入口：

- **入口**：ConfigPage → "家长管理后台"按钮，家长 PIN 校验后 push。进入即调 `lockPortrait`，离开 `restoreAutoLandscape`。
- **统计卡**：`/api/v1/admin/stats` → `userCount / wordCount / categoryCount / packCount / latestVersion / lastPublishedAt / llmDraftPending / lessonImportDraftPending`。
- **课本导入卡**（V0.5.8 替代旧的"发布新版词包"流）：
  - 📷 拍照（`@kit.CameraKit.cameraPicker`）/ 🖼️ 从相册（`@kit.CoreFileKit.picker.PhotoViewPicker`）任一通道返回 URI。
  - 客户端用 `LessonImagePicker` 嗅 MIME（jpg/jpeg/png/webp 白名单）+ 读字节，组装 `PickedImage` 后 `ParentApiClient.importLesson(image)` 走 `multipart/form-data` POST `/api/v1/family/{family_id}/lessons/import`（客户端用已绑定设备的 `fam-…`，否则 `_` 占位）。
  - 服务端 `family_lessons.import_lesson()` 调 OpenAI vision，落 `LessonImportDraft` 文档，返回 `LessonDraftDto`。客户端把 `id` + `extracted.words.length` 暂存，点 "去复核 →" push `LessonDraftReviewPage`。
  - 8 MB / 非白名单 MIME / 网络异常 / 非 2xx 都映射到友好文案（"图片超过 8 MB" / "仅支持 JPG / PNG / WebP" / "网络异常" / "服务异常 (HTTP …)"）。
- **待复核草稿列表**：`/api/v1/family/{family_id}/lesson-drafts?status=pending` → 时间戳行 + "复核 →" 按钮直跳 `LessonDraftReviewPage`。`onPageShow` 触发 refresh，所以从复核页 back 之后已 approve / reject 的草稿会立刻从列表里消失。
- **发布新版本词包**：`POST /api/v1/admin/packs/publish` + 可选 notes 单独保留，让家长可以把多张课本图都复核入库后一次性发布。

`LessonDraftReviewPage` 单独承担课本复核：

- 路由参数 `{ draftId: string }`，`getLessonDraft` 拉到草稿后渲染原图缩略 + 可改主题标签 + 候选词列表。
- 每行三件套：✓ 保留、`编辑` 弹窗（英文 / 中文双输入，trim 校验非空）、✎ 已编辑标记。
- "全部确认"先 `PATCH /api/v1/family/{family_id}/lesson-drafts/{id}` 提交 edited extraction，再 `POST /approve`；"全部拒绝"`POST /reject`。两条路径都在 toast 后 back 到 ParentAdminPage；HTTP 409 ALREADY_REVIEWED 自动 back，避免家长在已处理的草稿上反复点。

> **V0.5.8 已下线设备端 JWT 登录卡片**。`auth.py` 仍服务 JSON admin 与 **V0.8.2** `/admin/login` HTML。家长账户与 family 行级隔离已在 `/api/v1/family/{family_id}/**` 落地。

### 13.7 V0.8 后台（Web，已交付）

| 子版本 | 受众 | 入口 | 实现要点 |
| --- | --- | --- | --- |
| V0.8.1 | 家长 | `/family/{family_id}/packs/*` | Cookie 软鉴权 HTML 工作台 + `parent_family_pack.py` JSON；子端合并 `packs/latest.json` |
| V0.8.2 | 系统管理员 | `/admin/*` | `admin_pages.py` + `admin_audit_service.py`；原因 + 确认 + 审计 |

设计全文：[`superpowers/specs/2026-05-08-v0.8-backoffice-and-vocabulary-management-design.md`](superpowers/specs/2026-05-08-v0.8-backoffice-and-vocabulary-management-design.md)。测试：`test_parent_packs_pages.py`、`test_child_packs_merged.py`、`test_admin_pages.py`。

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

### 15.1 设备无关单测（`harmonyos/entry/src/test/`）

主集合 `LocalUnit.test.ets` + 多个独立 `*.test.ets`（含 V0.6.5 新增的 `Pack.test.ets` / `BuiltinPackLoader.test.ets` / `GlobalPackService.test.ets` / `PackLibrary.test.ets` / `PackSelectionService.test.ets`）。覆盖：

- 纯算法：`shuffle` 不丢元素；`QuestionGenerator` 三选一不重复且包含答案；`PlanQuestionSource` 题型链；`MemoryScheduler.classify` 分桶。
- BattleEngine：答对 / 答错 / 连击双倍 / 怪物切换 / 胜负条件 / `computeStars`。
- CoinAccount：`earn` 上限截断、`today-first` 即使被截到 0 也翻 `todayAdventureCompleted`、`beginToday` 跨天重置、`redeem` 不受日封顶限制、txn 历史滚动 cap。
- 持久化：WrongAnswerStore / WishlistStore / RedemptionHistoryStore 的 round-trip + 兼容老 schema 反序列化。
- 三层词包（V0.6.5）：`Pack` + `SceneMetadata` 默认值、`BuiltinPackLoader.parsePackJson` 容错、`GlobalPackService.parsePacks` + 200/304/204/网络异常分支、`PackLibrary` union + 覆盖优先级 + scene fallback、`PackSelectionService` 激活集 / pin / perfect-rotation / prefs round-trip。
- 解析：`parsePackCategories`。
- 家长管理后台 HTTP（V0.5.8）：`ParentApiClient` 课本导入流（pre-flight 大小 / MIME 校验、`multipart/form-data` POST、JSON 解析、HTTP 错误映射）、`MultipartBuilder` 字节级 round-trip + `escapeFilename` 头注入防护、`LessonImagePicker` 取消 / MIME 嗅探。

> V0.6.6 删除了 `parseCustomWords` / `computeFinalPool` / `KNOWN_CATEGORIES` 相关单测，对应函数已下线。

跑法：`cd harmonyos && hvigorw -p module=entry@default test`，BUILD SUCCESSFUL = 全部通过（hvigor 在任一断言失败时返回非 0）。

### 15.2 设备 UI 测试（`harmonyos/entry/src/ohosTest/ets/test/`）

20 个 Hypium UI 测试文件（含 V0.5.8 新增的 `LessonDraftReviewFlow.ui.test.ets` 和 V0.6.7.3 新增的 `PackManagerFlow.ui.test.ets`）。覆盖：

- 路由：`RoutingFlow.ui.test.ets`（首页 → 战斗 → 结算 → 重玩 / 返回的全闭环）。
- 战斗题型：`SpellQuestionFlow / FillLetterFlow`。
- 暴击 / 命中：`MagicAttack / CritSpectacle`。
- 复习模式：`ReviewMode.ui.test.ets`。
- 今日冒险 / 区域 / 计划：`AdventureFlow / RegionPickerFlow / TodayPlanFlow`。
- 学习报告：`LearningReportFlow.ui.test.ets`。
- 愿望单（默认 + 自定义）：`WishlistFlow / CustomWishlistFlow`，含 PIN 闸 + 验证错误 + 端到端添加。
- 词包管理（V0.6.7.3+）：`PackManagerFlow.ui.test.ets`（class `PackManagerFlow`），9 个用例覆盖：① `navigatesFromConfigAndRendersHeaderStatusAndSync`（ConfigPage → PackManagerPage 入口 + header / status row 烟测）；② `activePacksRenderPinButtonsWithFixedLabelCopy`（5 个 builtin pack 都渲染 `PackPin_<id>`，文案为 `📌 固定` / `已固定`）；③ `togglingPackOffHidesPinButtonAndOnRestoresIt`（V0.6.7.3 conditional render：未激活 pack 的 pin button 用 `Blank` 占位）；④ `homeRegionChipsRenderEnglishPackNames`（V0.6.7.5 烟测 5 个 chip 严格英文命名 — `Fruit Forest / School Castle / Home Cottage / Animal Safari / Ocean Realm`）；⑤ `togglingNonSelectedPackOffRemovesItsHomeRegionChip`（V0.6.7.4 跨页传播烟测）；⑥ `togglingSelectedPackOffSwapsAdventureCardThenRestores`（V0.6.7.4 `chipPacks[0]` fallback + `TODAY_REGION_ID_KEY` 复位）；⑦ `syncedGlobalPackAppearsInListAndActivatingItGrowsHomeChipRow`（V0.6.7.6 三层 pack 之**全局层**：tap 同步按钮触发 `GlobalPackService.ensureLatest()` 命中 mock `/api/v1/public/global-packs/latest.json` 拿到 `space-station` fixture，断言 `PackSourceTag_space-station == 官方` + `PackLabel_space-station == Space Station`，关 `home-cottage` 开 `space-station` 后回 HomePage 验证 `RegionChip_space-station == Space Station` + `RegionChip_home-cottage` 消失，激活上限 5/5 闸不动）；⑧ `boundDeviceSyncPullsFamilyPackAndAffectsHomeChipRow`（V0.6.7.6 三层 pack 之**家庭层**：先 `seedMockBinding()` 在 mock 侧 `_active_bindings` 挂 deterministic JWT，再 UI 级 `bindViaShortCode(driver)` 走 `ConfigBindParentButton → ScanBindingPage → ScanBindingManualSubmit → ScanBindingSuccessBack` 完成 redeem 让 `CloudCredentials` 在 live ability 上落实，然后 sync 命中 mock `/api/v1/family/{family_id}/family-packs/latest.json`（Bearer 闸 + ETag）拿到 `family-snacks` fixture，断言 `PackSourceTag_family-snacks == 家庭` + `PackLabel_family-snacks == Family Snacks`，关 `animal-safari` 开 `family-snacks` 后回 HomePage 验证 `RegionChip_family-snacks` 出现 + 文本英文 + builtin 消失；`finally` 还原激活集到 5 builtin 默认 + `unbindMockBinding()` + `wipeBoundDeviceState()` 清 `wordmagic_cloud` 全部绑定 keys，让随后跑的 `ParentBindingFlowV06.unboundConfigPageRendersBindEntryOnly` 还能从未绑定起步）；⑨ `tappingPinFlipsLabelBetweenUnpinnedAndPinnedStates`（pin button 文字回路烟测）。多个用例用 `try/finally` 兜底翻回 ON 防止 assertion 失败污染设备 prefs。配套 `server/mock_ui_server.py` V0.6.7.6 的两个 fixture：`FIXTURE_GLOBAL_PACK_PAYLOAD`（`space-station` / "Space Station" 3 词，匿名 ETag）+ `FIXTURE_FAMILY_PACK_PAYLOAD`（`family-snacks` / "Family Snacks" 3 词，Bearer 闸 + ETag），`pack_id` 都刻意避开 builtin 名让 chip row 在「关 1 builtin / 开 1 新包」时能客观表现 row composition 的变化。
- 设置 / 家长管理后台：`ConfigFlow / ParentAdminFlow / LessonDraftReviewFlow`（后两者 V0.5.8 起取代 `AdminConsoleFlow`），含 PIN 闸 + 课本导入按钮 / 待复核列表 / 路由注册的烟雾测试。**V0.6.7 移除**：原 `ConfigSyncFlow`（针对 ConfigPage 已下线的『词库同步』行）；三层 pack 同步现在归 PackManagerPage 管。**V0.6.7.7 新增**：`customTimerDialogAcceptsThreeSecondsAndUpdatesChip`（`ConfigTimerCustom` 打开 `CustomTimerDialog` → 输入 `3` → 确定 → 断言按钮文案含 `✓自定义` 和 `3s` + `ConfigTimer30s` 不带 `✓` → 保存 → 重开 ConfigPage 验证 3s 不被 sanitizeTimer snap 回 30s）和 `customTimerDialogRejectsZeroAndKeepsDialogOpen`（输入 `0` → 确定 → 断言 `CustomTimerDialogError` 显示且 dialog 仍打开），都用 `restoreDefaultTimerChip` 在 `finally` 里把 chip 还原回 5m 防设备 prefs 污染。同步加固 `scrollToParentPinButton` 的 visibility 判定（要求按钮高度 ≥ 100px 才认为完全在 viewport 内），消除 `configParentPinButtonNavigatesToSetupPage` 系列 PIN setup 用例在 25px clipped slice 下点击不命中的 flakiness。`ParentAdminFlow` 的 V0.5.8 增量包含 5 个走 mock server HTTP 的端到端用例：`refreshShowsMockedStats`（GET `/admin/stats`）、`pendingListShowsMockedDraft`（GET `/api/v1/family/_/lesson-drafts`）、`tapPublishShowsSuccessSummary`（POST `/admin/packs/publish` 后断言 `已发布 v\d+` 摘要）、`tapReviewLinkOpensReviewPageWithMockedDraft`（GET `/api/v1/family/_/lesson-drafts/{id}` 跨页路由 + 解析 + word row 渲染）、`tapPickGalleryUploadsAndShowsImported`（POST `/api/v1/family/_/lessons/import` multipart 上传：从 ohosTest rawfile 把 `lesson_import_fixture.jpg`（226KB 真实 JPG）写到 app 沙箱 tempDir，picker override 让 `RealPhotoPickerAdapter` 直接返回该路径，触发真实的 `fs.open`/`fs.read`/multipart/HTTP 调用链，最后断言 `✓ 已识别 3 个单词，请确认` 与 `去复核 →` 按钮）。
- 家长账户绑定：`ParentBindingFlow.ui.test.ets`（V0.6 + V0.6.x 增量），覆盖 `unboundConfigPageRendersBindEntryOnly` / `tapBindOpensScanBindingPage`（含 `ScanBindingScannerButton.isEnabled()` polling 防止 `bootstrapService` 异步链路退化为永久禁用）/ `shortCodeRedeemFlipsConfigToBound` / `unbindFromBoundDeviceInfoPageFlipsBackToUnbound`（V0.6.7.2：原 `unbindWithPinFlipsBackToUnbound` 重写 — 解除按钮迁移到 `BoundDeviceInfoPage`，测试驱动 `ConfigBoundDeviceInfoButton → BoundDeviceInfoUnbindButton → ParentPinDialog → BoundDeviceInfoUnbindToast → 自动 back → ConfigPage 翻回未绑定`），加上 V0.6.x 新增的 `pickQrFromGalleryRedeemsAndFlipsToBound`：沿用 V0.5.8 lesson-fixture 的「ohosTest rawfile 预打包 → tempDir 拷贝 → AppStorage 双 override key（`SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY` 喂 picker 路径，`SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY` 喂 ScanKit decode payload）」机制，端到端验证从图库选 QR → 解码 → redeem → 绑定成功的链路，固件 `scan_binding_qr_fixture.png` 由 `tools/generate_scan_binding_qr_fixture.py` 用 `qrcode[pil]` 生成并入仓。
- 图鉴：`MonsterCodexFlow.ui.test.ets`。

入口 `harmonyos/entry/src/ohosTest/ets/test/List.test.ets`，**`testsuite()` 第一行**就把 `serverBaseUrlOverride = http://127.0.0.1:8123` 写进 `AppStorage`，所有页面里通过 `effectiveServerBaseUrl()` 取 URL 的请求都被路由到本地 mock。生产 / release 包从不写这把 key，因此线上版本依然命中 Vercel。

V0.5.8 起推荐用 `scripts/run_ui_tests.sh`，它会：

1. 在 host 起 `server/mock_ui_server.py`（FastAPI，**无 MongoDB**，纯 fixture）；
2. `hdc rport tcp:8123 tcp:8123` 把模拟器 / 真机的 `127.0.0.1:8123` 反向转回 host；
3. `hdc shell aa test ...`（per-test timeout 60s）；
4. 退出时杀 mock 进程 + 清掉 rport 映射。

```bash
cd harmonyos && hvigorw --mode module -p module=entry@ohosTest assembleHap
hdc install -r harmonyos/entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
scripts/run_ui_tests.sh                     # 全量 49 个测试
scripts/run_ui_tests.sh --suite ParentAdminFlow   # 单 suite 调试
scripts/run_ui_tests.sh --rebuild           # 顺手重 build / 重装两个 HAP
```

不走脚本时（DevEco Run），先手工起 mock 和 rport：

```bash
(cd server && uv run python mock_ui_server.py) &
hdc rport tcp:8123 tcp:8123
```

不起 mock 直接跑 ohosTest，`ParentAdminFlow` 会因为 127.0.0.1:8123 不可达而失败（这是有意的：测试不允许偷偷 fallback 到 prod）。

成功标志：`OHOS_REPORT_RESULT: stream=Tests run: N, Failure: 0, Error: 0`。

### 15.3 服务端测试（`server/tests/`）

28 个文件（含 `conftest.py` / `__init__.py`，26 个 `test_*.py`）。覆盖：

- 路由层：auth / public_packs / admin_words / admin_packs / admin_drafts / admin_categories / family_lessons / admin_stats。
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

> 完整版本表与优先级见 [`WordMagicGame_roadmap.md`](WordMagicGame_roadmap.md) §2.1、§23。本节只列相对当前基线的方向。

### 已交付（本文档基线内）

- **V0.6.x–V0.7.0**：学习内核、三层词包、家长绑定、monorepo 重排。
- **V0.7.1**：Harmony / iOS / Android bootstrap parity（17 页）。
- **V0.8.1 / V0.8.2**：家长 Web 词库 + 子端合并拉取；系统管理员 `/admin/` HTML + 审计。

### 进行中 / 下一批（路线图）

- **三端 feature SOP**：`docs/features/<feature-id>/` — Harmony 先交付 → 复制触发签字 → iOS / Android。
- **V0.10**：战斗 BGM 与 TTS 混音（V0.4.8 deferred）。
- **V0.9**：AI 语境与句子填词。
- **V0.11**：Cocos 表现层评估。

### 可选增强（非阻塞）

- 云端学习报告按 pack、愿望单兑换 push 通知（roadmap §2.1）。
- JSON `admin_*` 鉴权硬化；设备端 ParentAdmin 逐步迁离全局 JSON admin 调用。
- 家长 PIN 哈希、词包 push 式 silent refresh、学习报告导出等 V1.0 候选（roadmap）。

---

## 18. 关联文档与代码索引

- [`docs/WordMagicGame_roadmap.md`](WordMagicGame_roadmap.md)：所有子版本的时间线 + 验收。
- [`docs/superpowers/specs/2026-05-08-v0.8-backoffice-and-vocabulary-management-design.md`](superpowers/specs/2026-05-08-v0.8-backoffice-and-vocabulary-management-design.md)：V0.8.1 / V0.8.2 后台（**已完成**）。
- [`docs/ios-replica/00-index.md`](ios-replica/00-index.md)、[`docs/android-replica/00-index.md`](android-replica/00-index.md)：三端 bootstrap 阶段图与 17 页矩阵。
- [`docs/sop/00-three-platform-feature-sop.md`](sop/00-three-platform-feature-sop.md)：V0.7.1 之后新功能生命周期。
- [`docs/superpowers/specs/`](superpowers/specs/)：各版本设计文档归档。
- [`docs/superpowers/plans/`](superpowers/plans/)：对应实现计划与 checklist。
- [`docs/arkts-references/`](arkts-references/)：HarmonyOS / ArkTS / hvigor 相关命令与 API 速查。
- [`server/README.md`](../server/README.md) / [`server/pyproject.toml`](../server/pyproject.toml)：服务端依赖与启动。
- [`AGENTS.md`](../AGENTS.md) / [`CLAUDE.md`](../CLAUDE.md)：项目内 AI 代理工作约定（包括 server 全绿要求）。
- [`.cursor/ohos-dev-commands.md`](../.cursor/ohos-dev-commands.md)：HarmonyOS 构建 / lint / 测试命令的真源。

每次新增大功能时先看本文档是否仍符合架构边界；若引入账号、长连接、或服务端结构性变化，必须新增专项设计文档并更新本文 §3 / §13 / §17。
