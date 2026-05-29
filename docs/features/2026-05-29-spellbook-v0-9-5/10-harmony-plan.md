# V0.9.5 Spellbook Codex — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)

This plan is intentionally not expanded yet. Create the task-by-task HarmonyOS implementation plan only after the owner reviews and approves [`00-design.md`](00-design.md).

## Draft Scope

- Add spellbook domain helpers for card state, pack completion, cover resolution, and reward claim eligibility.
- Add local `SpellbookRewardStore`.
- Add `SpellbookPage` with stable IDs from the design.
- Wire `HomeSpellbookButton` and `HomePackSpellbookCover`.
- Parse `scene.spellbookCoverUrl` through pack models and cover caching.
- Add focused local and ohosTest coverage.
- Bump HarmonyOS metadata to `0.9.5 / 1009005` during implementation.
