# 从零代码到三端应用：一次 Agentic Coding 独立开发记录

> Draft status: story outline + evidence-backed timeline
> Repo snapshot: 2026-05-19
> Project: WordMagicGame / 魔法背单词

这不是一篇“AI 帮我写了几个页面”的文章。

更准确地说，这是一次把 Agent 当成产品、研发、测试、发布、运维团队来协作的独立开发实验。我自己没有 App 开发经验，也没有亲手写过一行业务代码，但通过 Codex、Cursor、GitHub、Vercel、App Store Connect、DevEco Studio、Xcode、Gradle 这些工具的组合，在一个月左右的时间里，把一个儿童英语学习游戏从想法推进到了：

- HarmonyOS NEXT 原生客户端；
- iOS 原生 Swift / SwiftUI 客户端，并完成 App Store v0.7.0 提审；
- Android 原生 Kotlin / Jetpack Compose 客户端，并完成 release hardening 与 Google Play 准备；
- Python / FastAPI / MongoDB / Vercel 后端；
- GitHub Actions、Vercel Preview、E2E 测试、预览地址 manifest、Cursor Cloud 自动修复思路；
- 一套能继续扩展三端功能的 SOP、测试、发布清单和 agent 工具沉淀。

截至 2026-05-19，这个仓库的本地 git 历史中有 863 个 commit；GitHub PR 从 `#1` 走到 `#115`，其中 107 个已合并。PR log 本身就是这次 Agentic Coding 的开发日记。

## 一句话版本

我做的不是“让 AI 生成一个 App”，而是把需求、规格、计划、代码、测试、发布、修复、部署都变成 agent 可以接力执行的工作流。

人的角色从“写每一行代码”变成了：

- 定义产品方向；
- 拆小版本和验收标准；
- 判断平台约束；
- 给 agent 提供明确上下文；
- 看 PR、跑测试、接管浏览器或真机完成审核动作；
- 在工具失效、审核卡住、平台规则冲突时做取舍。

这个模式特别适合独立开发应用软件和服务：一个人不必同时精通 HarmonyOS、iOS、Android、FastAPI、Vercel、App Store、Google Play、AppGallery，但必须建立一套能让 agent 安全前进的工程护栏。

## 故事主线

### 第一幕：先让一个想法能跑起来

项目从一个普通 HarmonyOS 工程开始。最早的几天不是追求完整产品，而是先建立开发反馈回路：

- `2026-04-20`：加入 HarmonyOS Hello World 项目。
- `2026-04-22`：开始把 Cursor Harmony autofix skills、dev commands、UI test 规范放进仓库。
- `2026-04-23`：把 WordMagicGame 的 V0.1 规格文档、页面路由、题库、战斗页、配置页和 E2E 测试陆续合入。

这一阶段最重要的不是页面多漂亮，而是第一次形成闭环：

`HomePage -> BattlePage -> ResultPage`

孩子可以从首页进入战斗，回答单词题，看到结果。这个闭环一旦跑通，后面所有功能都可以围绕它迭代。

关键 PR：

- [#7 docs: add WordMagicGame V0.1 overall specification](https://github.com/terryma2024/happyword/pull/7)
- [#8 feat: T2-T4 routing skeleton, word repo, and question generator](https://github.com/terryma2024/happyword/pull/8)
- [#9 feat: T5-T8 battle engine, ConfigPage, and end-to-end test coverage](https://github.com/terryma2024/happyword/pull/9)

这里第一次体现了 Agentic Coding 的节奏：先让 agent 把模糊需求整理成规格，再要求它按任务拆分实现，最后用测试把功能钉住。

### 第二幕：从玩具变成产品

从 `2026-04-24` 到 `2026-04-30`，项目开始从一个可玩 demo 变成一个有产品形态的学习游戏。

这段时间加入了：

- 音效、角色受击、暴击表现；
- 今日冒险、主题区域、怪物图鉴；
- 拼写题、填字题、遗忘曲线；
- 愿望单、家长 PIN、兑换记录；
- app icon、工具栏图标、Recraft 生成的游戏素材；
- 学习报告、复习模式、更多主题区域。

代表 PR：

- [#10 WordMagicGame V0.2: audio, animations, crit spectacle, pronunciation, learning record, review mode](https://github.com/terryma2024/happyword/pull/10)
- [#16 Feat/v0.3 fun learning core](https://github.com/terryma2024/happyword/pull/16)
- [#20 feat(v0.3.8): boss codex expansion](https://github.com/terryma2024/happyword/pull/20)
- [#23 V0.3.9 wishlist redemption flow refactor](https://github.com/terryma2024/happyword/pull/23)
- [#25 V0.4: deep-learning question types + spelling + 5 regions + V0.4.8 polish](https://github.com/terryma2024/happyword/pull/25)

这一幕里我逐渐形成了一个重要习惯：不直接说“加一个功能”，而是让 agent 先写 `spec` 和 `plan`。等设计边界清楚了，再让它实现。这样做的好处是，agent 不会在一个模糊需求里自由发挥太远，后续 review 也有依据。

### 第三幕：把后端和自动部署接进来

`2026-04-30` 的 [PR #26](https://github.com/terryma2024/happyword/pull/26) 是一个明显转折点：项目从纯客户端游戏进入“客户端 + 后端服务”的形态。

后端的第一条最薄链路包括：

- `server/` Python / FastAPI 工程；
- MongoDB / Beanie 数据模型；
- JWT 登录；
- admin bootstrap；
- public word pack endpoint；
- Vercel serverless 入口；
- HarmonyOS 客户端远端词包拉取与缓存。

随后几天继续加上：

- LLM 单词草稿；
- 教材照片识别；
- Vercel Blob 素材存储；
- 家长后台；
- 词包发布、回滚、缓存、ETag；
- GitHub Actions server CI；
- Vercel Preview E2E；
- Cursor Cloud 自动修复失败 E2E 的方案；
- preview manifest 通过 Vercel Blob 暴露给客户端 DevMenu。

这部分是我理解 Agentic Coding 后最有价值的地方：agent 不只是写功能，还能把“后端是否能部署、PR 是否能预览、测试失败谁来修、客户端怎么切 preview 环境”这些独立开发者很容易忽略的运维问题，一起纳入工程系统。

代表 PR：

- [#26 V0.5.1 Walking Skeleton: server + client + Vercel deploy](https://github.com/terryma2024/happyword/pull/26)
- [#27 feat: V0.5 server-side word pack + client follow-up + spec refresh](https://github.com/terryma2024/happyword/pull/27)
- [#30 V0.6: Parent account + family-scoped device binding](https://github.com/terryma2024/happyword/pull/30)
- [#42 ci(preview-manifest): rebuild from Vercel deployments instead of PR webhook](https://github.com/terryma2024/happyword/pull/42)
- [#49 fix(parent-admin): unstick lesson-import flow](https://github.com/terryma2024/happyword/pull/49)

### 第四幕：从单端到三端原生

一开始项目只有 HarmonyOS。后来我做了一个重要决定：不要走跨平台，不要再套一层 `clients/`，而是把三端客户端都放在 repo 根目录，用原生技术实现：

```text
harmonyos/   HarmonyOS NEXT / ArkTS / ArkUI
ios/         Swift / SwiftUI
android/     Kotlin / Jetpack Compose
server/      FastAPI / MongoDB / Vercel
shared/      contracts, schemas, fixtures only
```

`2026-05-10` 的 [PR #54](https://github.com/terryma2024/happyword/pull/54) 把 HarmonyOS 项目迁移到 `harmonyos/`，正式形成 monorepo。随后 iOS 和 Android 不是重新设计，而是按照 HarmonyOS 已经稳定的产品语义复制：

- 页面路由矩阵；
- Home / Battle / Result 核心闭环；
- PackManager；
- 愿望单；
- 怪物图鉴；
- 今日计划；
- 学习报告；
- 设备绑定；
- 家长后台入口；
- Debug Preview 路由；
- Release 构建隐藏调试入口。

代表 PR：

- [#54 Move HarmonyOS project under harmonyos](https://github.com/terryma2024/happyword/pull/54)
- [#60 add iOS replica specs and XcodeGen scaffold](https://github.com/terryma2024/happyword/pull/60)
- [#64 iOS native WordMagic replica](https://github.com/terryma2024/happyword/pull/64)
- [#66 Add Android replica client](https://github.com/terryma2024/happyword/pull/66)
- [#69 align Android replica with HarmonyOS](https://github.com/terryma2024/happyword/pull/69)
- [#80 phase 5 release hardening](https://github.com/terryma2024/happyword/pull/80)

这也是整件事最反直觉的地方：我没有 iOS / Android 开发经验，但只要 HarmonyOS 端的产品语义、截图、测试、共享 fixtures 和 release gate 足够清楚，agent 就能把复制工作拆成可验证的小步骤。

### 第五幕：发布不是终点，而是另一套工程

当 App 可以跑起来后，真正复杂的事情才开始：商店审核、隐私、账号删除、截图、测试账号、release build、签名、真机 smoke、后端可用性。

iOS 的发布工作最终沉淀在 `ios/release-pre.md`。截至 2026-05-17：

- version `0.7.0`；
- build `1007004`；
- TestFlight 上传成功；
- 真机 TestFlight smoke 通过；
- App Privacy labels 发布；
- 截图上传；
- primary category 为 Education；
- age rating 为 `4+`；
- 定价免费；
- 手动发布；
- App Store Connect 状态为 `正在等待审核`。

关键记录：

- [#104 Prepare v0.7.0 iOS and HarmonyOS release](https://github.com/terryma2024/happyword/pull/104)
- commit `9be34a5 Document iOS App Store submission`
- `ios/release-pre.md`

HarmonyOS / AppGallery 也进入了 release 准备，但它更真实地暴露了另一些阻塞：

- AppGallery app record 已创建；
- release metadata 已填写；
- official signing material 和 release build 已完成；
- 但仍有 APP 备案、真机 release smoke、截图替换、审核 hotfix 等工作。

Android 则完成了 release hardening 和 Google Play 准备：

- unit test；
- debug build；
- connected UI test；
- release build；
- AAB 生成；
- release manifest 权限检查；
- 但 Google Play Console app 创建受开发者账号验证阻塞。

这部分我想在文章里保留“不完美”的状态。因为真实的独立开发不是所有平台都一键通过，而是 agent 把每个平台的阻塞拆清楚，让人知道下一步该做什么。

## 时间线

| 日期 | 里程碑 | 证据 |
| --- | --- | --- |
| 2026-04-16 | 仓库初始化 | `ea11685 Initial commit` |
| 2026-04-20 | HarmonyOS Hello World 工程落地 | `5d790f3 feat: add HarmonyOS Hello World (ArkTS) project` |
| 2026-04-22 | Cursor / Harmony autofix skills 与 dev commands 进入仓库 | PR [#1](https://github.com/terryma2024/happyword/pull/1) |
| 2026-04-23 | WordMagicGame V0.1 规格、路由、战斗闭环和 E2E 测试形成 | PR [#7](https://github.com/terryma2024/happyword/pull/7), [#8](https://github.com/terryma2024/happyword/pull/8), [#9](https://github.com/terryma2024/happyword/pull/9) |
| 2026-04-24 | V0.2：音效、动画、暴击、发音、学习记录、复习模式 | PR [#10](https://github.com/terryma2024/happyword/pull/10) |
| 2026-04-28 | 产品路线图、V0.3 趣味学习核心、Recraft 工具沉淀 | PR [#15](https://github.com/terryma2024/happyword/pull/15), [#16](https://github.com/terryma2024/happyword/pull/16), [#17](https://github.com/terryma2024/happyword/pull/17) |
| 2026-04-29 | Boss 图鉴、愿望单、图标体系、拼写题开始完善 | PR [#20](https://github.com/terryma2024/happyword/pull/20), [#23](https://github.com/terryma2024/happyword/pull/23), [#24](https://github.com/terryma2024/happyword/pull/24) |
| 2026-04-30 | V0.4 深度学习与拼写完成；V0.5 后端 Walking Skeleton 上线 | PR [#25](https://github.com/terryma2024/happyword/pull/25), [#26](https://github.com/terryma2024/happyword/pull/26) |
| 2026-05-01 | 远端词包、LLM、图片导入、家长后台、客户端缓存推进 | PR [#27](https://github.com/terryma2024/happyword/pull/27), [#29](https://github.com/terryma2024/happyword/pull/29) |
| 2026-05-02 到 2026-05-07 | V0.6 家长账号、家庭绑定、云同步、E2E Preview、CI/CD 自动化 | PR [#30](https://github.com/terryma2024/happyword/pull/30), [#31](https://github.com/terryma2024/happyword/pull/31), [#42](https://github.com/terryma2024/happyword/pull/42) |
| 2026-05-08 到 2026-05-09 | DevMenu、Vercel preview manifest、parent admin 修复、Vercel 部署治理 | PR [#45](https://github.com/terryma2024/happyword/pull/45), [#49](https://github.com/terryma2024/happyword/pull/49), [#51](https://github.com/terryma2024/happyword/pull/51) |
| 2026-05-10 | Monorepo 结构成型；HarmonyOS 迁移到 `harmonyos/`；iOS 复制计划开始 | PR [#54](https://github.com/terryma2024/happyword/pull/54), [#60](https://github.com/terryma2024/happyword/pull/60) |
| 2026-05-11 到 2026-05-12 | iOS native replica、Android replica、Android release hardening | PR [#64](https://github.com/terryma2024/happyword/pull/64), [#66](https://github.com/terryma2024/happyword/pull/66), [#69](https://github.com/terryma2024/happyword/pull/69), [#80](https://github.com/terryma2024/happyword/pull/80) |
| 2026-05-13 到 2026-05-15 | 三端 parity 工具、UI gap detector、iOS/Android/HarmonyOS 细节对齐 | PR [#85](https://github.com/terryma2024/happyword/pull/85), [#86](https://github.com/terryma2024/happyword/pull/86), [#87](https://github.com/terryma2024/happyword/pull/87), [#99](https://github.com/terryma2024/happyword/pull/99) |
| 2026-05-16 到 2026-05-17 | iOS v0.7.0 TestFlight、App Store metadata、隐私问卷、截图和提审；HarmonyOS release-prep | PR [#104](https://github.com/terryma2024/happyword/pull/104), [#109](https://github.com/terryma2024/happyword/pull/109), commit `9be34a5` |
| 2026-05-18 | AppGallery 审核修复、LLM provider 配置、CloudBase 迁移规划 | PR [#113](https://github.com/terryma2024/happyword/pull/113), [#114](https://github.com/terryma2024/happyword/pull/114) |
| 2026-05-19 | V0.8.4 战斗平衡与 iOS/Android parity 继续推进 | PR [#115](https://github.com/terryma2024/happyword/pull/115) |

## 我用到的工具

### Codex

Codex 更适合承担长链路、跨文件、跨平台、需要持续验证的任务。例如：

- 把 PDF / 口头想法整理成正式产品规格；
- 维护 roadmap；
- 做 monorepo 迁移方案；
- 改 server、shared contracts、release docs；
- 跑本地测试、处理 git、创建分支、push；
- 记录 release 状态；
- 在已有记忆和仓库上下文里继续推进。

Codex 对我最大的价值不是一次写多少代码，而是能“记住上下文并继续做事”。当任务涉及很多文件、很多前置决策、很多验证命令时，这种连续性很关键。

### Cursor

Cursor 更像是在代码仓库里快速开分支、改功能、补 UI、修测试的前线 agent。这个项目里大量 PR 都来自 `cursor/...` 分支：

- HarmonyOS UI 修复；
- 后端小修；
- Android / iOS parity；
- DevMenu 自动化；
- Vercel preview / CI 修复；
- 商店审核 blocker 的局部修复。

我对 Cursor 的使用方式不是“随便写一段代码”，而是给它明确的 repo 规则、dev commands、PR 目标和验证出口。

### GitHub PR

GitHub PR 是整个 Agentic Coding 工作流的账本。每个 PR 都承担几个作用：

- 隔离 agent 的改动；
- 留下可追溯的决策和实现记录；
- 触发 CI、E2E、preview；
- 让失败可以被定位到具体分支；
- 让我能用 PR log 复盘项目演进。

如果没有 PR 纪律，agent 越多，代码库越容易变成一团乱麻。

### GitHub Actions + Vercel Preview

后端不是只部署一次。项目里逐步建立了：

- server unit tests；
- Vercel preview deployment；
- preview E2E；
- per-PR MongoDB test database；
- preview URL manifest；
- staging smoke；
- Slack / Cursor Cloud 自动修复设计。

这让一个独立开发者也能有接近团队开发的反馈系统。

### Recraft

Recraft 用于生成游戏角色、怪物、图标等视觉素材。后续我把它沉淀成可复用工具和 skill，而不是每次手工复制 prompt：

- `tools/recraft/generate-v4-vector.mjs`
- `.agents/skills/recraft-v4-vector`
- `.cursor/skills/recraft-v4-vector`

这类工具沉淀很重要：第一次是生成一张图，第二次开始就应该变成流程。

### 平台工具

三端发布绕不开真实平台工具：

- HarmonyOS：DevEco Studio、Hvigor、CodeLinter、ohosTest、hdc、AppGallery Connect；
- iOS：Xcode、XcodeGen、xcodebuild、TestFlight、App Store Connect；
- Android：Gradle、Android Emulator、connectedDebugAndroidTest、AAB、Google Play Console；
- 后端：uv、pytest、ruff、mypy、Vercel CLI、MongoDB Atlas。

Agentic Coding 并没有消灭这些工具。它改变的是：我不用先成为每个工具的专家，agent 可以帮我把命令、配置、错误和验证路径串起来。

## 沉淀出来的可复用资产

这次项目里最值得他人借鉴的，不是某个页面实现，而是下面这些“让 agent 能持续工作”的资产。

### 1. `AGENTS.md`

仓库根目录的 `AGENTS.md` 定义了：

- 技术栈；
- 三端目录边界；
- HarmonyOS / Android / server 命令；
- release build 禁止暴露 Debug DevMenu；
- 三端 feature 生命周期；
- asset retention policy；
- server 测试纪律；
- Cursor Cloud 的 server-only 约束。

这等于给所有 agent 一个共同的“项目宪法”。

### 2. `docs/superpowers/specs/` 和 `docs/superpowers/plans/`

每个复杂功能都尽量先落成 spec 和 plan：

- 设计目标；
- 用户体验；
- 数据模型；
- 文件变更；
- 测试方式；
- 分阶段任务；
- 回滚和风险。

这样 agent 写代码时不是凭感觉，而是在执行一个已经讨论过的计划。

### 3. `.cursor/*-dev-commands.md`

HarmonyOS 和 Android 都有专门的 dev commands 文档，记录：

- build；
- lint；
- unit test；
- emulator / device；
- install；
- screenshot；
- log；
- UI automation。

这类文档的价值在于，把“我电脑上应该怎么跑”变成 agent 可以重复执行的命令清单。

### 4. 三端 feature SOP

`docs/sop/00-three-platform-feature-sop.md` 规定了后续 feature 的节奏：

1. HarmonyOS 先设计、实现、稳定；
2. 冻结设计和 delta letter；
3. iOS / Android 并行复制；
4. parity checklist 验收；
5. 共享语义变化必须 reopen checklist。

这避免了三端各自发挥，最后变成三个不同产品。

### 5. `shared/contracts` 与 fixtures

`shared/` 不放共享运行时代码，只放：

- schemas；
- API contracts；
- fixtures；
- protocol docs。

这能帮助三端对齐后端语义，又不会把原生客户端拖进跨平台 runtime。

### 6. parity-scout / gap detector

三端复制后，最大问题不是“能不能跑”，而是“看起来、用起来是否一致”。所以项目里沉淀了 parity scout 和 gap detector：

- 页面 registry；
- 截图采集；
- scope planner；
- findings；
- followup 生成；
- iOS / Android / HarmonyOS adapter。

这类工具让“跨端一致性”从主观感觉变成可追踪任务。

### 7. release-pre 文档

发布不是一句 `build release`。每个平台都需要自己的 release checklist：

- `ios/release-pre.md`
- `harmonyos/release-pre.md`
- `docs/android-replica/07-release-readiness-checklist.md`

这些文档记录的不只是完成项，也记录阻塞项。比如 iOS 已经提交 Apple Review；HarmonyOS 仍有 AppGallery / APP 备案 / 真机 smoke 等阻塞；Android 的 Google Play app creation 卡在开发者账号验证。

### 8. Vercel preview manifest

客户端 Debug DevMenu 可以切到 Vercel Preview，但 preview URL 是动态的。项目里把这个问题做成了 manifest：

- GitHub Actions 从 Vercel deployments 重建 preview 列表；
- 写入 Vercel Blob；
- FastAPI 暴露 public endpoint；
- 客户端读取 `GET /api/v1/public/preview-urls.json`。

这让移动端也能跟上 PR preview，而不是每次手动复制 URL。

## 我踩到的坑

### Agent 很会执行，但需要边界

如果只说“做一个背单词 App”，agent 会生成很多东西，但不一定是一个可持续维护的产品。真正有效的方式是给它：

- 版本边界；
- 页面边界；
- 文件边界；
- 测试边界；
- 发布边界。

### 平台审核比写代码更考验真实状态

iOS 提审时，真正花时间的是：

- 隐私标签；
- 支持 URL；
- 隐私政策；
- 账号删除；
- 截图尺寸；
- TestFlight build 替换；
- release build 隐藏 debug 入口；
- 真机 smoke。

这些都不能靠“代码看起来对”解决，必须进入真实平台。

### 自动化不是一次到位的

Vercel Preview、E2E、Cursor Cloud autofix、preview manifest 都经历了多次修正。Agentic Coding 的真实样子不是一次 prompt 成功，而是不断把失败写回系统，让下一次更稳。

### 不要把所有东西都交给共享层

三端原生开发最容易犯的错是：为了复用，把共享 runtime 塞进 `shared/`。这个项目最后选择只共享 contracts 和 fixtures，让每个平台保持原生实现。这让三端更符合平台习惯，也降低了构建和调试复杂度。

## 给独立开发者的可复制方法

如果我要把这套方法压缩成一个可执行模板，会是这样：

1. 先写产品规格，不急着写代码。
2. 把第一个版本压到最小闭环。
3. 每个功能都要求 agent 先写 spec / plan / test path。
4. 用 PR 隔离每个 agent 的工作。
5. 把 build / test / lint / install / screenshot 命令写进仓库。
6. 让 CI 和 preview 先服务后端，再逐步服务客户端。
7. 只把稳定语义放进 shared contracts，不抽象过早的共享 runtime。
8. 三端复制时，先冻结一个基准端，再让其他端并行追平。
9. 发布前建 release-pre 文档，把真实商店状态写进去。
10. 每次踩坑后，把修复方法沉淀成文档、脚本或 skill。

## 文章可以怎么讲

正式对外分享时，可以按这个叙事节奏写：

1. 我没有 App 开发经验，也没有写代码，但我想做一个真实儿童英语学习 App。
2. 一开始我以为关键是让 AI 写代码，后来发现关键是让 AI 进入工程流程。
3. 我先用 HarmonyOS 做出可玩的最小闭环。
4. 再把玩法、学习机制、美术和家长功能一点点产品化。
5. 然后接入后端、LLM、Vercel 自动部署和 E2E preview。
6. 当 HarmonyOS 稳定后，我把项目重构成 monorepo，让 iOS / Android 原生复制。
7. 最后我发现发布是另一套工程：隐私、截图、账号删除、真机 smoke、审核阻塞。
8. 回头看，Agentic Coding 的核心不是“替我写代码”，而是“让我一个人调度一支软件团队”。

## 当前事实边界

为了避免把故事写过头，当前状态应该这样表述：

- iOS：v0.7.0 build `1007004` 已提交 Apple Review，状态记录为 `正在等待审核`。
- HarmonyOS：AppGallery release-prep 已推进，存在备案、真机 smoke、截图替换和审核 hotfix 等未完成项。
- Android：原生客户端和 release hardening 已完成；Google Play 上架流程受开发者账号验证阻塞。
- 后端：FastAPI + MongoDB + Vercel 已支撑产品功能，并沉淀了 CI、preview、E2E、manifest、后续 CloudBase 迁移计划。

真实故事不需要假装所有平台都一夜之间完美发布。更有价值的是：用 agentic workflow，把每个平台的完成项和阻塞项都变成可以继续推进的工程任务。
