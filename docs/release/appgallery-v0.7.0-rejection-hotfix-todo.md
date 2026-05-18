# AppGallery v0.7.0 Rejection Hotfix Todo

Date: 2026-05-18

## Blocking Review Items

- [ ] APP备案: externally pending. After approval, fill the APP备案 / 核准信息 in AppGallery Connect and do not select "服务器不在中国大陆" unless the legal/server reality changes.
- [x] HarmonyOS first-launch privacy disclosure: show Privacy Policy and User Agreement before normal use.
- [x] HarmonyOS registration/login privacy disclosure: make the same Privacy Policy / User Agreement links visible in the app entry flow where account binding/login begins.
- [x] Minor-protection report channel: add an in-app `投诉与举报` entry that opens the support/report channel.
- [ ] Store screenshots: upload at least three same-size, clear, complete, landscape screenshots showing different scenes.

## Same-Issue Platform Parity

- [x] iOS: add first-launch privacy disclosure and `投诉与举报` row if missing.
- [x] Android: add first-launch privacy disclosure and `投诉与举报` row if missing.
- [x] Confirm iOS / Android config steppers refresh immediately; both are binding/state-copy driven and did not need the HarmonyOS stale-state fix.

## Non-Blocking Improvement Items

- [x] Improve low-contrast text detected by AppGallery store checks.
- [x] Fix HarmonyOS ConfigPage HP / monster count stepper refresh so values update immediately without re-entering the page.

## Resubmission Checklist

- [ ] Build a new signed HarmonyOS release package after fixes.
- [ ] Run release smoke on real device: first launch privacy dialog, settings privacy/report links, config stepper realtime updates, battle readability.
- [ ] Prepare at least three same-size screenshots: Home, Settings/Config, Battle, and optionally Parent import/review.
- [ ] In AppGallery review notes, mention: privacy prompt added, report channel added, screenshots replaced, and config realtime update fixed.
