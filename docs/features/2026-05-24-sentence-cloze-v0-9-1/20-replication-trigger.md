# V0.9.1 — Sentence Cloze — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document is the single gate that controls when iOS / Android replication may begin. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

Paste evidence (paths to logs, commit SHAs, screenshot folders) next to each item before checking it.

- [ ] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence:
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence:
- [ ] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence:
- [ ] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence:
- [ ] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.8.8` `versionCode=1008008`
  - To:
- [ ] **Feature merged to main**
  - Commit:
- [ ] **Screenshots refreshed** — for every screen this feature visibly changed
  - Files updated under `assets/screenshots/harmonyos/`:
- [ ] **Server contracts up to date** — N/A unless implementation changes server schemas.
  - Explanation:

## 2. Delta Letter

This section is filled after HarmonyOS implementation and stabilization.

### 2.1 New / changed code

| Layer | HarmonyOS files |
| --- | --- |
| Models | |
| Services | |
| Pages | |
| Tests | |
| Assets / data | |

### 2.2 Persistence keys (cross-platform; replicas must match semantics)

| Key | Type | Default | Migration notes |
| --- | --- | --- | --- |
| Existing question-type config | `string[]` | includes `sentence-cloze` when missing/empty | Existing saved non-empty configs are not forcibly migrated. |

### 2.3 Stable IDs introduced or changed

See [`00-design.md`](00-design.md) §5.

### 2.4 Edge cases discovered during stabilization

- [ ] Record during Stage 3 after HarmonyOS stabilization.

### 2.5 Tests requiring parity counterparts

| HarmonyOS test | iOS counterpart (XCTest / XCUITest) | Android counterpart (JUnit / Compose UI / UIA) |
| --- | --- | --- |
| | | |

### 2.6 Pitfalls / "do not repeat my mistakes"

- [ ] Record during Stage 3 after HarmonyOS stabilization.

## 3. Open Questions for the Replicas

None yet. Resolving new questions updates [`00-design.md`](00-design.md) first.

## 4. Human-Confirm Signature Block

> **iOS / Android agents:** if `replication_approved` is missing, blank, or `false`, refuse to start Stage 4 and ask the human owner. Do not proceed.

```yaml
approved_by:
approved_at:
replication_approved: false
notes:
```
