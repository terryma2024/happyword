# Feature Index

This is the canonical index of every cross-platform feature shipped *after* the initial HarmonyOS / iOS / Android baselines. The lifecycle is documented in [`docs/sop/00-three-platform-feature-sop.md`](../sop/00-three-platform-feature-sop.md).

For every feature, agents work inside `docs/features/<feature-id>/`, where `<feature-id> = YYYY-MM-DD-<kebab-slug>`.

## Stages

| Stage | File | Meaning |
| --- | --- | --- |
| 1 | `00-design.md` | Cross-platform design, single source of truth |
| 2 | `10-harmony-plan.md` | HarmonyOS implementation plan, task-by-task |
| 3 | `20-replication-trigger.md` | Stabilization gate + signed delta letter |
| 4a | `30-ios-plan.md` | iOS replication plan |
| 4b | `40-android-plan.md` | Android replication plan |
| 5 | `50-parity-checklist.md` | Three-platform parity matrix |
| Post | `60-followups.md` | Optional: post-replication parity fixes |

`Replication approved` means the human owner has signed the bottom of `20-replication-trigger.md`. Until that is true, iOS / Android agents must refuse to start Stage 4.

`Status` is the lowest-numbered stage that still has unchecked `- [ ]` items, or `Done` once Stage 5 is fully green.

## Features

| Feature ID | Slug | Owner | Status | Replication approved | Folder |
| --- | --- | --- | --- | --- | --- |
| `_example` | example-stable-id-toggle | (worked-through reference) | Done | yes | [`_example/`](_example/) |
<!-- Append new rows above this line, newest at the top. -->

## How to add a new feature

1. Pick a slug (kebab-case, short).
2. Allocate `<feature-id>` = `YYYY-MM-DD-<slug>`.
3. `cp -r docs/sop/templates/* docs/features/<feature-id>/` and rename each file to drop the `.template` segment.
4. Add a row to the table above with status `Stage 1`.
5. Start filling in `00-design.md`. Continue stage by stage per the SOP.
