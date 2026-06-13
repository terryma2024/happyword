# Parity checklist — Cocos battle on HarmonyOS (vs native BattlePage / iOS Cocos battle)

Verification target: **arm64 emulator** `127.0.0.1:5555` (2720×1260, ~2.16:1),
debug HAP `v1.0.2(2606112206)` + the surface-recreation engine patch,
2026-06-11. MatePad (3:2) rows are pending — the tablet's hdc channel was
`Unauthorized` (RSA confirm dialog needs a physical tap).

| Surface | Status | Evidence |
| --- | --- | --- |
| Cocos battle from Home start (开始今日冒险 → CocosBattlePage) | verified — engine boots, scene renders, takes touch input | [`01-cocos-battle-first-entry.jpeg`](screenshots/01-cocos-battle-first-entry.jpeg); hilog `GLES3 device initialized` + sprite shader compile at battle start |
| Adaptive resolution, 2.16:1 emulator | verified — cards not clipped, top bar (Combo/Battle/Countdown/Escape) hugs the visible top | same screenshots as above |
| Adaptive resolution, 3:2 MatePad | **pending** — device unauthorized | — |
| Correct answer: monster HP drop + combo increment | verified (combo 0→1, monster 5/5→4/5) | [`02-correct-answer-monster-hp-drop.jpeg`](screenshots/02-correct-answer-monster-hp-drop.jpeg) |
| Wrong answer: player HP drop + combo reset | verified (player 10→9, combo →0, monster HP unchanged) | [`03-wrong-answer-player-hp-drop.jpeg`](screenshots/03-wrong-answer-player-hp-drop.jpeg) |
| Combo-3 crit overlay | verified (golden flash overlay, "-2!" crit text, floating "-2" over monster, 2-damage hit) | [`06-combo3-crit-overlay.jpeg`](screenshots/06-combo3-crit-overlay.jpeg) |
| Monster defeat → next monster transition | verified (Monster 1/10 → 2/10, new monster card). **Reopened 2026-06-13** ([60-followups FU-1](60-followups.md)): codex encounter/defeat recording was missing on the Cocos path — fixed via `onAnswerOutcome`, re-verified by bridge unit tests; on-device codex re-check pending | [`07-monster-transition-2of10.jpeg`](screenshots/07-monster-transition-2of10.jpeg) |
| Question kinds seen (~10 answers, all 5 kinds enabled in ConfigPage) | sentence-cloze (句子填词) and choice (中文选词) seen in Cocos; choice also seen native-side. fill-letter / fill-letter-medium / spell did not appear (kind selection follows word memory state); renderers shared with iOS where all 5 are device-verified | [`01`](screenshots/01-cocos-battle-first-entry.jpeg), [`09-cocos-battle-config-back-on-choice-kind.jpeg`](screenshots/09-cocos-battle-config-back-on-choice-kind.jpeg) |
| Boss intro bubble | **not reached** on emulator (needs 9 defeats in one battle); scene code shared with iOS Task 3.5 device verification | — |
| Escape → ResultPage enriched stats | verified (stars, 击败怪物/答题数/正确率/学习单词, 魔法币). **Reopened 2026-06-13** ([60-followups FU-1](60-followups.md)): 学习单词 / newly-learned totals were stale — `LearningRecorder.recordAnswer` never ran on the Cocos path; fixed via `onAnswerOutcome`, re-verified by bridge unit tests; on-device ResultPage re-check pending | [`04-result-after-escape.jpeg`](screenshots/04-result-after-escape.jpeg) |
| Countdown timeout → ResultPage | verified (1 star, 7/7 answered, +1 魔法币) | [`11-result-after-timeout.jpeg`](screenshots/11-result-after-timeout.jpeg) |
| Re-entry: second battle of the process | **verified in Cocos** (engine patch landed) — three escape→home→battle cycles in one process, each re-renders in Cocos, no cppcrash; hilog shows `WM_XCOMPONENT_SURFACE_DESTROY` → `WM_XCOMPONENT_SURFACE_CREATED` rebind per cycle | [`05-second-battle-cocos-reentry.jpeg`](screenshots/05-second-battle-cocos-reentry.jpeg) |
| Backgrounding mid-battle (home key) + resume | verified — battle continues (countdown 4:52→4:43 across the round-trip), no crash | [`10-resume-after-background.jpeg`](screenshots/10-resume-after-background.jpeg) |
| Config switch OFF → native BattlePage | verified — native layout ("Time", L-badge card), zero engine surface activity in hilog | [`08-native-battle-config-off.jpeg`](screenshots/08-native-battle-config-off.jpeg) |
| Config switch back ON → Cocos again | verified — next battle renders in Cocos | [`09-cocos-battle-config-back-on-choice-kind.jpeg`](screenshots/09-cocos-battle-config-back-on-choice-kind.jpeg) |
| Audio spot-check (question TTS) | verified via hilog — per-battle `HiAI_TtsEngine` / `textToSynthesis` activity for `com.terryma.wordmagicgame` (zh_CN), TTS stop on battle exit/background (86 TTS log lines across the session). BGM/SFX not separately confirmed on emulator (no audible check possible over hdc) | hilog captures, 2026-06-11 22:07–22:16 |
| Crash log check | no new `cppcrash` under `/data/log/faultlog/faultlogger/` for the whole session (the three 18:1x–18:2x entries predate the patch and were its motivation) | faultlogger listing |
