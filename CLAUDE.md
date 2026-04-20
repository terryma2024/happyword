# HarmonyOS project guide

## Stack
- HarmonyOS NEXT
- ArkTS
- DevEco Studio managed project

## Commands
- Install deps: ohpm install
- Build debug HAP: ./hvigorw assembleHap
- Build module: ./hvigorw --mode module -p module=entry assembleHap
- Connect device: hdc list targets
- Install app: hdc install xxx.hap

## Rules
- Use ArkTS only
- Do not replace project structure unless necessary
- Prefer modifying entry/src/main/ets
- Keep UI components small and reusable
- Explain any build.gradle-like or hvigor changes before editing
