# V0.8.8 — Daily Check-in Rewards — Android Replication Plan

> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If the trigger is unsigned, stop.

## Pre-flight: verify the trigger is signed

- [x] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
- [x] If missing, stop and ask the human owner. Do not edit Android source.

## Scope After Signature

- [x] Translate `CheckInSnapshot`, local store, cloud sync, result-row, Home entry, and calendar UI from the signed Harmony delta letter.
- [x] Preserve all stable IDs from `00-design.md` §5 as Compose `Modifier.testTag(...)` strings.
- [x] Add JUnit counterparts for trigger §2.5.

## Verification

- [x] `env JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home GRADLE_USER_HOME=/private/tmp/happyword-gradle PATH=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:$PATH ./gradlew :app:testDebugUnitTest --tests cool.happyword.wordmagic.core.GrowthStoresTest --tests cool.happyword.wordmagic.core.CloudModelsTest`
  - Evidence: 2026-05-24 `BUILD SUCCESSFUL in 37s`.
- [x] `env JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home GRADLE_USER_HOME=/private/tmp/happyword-gradle PATH=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:$PATH ./gradlew :app:testDebugUnitTest`
  - Evidence: 2026-05-24 `BUILD SUCCESSFUL in 1s`.
