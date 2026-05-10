# iOS Replica Phase 0 — Environment And Project Bootstrap Design

> Status: design-for-implementation
> Date: 2026-05-10
> Scope: native iOS development environment and project bootstrap plan only.
> Related index: `docs/ios-replica/00-index.md`

## 1. Background

The repository is now a monorepo with root-level `harmonyos/`, `ios/`, `android/`, `server/`, and `shared/`. HarmonyOS is the only complete runtime client. The iOS directory currently contains a placeholder README and must remain a native Swift / SwiftUI client root, not a cross-platform runtime.

Local environment inspection before this spec found:

- macOS 15.7.4 on Apple Silicon.
- Swift CLI exists via Command Line Tools.
- Full `/Applications/Xcode.app` is not installed.
- `xcodebuild` and `simctl` are unavailable until Xcode is installed and selected.
- Homebrew exists; SwiftLint, SwiftFormat, XcodeGen, Tuist, Fastlane, and CocoaPods are not installed.
- This docs branch is safe to complete without Xcode; implementation cannot pass iOS build/test gates until Xcode is installed.

## 2. Goals

- Prepare a reproducible native iOS project bootstrap path under `ios/`.
- Define the minimum toolchain, project generation policy, schemes, and test gates for later implementation.
- Keep Phase 0 free of product behavior changes.
- Preserve monorepo rules: no shared runtime under `shared/`, no extra `clients/` layer, no changes to HarmonyOS project identity.

## 3. Non-Goals

- Do not create the iOS project in this docs-only branch.
- Do not migrate assets or create Swift files in this phase.
- Do not install Xcode or Homebrew packages from the plan itself.
- Do not introduce Flutter, React Native, Unity, or any other cross-platform runtime.
- Do not wire CI until an actual iOS project exists.

## 4. Source Evidence

- `ios/README.md`: declares Swift / SwiftUI and XCTest as the future native iOS direction.
- `AGENTS.md`: confirms iOS is root-level native Swift / SwiftUI.
- `docs/superpowers/specs/2026-05-06-v0.7.0-monorepo-native-clients-restructure-design.md`: records the accepted root-level module layout.
- `shared/contracts/README.md`: shared is a contract checkpoint, not a runtime SDK.

## 5. Project Shape

Recommended future layout:

```text
ios/
  project.yml
  WordMagicGame/
    App/
    Core/
    Features/
    Services/
    Resources/
  WordMagicGameTests/
  WordMagicGameUITests/
```

Boundary rules:

- `Core/` contains pure Swift models and engines with no SwiftUI import.
- `Services/` contains persistence, networking, asset loading, audio, and adapters.
- `Features/` contains SwiftUI screens grouped by product area.
- `Resources/` contains iOS-specific asset catalog entries and bundled JSON.
- Test fixtures should reference `shared/fixtures/**` by copying into test resources or loading from repo-relative paths in local tests; do not import `shared/` as runtime code.

## 6. Tooling Decisions

| Area | Decision | Rationale |
| --- | --- | --- |
| Project definition | XcodeGen `project.yml` | Text-reviewable, easy to regenerate, avoids manual `.xcodeproj` churn. |
| UI framework | SwiftUI | Native-first, matches user direction. |
| Minimum tests | XCTest + XCUITest | Mirrors iOS automation guidance and supports logic/UI separation. |
| Lint | SwiftLint | Later implementation should use local rules only after the codebase exists. |
| Format | SwiftFormat | Use in check mode first; do not auto-format unrelated files. |
| Package manager | Swift Package Manager | Use before CocoaPods unless a dependency forces otherwise. |
| CI | Deferred until project exists | Avoid speculative workflow files. |

## 7. Environment Setup Plan

Manual prerequisite steps before implementation:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS
brew install swiftlint swiftformat xcodegen
```

Verification commands:

```sh
xcodebuild -version
xcrun simctl list runtimes
xcrun simctl list devices available
swift --version
swiftlint version
swiftformat --version
xcodegen --version
```

Expected result:

- `xcodebuild` returns the installed Xcode version.
- `simctl` lists at least one iOS runtime.
- Tool versions are printed without shell errors.

## 8. Future Bootstrap Acceptance

When Phase 0 implementation begins, it is complete only when:

- `ios/project.yml` generates a project successfully.
- The app target launches to a placeholder screen.
- XCTest and XCUITest targets exist and run.
- `xcodebuild test -scheme WordMagicGame -destination 'platform=iOS Simulator,name=<chosen iPhone>'` passes.
- `swiftlint` and `swiftformat --lint .` pass or have documented initial findings.
- No runtime files are added under `shared/`.

## 9. Risks

- Full Xcode is missing on the current machine; implementation cannot be verified until this is resolved.
- Disk space is tight for Xcode plus simulator runtimes; keep at least 80 GB free before installing.
- XcodeGen introduces one extra tool but keeps project diffs reviewable.
- iPhone-first layout must not hard-code one simulator size; later implementation should use size classes and geometry constraints.
