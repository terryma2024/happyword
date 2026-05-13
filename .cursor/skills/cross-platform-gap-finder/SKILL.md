---
name: cross-platform-gap-finder
description: Use when checking WordMagicGame iOS or Android parity against HarmonyOS, investigating cross-platform behavior drift, visual drift, missing stable IDs, or deciding what replica gap to fix next.
---

# Cross-Platform Gap Finder

这个工具不是报告工具；它的第一目标是找出可修复的 iOS / Android gap。`gaps.md`、`gaps.json` 和 `visual-diffs/` 只是证据附件，行动项列表才是主输出。

## When To Use

Use this before fixing or reviewing cross-platform parity when the question is about:

- iOS / Android 是否复刻了 HarmonyOS 的预期行为。
- UI 风格、截图、布局是否和 HarmonyOS 漂移。
- Stable ID、XCUITest、Compose UI test、ohosTest 覆盖是否缺口。
- 从 `docs/superpowers/specs` 或 `docs/superpowers/plans` 找预期行为依据。

Do not use this as a substitute for platform build/test commands. It finds gaps; platform manifests still verify fixes.

## Required Command

Run from repo root:

```bash
uv run --project tools/parity parity-gap --baseline origin/main --out /private/tmp/happyword-gaps
```

Useful variants:

```bash
uv run --project tools/parity parity-gap --fetch --baseline origin/main --out /private/tmp/happyword-gaps
uv run --project tools/parity parity-gap --plan-doc-scope --out /private/tmp/happyword-gaps
uv run --project tools/parity parity-gap --doc-path docs/superpowers/specs/<spec>.md --out /private/tmp/happyword-gaps
uv run --project tools/parity parity-gap --doc-scope overall --out /private/tmp/happyword-gaps
uv run --project tools/parity parity-gap --kind behavior --doc-path docs/superpowers/specs/<spec>.md --out /private/tmp/happyword-gaps
uv run --project tools/parity parity-gap --platform ios --kind visual --out /private/tmp/happyword-gaps-ios
uv run --project tools/parity parity-gap --capture ios,android --out /private/tmp/happyword-gaps-live
uv run --project tools/parity parity-gap --fail-on P1 --out /private/tmp/happyword-gaps
```

Use `--capture` only when the simulator/emulator/device is expected to be available. Capture failures are still valid `screenshot_capture` gaps.

## Workflow

1. Run the command with the narrowest useful `--platform` / `--kind` filter.
2. If the user names a specific spec/plan path, pass it with `--doc-path`. This narrows expected-behavior clues and avoids stale historical specs.
3. If the user explicitly says `overall`, use `--doc-scope overall`. This is a global search and can be slow/noisy.
4. If no doc scope is specified and expected behavior matters, first run `--plan-doc-scope`, split the candidates by branch path, and let the user choose paths. Do not silently run global spec/plan search.
5. Read terminal output first; it is already sorted by severity and actionability.
6. Open `gaps.json` when selecting work for an agent because it contains structured evidence.
7. For any gap with a `docs/superpowers/...` evidence source, read that cited spec/plan line before editing code. These lines describe expected behavior more precisely than screenshots.
8. Use `visual-diffs/` only as supporting evidence. Human judgment decides whether a visual delta is acceptable.
9. After fixing a gap, run the relevant platform tests from `.cursor/*-dev-commands.md`, then rerun `parity-gap` for the affected platform/kind.

## Spec/Plan Search Scope

Default behavior is **not** global docs search. Use this decision rule:

- Specific spec/plan known → run with one or more `--doc-path <path>`.
- User says `overall` / 全局 / all specs → run with `--doc-scope overall`.
- Scope unclear → run `--plan-doc-scope`, show the branch paths to the user, and 让用户选择 which paths to search before rerunning.

Candidate branches normally include `docs/superpowers/specs`, `docs/superpowers/plans`, and `docs/features`.

## Gap Judgment

- `P0`: HarmonyOS-tested behavior or stable ID has no iOS/Android counterpart. Fix before claiming parity.
- `P1`: Counterpart exists but expected behavior, test flow, labels, routing, or state semantics diverge. Fix or document why the platform intentionally differs.
- `P2`: Screenshot evidence is missing, capture failed, or visual diff exceeds threshold. Review screenshots/diffs and refresh evidence after UI changes.
- `P3`: Naming/style clue needs human review. Do not block solely on P3 unless it points to a known product decision.

## Fix Selection

Prefer gaps with all three signals: HarmonyOS test reference, `docs/superpowers` clue, and missing platform test/ID. These are the least ambiguous. When a gap only comes from screenshots, inspect the corresponding source and screenshot before editing; visual diffs can be noisy across device sizes.
