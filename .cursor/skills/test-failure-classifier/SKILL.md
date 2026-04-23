---
name: test-failure-classifier
description: Classifies build, lint, and test failures into category (compile, lint, unit, ui, env-infra) and fixability tier only—no file edit instructions. Use after harmony-log-analyzer output or when routing HarmonyOS hvigor, codelinter, hdc, or on-device test failures in an autofix loop.
---

# test-failure-classifier

**Role:** **Type and tier only.** It does **not** say *which* files to edit or *how*—**`harmony-fix-strategy`** handles that.

## Categories

| Category | Typical signals |
|----------|-----------------|
| **compile** | ArkTS/ets errors, `hvigor` **Error** in compile/compileArk, missing symbol, type errors |
| **lint** | `codelinter` non-zero exit, rule violations in `code-linter.json5` output, static analysis errors from CodeLinter (not `hvigor` compile) |
| **unit** | Failed assert in `src/test` / Local test output, JUnit/arkxtest local failure, exit non-zero in **no-device** test phase |
| **ui** | UiTest / `ohosTest` / on-device test failure, selector not found, UI timeout, test under `ohosTest` path |
| **env-infra** | `codelinter` **not found** or not on `PATH`, `hdc` no target, simulator not booting, **signing** errors, SDK path wrong, OOM, install failure clearly environmental |
| **unknown** | Unparseable, mixed errors, or insufficient log |

## Tiers (fixability routing)

| Tier | Meaning | Typical next step |
|------|---------|-------------------|
| **agent_safe** | Likely fixable in app or test with minimal change | Allow **`harmony-fix-strategy`** to propose code edits |
| **agent_risky** | Flake, race, or ambiguous test/product boundary | `harmony-fix-strategy` may only propose **test** stabilization or ask user |
| **human_required** | signing, account, device farm, org policy, SDK install | **Stop** the loop; checklist for the user. No broad refactors |

## Input

- Short **excerpts** from the failing command (see [`.cursor/dev-commands.md`](.cursor/dev-commands.md) failure order).
- Which **phase** failed: build, codelinter, unit, emulator, ui.

## Output format (for orchestrator and fix-strategy)

- `category: ...`
- `tier: agent_safe | agent_risky | human_required`
- `one_line_summary: ...`

**Do not** add “edit `Foo.ets` line 12” here—that belongs in **`harmony-fix-strategy`**.
