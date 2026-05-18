# HarmonyOS v0.7.0 Release Preparation

> Scope: Huawei AppGallery / HarmonyOS release only. Android release work is intentionally excluded.
> App: `魔法背单词`
> Bundle name: `com.terryma.wordmagicgame`
> Version name: `0.7.0`
> Version code: `1007001`
> Last updated: 2026-05-18

## Source Of Truth

- Huawei AppGallery app distribution: https://developer.huawei.com/consumer/cn/appgallery/
- Huawei AppGallery Connect release services: https://developer.huawei.com/consumer/cn/solution/agconnect/release/
- Huawei developer policy center: https://developer.huawei.com/consumer/en/policy-center/
- HarmonyOS app config: `harmonyos/AppScope/app.json5`
- HarmonyOS signing/build config: `harmonyos/build-profile.json5`
- HarmonyOS module permissions: `harmonyos/entry/src/main/module.json5`
- HarmonyOS dev commands: `.cursor/ohos-dev-commands.md`

## Current Repo State

- [x] `versionName` is `0.7.0` in `harmonyos/AppScope/app.json5`.
- [x] `versionCode` is `1007001` in `harmonyos/AppScope/app.json5`.
- [x] Bundle name is `com.terryma.wordmagicgame`.
- [x] Debug-only battle finish button is gated by `BuildProfile.BUILD_MODE_NAME`.
- [x] Home version-label triple-tap is gated to debug builds.
- [x] Backend environment override falls back to production/staging behavior outside debug builds.
- [x] Debug HAP build passed locally with no observed `ArkTS:WARN` lines.
- [x] CodeLinter passed locally with no defects after the successful HAP build.
- [ ] No-device unit tests need a clean rerun: the latest local run completed `UnitTestArkTS`, printed `Darwin`, then the runner hung before reporting pass/fail.
- [x] Release-mode APP build passed locally with official AppGallery release certificate / profile and no observed `ArkTS:WARN` lines.
- [x] Official signing material was generated locally under `~/.ohos/config`; the local `build-profile.json5` credential-path/password change is intentionally not safe to commit.
- [ ] Real-device Release smoke test is not yet done.
- [x] AppGallery Connect app record was created and verified for `com.terryma.wordmagicgame`.
- [x] Huawei release metadata was filled in AppGallery Connect; final submission confirmation is still manual.
- [ ] AppGallery rejection hotfix is in progress; see `docs/release/appgallery-v0.7.0-rejection-hotfix-todo.md`.

## P0 Blockers To Clear Before Upload

- [ ] Wait for APP备案 approval and fill the approved APP备案 / 核准信息 in AppGallery Connect.
  - The current legal/server reality must not be represented as "服务器不在中国大陆" unless the approved备案 and deployment facts support that selection.
  - Do not resubmit until the filing information can be filled correctly.

- [x] Add in-app privacy-policy disclosure surfaces for AppGallery review.
  - First launch now blocks normal use behind a Privacy Policy / User Agreement consent dialog.
  - The parent binding/login entry also shows Privacy Policy / User Agreement links.

- [x] Add an in-app minor-protection complaint/report channel.
  - Settings now exposes `投诉与举报`, opening `https://happyword.cool/support`.
  - Support email for fallback review notes: `zjumty@gmail.com`.

- [ ] Replace AppGallery screenshots after rebuilding.
  - Upload at least three same-size, clear, complete, landscape screenshots.
  - Recommended set: Home, Settings/Config with report channel, Battle, plus optional parent binding/import scene.

- [ ] Replace local debug signing with official release signing.
  - Current `harmonyos/build-profile.json5` points to local `.ohos/config/...` files and `keyAlias: "debugKey"`.
  - Create or import AppGallery/HarmonyOS release certificate, profile, and keystore.
  - Update signing configuration carefully, because this is a DevEco/Hvigor project-file change.
  - Do not commit private passwords or local absolute credential paths unless the team explicitly decides this repository will carry local signing references.

- [ ] Confirm AppGallery Connect app record.
  - Bundle name: `com.terryma.wordmagicgame`.
  - App name: `魔法背单词`.
  - Vendor string: `马天一`.
  - Category: education or game, decided intentionally.
  - Distribution country/region: confirm initial market.
  - Paid/free status: confirm free unless monetization is implemented.

- [ ] Confirm production backend is ready for Huawei review.
  - Production API must be HTTPS and reachable from Huawei review devices.
  - Review account and sample flow must not depend on DevMenu, preview routing, local server, or Vercel bypass secret.
  - Parent binding, QR scan, photo import, word extraction, sync, and child practice flows must be reviewable.

- [ ] Confirm release build exposes no debug-only controls.
  - Settings must not expose Developer / Backend environment.
  - Home version-label triple-tap must not navigate to DevMenu.
  - Bypass secret page must not be reachable through normal Release UI.
  - Battle page must not show `[debug] end battle`.

- [ ] Confirm privacy policy URL.
  - Public URL must be accessible without login.
  - It must describe collected data, purpose, retention, deletion, third-party services, child/minor handling, and contact method.
  - It must match AppGallery Connect privacy/permission declarations.

- [ ] Confirm account deletion and data deletion flow.
  - Parent account or device binding deletion must be discoverable.
  - Server data deletion behavior must be documented for review notes and privacy policy.

- [ ] Confirm mainland China compliance prerequisites.
  - ICP/APP filing status for the app and backend domain.
  - Personal information protection disclosures.
  - Minor/child data handling.
  - If positioned as a game, confirm whether game-specific approval or ISBN review is needed before publication.

## P1 Build And Verification Checklist

- [x] Install HarmonyOS dependencies.

```sh
cd harmonyos
ohpm install
```

- [x] Run debug HAP build as a local compiler gate.

```sh
cd harmonyos
hvigorw assembleHap -p buildMode=debug --no-daemon
```

- [x] Confirm build log has no `ArkTS:WARN` lines.
- [x] Run CodeLinter after successful HAP build.

```sh
cd harmonyos
codelinter -c ./code-linter.json5 . --fix
```

- [ ] Run HarmonyOS unit tests to completion.

```sh
cd harmonyos
hvigorw -p module=entry@default test --no-daemon
```

- [x] Build Release package in release mode with official AppGallery signing material.

```sh
cd harmonyos
hvigorw assembleApp -p buildMode=release --no-daemon
```

- [x] Rebuild Release package with official AppGallery / production signing after signing material is ready.
- [ ] Install release package on a real HarmonyOS device.
- [ ] Smoke test Release build:
  - [ ] First launch privacy dialog: user agreement link, privacy policy link, agree flow.
  - [ ] Child home to battle to result.
  - [ ] Parent profile entry.
  - [ ] Parent binding.
  - [ ] QR scan.
  - [ ] Photo gallery import.
  - [ ] Camera import.
  - [ ] Word extraction result and review.
  - [ ] Sync after app restart.
  - [ ] Settings page has no developer backend entry.
  - [ ] Settings page has `投诉与举报` and HP / monster count values update immediately.
  - [ ] Home version-label triple-tap does not open DevMenu in Release.
  - [ ] Battle page has no `[debug] end battle`.
  - [ ] Network calls target production/staging-approved backend only.

## P1 Huawei Metadata

- [ ] App name: `魔法背单词`.
- [ ] Short description: Chinese, focused on parent-assisted vocabulary learning.
- [ ] Full description: learning flow, parent import, child practice, privacy posture.
- [ ] App icon and screenshots:
  - [ ] Use real app screenshots.
  - [ ] Do not show debug/dev screens.
  - [ ] Use at least three same-size landscape screenshots with different content.
  - [ ] Include home, settings/report, battle, and optionally parent import / binding flows.
- [ ] Privacy statement URL.
- [ ] Permission declarations:
  - [ ] `ohos.permission.INTERNET`: sync latest word packs and cloud binding data.
  - [ ] `ohos.permission.CAMERA`: parent textbook photo import and QR binding scan.
  - [ ] `ohos.permission.STORE_PERSISTENT_DATA`: stable device id for binding persistence.
- [ ] Review notes:
  - [ ] Demo parent account.
  - [ ] Demo child profile.
  - [ ] QR binding steps or alternative review path.
  - [ ] Sample textbook photo flow.
  - [ ] Account/data deletion path.
  - [ ] AppGallery rejection hotfix notes: privacy prompt added, registration/login policy links added, complaint/report channel added, screenshots replaced, config realtime update fixed.
  - [ ] Any server-side processing delay reviewers should expect.

## P2 Repo Follow-Ups

- [x] Add missing Chinese localized string for `permission_persistent_id_reason` in `harmonyos/entry/src/main/resources/zh_CN/element/string.json`.
- [x] Localize the `zh_CN` Internet / Camera permission reason strings to Chinese while leaving base resources as fallback English.
- [ ] Create a safe release-signing config pattern that avoids committing private secrets.
- [ ] Resolve no-device unit-test runner hang; latest scoped Hvigor test run did not report final pass/fail.
- [x] Add a repeatable release smoke-test note under `.cursor/ohos-dev-commands.md`.

## HarmonyOS Work Queue

1. [x] Obtain official release signing material from AppGallery Connect / DevEco workflow.
2. [x] Update local signing configuration without committing private credentials.
3. [x] Fix `permission_persistent_id_reason` Chinese localization.
4. [ ] Resolve no-device unit-test runner hang; latest scoped Hvigor test run did not report final pass/fail.
5. [x] Build release-mode APP with current local signing config.
6. [x] Build officially signed Release package.
7. [ ] Install signed Release package on a real HarmonyOS device.
8. [ ] Complete Release smoke test.
9. [x] Prepare Huawei privacy/permission declarations.
10. [ ] Replace screenshots and AppGallery metadata after rejection hotfix rebuild.
11. [ ] Submit v0.7.0 for Huawei review.
