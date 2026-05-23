# V0.8.6 — 怪物等级积分金币 — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) drives build -> codelinter -> unit -> emulator -> ohosTest. Commands come from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md). Do not invent flags.

**Goal:** Replace HarmonyOS battle coin rewards with defeated-monster level score after the design doc is approved.

**Architecture:** The implementation plan is intentionally not expanded yet. Per the Superpowers brainstorming gate, implementation planning starts only after the written design is reviewed and approved by the human owner.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

### Task 1: Pending Design Approval

**Files:**
- Read: `docs/features/2026-05-23-coin-reward-by-monster-level-v0-8-6/00-design.md`

- [ ] Human owner reviews and approves the written design.
- [ ] Invoke `superpowers:writing-plans` and replace this pending section with a task-by-task TDD implementation plan.
