# WordMagicGame iOS

Native iOS client placeholder for V0.7.x and later.

- Target implementation: Swift / SwiftUI.
- Tests: XCTest when the app project is created.
- Project generation: `/opt/homebrew/bin/xcodegen generate --spec ios/project.yml --project ios`.
- Bundle identifier: `com.terryma.wordmagicgame`, matching HarmonyOS `bundleName`.
- Scope guard: current scaffold only creates the native iOS project shell; product feature implementation follows the iOS replica specs.
- Shared code policy: use `../shared/contracts/` and `../shared/fixtures/` for protocol alignment, not shared runtime UI or business logic.
