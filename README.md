# Small Magician Word Adventure

快乐背单词是一个面向儿童的 HarmonyOS NEXT 英语单词学习小游戏。游戏把单词练习包装成“小魔法师对战怪物”的轻量冒险：孩子在横屏战斗中识别单词、补全拼写、积累魔法币，并通过每日计划和学习报告持续复习。

**路线图（里程碑与后续方向）：** [`docs/WordMagicGame_roadmap.md`](docs/WordMagicGame_roadmap.md)

## Screenshots

Clients ship separate binaries; screenshots are grouped **by platform** under [`assets/screenshots/`](assets/screenshots/).

### HarmonyOS NEXT (current reference UI)

Captured from a landscape phone/tablet viewport (`2720×1260` PNG from `uitest screenCap`). Long pages use numbered strips (`config-part*.png`, `learning-report-part*.png`, `parent-admin-part*.png`). Regenerate on a connected device or emulator with:

`python3 scripts/capture_harmony_screenshots.py` (see script docstring; requires `hdc`).

| Home | Battle | Result |
| --- | --- | --- |
| ![Home](assets/screenshots/harmonyos/home.png) | ![Battle](assets/screenshots/harmonyos/battle.png) | ![Result](assets/screenshots/harmonyos/result.png) |

| Monster codex (1 / 2) | Monster codex (2 / 2) | Today plan |
| --- | --- | --- |
| ![Codex 1](assets/screenshots/harmonyos/monster-codex-part1.png) | ![Codex 2](assets/screenshots/harmonyos/monster-codex-part2.png) | ![Today plan](assets/screenshots/harmonyos/today-plan.png) |

| Learning report (strip 1 / 2) | Learning report (strip 2 / 2) | Wishlist |
| --- | --- | --- |
| ![LR 1](assets/screenshots/harmonyos/learning-report-part1.png) | ![LR 2](assets/screenshots/harmonyos/learning-report-part2.png) | ![Wishlist](assets/screenshots/harmonyos/wishlist.png) |

| Redemption history | Pack manager | Parent PIN setup |
| --- | --- | --- |
| ![History](assets/screenshots/harmonyos/redemption-history.png) | ![Packs](assets/screenshots/harmonyos/pack-manager.png) | ![PIN](assets/screenshots/harmonyos/parent-pin-setup.png) |

| Config (scroll 1–4) | Parent admin (portrait scroll 1–4) | Bound child profile |
| --- | --- | --- |
| ![C1](assets/screenshots/harmonyos/config-part1.png) | ![A1](assets/screenshots/harmonyos/parent-admin-part1.png) | ![Child](assets/screenshots/harmonyos/bound-device-info.png) |
| ![C2](assets/screenshots/harmonyos/config-part2.png) | ![A2](assets/screenshots/harmonyos/parent-admin-part2.png) | |
| ![C3](assets/screenshots/harmonyos/config-part3.png) | ![A3](assets/screenshots/harmonyos/parent-admin-part3.png) | |
| ![C4](assets/screenshots/harmonyos/config-part4.png) | ![A4](assets/screenshots/harmonyos/parent-admin-part4.png) | |

| Dev menu (debug) | Vercel bypass secret |
| --- | --- |
| ![Dev menu](assets/screenshots/harmonyos/dev-menu.png) | ![Bypass](assets/screenshots/harmonyos/bypass-secret.png) |

**Not automated in the capture script (environment-dependent):**

- **`pages/ScanBindingPage`** — the bind button is hidden when the device already has a parent binding; capture `scan-binding.png` manually from an **unbound** install or after clearing binding.
- **`pages/LessonDraftReviewPage`** — needs at least one server-backed lesson draft in **pending**; capture manually from Parent admin when a row exists.

### iOS (planned)

Place future App Store / parity screenshots under [`assets/screenshots/ios/`](assets/screenshots/ios/).

### Android (planned)

Place future Play Store / parity screenshots under [`assets/screenshots/android/`](assets/screenshots/android/).

## Highlights

- **儿童友好的战斗学习循环**：选择正确单词会释放魔法攻击，答错会受到怪物反击，反馈直接、规则轻量。
- **多题型词汇训练**：支持三选一、补字母、完整拼写等题型，用不同怪物承载不同学习挑战。
- **今日冒险**：按主题区域生成每日练习计划，混合复习词、学习中词和新词。
- **本地学习记录**：记录词汇掌握状态，区分新词、学习中、熟悉、掌握，并支撑复习安排。
- **魔法愿望单**：完成冒险和击败怪物获得魔法币，孩子可以向家长申请兑换愿望。
- **怪物图鉴与主题区域**：包含 Slime、Zombie、Dragon 以及多个童话风 Boss，覆盖水果森林、学校城堡、家庭小屋、动物 Safari、海洋王国等区域。
- **离线优先**：首版词库、角色、怪物、音效和学习数据均在本地运行，适合平板短时练习。

## Tech Stack

- HarmonyOS NEXT client under `harmonyos/`
- ArkTS / ArkUI
- DevEco Studio managed project
- Python / FastAPI backend under `server/`
- Local rawfile assets for words, characters, icons, and sound effects

## Project Structure

```text
harmonyos/   HarmonyOS NEXT client; open this directory in DevEco Studio
ios/         Native iOS client placeholder; Swift / SwiftUI later
android/     Native Android client placeholder; Kotlin / Jetpack Compose later
server/      FastAPI content backend, parent web, device APIs, Vercel config
shared/      Contracts, schemas, and golden fixtures only
assets/      Design-source assets; per-platform screenshots under assets/screenshots/{harmonyos,ios,android}/
docs/        Product specs, roadmap, implementation plans, and runbooks
tools/       Asset generation and deployment helpers
scripts/     Root orchestration scripts
```

Documentation: [overall spec](docs/WordMagicGame_overall_spec.md) · [roadmap](docs/WordMagicGame_roadmap.md)

## Local Development

Open the HarmonyOS project in DevEco Studio from:

```text
/Users/bytedance/Projects/happyword/harmonyos
```

Install HarmonyOS dependencies:

```bash
cd harmonyos && ohpm install
```

Build debug HAP:

```bash
cd harmonyos && hvigorw assembleHap
```

Run CodeLinter after a successful HAP build:

```bash
cd harmonyos && codelinter -c ./code-linter.json5 . --fix
```

Connect a device or emulator:

```bash
hdc list targets
```

Install the built HAP:

```bash
hdc install harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
```

Run **no-device unit tests** (`harmonyos/entry/src/test/`):

```bash
cd harmonyos && hvigorw -p module=entry@default test
```

Run **on-device UI / Instrument tests** (`harmonyos/entry/src/ohosTest/`) with the project orchestrator — starts `server/mock_ui_server.py`, sets up `hdc rport`, installs HAPs, and runs `aa test`:

```bash
scripts/run_ui_tests.sh
```

Expect `TestFinished-ResultCode: 0` and `OHOS_REPORT_CODE: 0` when the suite passes. You need a connected device or emulator (`hdc list targets`).

The detailed build, test, device, and log workflow lives in [`.cursor/dev-commands.md`](.cursor/dev-commands.md).

### Debug: backend environment

Debug builds can switch API base URL at runtime (local machine, a Vercel preview deployment, or staging). Open the developer menu by **triple-tapping** the small grey **version label** at the **top-left of the home screen** (there is no Settings entry). The menu shows a card grid — **tap a card to apply** immediately (Preview runs a health probe first and may ask for a Vercel protection-bypass secret). The preview PR list is always fetched from production **`https://happyword.cool/api/v1/preview-urls.json`**, independent of the env you selected. Release builds hide the label and this flow. See [DevMenu runbook](docs/superpowers/runbooks/dev-menu-runbook.md), [backend env switcher spec](docs/superpowers/specs/2026-05-06-client-backend-env-switcher-design.md), and [triple-tap / DevMenu UI spec](docs/superpowers/specs/2026-05-07-home-version-triple-tap-design.md).

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
