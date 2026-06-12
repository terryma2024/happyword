# Small Magician Word Adventure

魔法背单词是一个面向儿童的英语单词学习冒险产品。游戏把单词练习包装成“小魔法师对战怪物”的轻量冒险：孩子在横屏战斗中识别单词、补全拼写、积累魔法币，并通过每日计划和学习报告持续复习。

仓库现在按 monorepo 组织：`harmonyos/`、`ios/`、`android/` 三个原生客户端与 `server/` 后端并列推进，`shared/` 只保存跨端契约、schema 和测试 fixtures。HarmonyOS NEXT 是参考实现；iOS / Android 已按原生 SwiftUI / Jetpack Compose 方向复制主要产品闭环，并通过三端 feature SOP 持续对齐。

**路线图（里程碑与后续方向）：** [`docs/WordMagicGame_roadmap.md`](docs/WordMagicGame_roadmap.md)

## Download

- iOS: [App Store 下载](https://apps.apple.com/cn/app/%E9%AD%94%E6%B3%95%E8%83%8C%E5%8D%95%E8%AF%8D/id6768499286)
- HarmonyOS: [华为应用市场下载](https://appgallery.huawei.com/app/detail?id=com.terryma.wordmagicgame)

## Screenshots

Clients ship separate binaries; screenshots are grouped **by platform** under [`assets/screenshots/`](assets/screenshots/).

### HarmonyOS NEXT (reference UI)

Captured from the current HarmonyOS device/emulator state. Gameplay and most child-facing surfaces are landscape; configuration and longer management surfaces are portrait after the recent orientation pass. Some long-page archives still keep numbered strips under `assets/screenshots/harmonyos/`, but this README shows one representative image per surface. Regenerate on a connected device or emulator with:

`python3 scripts/capture_harmony_screenshots.py` (see script docstring; requires `hdc`).

| Landscape: battle | Landscape: result | Landscape: question types |
| --- | --- | --- |
| ![HarmonyOS battle](assets/screenshots/harmonyos/battle.png) | ![HarmonyOS result](assets/screenshots/harmonyos/result.png) | ![HarmonyOS question types](assets/screenshots/harmonyos/config-question-types.png) |

| Landscape: daily check-in | Landscape: monster codex | Landscape: wishlist |
| --- | --- | --- |
| ![HarmonyOS daily check-in](assets/screenshots/harmonyos/daily-checkin-calendar.png) | ![HarmonyOS monster codex](assets/screenshots/harmonyos/monster-codex-part1.png) | ![HarmonyOS wishlist](assets/screenshots/harmonyos/wishlist.png) |

| Portrait: config | Portrait: today plan | Portrait: pack manager |
| --- | --- | --- |
| ![HarmonyOS config](assets/screenshots/harmonyos/config-part1.png) | ![HarmonyOS today plan](assets/screenshots/harmonyos/today-plan.png) | ![HarmonyOS pack manager](assets/screenshots/harmonyos/pack-manager.png) |

| Portrait: learning report | Portrait: redemption history | Portrait: parent admin |
| --- | --- | --- |
| ![HarmonyOS learning report](assets/screenshots/harmonyos/learning-report-part1.png) | ![HarmonyOS redemption history](assets/screenshots/harmonyos/redemption-history.png) | ![HarmonyOS parent admin](assets/screenshots/harmonyos/parent-admin-part1.png) |

**Capture notes:**

- V0.9.1 full UI automation is green on HarmonyOS, but the screenshot script remains environment-sensitive. The latest run refreshed several HarmonyOS PNGs and still reported failed/skipped steps for battle/result, parent PIN/admin, and scan-binding states.
- **`pages/ScanBindingPage`** — the bind button is hidden when the device already has a parent binding; capture `scan-binding.png` manually from an **unbound** install or after clearing binding.
- **`pages/LessonDraftReviewPage`** — needs at least one server-backed lesson draft in **pending**; capture manually from Parent admin when a row exists.

### iOS

Native SwiftUI client screenshots live under [`assets/screenshots/ios/`](assets/screenshots/ios/). Child-facing and settings routes below are landscape; Parent Admin is portrait. V0.9.1 sentence cloze and the missing Home / Config / Parent Admin screenshots were captured from the iPhone simulator after the full XCUITest suite passed.

| Landscape: home | Landscape: config | Landscape: sentence cloze battle |
| --- | --- | --- |
| ![iOS home](assets/screenshots/ios/home.png) | ![iOS config](assets/screenshots/ios/config.png) | ![iOS sentence cloze](assets/screenshots/ios/sentence-cloze-battle.png) |

| Landscape: daily check-in | Landscape: today plan | Portrait: parent admin |
| --- | --- | --- |
| ![iOS daily calendar](assets/screenshots/ios/daily-checkin-calendar.png) | ![iOS today plan](assets/screenshots/ios/daily-checkin-today-plan.png) | ![iOS parent admin](assets/screenshots/ios/parent-admin.png) |

### Android

Native Jetpack Compose client screenshots live under [`assets/screenshots/android/`](assets/screenshots/android/). Gameplay and most child-facing routes are landscape; Config and parent/admin flows are portrait. V0.9.1 config and sentence cloze screenshots were refreshed after the full connected UI suite passed.

| Landscape: home | Landscape: battle | Landscape: sentence cloze battle |
| --- | --- | --- |
| ![Android home](assets/screenshots/android/home.png) | ![Android battle](assets/screenshots/android/battle.png) | ![Android sentence cloze](assets/screenshots/android/sentence-cloze-battle.png) |

| Landscape: result | Portrait: config | Portrait: parent admin |
| --- | --- | --- |
| ![Android result](assets/screenshots/android/result.png) | ![Android config](assets/screenshots/android/config-landscape.png) | ![Android parent admin](assets/screenshots/android/parent-admin.png) |

## Highlights

- **儿童友好的战斗学习循环**：选择正确单词会释放魔法攻击，答错会受到怪物反击，反馈直接、规则轻量。
- **多题型词汇训练**：支持三选一、补字母、完整拼写等题型，用不同怪物承载不同学习挑战。
- **今日冒险**：按主题区域生成每日练习计划，混合复习词、学习中词和新词。
- **本地学习记录**：记录词汇掌握状态，区分新词、学习中、熟悉、掌握，并支撑复习安排。
- **魔法愿望单**：完成冒险和击败怪物获得魔法币，孩子可以向家长申请兑换愿望。
- **怪物图鉴与主题区域**：包含 Slime、Zombie、Dragon 以及多个童话风 Boss，覆盖水果森林、学校城堡、家庭小屋、动物 Safari、海洋王国等区域。
- **离线优先**：首版词库、角色、怪物、音效和学习数据均在本地运行，适合平板短时练习。

## Tech Stack

- HarmonyOS NEXT client: `harmonyos/`, ArkTS / ArkUI, DevEco Studio managed project
- iOS client: `ios/`, native Swift / SwiftUI
- Android client: `android/`, native Kotlin / Jetpack Compose
- Server: `server/`, Python / FastAPI / MongoDB / Vercel
- Shared contracts: `shared/`, schemas and golden fixtures only; no shared client runtime
- Assets: local rawfile assets plus durable design-source assets under `assets/`

## Project Structure

```text
harmonyos/   HarmonyOS NEXT client; open this directory in DevEco Studio
ios/         Native iOS client; Swift / SwiftUI
android/     Native Android client; Kotlin / Jetpack Compose
server/      FastAPI content backend, parent web, device APIs, Vercel config
shared/      Contracts, schemas, and golden fixtures only
assets/      Design-source assets; per-platform screenshots under assets/screenshots/{harmonyos,ios,android}/
docs/        Product specs, roadmap, implementation plans, and runbooks
tools/       Asset generation and deployment helpers
scripts/     Root orchestration scripts
```

Documentation: [overall spec](docs/WordMagicGame_overall_spec.md) · [roadmap](docs/WordMagicGame_roadmap.md)

## Local Development

Each top-level module owns its own toolchain. HarmonyOS is the reference client; iOS and Android are native clients that replicate the shared product contract. Server development and tests are independent of the client SDKs.

### HarmonyOS client

Open the HarmonyOS project in DevEco Studio from:

```text
harmonyos/
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

The detailed build, test, device, and log workflow lives in [`.cursor/ohos-dev-commands.md`](.cursor/ohos-dev-commands.md).

### Debug: backend environment

Debug builds can switch API base URL at runtime (local machine, a Vercel preview deployment, or staging). Open the developer menu by **triple-tapping** the small grey **version label** at the **top-left of the home screen** (there is no Settings entry). The menu shows a card grid — **tap a card to apply** immediately (Preview runs a health probe first and may ask for a Vercel protection-bypass secret). The preview PR list is always fetched from production **`https://happyword.cool/api/v1/public/preview-urls.json`**, independent of the env you selected. Release builds hide the label and this flow. See [DevMenu runbook](docs/superpowers/runbooks/dev-menu-runbook.md), [backend env switcher spec](docs/superpowers/specs/2026-05-06-client-backend-env-switcher-design.md), and [triple-tap / DevMenu UI spec](docs/superpowers/specs/2026-05-07-home-version-triple-tap-design.md).

### iOS client

The iOS module lives at [`ios/`](ios/) and uses native Swift / SwiftUI. It mirrors product contracts through `shared/` fixtures while keeping runtime code native to iOS.

Regenerate the Xcode project after changing `ios/project.yml` or target membership:

```bash
/opt/homebrew/bin/xcodegen generate --spec ios/project.yml --project ios
```

Build the simulator app:

```bash
cd ios && xcodebuild build -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/wordmagic-dd
```

Run XCTest unit tests:

```bash
cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests -derivedDataPath /private/tmp/wordmagic-dd
```

Run XCUITest UI tests:

```bash
cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameUITests -derivedDataPath /private/tmp/wordmagic-dd
```

Run the full iOS test suite:

```bash
cd ios && xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/wordmagic-dd
```

Boot, install, and launch the latest simulator build:

```bash
xcrun simctl boot 'iPhone 17 Pro'
xcrun simctl install booted /private/tmp/wordmagic-dd/Build/Products/Debug-iphonesimulator/WordMagicGame.app
xcrun simctl launch booted com.terryma.wordmagicgame -UITestResetState
```

The detailed iOS build, test, simulator, screenshot, and log workflow lives in [`.cursor/ios-dev-commands.md`](.cursor/ios-dev-commands.md).

### Android client

The Android module lives at [`android/`](android/) and uses native Kotlin / Jetpack Compose. It uses the same shared contracts and server APIs without introducing a cross-platform client runtime.

Check the Gradle / Android SDK environment:

```bash
cd android && ./gradlew -version
cd android && ./gradlew :app:tasks --all
```

Run JVM unit tests:

```bash
cd android && ./gradlew testDebugUnitTest
```

Build debug APK:

```bash
cd android && ./gradlew assembleDebug
```

Connect an emulator or device:

```bash
$ANDROID_HOME/platform-tools/adb devices
```

Install and launch the debug app:

```bash
cd android && ./gradlew installDebug
$ANDROID_HOME/platform-tools/adb shell am start -n cool.happyword.wordmagic/.MainActivity
```

Run connected Compose UI tests:

```bash
cd android && ./gradlew connectedDebugAndroidTest
```

When more than one Android device is online, set `ANDROID_SERIAL=<serial>` before Gradle install / UI-test commands, and use `adb -s <serial>` only for `adb` commands.

The detailed Android build, test, emulator, install, screenshot, and log workflow lives in [`.cursor/android-dev-commands.md`](.cursor/android-dev-commands.md).

## Server

The Python/FastAPI content backend lives under [`server/`](server/). It now covers the content CMS, parent-facing web shell, child-device APIs, and deployment support surfaces:

- **Admin console / CMS**: global words, categories, global pack drafts, publish / rollback, asset upload, LLM-assisted drafts, audit logs, parent/device/family-pack operations, system config, stats, and cron/admin maintenance routes.
- **Parent web + account flows**: OTP and password login, Google / Apple / WeChat / Alipay OAuth handoff, settings, support / privacy pages, feedback, parent inbox, redemption review, account deletion, device management, and family pack editing.
- **Child-device APIs**: device pairing and token auth, public/global pack sync, family pack sync, child profile, check-in calendar, word-stat sync, cloud wishlist, magic coin transactions, and redemption requests.
- **Lesson / AI import**: lesson image upload, LLM extraction drafts, parent/admin review flows, and family-pack import helpers.
- **Deployment / QA tooling**: Vercel serverless entrypoint, preview manifest support, staging smoke tests, offline pytest, preview E2E, and Mongo-backed local development.

Install dependencies:

```bash
cd server && uv sync
```

Run the local API after creating `server/.env.local` from `server/.env.local.example` and starting a local MongoDB:

```bash
cd server && uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

Run the offline test suite:

```bash
cd server && uv run pytest
```

Run quality checks:

```bash
cd server && uv run ruff check .
cd server && uv run ruff format --check .
cd server && uv run mypy app
```

Run deployed-server E2E tests after configuring `E2E_BASE_URL`, `E2E_MONGODB_URI`, `E2E_MONGO_DB_NAME`, and matching admin credentials:

```bash
cd server && uv run pytest -v -m e2e
```

Run staging smoke tests:

```bash
cd server && uv run pytest -v -m smoke
```

For the full local dev setup, MongoDB notes, offline / E2E / smoke workflows, and Vercel deployment details, see [`server/README.md`](server/README.md). Design references start from [V0.5 backend design](docs/superpowers/specs/2026-04-30-v0.5-content-backend-design.md) and the current QA pipeline in [server QA pipeline design](docs/superpowers/specs/2026-05-06-server-qa-pipeline-design.md).

## CI / GitHub Actions

Server automation is in a Vercel-to-CloudBase transition period. Both deployment paths are still represented in GitHub Actions:

- **`server-ci`** (`.github/workflows/server-ci.yml`): runs on PRs touching `server/**` and on manual dispatch. It runs offline `uv run pytest -v` on GitHub-hosted Ubuntu, uploads the server source as a short-lived artifact, then runs CloudBase staging E2E on the Beijing self-hosted runner when CloudBase / E2E secrets are configured.
- **`server-cd`** (`.github/workflows/server-cd.yml`): runs after pushes to `main` touching `server/**`; waits for the Vercel production deployment URL and runs the HTTP-only smoke subset (`pytest -m smoke`).
- **`server-cloudbase-cd`** (`.github/workflows/server-cloudbase-cd.yml`): runs after pushes to `main` and on manual dispatch; deploys `server/` to CloudBase Run, waits for 100% traffic, checks `/api/v1/public/health`, and runs smoke tests against `CLOUDBASE_PROD_BASE_URL`.
- **`preview-manifest`** (`.github/workflows/preview-manifest.yml`): legacy Vercel Blob preview-manifest cleanup / manual repair for closed PRs while Vercel Preview remains available.
- **`atlas-cleanup`** (`.github/workflows/atlas-cleanup.yml`): weekly and manual cleanup for stale per-PR Mongo Atlas E2E databases older than 14 days.
- **`vercel-prune`** (`.github/workflows/vercel-prune.yml`): weekly and manual pruning of old non-main Vercel deployments; production aliases are preserved.

The CloudBase staging E2E runner expects `python3.12`, `jq`, Node/npm, CloudBase CLI access, and `/usr/local/bin/uv`; it uses the Tencent Cloud PyPI mirror and shared staging database reset flow instead of deploying a per-PR Vercel preview. Missing optional secrets generally make gated jobs print warnings and skip their external path rather than failing first-time setup.

All required and optional secrets are documented — including Vercel legacy secrets, CloudBase Run credentials, CloudBase staging/prod URLs, E2E Mongo settings, cron secret, Slack alert webhook, COS / Mongo migration placeholders, and what breaks when each is missing — in [`docs/ci-secrets.md`](docs/ci-secrets.md). Read that page first when forking the repo or bringing up CI from scratch.

## Roadmap

The product roadmap — milestones, version threads, and planned work — lives in **[`docs/WordMagicGame_roadmap.md`](docs/WordMagicGame_roadmap.md)**. For product intent and scope, see also **[`docs/WordMagicGame_overall_spec.md`](docs/WordMagicGame_overall_spec.md)**.

Current major directions include battle audio mixing with BGM, richer learning reports, backend content tooling, parent account/device binding, AI-assisted story content, and a later Cocos2D battle presentation rewrite.
