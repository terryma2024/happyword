# iOS v0.7.0 Release Preparation

> Scope: Apple App Store only. Android release work is intentionally excluded.
> App: `WordMagicGame` / `魔法背单词`
> Bundle ID: `com.terryma.wordmagicgame`
> Version: `0.7.0`
> Build: `1007000`
> Last updated: 2026-05-16

## Source Of Truth

- Apple App Store submission: https://developer.apple.com/app-store/submitting/
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Apple account deletion requirement: https://developer.apple.com/support/offering-account-deletion-in-your-app
- Existing repo checklist: `docs/ios-replica/06-release-readiness-checklist.md`
- Project config: `ios/project.yml`
- Info.plist: `ios/WordMagicGame/Resources/Info.plist`

## Current Repo State

- [x] `MARKETING_VERSION` is `0.7.0` in `ios/project.yml`.
- [x] `CURRENT_PROJECT_VERSION` is `1007000` in `ios/project.yml`.
- [x] Bundle ID is `com.terryma.wordmagicgame`.
- [x] App display name is `魔法背单词`.
- [x] Release Simulator build succeeded locally with `xcodebuild build -scheme WordMagicGame -configuration Release -destination 'generic/platform=iOS Simulator'`.
- [x] `zh-Hans.lproj/InfoPlist.strings` exists for camera and photo-library permission strings.
- [x] Release-gated developer tools policy exists in code and has unit coverage in `ios/WordMagicGameTests/Core/CloudSyncTests.swift`.
- [x] Full iOS unit/UI test pass is verified on simulator `iPhone 17 Pro (iOS 26.4)`: 100 unit tests and 19 UI tests passed.
- [x] Release Simulator sanity check verified `-UITestRouteDevMenu` and `-UITestRouteBypassSecret` land on the normal home screen.
- [x] `NSPhotoLibraryAddUsageDescription` was removed because the iOS client only reads from Photos via `PhotosPicker` and does not write to the photo library.
- [ ] Real-device Release/TestFlight smoke test is not yet done.
- [ ] App Store Connect app record is not verified from this repo.
- [ ] App privacy questionnaire and privacy policy URL are not verified from this repo.
- [ ] In-app account deletion path is not verified from this repo.

## P0 Blockers To Clear Before Upload

- [ ] Confirm Apple Developer Program team access.
  - Expected team in repo: `DEVELOPMENT_TEAM: 99UX498DB4`.
  - Confirm this team can create distribution signing assets and upload to App Store Connect.

- [ ] Confirm App Store Connect app record.
  - Bundle ID: `com.terryma.wordmagicgame`.
  - SKU: choose a stable internal SKU, for example `wordmagicgame-ios`.
  - Primary language: recommend `zh-Hans` if the first market is mainland China.
  - Category: choose Education or Games only after product positioning is confirmed.
  - Kids Category: decide explicitly. If selected, review ads, analytics, external links, and parental-gate requirements carefully.

- [ ] Confirm production backend is ready for Apple review.
  - Production API must be HTTPS.
  - Review account must work without developer-only switches.
  - Parent binding, QR scan, photo import, word extraction, sync, and child practice flows must be reviewable.
  - Any Vercel preview/local/staging routing must be unreachable in Release.

- [ ] Confirm account deletion.
  - If the app lets a parent create or bind an account, the app must provide an in-app way to initiate account deletion.
  - Confirm deletion removes user data unless a specific legal retention reason exists.
  - Prepare reviewer notes describing where the deletion entry is.

- [ ] Confirm privacy policy URL.
  - Public URL must be accessible without login.
  - It must describe collected data, purpose, retention, deletion, third-party services, child/minor handling, and contact method.
  - It must match App Store Connect privacy answers.

- [ ] Confirm App Privacy details.
  - Inventory data collected by the app and server: account/binding data, child profile name, learning progress, uploaded textbook photos, generated word lists, device identifier, diagnostics/logs if any.
  - Decide whether each item is linked to identity.
  - Decide whether any data is used for tracking. Target answer should be no unless third-party tracking is actually present.

- [ ] Confirm permission usage is accurate.
  - Camera: textbook photo upload and parent QR binding.
  - Photo library read: choose textbook photos.
  - Photo library add: only keep if the app really saves images to the library; otherwise remove it before submission.

## P1 Build And Verification Checklist

- [ ] Regenerate Xcode project after any `ios/project.yml` change.

```sh
cd ios
/opt/homebrew/bin/xcodegen generate --spec project.yml --project .
```

- [x] Lint localized InfoPlist strings.

```sh
plutil -lint ios/WordMagicGame/Resources/zh-Hans.lproj/InfoPlist.strings
```

- [x] Run iOS unit/UI tests on an available simulator.

```sh
cd ios
xcodebuild test \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /private/tmp/wordmagic-ios-test
```

- [x] Run Release Simulator build.

```sh
cd ios
xcodebuild build \
  -scheme WordMagicGame \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/wordmagic-ios-release
```

- [ ] Run device Release build before archive/upload.

```sh
cd ios
xcodebuild build \
  -scheme WordMagicGame \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/wordmagic-ios-release-device
```

- [ ] Archive for App Store distribution.

```sh
cd ios
xcodebuild archive \
  -scheme WordMagicGame \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/WordMagicGame-v0.7.0.xcarchive
```

- [ ] Export or upload archive using Xcode Organizer or `xcodebuild -exportArchive`.
- [ ] Upload to TestFlight.
- [ ] Install TestFlight build on a real iPhone.
- [ ] Smoke test Release/TestFlight build:
  - [ ] First launch.
  - [ ] Child home to battle to result.
  - [ ] Parent profile entry.
  - [ ] Parent binding.
  - [ ] QR scan.
  - [ ] Photo library import.
  - [ ] Camera import.
  - [ ] Word extraction result and review.
  - [ ] Sync after app restart.
  - [ ] Settings page has no developer backend entry.
  - [ ] Home version-label triple-tap does not open DevMenu in Release.
  - [ ] Bypass secret route cannot be opened in Release.

## P1 App Store Connect Metadata

- [ ] App name: `魔法背单词`.
- [ ] Subtitle: prepare a short Chinese value proposition.
- [ ] Description: explain learning flow, parent import, child practice, and privacy posture.
- [ ] Keywords: prepare Chinese keywords within Apple limits.
- [ ] Support URL: public, reachable, and preferably Chinese.
- [ ] Marketing URL: optional; use only if public and polished.
- [ ] Privacy Policy URL: required.
- [ ] Copyright and contact info.
- [ ] Age rating questionnaire.
- [ ] Content rights declaration.
- [ ] Export compliance questionnaire.
- [ ] App screenshots:
  - [ ] iPhone 6.9-inch or current required size.
  - [ ] iPhone 6.5-inch if App Store Connect requests it.
  - [ ] iPad screenshots if iPad is supported.
  - [ ] Screens show actual app UI, not debug/dev screens.
- [ ] App preview video: optional; skip unless polished.
- [ ] Review notes:
  - [ ] Demo parent account.
  - [ ] Demo child profile.
  - [ ] Steps for QR binding or an alternative review path.
  - [ ] Sample textbook photo flow.
  - [ ] Account deletion path.
  - [ ] Any server-side delays reviewers should expect.

## P2 Compliance And Operational Prep

- [ ] Confirm ICP/APP filing status if distributing in mainland China or linking to China-hosted services.
- [ ] Confirm whether the product is positioned as an education app or game. If treated as a game in mainland China distribution, legal review may be needed for game-specific requirements.
- [ ] Confirm no paid content, subscriptions, or external purchase paths are present. If any exist, App Store IAP review is required.
- [ ] Confirm production observability is available without collecting unnecessary child data.
- [ ] Prepare rollback plan:
  - [ ] Keep previous build available.
  - [ ] Server feature flags or compatible APIs remain backwards-compatible.
  - [ ] Document who can pause release or remove from sale.

## iOS Work Queue

1. [x] Run and fix iOS tests on a valid simulator/device.
2. [x] Verify Release build hides every DevMenu and preview-routing entry.
3. [x] Decide whether `NSPhotoLibraryAddUsageDescription` is still needed; remove it if unused.
4. [ ] Validate account deletion entry and reviewer flow.
5. [ ] Draft App Store privacy questionnaire answers from actual server/client data.
6. [ ] Prepare privacy policy and support URL.
7. [ ] Archive and upload v0.7.0 to TestFlight.
8. [ ] Complete real-device TestFlight smoke test.
9. [ ] Prepare screenshots and App Store metadata.
10. [ ] Submit for Apple review.
