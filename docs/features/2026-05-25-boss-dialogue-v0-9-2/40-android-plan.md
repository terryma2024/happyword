# <Feature Name> — Android Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/android-dev-commands.md`](../../../.cursor/android-dev-commands.md). Use `./gradlew` from `android/`.

**Goal:** Replicate `<Feature Name>` semantics from HarmonyOS onto Android native (Kotlin / Jetpack Compose) preserving stable IDs, persistence keys, and behavior listed in the design + delta letter.

**Architecture:** Compose screens render state; pure Kotlin services own behavior. New / changed types match the boundaries listed in [`docs/android-replica/03-domain-logic.md`](../../android-replica/03-domain-logic.md). `shared/` stays contracts/fixtures only.

**Tech Stack:** Kotlin, Jetpack Compose, JUnit (JVM unit tests), Compose UI tests, UI Automator + adb scripting where Compose tests cannot reach.

---

### Pre-flight: verify the trigger is signed

- [ ] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
- [ ] If missing, stop and ask the human owner. Do not proceed past this point.

### Task 1: Domain types and pure logic

**Files:**
- Create / modify: `android/app/src/main/java/cool/happyword/wordmagic/core/...`
- Create / modify: `android/app/src/main/java/cool/happyword/wordmagic/data/...`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/...`

- [ ] Translate the design's domain rules (§6) into pure Kotlin types and services.
- [ ] Mirror persistence keys exactly per `00-design.md` §7 and trigger §2.2.
- [ ] Write JUnit cases that mirror the HarmonyOS unit tests listed in trigger §2.5.
- [ ] Run: `cd android && ./gradlew testDebugUnitTest` (see [`.cursor/android-dev-commands.md`](../../../.cursor/android-dev-commands.md) §3).

### Task 2: Compose screens with stable test tags

**Files:**
- Create / modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/...`

- [ ] Implement Compose screens; every UI element listed in `00-design.md` §5 carries `Modifier.testTag("<ID>")` verbatim.
- [ ] Use `contentDescription` only when the same string also doubles as accessibility text.
- [ ] Match orientation rules from HarmonyOS: child-flow landscape, parent-flow portrait.

### Task 3: Compose UI tests + UI Automator parity

**Files:**
- Create / modify: `android/app/src/androidTest/java/cool/happyword/wordmagic/...`

- [ ] For each row in trigger §2.5 with an Android counterpart, write the matching Compose UI test (preferred) or UI Automator case (when crossing process boundaries, e.g. permission dialogs).
- [ ] Run on a connected emulator listed by `adb devices`.

### Task 4: Versioning and screenshots

**Files:**
- Modify: `android/app/build.gradle.kts` (`versionName`, `versionCode`).

- [ ] Set `versionName` to the HarmonyOS `versionName` recorded in trigger §1.
- [ ] Pick a `versionCode` that monotonically increases. Document the chosen mapping rule the first time you do this; reuse it afterwards.
- [ ] Capture device / emulator screenshots for every screen this feature changed and place them under `assets/screenshots/android/`.

### Task 5: Verification

- [ ] All `testDebugUnitTest` JVM tests green.
- [ ] All affected Compose UI / UI Automator tests green.
- [ ] `cd android && ./gradlew assembleDebug` succeeds with no new warnings in files you changed.
- [ ] Update [`50-parity-checklist.md`](50-parity-checklist.md) Android columns; commit when each row is true.
