# V0.9.1 — Sentence Cloze — HarmonyOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
>
> **Run loop:** [`.cursor/skills/harmony-autofix-orchestrator/SKILL.md`](../../../.cursor/skills/harmony-autofix-orchestrator/SKILL.md) drives build -> codelinter -> unit -> emulator -> ohosTest. Commands come from [`.cursor/ohos-dev-commands.md`](../../../.cursor/ohos-dev-commands.md). Do not invent flags.

**Status:** Not started. This file will be written after the Stage 1 design review is approved.

**Goal:** Implement V0.9.1 sentence cloze on HarmonyOS first, using [`00-design.md`](00-design.md) as the frozen cross-platform contract.

**Architecture:** The implementation will add a sentence cloze generator, extend the question model/type policy/scheduler, wire the battle and settings UI, backfill built-in pack examples, and add unit + ohosTest coverage.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI, Hypium local tests, ohosTest UI automation.

---

## Stage 1 Review Gate

- [ ] Human owner has reviewed and approved [`00-design.md`](00-design.md).
- [ ] This plan has been rewritten with task-by-task TDD steps before implementation begins.
