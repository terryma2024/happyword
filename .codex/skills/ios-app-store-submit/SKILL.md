---
name: ios-app-store-submit
description: Use this skill when the user asks to release the iOS app, upload a build, submit to App Store Connect review, or "在 App Store 上架/提交审核" for WordMagicGame.
---

# iOS App Store Submit

## Overview

Fast path for archiving WordMagicGame iOS, uploading the App Store build, selecting it in App Store Connect, and submitting it for review.

Use Chrome/App Store Connect browser automation only when the user is already logged in. If Apple asks for OTP, CAPTCHA, password, or account recovery, stop and ask the user.

## Project Constants

- App: WordMagicGame / 魔法背单词
- iOS root: `ios/`
- Bundle ID: `com.terryma.wordmagicgame`
- App Store Connect app ID: `<asc-app-id>`; read it from the existing App Store Connect URL or local release notes.
- Team ID: `<team-id>`; read it from signing settings, export options, or Xcode distribution logs.
- Export options: `ios/ExportOptions.AppStore.plist`
- Release ledger: `ios/release-pre.md`
- Scheme: `WordMagicGame`

Run iOS build/archive/upload commands with sandbox escalation by default so Xcode, signing certificates, keychain credentials, and network upload can use the developer machine's real state.

## Preflight

Read these before touching App Store Connect:

- `ios/project.yml`
- `ios/WordMagicGame.xcodeproj/project.pbxproj`
- `ios/WordMagicGame/Resources/Info.plist`
- `ios/ExportOptions.AppStore.plist`
- `ios/release-pre.md`
- `git status --short`

Confirm:

- `MARKETING_VERSION` equals the requested version.
- `CURRENT_PROJECT_VERSION` is the intended monotonically increasing build number.
- `project.yml` and `project.pbxproj` agree on version/build.
- `ExportOptions.AppStore.plist` uses app-store distribution for the expected signing team.
- Any release notes or screenshots required by the release ledger are known.

Do not claim "上架成功" after upload only. Distinguish: archived, uploaded, processed, selected for version, submitted for review, approved, live.

## Xcode Build And Upload

From the repository root, use unique paths under `/private/tmp`:

```sh
cd ios
xcodebuild build \
  -scheme WordMagicGame \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/wordmagic-ios-release-device-v<version>-b<build>
```

Archive:

```sh
xcodebuild archive \
  -scheme WordMagicGame \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/WordMagicGame-v<version>-b<build>.xcarchive
```

Verify the archived app metadata:

```sh
plutil -p /private/tmp/WordMagicGame-v<version>-b<build>.xcarchive/Products/Applications/WordMagicGame.app/Info.plist
```

Check `CFBundleShortVersionString`, `CFBundleVersion`, and `CFBundleIdentifier`.

Upload to App Store Connect:

```sh
xcodebuild -exportArchive \
  -archivePath /private/tmp/WordMagicGame-v<version>-b<build>.xcarchive \
  -exportOptionsPlist ExportOptions.AppStore.plist \
  -exportPath /private/tmp/WordMagicGame-v<version>-b<build>-export
```

For this project the export options upload directly to Apple, so the export directory may stay empty. Treat `Upload succeeded` as the upload proof.

Capture the `.xcdistributionlogs` directory printed by Xcode. If needed, find the upload ID:

```sh
rg -n "buildUploads|cfBundleShortVersionString|cfBundleVersion|Upload succeeded" <xcdistributionlogs-dir>
```

When Apple processing is slow, check the build upload JSON in the existing App Store Connect session:

```text
https://appstoreconnect.apple.com/iris/provider/<provider-id>/v1/buildUploads/<buildUpload-id>
```

Prefer reading `<provider-id>` and `<buildUpload-id>` from the Xcode distribution logs instead of hardcoding account-specific values.

## App Store Connect Fast Path

Use Chrome when possible because App Store Connect depends on the user's logged-in Apple session.

Open:

```text
https://appstoreconnect.apple.com/apps/<asc-app-id>/distribution
```

Then:

1. If the target version does not exist and only the current deliverable is shown, click `添加 iOS App`, enter the version, and create it.
2. Fill `此版本的新增内容` from `ios/release-pre.md` or the signed feature notes, then save.
3. Wait until the uploaded build's `buildUploads/<id>` state is `COMPLETE` with no errors/warnings.
4. Refresh the version page, click `添加构建版本`, choose the target build, and confirm.
5. If App Store Connect says `缺少出口合规证明`, click `管理`, choose `不属于上述的任意一种算法`, and save.
6. Save the version page.
7. Click `添加以供审核`.
8. Open `草稿提交 (1)` and click `提交以供审核`.
9. Verify the app/version status is `正在等待审核` or record the exact current status.

For v1.0.2, the submitted release note was:

```text
V1.0.2 新增怪物图鉴进度：未遇到的怪物保持神秘状态，遇到和击败后逐步解锁图鉴信息；加入击败进度与金币里程碑奖励，并优化图鉴浏览和若干稳定性细节。
```

## Ledger Update

Update `ios/release-pre.md` after submission with:

- Last updated date/time.
- Final version/build.
- Archive path.
- Upload proof and `buildUpload` ID.
- Whether build processing completed.
- Whether the build was selected for the version.
- Export compliance choice.
- Review submission ID, if visible.
- Final App Store Connect status, such as `正在等待审核`.

Keep existing historical notes; add concise new evidence instead of rewriting the whole ledger.

## Final Verification

Before telling the user the process is complete, collect fresh evidence:

- Release device build exited 0.
- Archive exited 0.
- Archive Info.plist has the expected version/build/bundle ID.
- Upload output says `Upload succeeded`.
- App Store Connect shows the expected status, usually `正在等待审核`.
- `git diff -- ios/release-pre.md` reflects the release ledger update.
- `git status --short` shows only expected local changes.

If full tests were not rerun during release submission, say that explicitly.
