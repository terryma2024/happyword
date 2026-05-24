# V0.8.8 — Daily Check-in Rewards — Android Replication Plan

> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If the trigger is unsigned, stop.

## Pre-flight: verify the trigger is signed

- [ ] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
- [ ] If missing, stop and ask the human owner. Do not edit Android source.

## Scope After Signature

- Translate `CheckInSnapshot`, local store, cloud sync, result-row, Home entry, and calendar UI from the signed Harmony delta letter.
- Preserve all stable IDs from `00-design.md` §5 as Compose `Modifier.testTag(...)` strings.
- Add JUnit / Compose UI counterparts for trigger §2.5.
