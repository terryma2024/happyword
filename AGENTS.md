# HarmonyOS project guide

## Stack
- HarmonyOS NEXT
- ArkTS
- DevEco Studio managed project

## Commands
- **Phased build/test commands, log paths, and device rules:** [`.cursor/dev-commands.md`](.cursor/dev-commands.md) (source of truth for the Harmony autofix skills).
- Install deps: ohpm install
- Build debug HAP: hvigorw assembleHap
- After a successful HAP build, run CodeLinter (see [`.cursor/dev-commands.md`](.cursor/dev-commands.md)): `codelinter -c ./code-linter.json5 . --fix`
- Build module: hvigorw --mode module -p module=entry assembleHap
- Connect device: hdc list targets
- Install app: hdc install xxx.hap

## Rules
- Use ArkTS only
- Do not replace project structure unless necessary
- Prefer modifying entry/src/main/ets
- Keep UI components small and reusable
- Explain any build.gradle-like or hvigor changes before editing
- For all feature development and bugfix tasks, use the applicable Superpowers workflow before implementing changes.

## Server (`server/`) discipline
- Every commit that touches `server/` MUST run `uv run pytest` with **0 errors and 0 warnings**.
- `pyproject.toml` sets `filterwarnings = ["error", ...]` so any new warning fails the suite.
- If a warning comes from a third-party dependency we cannot fix, add a *narrow* `ignore:...` entry to `[tool.pytest.ini_options].filterwarnings` with a comment explaining the source and why we cannot resolve it upstream.
- Never use a blanket `ignore` (e.g. `ignore::DeprecationWarning`) — always pin by message + module.
