# iOS Screenshot Parity Plan

## Visual Strategy

The iOS replica should be behaviorally equivalent to HarmonyOS while adapting layout for iPhone. The goal is not pixel-perfect copying from 2720 x 1260 tablet captures. It is visual and interaction parity:

- Keep the same screen purpose, hierarchy, labels, colors, and action priority.
- Compress landscape child screens for iPhone by reducing whitespace and using two or three stable columns.
- Keep ParentAdmin and LessonDraftReview portrait because the source product intentionally locks those parent workflows to portrait.
- Preserve touch target clarity for children: primary actions are large, answer buttons are stable, and dense parent/admin controls stay out of the child path.

## Source Screenshot Inventory

| Screenshot | Group | iOS phase | Adaptation target |
| --- | --- | --- | --- |
| `home.png` | Core learning | Phase 1 | iPhone landscape home, compact toolbar and adventure card. |
| `battle.png` | Core learning | Phase 1 | iPhone landscape combat, three zones plus bottom answers. |
| `result.png` | Core learning | Phase 1 | iPhone landscape result summary and next actions. |
| `config-part1.png` to `config-part4.png` | Settings | Phase 1 / 2 | Landscape settings; Phase 1 includes battle knobs, PIN, ParentAdmin entry. |
| `parent-admin-part1.png` to `parent-admin-part4.png` | Parent admin | Phase 1 | iPhone portrait parent console. |
| `pack-manager.png` | Pack management | Phase 2 | Landscape/portrait-adaptive list, first accepted as landscape from Config. |
| `wishlist.png` | Growth loop | Phase 2 | Landscape wishlist with local PIN-gated actions. |
| `redemption-history.png` | Growth loop | Phase 2 | Landscape list. |
| `monster-codex-part1.png`, `monster-codex-part2.png` | Growth loop | Phase 2 | Landscape carousel/card viewer. |
| `today-plan.png` | Growth loop | Phase 2 | Landscape read-only daily plan. |
| `learning-report-part1.png`, `learning-report-part2.png` | Growth loop | Phase 2 | Landscape report, pack-keyed breakdown. |
| `parent-pin-setup.png` | Parent control | Phase 1 | Landscape PIN setup/edit. |
| `bound-device-info.png` | Parent cloud | Phase 3 | Landscape child profile and unbind. |
| `bypass-secret.png` | Debug | Phase 4 | Debug-only editor. |
| `dev-menu.png` | Debug | Phase 4 | Debug-only backend environment switcher. |

## Phase 1 Visual Rules

### Home

Source: `assets/screenshots/harmonyos/home.png`.

iPhone landscape adaptation:

- Keep the title `Small Magician Word Adventure`, but reduce display size and place it near the top center.
- Keep child badge, coin badge, and toolbar actions, but collapse the six circular toolbar buttons into a compact trailing toolbar row.
- Keep the AdventureCard as the central object. On iPhone, it should take most of the width and less vertical whitespace.
- Keep pack chips as horizontal scroll pills. Active chip remains red; inactive chips remain white/outlined.
- Keep action button semantics: `开始冒险` or `再战一局` is the dominant red full-width button inside the card.
- Preserve English pack names on chips and card title, matching the V0.6.7.5 all-English decision.

Acceptance notes:

- The active pack title, chip row, tag row, description, and primary button must be visible without scrolling on a landscape iPhone.
- Version label can be smaller and low-priority, but debug triple-tap behavior belongs to Phase 4.

### Battle

Source: `assets/screenshots/harmonyos/battle.png`.

iPhone landscape adaptation:

- Use a three-zone layout: player card left, question center, monster card right.
- Bottom answer row remains the largest touch surface; each answer button must keep stable height and not shift during feedback.
- Keep top status: combo left, title center, timer right.
- Retain speaker action near the prompt.
- Character art should remain readable, but cards may be narrower than HarmonyOS.
- Debug `end battle` affordance is not in production UI; if kept for test builds, hide behind debug compile/config.

Acceptance notes:

- The prompt and all answer buttons fit without scroll.
- Three answer buttons remain tappable on iPhone landscape.
- HP bars remain visible for both sides.

### Result

Source: `assets/screenshots/harmonyos/result.png`.

iPhone landscape adaptation:

- Keep victory/loss title, star rating, learned word count, accuracy, defeated monsters, and today reward delta.
- Use one compact stats row or two-column grid, not a tall tablet card.
- Primary next actions: back home and wishlist when today rewards are earned.

### Config And PIN

Sources: `config-part1.png` to `config-part4.png`, `parent-pin-setup.png`.

Phase 1 includes:

- Player HP, monster HP, monster count steppers.
- Timer presets plus custom timer entry.
- Auto pronunciation toggle.
- Parent PIN setup/edit.
- ParentAdmin entry after PIN gate.
- PackManager row as a disabled or placeholder navigation target until Phase 2, unless the implementation team chooses to bring PackManager forward.

iPhone landscape adaptation:

- Use a scrollable form with compact rows.
- Stepper rows keep large minus/plus controls but reduce circular button diameter.
- Timer chips remain pills; selected chip remains gold.
- ParentAdmin row must clearly communicate it opens a parent-only portrait workflow.

### ParentAdmin

Sources: `parent-admin-part1.png` to `parent-admin-part4.png`.

ParentAdmin remains iPhone portrait in Phase 1.

Keep:

- Back button.
- Title `家长管理后台`.
- Server label.
- Overview card with refresh state.
- Lesson import card with camera/gallery actions.
- Pending draft list.
- Publish new pack card and notes field.

Phase 1 implementation may use fake/mock adapters, but the design must preserve real `ParentApiClient` boundaries for:

- `GET /api/v1/admin/stats`
- `GET /api/v1/admin/lesson-drafts`
- `POST /api/v1/admin/lessons/import`
- `POST /api/v1/admin/packs/publish`

### LessonDraftReview

No dedicated screenshot is currently present, but V0.5.8 spec defines the flow.

Portrait iPhone design:

- Show source image thumbnail at the top.
- Show editable category/theme label.
- Render candidate word rows with keep/drop and edit actions.
- Keep primary actions fixed near the bottom when possible: approve all and reject all.
- Handle `ALREADY_REVIEWED` by returning to ParentAdmin after showing a short message.

## Later Visual Groups

### Pack Management

Source: `pack-manager.png`.

Phase 2 must preserve:

- Header `我的词包`.
- Active count `已激活 5 / 5`.
- Sync button.
- Source tag: `内置`, `官方`, `家庭`.
- Pin button label: `固定` / `已固定`.
- Toggle switch on the right.

### Growth Pages

Sources: `wishlist.png`, `monster-codex*.png`, `today-plan.png`, `learning-report*.png`.

Phase 2 should keep the existing clean, large-card language but compress vertical spacing for iPhone landscape. LearningReport must use pack-keyed rows, not old category rows.

### Debug Pages

Sources: `dev-menu.png`, `bypass-secret.png`.

Phase 4 only. These pages must be debug-build-only and unavailable in release builds.
