# iOS dev commands manifest (source of truth)

> For the per-feature lifecycle (HarmonyOS-first design, stabilization gate, parallel iOS/Android replication, parity checklist), see [`docs/sop/00-three-platform-feature-sop.md`](../docs/sop/00-three-platform-feature-sop.md). This manifest only owns iOS commands.

Read this file before running iOS build, test, simulator, or screenshot commands. Keep it aligned with the native Swift / SwiftUI app under `ios/`; do not invent scheme names or simulator flags when a known command is listed here.

- **last_verified_xcode:** Xcode 17.x with iOS 26.4 simulator runtime on this machine
- **repo_root:** repository root (`<repo-root>`)
- **ios_project_root:** `ios/`
- **xcode_project:** `ios/WordMagicGame.xcodeproj`
- **scheme:** `WordMagicGame`
- **default_simulator:** `iPhone 17 Pro`
- **bundle_id:** `com.terryma.wordmagicgame`
- **derived_data_path:** `/private/tmp/wordmagic-dd`

## Conventions

- Run `xcodebuild` from `ios/` unless the command explicitly says otherwise.
- Use the generated Xcode project at `ios/WordMagicGame.xcodeproj`. If `ios/project.yml` changes, regenerate the project before building.
- Prefer a stable DerivedData path (`/private/tmp/wordmagic-dd`) for agent runs so build products and screenshots are easy to locate.
- **Phase order (autofix loop):** project generation when needed -> build -> unit tests -> UI tests -> simulator screenshot / visual comparison -> `git diff --check`.
- Child-facing pages are iPhone landscape: Home, Battle, Result, Config, Parent PIN. Parent workflows are portrait: ParentAdmin and LessonDraftReview.
- Keep iOS text and assets aligned with current product decisions: app display name is `魔法背单词`; Home buttons and labels are Chinese; Battle chrome labels and answer buttons are English, while the central question prompt follows HarmonyOS and displays the Chinese `promptZh`; button images and character images reuse HarmonyOS resources.
- Keep Battle pronunciation aligned with HarmonyOS: use the platform TTS service, pronounce the English `answer`, auto-speak on Battle entry and after switching to the next question, suppress auto-speak during reveal/feedback, and let the speaker button manually replay regardless of `autoSpeak`.
- For UI parity work, capture an iPhone simulator screenshot after each visible change and compare against `assets/screenshots/harmonyos/*.png` plus the latest user-provided screenshot. Save temporary agent screenshots under `/private/tmp/`; only add screenshots under `assets/screenshots/ios/` after explicit user approval.

---

## 1) Project Generation - `ios-project-generate`

Run this only when `ios/project.yml` or target membership changes. Do not manually patch `ios/WordMagicGame.xcodeproj/project.pbxproj` when XcodeGen can express the change.

| Step | Command | Success signal |
| --- | --- | --- |
| Check XcodeGen | `/opt/homebrew/bin/xcodegen --version` | Version prints, preferably `>= 2.45.0` |
| Regenerate project | `/opt/homebrew/bin/xcodegen generate --spec ios/project.yml --project ios` | Exit 0; `ios/WordMagicGame.xcodeproj/project.pbxproj` updated |

**Working directory:** repository root.

**Notes:**

- If XcodeGen is missing, do not rewrite the project by hand unless the user approves a local fallback.
- After regeneration, run a build and the affected tests because target membership changes can silently drop files.

---

## 2) Build - `ios-build`

| Step | Command | Success signal |
| --- | --- | --- |
| Build app for simulator | `xcodebuild build -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/wordmagic-dd` | `** BUILD SUCCEEDED **` |

**Working directory:** `ios/`.

**Common build product path:**

```sh
/private/tmp/wordmagic-dd/Build/Products/Debug-iphonesimulator/WordMagicGame.app
```

**If the simulator service is unavailable:**

- First verify Xcode is selected: `xcode-select -p`.
- Then verify simulators: `xcrun simctl list devices available`.
- If running inside a sandboxed agent environment, CoreSimulator access may require an elevated local command. Do not claim simulator verification passed unless `xcodebuild` actually reaches `BUILD SUCCEEDED` or `TEST SUCCEEDED`.

---

## 3) Unit Tests - `ios-unit-test`

Use focused tests while iterating, then broaden when the change touches shared app state, routing, or metadata.

| Scope | Command | Success signal |
| --- | --- | --- |
| All unit tests | `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests -derivedDataPath /private/tmp/wordmagic-dd` | Unit test suite passes |
| One test class | `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests/AppMetadataTests -derivedDataPath /private/tmp/wordmagic-dd` | Selected tests pass |
| One test method | `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameTests/AppMetadataTests/testDisplayNameIsChineseProductName -derivedDataPath /private/tmp/wordmagic-dd` | Selected test passes |

**Working directory:** `ios/`.

**Unit-test policy:**

- Core logic must be tested with XCTest before it is wired into SwiftUI.
- Keep `BattleEngine`, question generation, config, parent DTOs, and stores testable without SwiftUI views.
- If adding or changing app metadata, assert both code-level metadata and bundled `Info.plist` where practical.

---

## 4) UI Tests - `ios-ui-test`

XCUITest is the iOS equivalent of HarmonyOS `ohosTest` for this repo. Prefer stable `accessibilityIdentifier` / accessibility labels over coordinate taps.

| Scope | Command | Success signal |
| --- | --- | --- |
| All UI tests | `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameUITests -derivedDataPath /private/tmp/wordmagic-dd` | UI test suite passes |
| Home -> Battle -> Result flow | `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameUITests/WordMagicGameUITests/testHomeBattleResultDeterministicFlow -derivedDataPath /private/tmp/wordmagic-dd` | Flow passes |
| Battle labels / countdown flow | `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameUITests/WordMagicGameUITests/testBattleScreenUsesEnglishLabelsAndLiveCountdown -derivedDataPath /private/tmp/wordmagic-dd` | Flow passes |
| Parent admin mock flow | `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WordMagicGameUITests/WordMagicGameUITests/testConfigPinParentAdminAndLessonReviewMockFlow -derivedDataPath /private/tmp/wordmagic-dd` | Flow passes |

**Working directory:** `ios/`.

**Launch arguments used by current tests:**

- `-UITestResetState` resets deterministic local state.
- `-UITestRouteBattle` starts directly on Battle for focused battle assertions.

**Orientation policy:**

- Assert landscape for child screens.
- Assert portrait for ParentAdmin and LessonDraftReview.
- When a flow returns from a portrait parent page to Config/Home, verify landscape is restored.

---

## 5) Full Verification - `ios-full-test`

Run this before saying an iOS implementation is complete, unless the user explicitly asked for a smaller smoke check.

| Step | Command | Success signal |
| --- | --- | --- |
| Full suite | `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/wordmagic-dd` | `** TEST SUCCEEDED **` |
| Diff whitespace check | `git diff --check` | Exit 0 |

**Expected current shape:** unit tests under `WordMagicGameTests` and UI tests under `WordMagicGameUITests` both run from the `WordMagicGame` scheme.

---

## 6) Simulator Management - `ios-simulator-manage`

| Step | Command | Success signal |
| --- | --- | --- |
| List available devices | `xcrun simctl list devices available` | Shows `iPhone 17 Pro` or another usable iPhone simulator |
| Boot default simulator | `xcrun simctl boot 'iPhone 17 Pro'` | Device boots, or command reports it is already booted |
| Install latest build | `xcrun simctl install booted /private/tmp/wordmagic-dd/Build/Products/Debug-iphonesimulator/WordMagicGame.app` | Exit 0 |
| Launch Home | `xcrun simctl launch booted com.terryma.wordmagicgame -UITestResetState` | Prints bundle id and process id |
| Launch Battle directly | `xcrun simctl launch booted com.terryma.wordmagicgame -UITestResetState -UITestRouteBattle` | Prints bundle id and process id |
| Terminate app | `xcrun simctl terminate booted com.terryma.wordmagicgame` | Exit 0 or already terminated |

**Working directory:** any.

**Notes:**

- `simctl` screenshots may be saved in the device's raw orientation. If needed, rotate a temporary copy with `sips -r -90 <input> --out <output>` for readable landscape comparison.
- Do not use simulator screenshots as proof that tests pass. Screenshots prove visual state; XCUITest proves behavior.

**Reuse existing simulators (preferred):**

- Prefer **`booted`** when a single Simulator window is already open:
  `xcrun simctl install booted …/WordMagicGame.app` and `xcrun simctl launch booted …`
  target that device without starting another runtime.
- If **multiple** simulators are booted, pick the intended UDID from
  `xcrun simctl list devices | grep Booted` and use
  `xcrun simctl install <udid> …` / `xcrun simctl launch <udid> …` instead of
  booting extra devices.
- Avoid `simctl boot` churn for routine install/QA — reuse what Xcode / Simulator
  already has running unless the task explicitly needs a cold device.

---

## 7) Screenshots / Visual Parity - `ios-screenshot`

Use this loop for every visible UI change:

1. Build the app.
2. Install and launch the target screen.
3. Capture an iPhone simulator screenshot into `/private/tmp/`.
4. Compare against HarmonyOS screenshot references and the latest user-provided screenshot.
5. Iterate spacing, labels, typography, and assets until hierarchy and style match.

| Screen | Launch command | Screenshot command | Reference |
| --- | --- | --- | --- |
| Home | `xcrun simctl launch booted com.terryma.wordmagicgame -UITestResetState` | `xcrun simctl io booted screenshot /private/tmp/wordmagic-ios-home.png` | `assets/screenshots/harmonyos/home.png` |
| Battle | `xcrun simctl launch booted com.terryma.wordmagicgame -UITestResetState -UITestRouteBattle` | `xcrun simctl io booted screenshot /private/tmp/wordmagic-ios-battle.png` | `assets/screenshots/harmonyos/battle.png` |
| Result | Prefer XCUITest or deterministic debug route when available | `xcrun simctl io booted screenshot /private/tmp/wordmagic-ios-result.png` | `assets/screenshots/harmonyos/result.png` |
| ParentAdmin | Navigate through Config/PIN XCUITest path | `xcrun simctl io booted screenshot /private/tmp/wordmagic-ios-parent-admin.png` | `assets/screenshots/harmonyos/parent-admin-part*.png` |

**Acceptance rules:**

- Text must not overlap, clip, or spill out of buttons/cards at iPhone 17 Pro landscape and portrait sizes.
- Home and Battle are fixed landscape; ParentAdmin is fixed portrait.
- Battle answer buttons must remain stable in size during feedback.
- Battle animation work should be checked with short simulator recordings when screenshots cannot capture the timing.

Optional recording command:

```sh
xcrun simctl io booted recordVideo /private/tmp/wordmagic-ios-battle.mov
```

Stop recording with Ctrl-C in the terminal running the command.

---

## 8) Failure Artifacts - `ios-log-analyzer`

Read in this order:

1. **Console:** last 200-400 lines of `xcodebuild` output. Look for the first Swift compile error or XCTest failure, not just the final summary.
2. **Result bundle:** path printed after test runs, usually under `/private/tmp/wordmagic-dd/Logs/Test/*.xcresult`.
3. **Build products:** `/private/tmp/wordmagic-dd/Build/Products/Debug-iphonesimulator/`.
4. **Simulator state:** `xcrun simctl list devices` and `xcrun simctl get_app_container booted com.terryma.wordmagicgame data` when state or sandbox files matter.
5. **Screenshots / recordings:** `/private/tmp/wordmagic-ios-*.png` and `/private/tmp/wordmagic-ios-*.mov`.

Helpful commands:

```sh
xcrun xcresulttool get --legacy --path /private/tmp/wordmagic-dd/Logs/Test/<result>.xcresult
xcrun simctl spawn booted log stream --style compact --predicate 'process == "WordMagicGame"'
```

---

## 9) Agent Rules For iOS Work

- Follow the applicable Superpowers workflow for feature work and bug fixes. For behavior changes, write or update the test first and watch it fail when practical.
- Keep SwiftUI components small and reusable, matching existing files under `ios/WordMagicGame/Features/**`.
- Do not add shared client runtime code under `shared/`; only consume schemas and fixtures there.
- Do not expose DevMenu, bypass-token, or preview-environment controls in release-facing iOS UI.
- Do not delete HarmonyOS-derived source assets. If an asset becomes unused, keep it under the appropriate asset/source folder per the repo asset retention policy.
- Prefer XCUITest accessibility identifiers for automation surfaces that agents will need to tap later.
- After visible UI changes, include the latest simulator screenshot path in the final response.
