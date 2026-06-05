# Monster Codex Progress v1.0.2 Design

> Date: 2026-06-05
> Owner: matianyi
> Status: Approved UX, ready for implementation planning
> Feature folder: [`docs/features/2026-06-05-monster-codex-progress-v1-0-2/`](../../features/2026-06-05-monster-codex-progress-v1-0-2/)

## Summary

Monster Codex entries are no longer fully visible by default. Each monster has local progress keyed by catalog index. Before the player encounters a monster, the codex hides its image, name, kind label, and description. After encounter, the entry reveals normally, shows defeat count, and shows two milestone reward buttons for 50 and 100 defeats.

This feature also renames the first three display names to match the existing Chinese fairy-tale tone:

| Old display | New display |
| --- | --- |
| `Slime` | `软泥小灵` |
| `Zombie` | `书页僵僵` |
| `Dragon` | `云眠巨龙` |

Internal keys, asset paths, catalog order, and battle semantics remain unchanged.

## UX Rules

Unencountered state:

- Image shows a mysterious generated question-mark SVG on a transparent background.
- Name, kind label, and description show `?` characters with the same character count as the original visible text.
- The position indicator still shows `N / 100`.
- Defeat count is hidden.
- Coin reward buttons are hidden.

Encountered state:

- Image, display name, kind label, and description show normally.
- Defeat count appears below the position indicator.
- Two reward buttons always appear below defeat count:
  - `50 金币 X/50` disabled until defeat count reaches 50.
  - `100 金币 X/100` disabled until defeat count reaches 100.
  - `领 50 金币` / `领 100 金币` enabled once the milestone is reached and unclaimed.
  - `已领 50 金币` / `已领 100 金币` disabled once claimed.

Reward rules:

- 50 defeats can claim 50 coins once.
- 100 defeats can claim 100 coins once.
- If the player reaches 100 defeats without claiming the 50-defeat reward, both rewards can be claimed, totaling 150 coins.
- Claiming rewards does not consume defeat count.
- Claims do not count against the existing daily 20-coin cap.
- After the 100 reward is claimed, no further rewards exist for that monster.

## Data Model

Create a local `MonsterProgressStore` with snapshot version 1:

```text
MonsterProgressSnapshot {
  version: 1
  records: MonsterProgressRecord[]
}

MonsterProgressRecord {
  catalogIndex: number
  encountered: boolean
  defeatCount: number
  claimedMilestones: number[] // allowed values: 50, 100
}
```

Records are keyed by one-based `catalogIndex`. Invalid indexes are ignored by parser helpers. Missing records default to not encountered, zero defeats, and no claimed milestones.

## Battle Integration

Battle state already resolves the current monster through the catalog index provider. The new progress store records:

- Encounter: when a monster is spawned, including the first monster at battle start and each later replacement.
- Defeat: when the current monster HP reaches 0, before the engine advances to the next monster.

This keeps "seen but not defeated" distinct from "defeated once or more."

## Coin Integration

CoinAccount gets an explicit cap-free credit path for codex milestone rewards. This path updates total coins and transaction history, but does not update `todayCoinsEarned` and therefore bypasses the daily 20-coin battle reward cap. Reward transaction reasons should be stable:

- `monster-codex:50:<catalogIndex>`
- `monster-codex:100:<catalogIndex>`

The progress store must mark the milestone claimed only when the cap-free coin credit succeeds.

## Visual Asset

Generate one editable vector asset with `recraft-v4-vector`:

```text
original mysterious magical question mark silhouette for a children's monster codex, transparent background, clean SVG vector game asset, soft blue grey glow, whimsical, no text
```

Runtime asset target:

- `harmonyos/entry/src/main/resources/rawfile/character/monster-mystery-question.svg`

Design-source retention target:

- `assets/icons/monster-mystery-question.svg`
- Add a one-line entry to `assets/icons/README.md`.

## Testing

Use TDD for implementation.

Pure unit tests should cover:

- Snapshot parse defaults and invalid record filtering.
- Encounter marks a monster visible without incrementing defeat count.
- Defeat increments only the defeated catalog index.
- 50/100 milestones become claimable at the right thresholds.
- 100 defeats can still claim the 50 milestone if it was skipped.
- Claimed milestones cannot be claimed twice.
- Codex display masking preserves original string lengths for hidden entries.
- First three display names are `软泥小灵`, `书页僵僵`, and `云眠巨龙`.

UI tests should cover:

- A locked codex entry hides defeat count and reward buttons.
- An encountered but under-threshold entry shows disabled 50/100 buttons with progress.
- A 100-defeat entry can claim both rewards and updates the coin balance.

## Versioning

HarmonyOS version bump:

- `versionName`: `1.0.1` -> `1.0.2`
- `versionCode`: `1010001` -> `1020001`

iOS and Android replication use the same visible version when Stage 4 is approved.

## Open Questions

None.
