# Small Magician Word Adventure

快乐背单词是一个面向儿童的 HarmonyOS NEXT 英语单词学习小游戏。游戏把单词练习包装成“小魔法师对战怪物”的轻量冒险：孩子在横屏战斗中识别单词、补全拼写、积累魔法币，并通过每日计划和学习报告持续复习。

**路线图（里程碑与后续方向）：** [`docs/WordMagicGame_roadmap.md`](docs/WordMagicGame_roadmap.md)

## Screenshots

| 首页与今日冒险 | 战斗答题 |
| --- | --- |
| ![Home](assets/screenshots/01-home.jpeg) | ![Battle](assets/screenshots/02-battle.jpeg) |

| 怪物图鉴 | 今日学习计划 | 魔法愿望单 |
| --- | --- | --- |
| ![Monster Codex](assets/screenshots/03-monster-codex.jpeg) | ![Today Plan](assets/screenshots/04-today-plan.jpeg) | ![Wishlist](assets/screenshots/05-wishlist.jpeg) |

## Highlights

- **儿童友好的战斗学习循环**：选择正确单词会释放魔法攻击，答错会受到怪物反击，反馈直接、规则轻量。
- **多题型词汇训练**：支持三选一、补字母、完整拼写等题型，用不同怪物承载不同学习挑战。
- **今日冒险**：按主题区域生成每日练习计划，混合复习词、学习中词和新词。
- **本地学习记录**：记录词汇掌握状态，区分新词、学习中、熟悉、掌握，并支撑复习安排。
- **魔法愿望单**：完成冒险和击败怪物获得魔法币，孩子可以向家长申请兑换愿望。
- **怪物图鉴与主题区域**：包含 Slime、Zombie、Dragon 以及多个童话风 Boss，覆盖水果森林、学校城堡、家庭小屋、动物 Safari、海洋王国等区域。
- **离线优先**：首版词库、角色、怪物、音效和学习数据均在本地运行，适合平板短时练习。

## Tech Stack

- HarmonyOS NEXT
- ArkTS / ArkUI
- DevEco Studio managed project
- Local rawfile assets for words, characters, icons, and sound effects

## Project Structure

```text
entry/src/main/ets/
  pages/        HomePage, BattlePage, ResultPage, TodayPlanPage, WishlistPage
  components/   CharacterCard, ChoiceButton, HpBar, MagicProjectile
  models/       BattleState, Question, WordEntry, SessionResult
  services/     BattleEngine, QuestionGenerator, LearningRecorder, AudioService
  data/         AdventureCatalog, MonsterCatalog, MonsterCodex

entry/src/main/resources/rawfile/
  data/         bundled word lists
  character/    player and monster SVG assets
  sound/        battle sound effects and BGM candidates

docs/
  WordMagicGame_overall_spec.md
  WordMagicGame_roadmap.md
```

Documentation: [overall spec](docs/WordMagicGame_overall_spec.md) · [roadmap](docs/WordMagicGame_roadmap.md)

## Local Development

Install dependencies:

```bash
ohpm install
```

Build debug HAP:

```bash
hvigorw assembleHap
```

Run CodeLinter after a successful HAP build:

```bash
codelinter -c ./code-linter.json5 . --fix
```

Connect a device or emulator:

```bash
hdc list targets
```

Install the built HAP:

```bash
hdc install entry/build/default/outputs/default/entry-default-signed.hap
```

Run **no-device unit tests** (`entry/src/test/`):

```bash
hvigorw -p module=entry@default test
```

Run **on-device UI / Instrument tests** (`entry/src/ohosTest/`) with the project orchestrator — starts `server/mock_ui_server.py`, sets up `hdc rport`, installs HAPs, and runs `aa test`:

```bash
scripts/run_ui_tests.sh
```

Expect `TestFinished-ResultCode: 0` and `OHOS_REPORT_CODE: 0` when the suite passes. You need a connected device or emulator (`hdc list targets`).

The detailed build, test, device, and log workflow lives in [`.cursor/dev-commands.md`](.cursor/dev-commands.md).

### Debug: backend environment

Debug builds can switch API base URL at runtime (local machine, a Vercel preview deployment, or staging). Open the developer menu by **triple-tapping** the small grey **version label** at the **top-left of the home screen** (there is no Settings entry). The menu shows a card grid — **tap a card to apply** immediately (Preview runs a health probe first and may ask for a Vercel protection-bypass secret). The preview PR list is always fetched from production **`https://happyword.vercel.app/api/v1/preview-urls.json`**, independent of the env you selected. Release builds hide the label and this flow. See [DevMenu runbook](docs/superpowers/runbooks/dev-menu-runbook.md), [backend env switcher spec](docs/superpowers/specs/2026-05-06-client-backend-env-switcher-design.md), and [triple-tap / DevMenu UI spec](docs/superpowers/specs/2026-05-07-home-version-triple-tap-design.md).

## Server

The Python/FastAPI content backend (词库管理、家长账户、设备配对、家庭包等) lives under [`server/`](server/). For local dev, offline + E2E tests, and Vercel 部署说明，见 [`server/README.md`](server/README.md)。设计规范见 [V0.5 后端设计](docs/superpowers/specs/2026-04-30-v0.5-content-backend-design.md)。

## CI / GitHub Actions

The `server-ci` / `server-cd` / `cursor-autofix-e2e` / `preview-manifest` /
`atlas-cleanup` workflows expect a small set of GitHub Actions secrets
(Vercel, Mongo Atlas, Slack, Cursor). All of them are documented — with
**how to obtain each value and what breaks when one is missing** — in
[`docs/ci-secrets.md`](docs/ci-secrets.md). Read that page first when
forking the repo or bringing up CI from scratch.

## Roadmap

The product roadmap — milestones, version threads, and planned work — lives in **[`docs/WordMagicGame_roadmap.md`](docs/WordMagicGame_roadmap.md)**. For product intent and scope, see also **[`docs/WordMagicGame_overall_spec.md`](docs/WordMagicGame_overall_spec.md)**.

Current major directions include battle audio mixing with BGM, richer learning reports, backend content tooling, parent account/device binding, AI-assisted story content, and a later Cocos2D battle presentation rewrite.
