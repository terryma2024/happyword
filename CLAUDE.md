# WordMagicGame monorepo guide

## Stack
- HarmonyOS NEXT client: `harmonyos/`, ArkTS / ArkUI, DevEco Studio managed project
- iOS client: `ios/`, native Swift / SwiftUI when implementation starts
- Android client: `android/`, native Kotlin / Jetpack Compose when implementation starts
- Server: `server/`, Python / FastAPI / MongoDB / Vercel
- Shared contracts: `shared/`, schemas and fixtures only; no shared client runtime

## Commands
- **HarmonyOS phased build/test commands, log paths, and device rules:** [`.cursor/ohos-dev-commands.md`](.cursor/ohos-dev-commands.md) (source of truth for Harmony autofix skills).
- Harmony install deps: `cd harmonyos && ohpm install`
- Harmony build debug HAP: `cd harmonyos && hvigorw assembleHap`
- The HAP build log must have **no** `ArkTS:WARN` lines (deprecated APIs); see [`.cursor/ohos-dev-commands.md`](.cursor/ohos-dev-commands.md) **ArkTS compiler warnings**.
- After a successful HAP build, run CodeLinter: `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
- Harmony build module: `cd harmonyos && hvigorw --mode module -p module=entry assembleHap`
- Connect device: `hdc list targets`
- Install app: `hdc install harmonyos/entry/build/default/outputs/default/entry-default-signed.hap`
- Server tests: `cd server && uv run pytest`
- **Cocos battle scene (V1.1.0, iOS-embedded):** project root `cocos/` (Cocos Creator 3.8). TS unit tests: `cd cocos && npm test`. Headless iOS build: `tools/cocos/build-ios.sh` (quits the editor; rebuilds data + arm64 device engine libs). Art under `cocos/assets/resources/art/` is generated — edit SVG sources in the iOS asset catalog, then rerun `tools/cocos/sync-art.sh`. Embed recipe and gotchas: [`cocos/README.md`](cocos/README.md). Cocos battle runs on device builds only; simulator falls back to the native BattleView.

## Rules
- For HarmonyOS feature work, use ArkTS only and prefer modifying `harmonyos/entry/src/main/ets`.
- Keep `harmonyos/` as a complete DevEco Studio project root. Explain any Hvigor or DevEco project-file changes before editing.
- Do not add shared client runtime code under `shared/`; use it only for contracts, schemas, and fixtures.
- Do not replace project structure unless necessary.
- Keep UI components small and reusable
- For all feature development and bugfix tasks, use the applicable Superpowers workflow before implementing changes.
- Debug builds only: **Settings → Developer → Backend environment** opens the DevMenu for switching staging / local / preview API routing; release builds must not expose this entry.
- **ohosTest UI automation** excludes DevMenu and the version-label triple-tap path — developers exercise those manually; see [`.cursor/ohos-dev-commands.md`](.cursor/ohos-dev-commands.md) section 4.

## Three-platform feature lifecycle

Every product feature added *after* the initial HarmonyOS / iOS / Android baselines follows the SOP at [`docs/sop/00-three-platform-feature-sop.md`](docs/sop/00-three-platform-feature-sop.md). The orchestrator skill is [`.cursor/skills/three-platform-feature-orchestrator/SKILL.md`](.cursor/skills/three-platform-feature-orchestrator/SKILL.md).

- HarmonyOS first: design, build, stabilize. iOS and Android replicate **in parallel** afterwards from a frozen design + signed delta letter; replicas do not redesign.
- One folder per feature: `docs/features/<feature-id>/` with `00-design.md`, `10-harmony-plan.md`, `20-replication-trigger.md`, `30-ios-plan.md`, `40-android-plan.md`, `50-parity-checklist.md`. Templates: [`docs/sop/templates/`](docs/sop/templates/). Worked example: [`docs/features/_example/`](docs/features/_example/). Index: [`docs/features/README.md`](docs/features/README.md).
- Replication gate: soft (Harmony tests / `0` `ArkTS:WARN` / CodeLinter / version bump / screenshots / contracts) **plus** a human-confirm signature block at the bottom of `20-replication-trigger.md` (`replication_approved: true`). **iOS / Android agents must refuse to start Stage 4 without the signature.**
- Bugfixes that change shared semantics reopen the parity checklist via `60-followups.md`; platform-local bugfixes do not.
- The one-time port plans under [`docs/ios-replica/`](docs/ios-replica/) and [`docs/android-replica/`](docs/android-replica/) remain the V0.6.7.8 bootstrap reference and are **not** part of this lifecycle.

## Asset retention policy
- **Never delete resource files (SVG / PNG / audio / fonts / image source) when they become unused at runtime.** Move them under `assets/` instead — e.g. `assets/icons/` for design-source SVGs whose rasterized PNGs ship in `harmonyos/entry/src/main/resources/rawfile/`. This keeps the design source available for re-rasterization, redesign, rollback, or A/B comparison.
- The same applies to retired UI mockups, deprecated audio takes, and old illustration variants — back them up under `assets/<category>/` and add a one-line entry in the matching `assets/<category>/README.md`.
- Code files (`.ets`, `.ts`, `.py`) follow the normal git-history-as-backup model and do **not** need to be moved — only binary / design-source resources.

## Server (`server/`) discipline
- Every commit that touches `server/` MUST run `uv run pytest` with **0 errors and 0 warnings**.
- `pyproject.toml` sets `filterwarnings = ["error", ...]` so any new warning fails the suite.
- If a warning comes from a third-party dependency we cannot fix, add a *narrow* `ignore:...` entry to `[tool.pytest.ini_options].filterwarnings` with a comment explaining the source and why we cannot resolve it upstream.
- Never use a blanket `ignore` (e.g. `ignore::DeprecationWarning`) — always pin by message + module.

## Cursor Cloud specific instructions

This section captures non-obvious caveats for cloud agents working on the
**`server/`** Python backend. The HarmonyOS client (`harmonyos/entry/`) is **not** set up
on cloud agent VMs — those workflows still require DevEco Studio + HarmonyOS
SDK on a developer machine. If a task touches the client, escalate / run it
locally instead of in the cloud agent.

### Server scope (what cloud agents can do here)
- `cd server && uv sync` — refresh deps. Already covered by the cloud agent
  update script, so this typically only matters when iterating manually after
  editing `pyproject.toml`.
- `cd server && uv run pytest` — full suite is **offline**. MongoDB is mocked
  via `mongomock-motor`, HTTP via stubs. No services need to be running.
  Project rule: must finish with **0 errors, 0 warnings**.
- `cd server && uv run ruff check .` and `uv run mypy .` — lint / type-check.
  Both currently report a small number of pre-existing findings (e.g. in
  `server/mock_ui_server.py`, `server/scripts/`, and a few `tests/`
  files); only fix the ones in files you actually touch.
- `cd server && uv run ruff check . --fix` — apply ruff auto-fixes.

### Running the server locally (uvicorn)
Tests don't need MongoDB, but **`uv run uvicorn app.main:app` does**, because
the FastAPI lifespan opens a real Mongo connection via Motor + Beanie
(`init_beanie` + `bootstrap_admin_user`). The cloud agent VM snapshot ships
with **MongoDB 8.0** already installed (apt), but **not** running, because the
VM has no systemd. Start it manually before running the server:

```sh
mongod --dbpath /var/lib/mongodb \
       --logpath /var/log/mongodb/mongod.log \
       --bind_ip 127.0.0.1 --port 27017 --fork
```

The data dir `/var/lib/mongodb` and log dir `/var/log/mongodb` are owned by
`ubuntu:ubuntu` so no `sudo` is needed once the VM is up.

Then create `server/.env.local` (already gitignored — see
`server/.env.local.example` for the schema) with at minimum:

```
MONGODB_URI=mongodb://127.0.0.1:27017
MONGO_DB_NAME=happyword_dev
JWT_SECRET=<any-32-char-string-for-local-dev>
ADMIN_BOOTSTRAP_USER=admin
ADMIN_BOOTSTRAP_PASS=<choose-a-local-password>
```

`OPENAI_API_KEY` and `BLOB_READ_WRITE_TOKEN` are optional — LLM /
asset-upload endpoints will return config errors without them, but everything
else (auth, words, packs, public `/api/v1/public/packs/latest.json`) works fine.

Start the dev server (foreground or via tmux):

```sh
cd server && uv run uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

### Public health endpoint is namespaced
The health route is `GET /api/v1/public/health`, **not** `/health`. The unprefixed
path returns 404 (this surprised me on first run).

### Mock UI server (separate from main server)
`server/mock_ui_server.py` is a **separate** stub-only FastAPI app used by the
HarmonyOS `ohosTest` UI suite (`scripts/run_ui_tests.sh`). It listens on port
8123, has no MongoDB dependency, and is irrelevant when developing the main
backend. Don't confuse it with `app.main:app`.

### Vercel deployment
The `server/` app is also deployed as Vercel serverless functions
(`server/vercel.json` + `server/api/index.py` → `app.main:app`; Vercel Root Directory = `server`). Local
development does **not** require the Vercel CLI; only deployment does. See
`tools/vercel/` for the deploy/smoke shell scripts.
