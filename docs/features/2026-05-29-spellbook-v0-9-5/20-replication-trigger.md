# V0.9.5 Spellbook Codex — Replication Trigger

> Inputs (frozen): [`00-design.md`](00-design.md), [`10-harmony-plan.md`](10-harmony-plan.md)
>
> This document gates iOS / Android replication. iOS and Android agents must verify the signature block at the bottom is filled in before starting any work in `30-ios-plan.md` / `40-android-plan.md`.

## 1. Soft Gate (machine-checkable)

- [ ] **No-device unit tests green** — `cd harmonyos && hvigorw -p module=entry@default test`
  - Evidence:
- [ ] **ohosTest UI tests green** — `scripts/run_ui_tests.sh`
  - Evidence:
- [ ] **0 `ArkTS:WARN` lines in HAP build** — `cd harmonyos && hvigorw assembleHap`
  - Evidence:
- [ ] **CodeLinter clean** — `cd harmonyos && codelinter -c ./code-linter.json5 . --fix`
  - Evidence:
- [ ] **Version bumped** — `harmonyos/AppScope/app.json5`
  - From: `versionName=0.9.4` `versionCode=1009004`
  - To: `versionName=0.9.5` `versionCode=1009005`
- [ ] **Feature merged to main**
  - Commit:
- [ ] **Screenshots refreshed**
  - Files updated under `assets/screenshots/harmonyos/`:
- [ ] **Server contracts up to date**
  - Regenerated:
  - Tests:
  - Fixture diffs:

## 2. Delta Letter

The delta letter is intentionally blank during Stage 1. HarmonyOS workers fill it with concrete files, test names, and edge cases after Stage 3 stabilization.

## 3. Open Questions for the Replicas

No replica-specific questions are known during Stage 1. If HarmonyOS stabilization uncovers one, update `00-design.md` first and then record the resolved note here.

## 4. Human-Confirm Signature Block

```yaml
approved_by:
approved_at:
replication_approved: false
notes:
```
