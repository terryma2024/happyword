# Monster Codex Progress v1.0.2 — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

Paste evidence (paths to logs, commit SHAs, screenshot folders) next to each item before checking it.

- [x] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: local run on 2026-06-05, `BUILD SUCCESSFUL`; includes `MonsterProgressStore.test.ets`, `CoinAccount.test.ets`, and `MonsterCodex.test.ets`.
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: not run in this pass; requires HarmonyOS UI test target.
- [x] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: local run on 2026-06-05, `BUILD SUCCESSFUL`, no `ArkTS:WARN` lines observed.
- [x] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: local run on 2026-06-05, `No defects found in your code.`
- [x] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=1.0.1` `versionCode=1010001`
  - To: `versionName=1.0.2` `versionCode=1020001`
- [ ] **Feature merged to main**
  - Commit: pending
- [ ] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`: pending
- [x] **Server contracts up to date** — N/A; this feature is local client state only.
  - Regenerated: N/A
  - Tests: N/A
  - Fixture diffs: N/A

## 2. Delta Letter

This section is filled after HarmonyOS stabilization. iOS and Android agents consume it verbatim.

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Models | `harmonyos/entry/src/main/ets/data/MonsterCodex.ets` |
| Services | `harmonyos/entry/src/main/ets/services/MonsterProgressStore.ets`, `harmonyos/entry/src/main/ets/services/CoinAccount.ets` |
| Pages | `harmonyos/entry/src/main/ets/pages/MonsterCodexPage.ets`, `harmonyos/entry/src/main/ets/pages/BattlePage.ets` |
| Tests | `harmonyos/entry/src/test/MonsterProgressStore.test.ets`, `harmonyos/entry/src/test/CoinAccount.test.ets`, `harmonyos/entry/src/test/MonsterCodex.test.ets` |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| `monster_progress/snapshot_v1` | JSON string | `{"version":1,"records":[]}` | No older snapshot exists. |

### 2.3 Stable IDs introduced or changed

> Cross-link to [`00-design.md`](00-design.md) §5.

| ID | Where | Notes |
| --- | --- | --- |
| `CodexDefeatCount` | Monster Codex | New. |
| `CodexReward50Button` | Monster Codex | New. |
| `CodexReward100Button` | Monster Codex | New. |

### 2.4 Edge cases discovered during stabilization

- Locked entries hide defeat count and reward buttons entirely.
- Encountered entries always render both milestone buttons; labels become claimable only at 50 / 100 defeats and disabled again after claiming.
- Reaching 100 defeats before claiming the 50-tier still allows both claims.
- Monster rewards use cap-free coin credit and do not mutate the daily 20-coin earned counter.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |
| `harmonyos/entry/src/test/MonsterProgressStore.test.ets` | [ ] | [ ] |
| `harmonyos/entry/src/test/MonsterCodex.test.ets` | [ ] | [ ] |
| Codex ohosTest flow for locked / disabled / claimable / claimed states | [ ] | [ ] |

### 2.6 Pitfalls / "do not repeat my mistakes"

- Keep the original monster keys, asset paths, and catalog order stable when changing display names.
- The mystery image must be copied to `rawfile/character/` as well as retained under `assets/icons/`.
- Do not mark `replication_approved: true` until the human owner reviews the HarmonyOS screen states.

## 3. Open Questions for the Replicas

None.

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by:
approved_at:
replication_approved: false
notes:
```
