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
| `2026-06-01-pcm-audio-v0-10` | pcm-audio-v0-10 | matianyi | Stage 4 replication | yes | [`2026-06-01-pcm-audio-v0-10/`](2026-06-01-pcm-audio-v0-10/) |
| `2026-05-29-spellbook-v0-9-5` | spellbook-v0-9-5 | (V0.9.5 — 魔法书图鉴) | Done | yes | [`2026-05-29-spellbook-v0-9-5/`](2026-05-29-spellbook-v0-9-5/) |
| `2026-05-26-learning-plan-review-v0-9-3` | learning-plan-review-v0-9-3 | (V0.9.3 — 学习计划与复习逻辑重构) | Done | yes | [`2026-05-26-learning-plan-review-v0-9-3/`](2026-05-26-learning-plan-review-v0-9-3/) |
| `2026-05-25-boss-dialogue-v0-9-2` | boss-dialogue-v0-9-2 | (V0.9.2 — Boss 个性与登场对话) | Done | yes | [`2026-05-25-boss-dialogue-v0-9-2/`](2026-05-25-boss-dialogue-v0-9-2/) |
| `2026-05-24-sentence-cloze-v0-9-1` | sentence-cloze-v0-9-1 | (V0.9.1 — 句子填词题型) | Done | yes | [`2026-05-24-sentence-cloze-v0-9-1/`](2026-05-24-sentence-cloze-v0-9-1/) |
| `2026-05-23-daily-checkin-v0-8-8` | daily-checkin-v0-8-8 | (V0.8.8 — 每日打卡与连续奖励) | Done | yes | [`2026-05-23-daily-checkin-v0-8-8/`](2026-05-23-daily-checkin-v0-8-8/) |
| `2026-05-23-coin-reward-by-monster-level-v0-8-6` | coin-reward-by-monster-level-v0-8-6 | (V0.8.6 — 怪物等级积分金币) | Done | yes | [`2026-05-23-coin-reward-by-monster-level-v0-8-6/`](2026-05-23-coin-reward-by-monster-level-v0-8-6/) |
| `2026-05-18-battle-balance-v0-8-4` | battle-balance-v0-8-4 | (V0.8.4 — 战斗平衡与题型节奏) | Stage 5 cleanup | yes | [`2026-05-18-battle-balance-v0-8-4/`](2026-05-18-battle-balance-v0-8-4/) |
| `2026-05-18-battle-polish-v0-8-3` | battle-polish-v0-8-3 | (V0.8.3 — 战斗与词包体验小优化) | Done | yes | [`2026-05-18-battle-polish-v0-8-3/`](2026-05-18-battle-polish-v0-8-3/) |
| `_example` | example-stable-id-toggle | (worked-through reference) | Done | yes | [`_example/`](_example/) |
<!-- Append new rows above this line, newest at the top. -->

## How to add a new feature

1. Pick a slug (kebab-case, short).
2. Allocate `<feature-id>` = `YYYY-MM-DD-<slug>`.
3. `cp -r docs/sop/templates/* docs/features/<feature-id>/` and rename each file to drop the `.template` segment.
4. Add a row to the table above with status `Stage 1`.
5. Start filling in `00-design.md`. Continue stage by stage per the SOP.
