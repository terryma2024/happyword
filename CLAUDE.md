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
