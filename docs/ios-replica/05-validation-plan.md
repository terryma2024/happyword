# iOS Replica Validation Plan

## Docs-Only Validation For This Branch

Run from the worktree:

```sh
git status --short
find docs/ios-replica -type f -maxdepth 1 -print | sort
rg -n 'TO''DO|TB''D|implement ''later|fill ''in' docs/ios-replica
rg -n "ParentAdmin|LessonDraftReview" docs/ios-replica
rg -n "HomePage|BattlePage|ResultPage|ConfigPage|PackManagerPage|DevMenuPage|BypassSecretPage" docs/ios-replica/00-index.md
```

Expected:

- Only `docs/ios-replica/**` files are modified/added.
- Six docs exist.
- Placeholder scan has no hits.
- ParentAdmin and LessonDraftReview appear in Phase 1 docs.
- All 17 HarmonyOS pages are mapped in `00-index.md`.

## Future Phase 1 XCTest

Pure logic tests first:

| Test area | Scenarios |
| --- | --- |
| `BattleEngine` | start, correct answer, wrong answer, combo burst after three correct, monster defeat, win, HP loss, timer loss. |
| `GameConfig` | defaults, timer presets, custom timer 1...3600, invalid timer rejection/clamp policy. |
| `QuestionGenerator` | three options contain answer, no duplicate options, fallback when same-category distractors are insufficient. |
| `TodayAdventureBuilder` | build from pack words, boss slots, first-today flag, deterministic seeded plan. |
| ParentAdmin DTOs | stats, draft list, draft detail, import response, publish response, already-reviewed error envelope. |
| `LessonDraftReviewStore` | keep/drop toggle, edit row, approve payload contains only kept/edited words, reject clears local edit state. |

No SwiftUI view should be needed for these tests.

## Future Phase 1 XCUITest

Core child flow:

1. Launch in iPhone landscape with deterministic fixture words.
2. Verify Home title, selected pack chip, primary start button.
3. Start battle.
4. Answer deterministic questions.
5. Verify Battle status, answer buttons, HP bars, timer.
6. Finish battle.
7. Verify Result stars and Home return.

Parent admin flow:

1. Launch in iPhone landscape.
2. Open Config.
3. Set or enter parent PIN.
4. Open ParentAdmin and verify portrait orientation.
5. Mock refresh stats.
6. Mock gallery/camera import.
7. Open LessonDraftReview.
8. Edit a candidate word.
9. Approve via mock client.
10. Return to ParentAdmin, then Config, and verify landscape is restored.

## Screenshot Acceptance

Phase 1 screenshot set:

| iOS screenshot | Source comparison |
| --- | --- |
| Home iPhone landscape | `assets/screenshots/harmonyos/home.png` |
| Battle iPhone landscape | `assets/screenshots/harmonyos/battle.png` |
| Result iPhone landscape | `assets/screenshots/harmonyos/result.png` |
| Config iPhone landscape | `assets/screenshots/harmonyos/config-part1.png` to `config-part4.png` |
| Parent PIN iPhone landscape | `assets/screenshots/harmonyos/parent-pin-setup.png` |
| ParentAdmin iPhone portrait | `assets/screenshots/harmonyos/parent-admin-part1.png` to `parent-admin-part4.png` |
| LessonDraftReview iPhone portrait | V0.5.8 spec; no current screenshot baseline. |

Acceptance rule:

- Child pages are judged by hierarchy and behavior, not pixel position.
- ParentAdmin is judged by section coverage and portrait flow.
- Text must not overlap or clip in iPhone landscape/portrait.

## Contract Fixture Validation

Future Swift tests should decode:

- `shared/fixtures/packs/global-packs-latest.sample.json`
- `shared/fixtures/packs/family-packs-latest.sample.json`
- `shared/fixtures/pairing/pair-redeem.sample.json`
- `shared/fixtures/child/word-stats-sync.sample.json`
- `shared/fixtures/public/preview-urls.sample.json`

The fixture tests must be part of the iOS target before real networking is enabled.

## Release Gates For Later Implementation

Before any iOS implementation branch is considered ready:

- `xcodebuild test` passes on an iPhone simulator.
- XCTest covers Phase 1 pure logic.
- XCUITest covers child core flow and ParentAdmin mock flow.
- Screenshot captures are saved under `assets/screenshots/ios/` only after user approval.
- Release build hides DevMenu and bypass token surfaces.
- No runtime code is added under `shared/`.

## Known Local Environment Gap

This machine currently needs full Xcode installation before SwiftUI project verification can run. The docs-only branch can be completed without Xcode, but later implementation cannot satisfy `xcodebuild` gates until Xcode and simulator runtimes are installed.
