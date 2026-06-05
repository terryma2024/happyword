# iOS Release Preparation

> Scope: Apple App Store only. Android release work is intentionally excluded.
> App: `WordMagicGame` / `魔法背单词`
> Bundle ID: `com.terryma.wordmagicgame`
> Version: `1.0.0`
> Build: `1010000`
> Last updated: 2026-06-03

## Source Of Truth

- Apple App Store submission: https://developer.apple.com/app-store/submitting/
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Apple account deletion requirement: https://developer.apple.com/support/offering-account-deletion-in-your-app
- Existing repo checklist: `docs/ios-replica/06-release-readiness-checklist.md`
- Project config: `ios/project.yml`
- Info.plist: `ios/WordMagicGame/Resources/Info.plist`

## Current Repo State

- [x] `MARKETING_VERSION` is `1.0.0` in `ios/project.yml`.
- [x] `CURRENT_PROJECT_VERSION` is `1010000` in `ios/project.yml`.
- [x] Bundle ID is `com.terryma.wordmagicgame`.
- [x] App display name is `魔法背单词`.
- [x] Release Simulator build succeeded locally with `xcodebuild build -scheme WordMagicGame -configuration Release -destination 'generic/platform=iOS Simulator'`.
- [x] Release archive succeeded locally at `/private/tmp/WordMagicGame-v1.0.0-b1010000.xcarchive`.
- [x] App Store Connect upload succeeded for build `1.0.0 (1010000)` on 2026-06-01; TestFlight/App Store Connect processing completed.
- [x] `zh-Hans.lproj/InfoPlist.strings` exists for camera and photo-library permission strings.
- [x] Release-gated developer tools policy exists in code and has unit coverage in `ios/WordMagicGameTests/Core/CloudSyncTests.swift`.
- [x] Full iOS unit/UI test pass is verified on simulator `iPhone 17 Pro (iOS 26.4)`: 100 unit tests and 19 UI tests passed.
- [x] Release Simulator sanity check verified developer-only routes land on the normal home screen.
- [x] `NSPhotoLibraryAddUsageDescription` was removed because the iOS client only reads from Photos via `PhotosPicker` and does not write to the photo library.
- [x] Real-device Release/TestFlight smoke test passed for build `0.7.0 (1007004)`.
- [x] App Store Connect app record is verified by successful upload (`adamId: 6768499286`).
- [x] App privacy questionnaire draft is derived from the current repo behavior.
- [x] Privacy policy URL exists in repo as public server page: `https://happyword.com.cn/privacy`.
- [x] Support URL exists in repo as public server page: `https://happyword.com.cn/support`.
- [x] In-app account deletion initiation path is verified from this repo: `学习档案` -> `账号与数据管理` opens `/family/<family_id>/account`.
- [x] Apple App Review approved iOS version `0.8.4` / build `1008006`; App Store Connect status is `可分发`.
- [x] iOS version `0.9.4` / build `1009004` was submitted for App Review on 2026-05-29; App Store Connect status is `正在等待审核`.
- [x] iOS version `0.9.5` / build `1009005` was uploaded to App Store Connect/TestFlight, export-compliance answered as no listed encryption algorithm, selected for the App Store version, and submitted for App Review on 2026-05-30. App Store Connect status is `正在等待审核`.
- [x] iOS version `1.0.0` / build `1010000` was archived, uploaded to App Store Connect/TestFlight, export-compliance answered as no listed encryption algorithm, selected for the App Store version, and submitted for App Review on 2026-06-01. App Store Connect status is `正在等待审核`.
- [x] App Store availability was re-enabled on 2026-05-24 for the available storefront set. App Store Connect now shows 148 countries/regions `正在处理为可用`.
- [ ] EU / DSA trader-status countries remain unavailable until the account owner provides trader status in App Store Connect.

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

- [x] Confirm production backend is ready for Apple review.
  - Production API must be HTTPS.
  - Review account must work without developer-only switches.
  - Parent binding, QR scan, photo import, word extraction, sync, and child practice flows must be reviewable.
  - Any Vercel preview/local/staging routing must be unreachable in Release.
  - Apple approved iOS version `0.8.4` / build `1008006` by 2026-05-24, confirming the reviewer path was sufficient for App Review.

- [x] Confirm account deletion.
  - The bound learning-device screen provides an in-app initiation path: `游戏配置` -> `学习档案` -> `账号与数据管理`.
  - The iOS entry opens the parent Web account settings page, where the authenticated parent can delete the account or cancel deletion during the grace period.
  - Server route source: `server/app/routers/parent_account.py` (`POST /api/v1/family/{family_id}/account/delete` and HTML `/family/{family_id}/account`).
  - Reviewer note draft: bind or seed a learner profile, open `游戏配置` -> `学习档案` -> `账号与数据管理`; log in to the parent web page with a reachable reviewer email and OTP; use `删除账号`.

- [x] Confirm privacy policy URL.
  - Public URL: `https://happyword.com.cn/privacy`.
  - It is implemented as `/privacy` without a parent session requirement.
  - It describes collected data, purpose, deletion/export path, third-party services, child/minor handling, and support contact.
  - Support URL: `https://happyword.com.cn/support`.

- [x] Confirm App Privacy details.
  - Inventory data collected by the app and server: account/binding data, child profile name, learning progress, uploaded textbook photos, generated word lists, device identifier, diagnostics/logs if any.
  - App Store Connect privacy labels were published on 2026-05-17.
  - Declared data types: Email Address, User ID, Device ID, Photos or Videos, Other User Content, Product Interaction.
  - Declared as linked to the user and not used for tracking.

## App Store Privacy Questionnaire Draft

> Repo-derived draft, not a legal/privacy-policy substitute. Apple asks for app-level collection practices, including third-party partners; data is generally treated as linked when it is tied to account, device, or family identifiers.

### Top-Level Answers

- Does the app collect data from this app? **Yes**.
- Is any collected data used for tracking? **No** based on the current repo: no `AdSupport`, `AppTrackingTransparency`, ad SDK, analytics SDK, or third-party tracking integration is present in the iOS target.
- Is data linked to the user? **Yes** for parent account, child profile, device binding, learning sync, wishlist/redemption, and lesson-import data because these are tied to `family_id`, `child_profile_id`, `device_id`, account email, or device token.
- Third-party services involved by the backend: Tencent CloudBase Run hosting,
  Tencent COS for new uploads, Shanghai Lighthouse MongoDB-compatible data
  store, configured email provider for OTP, and Qwen vision extraction for
  textbook-image lesson import. Historical uploaded assets or rollback paths may
  still reference Vercel Blob / MongoDB Atlas until archival or backfill is
  complete. No third-party SDK is embedded in the iOS app target.

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

- Explain parent email OTP login, family/device binding, learner profile nickname/avatar, generated/custom word packs, learning progress sync, wishlist/redemption flow, and textbook image import.
- Explain that textbook images may be processed by backend services and Qwen
  vision extraction when lesson import is used.
- Explain account deletion: in iOS open `游戏配置` -> `学习档案` -> `账号与数据管理`; parent deletes from the Web account page with a grace period and cancel option.
- State that data is not used for third-party tracking or targeted advertising unless that changes before submission.

- [x] Confirm permission usage is accurate.
  - Camera: textbook photo upload and parent QR binding.
  - Photo library read: choose textbook photos.
  - Photo library add: not used by the iOS client; `NSPhotoLibraryAddUsageDescription` was removed before submission.

## P1 Build And Verification Checklist

- [x] Regenerate Xcode project after the `1008006` build-number change.

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
  - Latest archive: `/private/tmp/WordMagicGame-v0.7.0-b1007004.xcarchive`.

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
  - Previous internal smoke build: `0.7.0 (1007002)`.
  - Latest internal smoke build: `0.7.0 (1007004)`.
  - Reason for replacement: previous `1007000` was built before latest `origin/main` and did not include the scan-binding parent login link; release version label was also hidden with the DevMenu gate.
  - Reason for second replacement: `1007001` did not include the iOS credential-persistence guard added after simulator smoke testing.
  - Reason for third replacement: `1007002` did not include the iOS force-light-mode release fix for system dark mode.
  - Reason for fourth replacement: `1007003` did not include the iOS parent-admin real backend flow, lesson-review scrolling/editing, and source-image preview fixes verified on simulator.
  - Upload result: `xcodebuild -exportArchive` reported `Upload succeeded` for `WordMagicGame`; App Store Connect processing completed.
  - TestFlight result: `1007004` is now `正在测试` in `Internal Smoke`.
- [x] Install TestFlight build on a real iPhone.
- [x] Smoke test Release/TestFlight build:
  - [x] First launch.
  - [x] Child home to battle to result.
  - [x] Parent profile entry.
  - [x] Parent binding.
  - [x] QR scan.
  - [x] Photo library import.
  - [x] Camera import.
  - [x] Word extraction result and review.
  - [x] Sync after app restart.
  - [x] Settings page has no developer backend entry.
  - [x] Home version-label triple-tap does not open DevMenu in Release.
  - [x] Legacy preview bypass route is not present in the client.

## P1 App Store Connect Metadata

- [x] App name: `魔法背单词`.
- [x] Subtitle draft: `家长导入，闯关背单词`.
- [x] Description draft prepared below.
- [x] Keywords draft prepared below.
- [x] Support URL: public, reachable, and preferably Chinese: `https://happyword.com.cn/support`.
- [x] Marketing URL: skip for v0.7.0 unless a polished public product page is added.
- [x] Privacy Policy URL: required: `https://happyword.com.cn/privacy`.
- [x] Copyright and contact-info finalized below.
- [x] Age rating questionnaire draft prepared below.
- [x] Content rights declaration draft prepared below.
- [x] Export compliance questionnaire for TestFlight build `1007003`.
- [x] Export compliance status accepted for replacement TestFlight build `1007004`; App Store Connect allowed internal TestFlight testing.
- [x] App screenshots:
  - [x] iPhone 6.9-inch or current required size.
  - [x] Active iPhone set replaced on 2026-05-29 with `1290x2796` portrait collage screenshots at `assets/screenshots/appstore/ios/v0.8.4-review-fix/iphone/`.
  - [x] Previous `2778x1284` landscape iPhone set archived at `assets/screenshots/appstore/ios/v0.8.4-review-fix/archived/iphone-landscape-2026-05-29/`.
  - [x] iPad screenshots if iPad is supported.
  - [x] Screens show actual app UI, not debug/dev screens.
  - [x] iPhone screenshots regenerated on `WordMagic AppStore iPhone 13 Pro Max` because App Store Connect rejected the prior `2622x1206` iPhone 17 Pro size. The later search-result fix promoted the `1290x2796` portrait collage set to active.
  - [x] Active iPhone portrait screenshots replaced the old landscape iPhone screenshots in App Store Connect on 2026-05-29. ASC accepted the derived `1284x2778` 6.5-inch set at `assets/screenshots/appstore/ios/v0.8.4-review-fix/iphone-asc-6-5/`.
  - [x] Existing iPad screenshots remain available for App Store Connect.
- [ ] App preview video: optional; skip unless polished.
- [x] Review notes draft prepared below.
  - [x] Reviewer-owned email OTP path finalized: reviewer should use their own reachable email address to receive the one-time code.
  - [x] Demo learner profile.
  - [x] Steps for QR binding or an alternative review path.
  - [x] Sample textbook photo flow.
  - [x] Account deletion path: `游戏配置` -> `学习档案` -> `账号与数据管理`.
  - [x] Reviewer notes mention that server word extraction may take several seconds.

### App Store Connect Draft Values

Use the following values for the App Store Connect version metadata unless the release owner chooses different positioning.

| Field | Draft |
| --- | --- |
| App name | `魔法背单词` |
| Subtitle | `家长导入，闯关背单词` |
| Primary category | Education |
| Secondary category | Games, optional. Skip if App Store Connect does not require it. |
| Kids Category | Do not select for v0.7.0 unless legal/product explicitly wants the stricter Kids Category obligations. The app is child-facing, but it also has parent account, web login, support, and textbook-image import flows. |
| Privacy Policy URL | `https://happyword.com.cn/privacy` |
| Support URL | `https://happyword.com.cn/support` |
| Marketing URL | Leave empty for v0.7.0. |
| Copyright | `© 2026 TianYi Ma` |
| Contact email | `support@happyword.com.cn` |

### Description Draft

```text
魔法背单词是一款家庭英语单词练习应用，也为家长提供词库导入和学习同步工具。

学习者可以在闯关式练习中认识单词、选择释义、复习错题，并通过本地学习记录逐步巩固。家长可以绑定学习设备，从课本照片或相册图片中导入单词，审核识别结果后发布为可练习的词包。

主要功能：
- 闯关式英语单词练习
- 错题复习与学习进度记录
- 家长账号绑定与学习档案管理
- 拍照或相册导入课本单词
- 识别结果审核、编辑与发布
- 家庭词包和学习数据同步
- 账号与数据管理入口

我们重视家庭数据保护。应用不包含广告 SDK，不做跨应用追踪。家长主动上传的教材图片仅用于生成可审核的单词草稿；家长可在账号与数据管理页面导出数据或发起账号删除。
```

### Keywords Draft

```text
英语学习,背单词,英语启蒙,单词练习,家庭学习,课本导入,自然拼读,词汇记忆,复习巩固,英语游戏
```

### Promotional Text Draft

```text
把课本里的单词变成可以闯关练习的家庭词包。
```

### Review Notes Draft

```text
Thank you for reviewing WordMagicGame / 魔法背单词.

Recommended review path:
1. Launch the iOS app.
2. Use the learning flow from the home screen to start a word battle and complete a short practice session.
3. Open 游戏配置, then 学习档案.
4. For parent features, use 家长账号 to bind a parent account. The parent web login uses email one-time codes. Please use your own reachable reviewer email address to receive the OTP.
5. After binding, open 家长管理后台 to test textbook import.
6. Use 拍照导入 or 从相册导入 with a sample textbook/word-list image. The server may take several seconds to extract words from the image.
7. Open the pending lesson draft, review the source image preview and extracted words, edit if needed, then publish the word pack.
8. Restart the app and confirm the synced word pack is available to the learning flow.
9. To review account deletion, open 游戏配置 -> 学习档案 -> 账号与数据管理. This opens the account page in the app's Safari view where the parent can export account data or request account deletion.

Notes:
- The app does not include ads, in-app purchases, or third-party tracking SDKs.
- Camera permission is used for textbook photo import and parent account QR binding.
- Photo Library permission is used to choose textbook images for lesson import.
- Release builds do not expose developer backend switching or preview routing controls.
```

### Privacy Answers Draft

- Data collection: Yes.
- Tracking: No.
- Linked to user: Yes for parent email, family/account identifiers, child profile, device binding, learning progress, family packs, wishlist/redemption data, and uploaded lesson images.
- Third-party tracking SDKs: No.
- Ads: No.
- Purchases / IAP: No for v0.7.0.
- Photos or videos: Yes, only when the parent chooses textbook images for lesson import.
- Diagnostics: No intentional client-side diagnostics SDK in the iOS target. Server request logs may exist for service operation.

### Age Rating Draft

- Cartoon or fantasy violence: None or infrequent/mild if App Store Connect treats battle animations as fantasy conflict.
- Realistic violence, sexual content, profanity, alcohol/drugs, gambling, contests, unrestricted web access: No.
- User-generated content / social networking: No public UGC or social feed.
- Medical/treatment information: No.
- In-app purchases / loot boxes: No.
- Target age rating expectation: likely 4+, subject to App Store Connect questionnaire result.

### Content Rights Draft

- The app contains original app UI, game art, built-in word data, and generated/imported family word content.
- No paid third-party media, streaming media, or copyrighted textbook pages are redistributed by the app.
- Parent-uploaded textbook images are used for private lesson extraction and review, not for public distribution.

### Screenshot Plan

- Captured from an equivalent Release simulator build for `0.7.0 (1007004)`.
- Search-result iPhone portrait set: `assets/screenshots/appstore/ios/v0.8.4-search-portrait/iphone/`.
  - Size: `1290x2796`.
  - Format: PNG, 8-bit RGB, no alpha.
  - Files: `01-parent-import-child-adventure.png`, `02-battle-practice.png`, `03-learning-result.png`, `04-parent-admin-import.png`, `05-pack-manager.png`.
  - Composition: the first three files are portrait poster collages made from multiple landscape app screenshots.
  - Promoted to the active iPhone upload directory on 2026-05-29.
- iPhone screenshot set: `assets/screenshots/appstore/ios/v0.8.4-review-fix/iphone/`.
  - Size: `1290x2796`.
  - Format: PNG, 8-bit RGB, no alpha.
  - Composition: portrait poster collages; the first three files are the App Store search-result thumbnails.
  - Files: `01-home.png`, `02-battle.png`, `03-result.png`, `04-learning-profile.png`, `05-pack-manager.png`.
- Archived iPhone landscape set: `assets/screenshots/appstore/ios/v0.8.4-review-fix/archived/iphone-landscape-2026-05-29/`.
  - Size: `2778x1284`.
  - Files: `01-home.png`, `02-battle.png`, `03-result.png`, `04-learning-profile.png`, `05-pack-manager.png`.
- iPad screenshot set: `assets/screenshots/appstore/ios/v0.8.4-review-fix/ipad/`.
  - Device: `iPad Pro 13-inch (M5) (iOS 26.4)`.
  - Size: `2064x2752`.
  - Files: `01-home.png`, `02-battle.png`, `03-result.png`, `04-learning-profile.png`, `05-pack-manager.png`.
- App Store Connect submission state as of 2026-05-30:
  - Version metadata fields filled for `iOS App 版本 0.8.4`: promotional text, description, keywords, support URL, version, copyright, reviewer notes, App Review contact, and post-review release settings.
  - Build `1008006` selected for submission.
  - App Privacy labels published.
  - App Info completed: subtitle, content rights, primary category `Education`, and age rating `4+`.
  - Pricing completed: free app and public distribution.
  - Version `0.8.4 (1008006)` passed Apple review; App Store Connect status is `可分发`.
  - Availability was re-enabled on 2026-05-24 after approval. App Store Connect shows 148 countries/regions `正在处理为可用`; remaining EU / DSA trader-status regions require account-owner trader-status completion.
  - Version `0.9.4 (1009004)` was uploaded, export-compliance answered as no listed encryption algorithm, selected for the App Store version, and submitted for review. App Store Connect status is `正在等待审核`.
  - Version `0.9.5 (1009005)` was uploaded, export-compliance answered as no listed encryption algorithm, selected for the App Store version, and submitted for review on 2026-05-30. App Store Connect status is `正在等待审核`; submission confirmation said review may take up to 48 hours.
  - Version `1.0.0 (1010000)` was uploaded, export-compliance answered as no listed encryption algorithm, selected for the App Store version, and submitted for review on 2026-06-01. App Store Connect status is `正在等待审核`; submission confirmation said review may take up to 48 hours.
- Screenshots cover:
  1. Learning home screen.
  2. Battle/practice screen.
  3. Practice result screen.
  4. Learning profile / binding entry.
  5. Word-pack manager screen.
- Rejected screenshot archive: `assets/screenshots/appstore/ios/v0.7.0-b1007004/rejected/lesson-review-image-load-failed/`.
  - Reason: the lesson-review screenshots showed `图片加载失败`, so they must not be used for App Store submission.
- Do not show DevMenu, preview URLs, local mock labels, browser errors, OTP codes, personal email, or private child data.

## P2 Compliance And Operational Prep

- [ ] Confirm ICP/APP filing status if distributing in mainland China or linking to China-hosted services.
- [ ] Confirm whether the product is positioned as an education app or game. If treated as a game in mainland China distribution, legal review may be needed for game-specific requirements.
- [ ] Confirm no paid content, subscriptions, or external purchase paths are present. If any exist, App Store IAP review is required.
- [ ] Confirm production observability is available without collecting unnecessary child data.
- [ ] Complete App Store Connect trader status if the app should be available in EU / DSA-covered storefronts.
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
8. [x] Complete real-device TestFlight smoke test.
9. [x] Prepare screenshots and App Store metadata.
10. [x] Submit for Apple review.
11. [x] Apple App Review approved `0.8.4 (1008006)`.
12. [x] Re-enable App Store availability after approval; 148 countries/regions are processing to available.
13. [ ] Decide whether to complete EU / DSA trader-status information for the remaining unavailable countries/regions.
