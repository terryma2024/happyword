# V0.8.6 — 怪物等级积分金币 — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

Paste evidence (paths to logs, commit SHAs, screenshot folders) next to each item before checking it.

- [ ] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence: Pending HarmonyOS implementation.
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence: Pending HarmonyOS implementation.
- [ ] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence: Pending HarmonyOS implementation.
- [ ] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence: Pending HarmonyOS implementation.
- [ ] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: Pending HarmonyOS implementation.
  - To: Pending HarmonyOS implementation.
- [ ] **Feature merged to main**
  - Commit: Pending HarmonyOS implementation.
- [ ] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`: Pending HarmonyOS implementation.
- [ ] **Server contracts up to date** — not required; this is a client-only reward-rule change.
  - Regenerated: N/A
  - Tests: N/A
  - Fixture diffs: N/A

## 2. Delta Letter

Filled after HarmonyOS stabilization. iOS and Android agents must not start until §4 is signed.

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Models | Pending HarmonyOS implementation. |
| Services | Pending HarmonyOS implementation. |
| Pages | Pending HarmonyOS implementation. |
| Tests | Pending HarmonyOS implementation. |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

No new persistence keys.

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| Existing coin ledger | Platform-local wallet model | Existing default | Existing balances remain unchanged; future battle rewards use monster-level score. |

### 2.3 Stable IDs introduced or changed

No new stable IDs are planned.

| ID | Where | Notes |
| --- | --- | --- |
| Existing result/home coin labels | Result and Home screens | Continue to assert displayed earned coins / balance. |

### 2.4 Edge cases discovered during stabilization

- Pending HarmonyOS implementation.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |
| Pending HarmonyOS implementation. | Pending Stage 4a. | Pending Stage 4b. |

### 2.6 Pitfalls / "do not repeat my mistakes"

- Pending HarmonyOS implementation.

## 3. Open Questions for the Replicas

No open questions. The written design states that monster-level score completely replaces star and Bonus coin formulas.

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by:
approved_at:
replication_approved: false
notes:
```
