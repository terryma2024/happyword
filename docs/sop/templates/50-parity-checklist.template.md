# <Feature Name> — Parity Checklist

> Inputs (frozen): [`00-design.md`](00-design.md), [`20-replication-trigger.md`](20-replication-trigger.md)
>
> The feature is **Done** only when every row below is `[x]` in all three platform columns. A row that goes red after Done reopens the feature via [`60-followups.md`](60-followups.md); do not silently fix-and-close.

## 1. User flows

> One row per flow listed in `00-design.md` §4.

| Flow | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| <Flow A: from screen X to screen Y> | [ ] | [ ] | [ ] | |
| <Flow B> | [ ] | [ ] | [ ] | |

## 2. Stable IDs

> One row per ID in `00-design.md` §5. Tick each platform when the ID is implemented verbatim and used by at least one UI test.

| ID | Harmony | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| `<ExampleId>` | [ ] | [ ] | [ ] | |

## 3. Pure-rule tests

> One row per HarmonyOS unit test in trigger §2.5. Tick each platform when the equivalent test exists and is green on that platform.

| HarmonyOS test | iOS counterpart | Android counterpart |
| --- | --- | --- |
| `<harmonyos/entry/src/test/...>` | [ ] | [ ] |

## 4. Contract usage

If the feature touches `shared/contracts/` or `shared/fixtures/`, list each consumer per platform and tick it once the platform reads the regenerated contract.

| Contract / fixture | Harmony | iOS | Android |
| --- | --- | --- | --- |
| `<shared/contracts/openapi/...>` | [ ] | [ ] | [ ] |

## 5. Screenshots

> One row per visibly-changed screen. The SOP requires presence in all three folders, not pixel-perfect diff.

| Screen | `assets/screenshots/harmonyos/...` | `assets/screenshots/ios/...` | `assets/screenshots/android/...` |
| --- | --- | --- | --- |
| <Home> | [ ] | [ ] | [ ] |

## 6. Versions

| Platform | Field | Value |
| --- | --- | --- |
| HarmonyOS | `harmonyos/AppScope/app.json5` `versionName` / `versionCode` | <value> |
| iOS | `CFBundleShortVersionString` / `CFBundleVersion` | <value> |
| Android | `android/app/build.gradle.kts` `versionName` / `versionCode` | <value> |

## 7. Sign-off

- [ ] Owner verified all rows above are green.
- [ ] Owner ran a smoke pass on at least one device per platform.
- [ ] Feature linked from [`docs/features/README.md`](../../features/README.md) is marked `Done`.

```yaml
done_by:
done_at:
notes:
```
