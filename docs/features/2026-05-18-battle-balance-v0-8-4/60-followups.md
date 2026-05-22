# V0.8.4 Followups

## 2026-05-21 Phrase Question Rendering

- [x] HarmonyOS: phrase fill-letter templates preserve word spaces; `a` / `an` / `the` article letters are displayed but never selected as blanks; Spell preserves spaces and pre-fills article letters.
- [x] iOS: mirrored the HarmonyOS phrase/article token rules in Core question generation.
- [x] Android: mirrored the HarmonyOS phrase/article token rules in Core question generation.
- [x] Verification: HarmonyOS local unit tests and Android focused JVM tests cover phrase spacing plus article exclusion. iOS Core type-check passes; full Xcode test run is blocked on this machine by missing iOS Simulator runtimes.
