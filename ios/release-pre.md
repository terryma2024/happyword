# iOS v0.7.0 Release Preparation

> Scope: Apple App Store only. Android release work is intentionally excluded.
> App: `WordMagicGame` / `魔法背单词`
> Bundle ID: `com.terryma.wordmagicgame`
> Version: `0.7.0`
> Build: `1007002`
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
- [x] `CURRENT_PROJECT_VERSION` is `1007002` in `ios/project.yml`.
- [x] Bundle ID is `com.terryma.wordmagicgame`.
- [x] App display name is `魔法背单词`.
- [x] Release Simulator build succeeded locally with `xcodebuild build -scheme WordMagicGame -configuration Release -destination 'generic/platform=iOS Simulator'`.
- [x] Release archive succeeded locally at `/private/tmp/WordMagicGame-v0.7.0-b1007002.xcarchive`.
- [x] App Store Connect upload succeeded for replacement build `0.7.0 (1007002)`; build is added to TestFlight internal group `Internal Smoke`.
- [x] `zh-Hans.lproj/InfoPlist.strings` exists for camera and photo-library permission strings.
- [x] Release-gated developer tools policy exists in code and has unit coverage in `ios/WordMagicGameTests/Core/CloudSyncTests.swift`.
- [x] Full iOS unit/UI test pass is verified on simulator `iPhone 17 Pro (iOS 26.4)`: 100 unit tests and 19 UI tests passed.
- [x] Release Simulator sanity check verified `-UITestRouteDevMenu` and `-UITestRouteBypassSecret` land on the normal home screen.
- [x] `NSPhotoLibraryAddUsageDescription` was removed because the iOS client only reads from Photos via `PhotosPicker` and does not write to the photo library.
- [ ] Real-device Release/TestFlight smoke test is not yet done for build `0.7.0 (1007002)`.
- [x] App Store Connect app record is verified by successful upload (`adamId: 6768499286`).
- [x] App privacy questionnaire draft is derived from the current repo behavior.
- [x] Privacy policy URL exists in repo as public server page: `https://happyword.cool/privacy`.
- [x] Support URL exists in repo as public server page: `https://happyword.cool/support`.
- [x] In-app account deletion initiation path is verified from this repo: `孩子档案` -> `账号与数据管理` opens `/family/<family_id>/account`.

## P0 Blockers To Clear Before Upload

- [x] Confirm Apple Developer Program team access.
  - Expected team in repo: `DEVELOPMENT_TEAM: 99UX498DB4`.
  - Confirmed by successful App Store Connect upload from local archive.

- [x] Confirm App Store Connect app record.
  - Bundle ID: `com.terryma.wordmagicgame`.
  - App Store Connect app id: `6768499286`.
  - SKU: choose a stable internal SKU, for example `wordmagicgame-ios`.
  - Primary language: recommend `zh-Hans` if the first market is mainland China.
  - Category: choose Education or Games only after product positioning is confirmed.
  - Kids Category: decide explicitly. If selected, review ads, analytics, external links, and parental-gate requirements carefully.

- [ ] Confirm production backend is ready for Apple review.
  - Production API must be HTTPS.
  - Review account must work without developer-only switches.
  - Parent binding, QR scan, photo import, word extraction, sync, and child practice flows must be reviewable.
  - Any Vercel preview/local/staging routing must be unreachable in Release.

- [x] Confirm account deletion.
  - The bound child-device screen provides an in-app initiation path: `游戏配置` -> `孩子档案` -> `账号与数据管理`.
  - The iOS entry opens the parent Web account settings page, where the authenticated parent can delete the account or cancel deletion during the grace period.
  - Server route source: `server/app/routers/parent_account.py` (`POST /api/v1/family/{family_id}/account/delete` and HTML `/family/{family_id}/account`).
  - Reviewer note draft: bind or seed a child profile, open `游戏配置` -> `孩子档案` -> `账号与数据管理`; log in to the parent web page with the demo parent email/OTP; use `删除账号`.

- [x] Confirm privacy policy URL.
  - Public URL: `https://happyword.cool/privacy`.
  - It is implemented as `/privacy` without a parent session requirement.
  - It describes collected data, purpose, deletion/export path, third-party services, child/minor handling, and support contact.
  - Support URL: `https://happyword.cool/support`.

- [ ] Confirm App Privacy details.
  - Inventory data collected by the app and server: account/binding data, child profile name, learning progress, uploaded textbook photos, generated word lists, device identifier, diagnostics/logs if any.
  - Decide whether each item is linked to identity.
  - Decide whether any data is used for tracking. Target answer should be no unless third-party tracking is actually present.

## App Store Privacy Questionnaire Draft

> Repo-derived draft, not a legal/privacy-policy substitute. Apple asks for app-level collection practices, including third-party partners; data is generally treated as linked when it is tied to account, device, or family identifiers.

### Top-Level Answers

- Does the app collect data from this app? **Yes**.
- Is any collected data used for tracking? **No** based on the current repo: no `AdSupport`, `AppTrackingTransparency`, ad SDK, analytics SDK, or third-party tracking integration is present in the iOS target.
- Is data linked to the user? **Yes** for parent account, child profile, device binding, learning sync, wishlist/redemption, and lesson-import data because these are tied to `family_id`, `child_profile_id`, `device_id`, account email, or device token.
- Third-party services involved by the backend: Vercel hosting/CDN/blob storage, MongoDB data store, configured email provider for OTP, and OpenAI vision extraction for textbook-image lesson import. No third-party SDK is embedded in the iOS app target.

### Data Types To Declare

| App Store data type | Collected? | Linked? | Tracking? | Purpose | Repo evidence |
| --- | --- | --- | --- | --- | --- |
| Contact Info - Email Address | Yes | Yes | No | App Functionality, Account Management | Parent OTP login stores `users.email`; parent web/API auth uses email verification. |
| Identifiers - User ID | Yes | Yes | No | App Functionality, Account Management | `family_id`, `child_profile_id`, `binding_id`, parent `username` identify account/family records. |
| Identifiers - Device ID | Yes | Yes | No | App Functionality, Security | iOS creates a local device id and sends it during pair redeem; server stores `device_bindings.device_id`. |
| User Content - Photos or Videos | Yes, if parent imports lessons from camera/photos | Yes | No | App Functionality | Lesson import uploads textbook photos to backend/blob before extraction. |
| User Content - Other User Content | Yes | Yes | No | App Functionality | Family word packs, lesson drafts, child wishlist item names, redemption requests, and child nickname/avatar. |
| Usage Data - Product Interaction | Yes | Yes | No | App Functionality, Personalization | Synced word stats include seen/correct/wrong counts, review timing, mastery, and memory state. |
| Diagnostics - Crash Data / Performance Data / Other Diagnostics | Not intentionally collected by app code | TBD | No | TBD | No iOS diagnostics SDK is present; verify Vercel/server request logs before final App Store Connect entry. |

### Data Types To Answer No Unless Product Changes

- Location, Contacts, Health, Fitness, Financial Info, Purchases, Browsing History, Search History, Sensitive Info.
- Phone Number and Physical Address.
- Advertising Data.
- Precise or coarse location.
- Audio data: pronunciation uses on-device `AVSpeechSynthesizer`; no microphone path is present.

### Privacy Policy Notes To Match

- Explain parent email OTP login, family/device binding, child profile nickname/avatar, generated/custom word packs, learning progress sync, wishlist/redemption flow, and textbook image import.
- Explain that textbook images may be processed by backend services and OpenAI vision extraction when lesson import is used.
- Explain account deletion: in iOS open `游戏配置` -> `孩子档案` -> `账号与数据管理`; parent deletes from the Web account page with a grace period and cancel option.
- State that data is not used for third-party tracking or targeted advertising unless that changes before submission.

- [ ] Confirm permission usage is accurate.
  - Camera: textbook photo upload and parent QR binding.
  - Photo library read: choose textbook photos.
  - Photo library add: only keep if the app really saves images to the library; otherwise remove it before submission.

## P1 Build And Verification Checklist

- [x] Regenerate Xcode project after the `1007002` build-number change.

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

- [x] Run device Release build before archive/upload.

```sh
cd ios
xcodebuild build \
  -scheme WordMagicGame \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/wordmagic-ios-release-device
```

- [x] Archive for App Store distribution.
  - Latest archive: `/private/tmp/WordMagicGame-v0.7.0-b1007002.xcarchive`.

```sh
cd ios
xcodebuild archive \
  -scheme WordMagicGame \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/WordMagicGame-v0.7.0.xcarchive
```

- [x] Export or upload archive using Xcode Organizer or `xcodebuild -exportArchive`.
- [x] App Store Connect export options are stored in `ios/ExportOptions.AppStore.plist`.
- [x] Upload replacement build to TestFlight.
  - Previous internal smoke build: `0.7.0 (1007001)`.
  - Latest internal smoke build: `0.7.0 (1007002)`.
  - Reason for replacement: previous `1007000` was built before latest `origin/main` and did not include the scan-binding parent login link; release version label was also hidden with the DevMenu gate.
  - Reason for second replacement: `1007001` did not include the iOS credential-persistence guard added after simulator smoke testing.
  - Upload result: `xcodebuild -exportArchive` reported `Upload succeeded` for `WordMagicGame`; App Store Connect processing completed.
  - TestFlight result: `1007002` export compliance was answered in App Store Connect and the build is now `正在测试` in `Internal Smoke`.
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
- [x] Support URL: public, reachable, and preferably Chinese: `https://happyword.cool/support`.
- [ ] Marketing URL: optional; use only if public and polished.
- [x] Privacy Policy URL: required: `https://happyword.cool/privacy`.
- [ ] Copyright and contact info.
- [ ] Age rating questionnaire.
- [ ] Content rights declaration.
- [x] Export compliance questionnaire for TestFlight build `1007002`.
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
  - [x] Account deletion path: `游戏配置` -> `孩子档案` -> `账号与数据管理`.
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
4. [x] Validate account deletion entry and reviewer flow.
5. [x] Draft App Store privacy questionnaire answers from actual server/client data.
6. [x] Prepare privacy policy and support URL.
7. [x] Archive and upload v0.7.0 to TestFlight.
8. [ ] Complete real-device TestFlight smoke test.
9. [ ] Prepare screenshots and App Store metadata.
10. [ ] Submit for Apple review.
