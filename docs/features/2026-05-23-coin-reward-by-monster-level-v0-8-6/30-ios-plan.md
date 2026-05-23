# V0.8.6 — 怪物等级积分金币 — iOS Replication Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Inputs (frozen):**
> - Design: [`00-design.md`](00-design.md)
> - Replication trigger (must carry `replication_approved: true`): [`20-replication-trigger.md`](20-replication-trigger.md)
>
> **Do not redesign.** If you find an ambiguity, file it in `20-replication-trigger.md` §3 and update `00-design.md` first. Then come back here.
>
> **Run loop:** Commands come from [`.cursor/ios-dev-commands.md`](../../../.cursor/ios-dev-commands.md). Use `xcodebuild` from `ios/` and the project's stable DerivedData path.

**Goal:** Replicate V0.8.6 monster-level coin reward semantics from HarmonyOS onto iOS native after the replication trigger is signed.

**Architecture:** SwiftUI views render state; pure Swift battle/domain code owns reward behavior. iOS consumes the frozen design plus the HarmonyOS delta letter and does not redesign the formula.

**Tech Stack:** Swift, SwiftUI, XCTest, XCUITest. Project generated from `ios/project.yml` via XcodeGen.

---

### Pre-flight: verify the trigger is signed

- [ ] Open [`20-replication-trigger.md`](20-replication-trigger.md) and confirm `replication_approved: true` with a non-empty `approved_by` and `approved_at`.
- [ ] If missing, stop and ask the human owner. Do not proceed past this point.

### Task 1: Pending Signed Trigger

- [ ] Replace this section with the iOS TDD replication plan after HarmonyOS stabilization and human approval.
