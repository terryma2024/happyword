# <Feature Name> — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

Paste evidence (paths to logs, commit SHAs, screenshot folders) next to each item before checking it.

- [ ] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: <log path or commit SHA>
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: <`TestFinished-ResultCode: 0` line>
- [ ] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: <log path; verify per `.cursor/ohos-dev-commands.md` §1>
- [ ] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: <log path>
- [ ] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=<old>` `versionCode=<old>`
  - To: `versionName=<new>` `versionCode=<new>`
- [ ] **Feature merged to main**
  - Commit: <SHA / PR link>
- [ ] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`: <list>
- [ ] **Server contracts up to date** — required only if server changed; otherwise mark `N/A` and explain.
  - Regenerated: <commit touching `shared/contracts/openapi/`>
  - Tests: `cd server && uv run pytest tests/test_shared_contracts.py -q` <log link>
  - Fixture diffs: <list of `shared/fixtures/` paths>

## 2. Delta Letter

This section is the agent-readable summary that iOS and Android agents will consume verbatim. Be specific. Avoid prose; prefer lists.

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Models | <list> |
| Services | <list> |
| Pages | <list> |
| Tests | <list> |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |

### 2.3 Stable IDs introduced or changed

> Cross-link to [`00-design.md`](00-design.md) §5. List only deltas vs. that table.

| ID | Where | Notes |
| --- | --- | --- |

### 2.4 Edge cases discovered during stabilization

> "What the design didn't predict but Harmony work uncovered." iOS / Android plans must encode these from day one.

- <case 1>
- <case 2>

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |

### 2.6 Pitfalls / "do not repeat my mistakes"

- <pitfall 1>
- <pitfall 2>

## 3. Open Questions for the Replicas

If iOS / Android need clarifications that are not yet captured in `00-design.md`, list them here. Resolving them updates `00-design.md` first; only then do the questions get checked off.

- [ ] <question>

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by:
approved_at:
replication_approved: false
notes:
```
