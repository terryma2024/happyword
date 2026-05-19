# Android v0.7.0 Release Preparation

> Scope: Google Play only. iOS App Store and Huawei AppGallery release work are intentionally excluded.
> App: `WordMagicGame Android` / `魔法背单词`
> Package name: `cool.happyword.wordmagic`
> Version name: `0.7.0`
> Version code: `1007000`
> Last updated: 2026-05-19

## Source Of Truth

- Google Play app setup: https://support.google.com/googleplay/android-developer/answer/9859152
- Google Play target API level requirement: https://developer.android.com/google/play/requirements/target-sdk
- Android App Bundle upload: https://developer.android.com/studio/publish/upload-bundle
- Play App Signing: https://support.google.com/googleplay/android-developer/answer/9842756
- Google Play Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Google Play account deletion requirement: https://support.google.com/googleplay/android-developer/answer/13327111
- Google Play target audience and content: https://support.google.com/googleplay/android-developer/answer/9867159
- Google Play content ratings: https://support.google.com/googleplay/android-developer/answer/9898843
- Android dev commands: `.cursor/android-dev-commands.md`
- Existing repo checklist: `docs/android-replica/07-release-readiness-checklist.md`
- Android Gradle config: `android/app/build.gradle.kts`
- Android manifest: `android/app/src/main/AndroidManifest.xml`

## Current Repo State

- [x] `versionName` is `0.7.0` in `android/app/build.gradle.kts`.
- [x] `versionCode` is `1007000` in `android/app/build.gradle.kts`.
- [x] `namespace` and `applicationId` are `cool.happyword.wordmagic`.
- [x] `compileSdk` is `36`.
- [x] `targetSdk` is `36`, which is above the current Google Play Android 15 / API 35 submission floor for phone/tablet apps.
- [x] `minSdk` is `26`.
- [x] Launcher display name now uses `@string/app_name`, with `app_name` set to `魔法背单词`.
- [x] Main manifest does not set `android:usesCleartextTraffic="true"`; the debug manifest keeps cleartext traffic for local mock servers only.
- [x] Main manifest declares `android.permission.INTERNET`.
- [x] Merged Release manifest was inspected on 2026-05-17.
  - Package: `cool.happyword.wordmagic`.
  - Version: `0.7.0 (1007000)`.
  - Label: `@string/app_name`.
  - Permissions merged into Release: `INTERNET`, `ACCESS_NETWORK_STATE`, `CAMERA`, and app-local `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
  - Camera-related features are declared `required="false"`.
- [x] Release-gated developer tools policy exists in `BuildGate` and is covered by JVM tests.
- [x] Release builds coerce Local/Preview backend routing to Staging unless production routing is already selected.
- [x] Android Phase 5 gate was previously verified on 2026-05-12: `testDebugUnitTest`, `assembleDebug`, `connectedDebugAndroidTest`, and `assembleRelease` passed.
- [x] 2026-05-17 local gates passed after Google Play prep edits:
  - `./gradlew testDebugUnitTest`.
  - `./gradlew assembleDebug`.
  - `./gradlew assembleRelease`.
  - `./gradlew bundleRelease`.
- [x] `bundleRelease` generated `android/app/build/outputs/bundle/release/app-release.aab`.
- [x] Release AAB was rebuilt with a local Google Play upload key on 2026-05-19.
  - Artifact: `android/app/build/outputs/bundle/release/app-release.aab`.
  - Size reported by Play Console for new installs: `21.7 MB`.
  - Local AAB SHA-256: `2db3e0a87a962e1110da6b29f29f2b62db8a5aaf9785e48bab8369146ba11648`.
  - `jarsigner -verify -verbose -certs` exited successfully with `jar verified`.
  - Upload key SHA-256 fingerprint: `8E:87:E9:8E:28:A6:18:0E:41:BC:09:9D:94:47:BC:53:E1:FA:FF:15:D4:83:53:F2:72:F5:37:AC:69:B1:36:B1`.
  - Signing material is local-only and gitignored under `android/release-signing.properties` and `android/release-keys/`; do not commit secrets.
- [x] Google Play developer account is verified enough to create apps.
  - Chrome reached Play Console Home on 2026-05-17.
  - Developer account: `Terry Ma`, personal account.
  - Account ID: `5614535425901020503`.
  - Account verification was completed by the release owner before 2026-05-18 continuation.
- [x] Google Play app draft was created on 2026-05-18.
  - App id: `4975321946272670251`.
  - App name: `魔法背单词`.
  - Package name: `cool.happyword.wordmagic`.
  - Default language: `Chinese (Simplified) - zh-CN`.
  - App/game: App.
  - Price: Free.
  - Package availability check passed before creation.
- [x] Play App Signing Terms of Service were accepted during app creation.
- [ ] Real-device Google Play internal test / release smoke test is not done.
- [x] Play Console App content items completed in draft:
  - Privacy policy URL: `https://happyword.cool/privacy`.
  - Ads: No ads.
  - Advertising ID: No.
  - Government apps: No.
  - Financial features: no financial features.
  - Health apps: no health features.
- [x] Play Console Store settings completed in draft:
  - Category: Education.
  - Contact email: `support@happyword.cool`.
  - Website: `https://happyword.cool/support`.
- [x] Play Console App access completed in draft.
  - Reviewer access credentials were entered in Play Console only; do not commit or document the password.
- [x] Play Console Content rating completed on 2026-05-18.
  - IARC submitted at 2026-05-18 23:16 Asia/Shanghai.
  - Ratings shown by Play Console: Brazil All ages, North America ESRB Everyone, Europe PEGI 3, Germany USK 6+, Rest of world IARC 3+, Russia 3+, South Korea 3+.
- [x] Play Console Target audience completed on 2026-05-18.
  - Target age groups: `6-8` and `9-12`.
  - Legal/regulatory child-compliance declaration was confirmed by the release owner and checked.
  - Teacher Approved program: not included for v0.7.0 first release.
  - Result: app is on the Designed for Families path and must continue to satisfy Play Families policy.
- [x] Play Console Data safety completed on 2026-05-18.
  - Data collection/share: Yes.
  - Encrypted in transit: Yes.
  - Account creation: username/email plus other authentication.
  - Account deletion URL: `https://happyword.cool/support`.
  - Families policy commitment shown in Data safety: Yes.
  - Shared: Photos.
  - Collected: Name, Email address, User IDs, Photos, App interactions, Other user-generated content, Device or other IDs.
- [x] Google Play default `zh-CN` Store listing was saved on 2026-05-19.
  - Short description: `家长导入单词，孩子闯关练习`.
  - Full description: completed with learning flow, parent import, child practice, and privacy posture.
  - Draft app icon, feature graphic, phone screenshots, 7-inch tablet screenshots, and 10-inch tablet screenshots are uploaded.
  - Play Console Dashboard no longer shows the initial app setup task list; next visible path is internal/closed testing and production access.
- [x] Google Play internal testing release was published on 2026-05-19.
  - Track: Internal testing.
  - Release: `1007000 (0.7.0)`.
  - Status: Active / available to internal testers.
  - Released on Play Console: May 19 8:42 AM.
  - Tester list: `HappyWord internal testers`, 1 tester.
  - Join link: `https://play.google.com/apps/internaltest/4700852462014477805`.
  - Play Console still shows temporary app name `cool.happyword.wordmagic (unreviewed)` until app setup/review is complete.
  - Non-blocking upload warnings remain: no deobfuscation mapping file and no native debug symbols uploaded.
- [ ] Final tablet screenshots and production review submission are not complete.

## P0 Decisions Before Play Console App Creation

- [ ] Decide whether the Google Play package name should remain `cool.happyword.wordmagic`.
  - Google Play package names are effectively permanent after first publication.
  - iOS and HarmonyOS currently use `com.terryma.wordmagicgame`, while Android uses `cool.happyword.wordmagic`.
  - If the team wants cross-store identifier consistency, change Android `applicationId` before creating the Play Console app record.
  - If the team wants the public domain-aligned package, keep `cool.happyword.wordmagic` and treat it as canonical for Android.

- [ ] Decide the public app label for Android.
  - Main manifest currently sets `android:label="WordMagicGame"`.
  - Store listing should use `魔法背单词` if the first market is Chinese-language families.
  - Update Android label/localized strings before screenshots and Play upload if the public label should match iOS.

- [ ] Confirm whether the first Google Play release is an app or a game.
  - Recommended for v0.7.0: choose **App**, primary category **Education**.
  - Avoid positioning as a game unless product/legal accepts the additional review expectations around child-facing game content.
  - Price: recommend **Free** for v0.7.0 because there is no paid content, subscription, IAP, or external purchase path.

- [ ] Confirm developer account access and verification.
  - Play Console account owner/admin is present as `Terry Ma` / personal account.
  - App creation and several App content drafts are available, so the account can create apps and manage basic app content.
  - Still verify upload, testing-track, and review-submission permissions after a signed AAB is ready.

## P0 Blockers To Clear Before Upload

- [x] Configure Google Play release signing safely.
  - Release signing pattern is now present in `android/app/build.gradle.kts`.
  - `android/release-signing.properties.example` documents the required local properties.
  - Local-only `android/release-signing.properties` was created for this machine and is gitignored.
  - Prefer Play App Signing with a Google-generated app signing key and a separate upload key.
  - Do not commit keystore files, passwords, private keys, or machine-specific signing paths.
  - Store signing material outside the repo or in local/CI secrets; losing the upload key requires a Play Console upload-key reset.

- [x] Build a signed release AAB.
  - Google Play new apps should be uploaded as Android App Bundles.
  - Expected artifact: `android/app/build/outputs/bundle/release/app-release.aab`.
  - Current generated AAB is signed with the local upload key and accepted by Play Console internal testing.
  - Increase `versionCode` for every replacement upload after the first accepted bundle.

- [x] Confirm Play Console app record.
  - App id: `4975321946272670251`.
  - Package name: `cool.happyword.wordmagic`.
  - Default language: `zh-CN` / Simplified Chinese.
  - App name: `魔法背单词`.
  - App/game: App.
  - Category: Education.
  - Price: Free.
  - Contact email: `support@happyword.cool`.
  - Declarations accepted during app creation: Developer Program Policies, Play App Signing Terms, and US export laws.

- [ ] Confirm production backend is ready for Google review.
  - Production API must be HTTPS and reachable from Google review devices.
  - Parent binding, QR scan, lesson import, word extraction, sync, and child practice flows must be reviewable without developer-only routing.
  - Review flow must not depend on local server, Preview URLs, or Vercel bypass secret.

- [ ] Confirm release build exposes no debug-only controls.
  - Config / Settings must not expose Developer Options or Backend environment.
  - Home version-label triple-tap must not navigate to DevMenu in release builds.
  - Bypass secret page must not be reachable through normal release UI.
  - Persisted Local/Preview route state must be coerced away on release launch.
  - Production/staging-approved routing must not attach preview bypass headers.

- [x] Confirm Android permissions from the merged release manifest.
  - Current main manifest declares only `INTERNET`.
  - Dependencies merge `CAMERA`, `ACCESS_NETWORK_STATE`, and app-local `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` into the release manifest.
  - If QR scan or camera textbook import is shipped natively, make sure Camera permission has clear in-app context and store disclosure.
  - If photo picking uses Android's system photo picker without broad storage permission, do not declare unnecessary media/storage permissions.

- [x] Confirm privacy policy and support URLs.
  - Privacy Policy URL: `https://happyword.cool/privacy`.
  - Support URL: `https://happyword.cool/support`.
  - Both URLs were entered in Play Console draft fields.
  - URLs must remain public, stable, non-geofenced for target regions, and aligned with Google Play Data safety answers.
  - Privacy policy must cover parent email OTP, family/device binding, child profile data, learning progress, uploaded lesson images, generated word packs, data retention/deletion, third-party processors, and contact method.

- [ ] Confirm account deletion and data deletion flow.
  - If Android enables parent account creation or directs users to account creation, Google Play requires both an in-app deletion path and a web deletion resource.
  - Match iOS reviewer path where possible: `孩子档案` -> `账号与数据管理` opens `/family/<family_id>/account`.
  - Web deletion resource must remain usable after the app is uninstalled.
  - Play Console App access cannot rely on reviewers creating accounts or using their own accounts; prepare a reviewer-accessible test family/account path before completing this declaration.

## P1 Build And Verification Checklist

- [ ] Check Android environment.

```sh
cd android
./gradlew -version
./gradlew :app:tasks --all
```

- [ ] Run JVM unit tests.

```sh
cd android
./gradlew testDebugUnitTest
```

- [ ] Run debug assemble.

```sh
cd android
./gradlew assembleDebug
```

- [ ] Run connected UI tests on one online emulator/device.

```sh
cd android
./gradlew connectedDebugAndroidTest
```

- [ ] Run release APK assemble as a compiler/package gate.

```sh
cd android
./gradlew assembleRelease
```

- [x] Build release AAB artifact.

```sh
cd android
./gradlew bundleRelease
```

- [x] Configure upload-key signing and rebuild the AAB before Play upload.

```sh
cd android
cp release-signing.properties.example release-signing.properties
# Fill WORDMAGIC_ANDROID_* values locally, then:
./gradlew bundleRelease
jarsigner -verify -verbose -certs app/build/outputs/bundle/release/app-release.aab
```

- [x] Inspect the generated release manifest / AAB.
  - [x] Confirm package, version, app label, permissions, cleartext policy, and exported activity.
  - [x] Confirm no `android:debuggable="true"` is present in the release merged manifest.
  - [x] Confirm no debug-only local URLs are present in the release merged manifest.
  - [x] Confirm upload-key signature after local signing properties are configured.

- [x] Upload AAB to Google Play internal testing first.
  - [x] Confirm Play App Signing is active enough for the uploaded AAB to be accepted and published to internal testing.
  - [x] Confirm bundle accepted without target API, signing, policy, or app content blockers.
  - [x] Confirm release is active and available to internal testers.
  - [ ] Upload deobfuscation mapping file and native debug symbols in a follow-up if production crash diagnostics need full symbolication.
  - [ ] Download/install from Google Play internal test or internal app sharing.

- [ ] Smoke test the Google Play-delivered build on a real Android device:
  - [ ] First launch.
  - [ ] Child home to battle to result.
  - [ ] Parent profile entry.
  - [ ] Parent binding.
  - [ ] QR scan.
  - [ ] Photo/gallery import if Android supports it for v0.7.0.
  - [ ] Camera import if Android supports it for v0.7.0.
  - [ ] Word extraction result and review.
  - [ ] Sync after app restart.
  - [ ] Settings/Config page has no developer backend entry.
  - [ ] Home version-label triple-tap does not open DevMenu in release.
  - [ ] Bypass secret route cannot be opened in release.
  - [ ] Network calls target production/staging-approved backend only.

## P1 Google Play Store Listing Metadata

- [x] App name: `魔法背单词`.
- [x] Short description: `家长导入单词，孩子闯关练习`.
- [x] Full description: learning flow, parent import, child practice, privacy posture.
- [x] Category: Education.
- [ ] Tags: choose education / language learning tags only if available and accurate.
- [x] Contact email: `support@happyword.cool`.
- [x] Privacy Policy URL: `https://happyword.cool/privacy`.
- [x] Website / support URL: `https://happyword.cool/support`.
- [x] App icon:
  - [x] Uploaded 512x512 draft asset generated from `ios/WordMagicGame/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`.
  - [ ] Confirm final production icon before review submission.
- [x] Feature graphic:
  - [x] Uploaded 1024x500 draft asset generated from `assets/screenshots/android/battle.png`.
  - [ ] Required for a polished listing and Google Play promotion surfaces.
  - [ ] Must represent actual app value, not a debug mock.
- [x] Phone screenshots:
  - [x] Uploaded five draft 16:9 screenshots generated from `assets/screenshots/android/`.
  - [ ] Replace with real Google Play/internal-test release screenshots before final review if these are not from the exact upload build.
  - [x] Uploaded set excludes DevMenu and bypass-secret debug screenshots.
- [ ] Tablet screenshots:
  - [x] 7-inch tablet slot has five draft screenshots.
  - [x] 10-inch tablet slot has three draft screenshots.
  - [ ] Replace with real tablet screenshots or explicitly confirm phone-layout screenshots are acceptable before review.
- [ ] Preview video: optional; skip unless polished.

### Google Play Draft Values

Use these values unless release owner chooses a different positioning.

| Field | Draft |
| --- | --- |
| App name | `魔法背单词` |
| Package name | `cool.happyword.wordmagic` |
| Default language | Simplified Chinese |
| App or game | App |
| Primary category | Education |
| Price | Free |
| Short description | `家长导入单词，孩子闯关练习` |
| Privacy Policy URL | `https://happyword.cool/privacy` |
| Support URL | `https://happyword.cool/support` |
| Contact email | `support@happyword.cool` |
| Ads | No |
| In-app purchases | No for v0.7.0 |
| Target audience | `6-8` and `9-12`; Designed for Families path |

### Full Description Draft

```text
魔法背单词是一款面向孩子的英语单词练习应用，也为家长提供词库导入和学习同步工具。

孩子可以在闯关式练习中认识单词、选择释义、复习错题，并通过本地学习记录逐步巩固。家长可以绑定孩子设备，从课本照片或相册图片中导入单词，审核识别结果后发布为孩子可练习的词包。

主要功能：
- 闯关式英语单词练习
- 错题复习与学习进度记录
- 家长账号绑定与孩子档案管理
- 拍照或相册导入课本单词
- 识别结果审核、编辑与发布
- 家庭词包和学习数据同步
- 账号与数据管理入口

我们重视儿童与家庭数据保护。应用不包含广告 SDK，不做跨应用追踪。家长主动上传的教材图片仅用于生成可审核的单词草稿；家长可在账号与数据管理页面导出数据或发起账号删除。
```

### Store Listing Completion Notes

- 2026-05-18: Chrome automation could open the default `zh-CN` store listing, inspect fields, upload asset files, and save listing assets as a draft.
- 2026-05-19: Chinese `Short description` and `Full description` were filled through desktop control with the macOS clipboard because the Codex Chrome extension still reports `Browser Use virtual clipboard is not installed` for Play Console text-field input.
- Current Play Console listing draft has:
  - App icon: 1/1.
  - Feature graphic: 1/1.
  - Phone screenshots: 5/8.
  - 7-inch tablet screenshots: 5/8.
  - 10-inch tablet screenshots: 3/8.
- Store listing save completed and Play Console Dashboard now goes directly to internal/closed testing and production-access tasks.
- Temporary upload assets were generated under `/private/tmp/happyword-play-assets/`; they are not committed to the repo.

## P1 Google Play Internal Testing Release

- Status: published on 2026-05-19.
- Track: Internal testing for Phones, Tablets, Chrome OS, and Android XR form factors.
- Release name/version: `1007000 (0.7.0)`.
- AAB: `android/app/build/outputs/bundle/release/app-release.aab`.
- Play Console bundle validation:
  - API levels: `26+`.
  - Target SDK: `36`.
  - Screen layouts: `4`.
  - ABIs: `4`.
  - Required features: `7`.
- Release delivery estimate shown by Play Console:
  - New install size: `21.7 MB`.
  - Download time: `12s`.
- Tester list:
  - List name: `HappyWord internal testers`.
  - Users: `1`.
  - Join link: `https://play.google.com/apps/internaltest/4700852462014477805`.
- Release notes were published in `zh-CN` using the draft below.
- Remaining Play Console warnings at publish time:
  - No deobfuscation file is associated with this App Bundle.
  - This App Bundle contains native code, but no debug symbols were uploaded.
- Play Console status after publish:
  - Track summary: `Active`.
  - Latest release: `1007000 (0.7.0)`.
  - Release status: `Available to internal testers`.
  - Review status: `Not reviewed`.
  - Temporary tester-facing app name remains `cool.happyword.wordmagic (unreviewed)` until app setup/review completes.

### Release Notes Draft

```text
v0.7.0 是 Android 原生版本的首个 Google Play 准备版本：
- 支持孩子闯关式单词练习与学习结果页
- 支持家长配置、孩子档案与家庭学习数据同步
- 支持词包管理、学习报告与本地成长激励
- Release 构建隐藏开发者路由和预览环境入口
```

## P1 Play Console App Content Forms

### Data Safety Draft

> Repo-derived draft, not a legal/privacy-policy substitute. Confirm against the shipped Android client, backend, and any third-party processors before submitting.

- Status: completed in Play Console on 2026-05-18.
- Does the app collect or share user data? **Yes**.
- Is data encrypted in transit? **Yes**.
- Can users request account deletion? **Yes**, with fixed Play URL `https://happyword.cool/support`.
- Can users request partial data deletion without deleting their account? **No** for the current submitted Data safety answer.
- Is data used for tracking? **No** based on current Android target: no ads SDK, no tracking SDK, no cross-app advertising identifier use observed.
- Is data linked to the user? **Yes** for account/family identifiers, device binding, child profile, learning progress, family packs, wishlist/redemption data, and uploaded lesson images.
- Families policy commitment is shown in Data safety.

| Google Play data category | Collected? | Shared? | Purpose | Notes |
| --- | --- | --- | --- | --- |
| Personal info - Name | Yes | No | App functionality, account management | Child nickname/profile display. Marked optional. |
| Personal info - Email address | Yes | No, except service processors | Account management, app functionality | Parent OTP login and account binding. |
| Personal info - User IDs | Yes | No | App functionality, account management, security/compliance | Family/profile/binding/account identifiers. Marked optional. |
| App activity - App interactions | Yes | No, except service processors | App functionality, personalization | Learning stats and practice progress. |
| App activity - Other user-generated content | Yes | No | App functionality, personalization | Family word packs, lesson drafts, child nickname/avatar, wishlist entries. |
| App info and performance - Diagnostics | No in submitted Play answer | No | N/A | No intentional client-side diagnostics SDK in Android target. |
| Device or other IDs | Yes | No, except service processors | Account/device binding, security | Device binding identifier; avoid advertising ID. |
| Photos and videos | Yes, when parent imports lesson images | Yes, to backend/processors | App functionality | Textbook image extraction and review. |

### Data Types To Answer No Unless Product Changes

- Location.
- Contacts.
- Health and fitness.
- Financial info.
- Purchases.
- Web browsing.
- Search history.
- Audio files.
- Calendar.
- SMS or call logs.
- Advertising ID / advertising data.
- Precise or coarse location.

### Account Deletion Draft

- In-app path: `孩子档案` -> `账号与数据管理`, once verified on Android.
- Web resource used in Google Play Data safety: `https://happyword.cool/support`.
- Bound-family account page remains `https://happyword.cool/family/<family_id>/account`.
- Follow-up: update the support page wording from iOS-specific to Android/iOS generic account/data deletion instructions before final Google review submission.
- Reviewer note should explain that parent login uses email OTP and that account deletion may include a grace period with cancel option.
- Play Console App access now has a reviewer test account entered directly in Play Console; keep credentials out of the repo.

### Target Audience And Content Draft

- Target audience: choose deliberately before submission.
  - Current Play Console state: completed and saved on 2026-05-18.
  - Recommended answer: the app is designed for family learning and child practice with parent-managed account features.
  - Primary age groups for v0.7.0: `6-8` and `9-12`.
  - Teacher Approved program: not included for v0.7.0 first release.
  - Treat adult parent controls as parent-managed support functionality in the follow-up questions rather than as the child practice target audience.
  - If any age group including children is selected, complete Families policy review carefully.
- Ads: No.
- Store listing appeal to children: Yes, because the child practice UI is child-facing.
- External links: support/privacy/account web pages are parent/account-management surfaces; ensure they are safe and relevant.
- User-generated content / social networking: No public UGC or social feed.
- App access instructions: provide reviewer flow and any seeded/demo data if production review cannot proceed from an empty account.

### Content Rating Draft

- Educational / language learning app with mild game-style practice.
- Completed 2026-05-18 with a conservative fantasy-violence interpretation for the childlike battle visuals:
  - Downloaded app has ratings-relevant content.
  - Violence against non-humans in a fantastical, childlike/pixelated style.
  - Unrealistic reactions, often from a distant perspective, with no blood/gore.
  - No fear, sexuality, gambling, profanity, drug/alcohol/tobacco, crude humor, user-to-user sharing, purchases, rewards, browser/search, location sharing, or age-restricted products.
  - App is primarily educational and has online content, but online content is not expected to contain violence, sexual material, offensive language, drugs, or age-restricted product promotion.
- Sexual content, profanity, drugs, gambling, realistic violence, user-to-user sharing, unrestricted web access: No.
- Purchases / loot boxes: No for v0.7.0.
- Resulting rating is determined by IARC / Play questionnaire and may vary by region.

## P1 Review Notes Draft

```text
Thank you for reviewing WordMagicGame Android / 魔法背单词.

Recommended review path:
1. Launch the Android app from the Google Play internal/production build.
2. Use the child learning flow from the home screen to start a word battle and complete a short practice session.
3. Open 游戏配置, then 孩子档案.
4. For parent features, use 家长账号 to bind a parent account. The parent web login uses email one-time codes. Please use your own reachable reviewer email address to receive the OTP.
5. After binding, open 家长管理后台 to test textbook import.
6. Use 拍照导入 or 从相册导入 if these entries are enabled in the Android v0.7.0 build. The server may take several seconds to extract words from the image.
7. Open the pending lesson draft, review the source image preview and extracted words, edit if needed, then publish the word pack.
8. Restart the app and confirm the synced word pack is available to the child learning flow.
9. To review account deletion, open 游戏配置 -> 孩子档案 -> 账号与数据管理. This opens the parent account page where the parent can export account data or request account deletion.

Notes:
- The app does not include ads, in-app purchases, or third-party tracking SDKs.
- Internet permission is used for account binding, word-pack sync, and lesson import.
- Camera permission is present in the merged release manifest because QR scan / barcode dependencies are included; camera hardware features are optional.
- Broad photo/media storage permission is not present in the merged release manifest.
- Release builds do not expose developer backend switching or preview routing controls.
```

## P2 Compliance And Operational Prep

- [ ] Confirm whether mainland China distribution is also planned through Google Play mirrors or only AppGallery/direct channels.
- [ ] Confirm ICP/APP filing posture for `happyword.cool` if mainland China users are targeted.
- [ ] Confirm no paid content, subscriptions, external purchase paths, or reward redemption flows that could be interpreted as commerce are enabled in Google Play release.
- [ ] Confirm production observability and support processes avoid collecting unnecessary child data.
- [ ] Confirm Play Console country/region availability and whether the app should be withheld from regions where child/family compliance is not yet reviewed.
- [ ] Prepare rollback plan:
  - [ ] Use internal testing before production.
  - [ ] Use staged rollout for production if accepted.
  - [ ] Keep server APIs backwards-compatible with v0.7.0.
  - [ ] Identify who can halt rollout, pause staged rollout, or deactivate server features.

## Android Work Queue

1. [x] Decide final Android package name before Play Console app creation.
2. [x] Decide final Android public app label and localization.
3. [x] Configure release upload-key signing pattern without committing secrets.
4. [x] Configure real upload key locally and rebuild signed `bundleRelease` AAB.
5. [x] Complete Google Play developer account verification.
6. [x] Create/verify Google Play app record.
7. [x] Enroll in Play App Signing by accepting terms during app creation.
8. [x] Upload v0.7.0 to internal testing.
9. [ ] Install the Google Play-delivered build on a real Android device.
10. [ ] Complete release smoke test.
11. [ ] Prepare screenshots, feature graphic, listing metadata, and release notes.
    - Draft icon, feature graphic, phone screenshots, and tablet screenshots are uploaded.
    - Store listing text is completed and saved.
    - Still replace temporary/draft screenshots with final release-device screenshots before review if product wants a polished public listing.
12. [x] Complete Data safety, target audience, content rating, app access, and account deletion forms.
13. [ ] Submit v0.7.0 for Google Play review.
