# Android Screenshot Parity Plan

## Visual Strategy

Android should match HarmonyOS behavior and product intent, not copy tablet pixels mechanically. The design target is phone-first native Compose:

- Child learning screens are landscape-first.
- Parent/admin screens are portrait-first.
- Screen hierarchy, labels, color intent, action priority, and accessibility semantics should stay aligned with HarmonyOS.
- Compose layouts must be adaptive enough for common phone sizes without hiding primary actions.

Source screenshots live under:

```text
assets/screenshots/harmonyos/
```

## Source Screenshot Inventory

| Screenshot | Group | Android phase | Adaptation target |
| --- | --- | --- | --- |
| `home.png` | Core learning | Phase 1 | Landscape phone home, compact toolbar and adventure card. |
| `battle.png` | Core learning | Phase 1 | Landscape combat, player/question/monster zones plus bottom answers. |
| `result.png` | Core learning | Phase 1 | Landscape result summary with next actions. |
| `config-part1.png` to `config-part4.png` | Settings | Phase 1 / 2 | Landscape scrollable settings; Phase 1 includes battle knobs, PIN, ParentAdmin. |
| `parent-pin-setup.png` | Parent gate | Phase 1 | Landscape PIN setup/edit. |
| `parent-admin-part1.png` to `parent-admin-part4.png` | Parent admin | Phase 1 | Portrait parent console. |
| `pack-manager.png` | Pack management | Phase 2 | Portrait or landscape-adaptive list; first accepted as portrait if easier. |
| `wishlist.png` | Growth loop | Phase 2 | Landscape wishlist with large child-safe cards. |
| `redemption-history.png` | Growth loop | Phase 2 | Landscape list. |
| `monster-codex-part1.png`, `monster-codex-part2.png` | Growth loop | Phase 2 | Landscape carousel/card viewer. |
| `today-plan.png` | Growth loop | Phase 2 | Landscape read-only daily plan. |
| `learning-report-part1.png`, `learning-report-part2.png` | Growth loop | Phase 2 | Landscape pack-keyed report. |
| `bound-device-info.png` | Parent cloud | Phase 3 | Portrait or landscape-adaptive child profile. |
| `dev-menu.png` | Debug | Phase 4 | Debug-only backend environment switcher. |
| `bypass-secret.png` | Debug | Phase 4 | Debug-only preview bypass editor. |

## Android Layout Rules

### Home

Source: `assets/screenshots/harmonyos/home.png`.

Android adaptation:

- Keep `Small Magician Word Adventure` as the main title.
- Keep child identity, coin count, and toolbar actions in a compact top row.
- Keep active pack chips as a horizontal row.
- Keep English pack names on chips and card title.
- Keep the selected pack visually obvious.
- The main adventure card must expose title, tags, short story/description, and primary button without vertical scrolling on a typical landscape phone.

Compose guidance:

- Use `Scaffold` only if it does not add wasted chrome.
- Use `LazyRow` for pack chips.
- Use stable `Modifier.testTag(...)` values matching the HarmonyOS automation intent, for example `HomeStartButton`, `RegionChip_fruit-forest`, and `AdventureCardTitle`.

### Battle

Source: `assets/screenshots/harmonyos/battle.png`.

Android adaptation:

- Use three zones: player left, question center, monster right.
- Keep answer buttons as the largest tap targets.
- Keep top status visible: combo, battle title, timer.
- Keep speaker/pronunciation action near the prompt.
- Keep HP bars visible for player and monster.
- Do not let feedback text resize the layout.

Compose guidance:

- Use stable fixed-height answer rows.
- Use `contentDescription` for speaker and character cards.
- Use `testTag` for `BattleAnswer_0`, `BattleAnswer_1`, `BattleAnswer_2`, `BattleTimer`, `PlayerHpBar`, and `MonsterHpBar`.

### Result

Source: `assets/screenshots/harmonyos/result.png`.

Android adaptation:

- Keep win/loss title, star rating, defeated monsters, learned word count, accuracy, and coin delta.
- Use compact rows instead of tablet-sized cards.
- Keep back-home as the primary command.
- Wishlist shortcut can remain hidden or disabled until Phase 2, but result state must already include coin fields.

### Config And Parent PIN

Sources: `config-part1.png` to `config-part4.png`, `parent-pin-setup.png`.

Phase 1 includes:

- Player HP stepper.
- Monster HP stepper.
- Monster count stepper.
- Timer chips: 30s, 3m, 5m, 10m.
- Custom timer dialog with 1...3600 second validation.
- Auto pronunciation toggle.
- Parent PIN setup/edit.
- ParentAdmin entry gated by PIN.
- PackManager row as disabled or placeholder until Phase 2.

Android adaptation:

- A scrollable settings list is acceptable.
- Stepper controls should use familiar minus/plus icon buttons.
- Timer chips should use segmented/pill selection.
- PIN entry should use numeric keyboard and never expose the stored PIN.

### ParentAdmin

Sources: `parent-admin-part1.png` to `parent-admin-part4.png`.

ParentAdmin is portrait in Phase 1.

Keep:

- Back button.
- Title `家长管理后台`.
- Server label.
- Overview refresh card.
- Lesson import card with camera/gallery actions.
- Pending draft list.
- Publish new pack card and notes field.

Android implementation may start with mock adapters, but the UI should preserve the real network boundary names from HarmonyOS and server contracts.

### LessonDraftReview

No dedicated screenshot exists, but V0.5.8 and iOS planning define the flow.

Portrait design:

- Source image thumbnail at top.
- Editable category/theme label.
- Candidate word rows with keep/drop/edit controls.
- Approve all and reject all primary actions.
- Already-reviewed handling returns to ParentAdmin after showing a short message.

## Later Screen Groups

### PackManager

Source: `pack-manager.png`.

Phase 2 must preserve:

- Header `我的词包`.
- Active count, for example `已激活 5 / 5`.
- Sync button.
- Source tags: `内置`, `官方`, `家庭`.
- Pin labels: `固定` / `已固定`.
- Toggle on the right.

### Growth Pages

Sources: `wishlist.png`, `redemption-history.png`, `monster-codex*.png`, `today-plan.png`, `learning-report*.png`.

Phase 2 should keep the child-friendly card language but use tighter spacing for phones. LearningReport must be pack-keyed, not category-keyed.

### Debug Pages

Sources: `dev-menu.png`, `bypass-secret.png`.

Phase 4 only. These must be debug-build-only and unavailable in release builds.
