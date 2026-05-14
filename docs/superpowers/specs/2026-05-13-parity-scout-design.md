# Parity Scout — Three-Platform UI / Behavior Gap Finder — Design

Date: 2026-05-13
Status: Draft (pending user review)
Scope: New tool `tools/parity_scout/` plus accompanying skill `.cursor/skills/parity-scout/SKILL.md`. No client-source changes.
Related: [`docs/sop/00-three-platform-feature-sop.md`](../../sop/00-three-platform-feature-sop.md), [`.cursor/skills/three-platform-feature-orchestrator/SKILL.md`](../../../.cursor/skills/three-platform-feature-orchestrator/SKILL.md), [`scripts/capture_harmony_screenshots.py`](../../../scripts/capture_harmony_screenshots.py).

## 1. Motivation

HarmonyOS is the source of truth in this repo (SOP §0). iOS and Android replicate from a frozen design + signed delta letter, but parity drift still slips through: a button label changes on Harmony, a margin shifts on Android, an iOS flow keeps an older copy of a removed step. Today the only detector is the human eye scanning `assets/screenshots/{harmonyos,ios,android}/` after the fact.

We want a tool that **proactively probes** for those gaps against the latest HarmonyOS `main` baseline, on simulators / devices, and surfaces findings narrow enough to be actionable. The tool is not a report generator; it is a gap finder. Its outputs feed the existing parity workflow (`docs/features/<id>/60-followups.md`).

## 2. Non-goals

- No new behavior / API contracts on the clients. We reuse the existing per-platform screenshot routes.
- No pixel-diff / SSIM / perceptual-hash engine. Analysis is done by the Cursor agent's vision over staged PNGs + spec excerpts.
- No automatic fix. Findings ride the existing `harmony-autofix-orchestrator` / per-platform manifests for repair.
- No external service / network calls. Everything is local file IO + local devices.
- No new UI test suites. We reuse what is already in `entry/src/ohosTest/**`, `WordMagicGameUITests`, `androidTest/`.
- No coverage of timing-dependent behavior (animation cadence, audio timing). Out of scope unless a future per-page checkpoint list is added.

## 3. Design decisions (resolved during brainstorming)

| Topic | Decision |
|---|---|
| Leaf of the search plan | **Page-entry**: one screen + the 3 platform routes that enter it. |
| Alignment source of truth | **Central registry**: `tools/parity_scout/page_suite_map.yml`. |
| Scope inputs | `--scope overall`, `--spec <path>`, `--feature <id>`, `--pages a,b`, `--suite Foo,Bar`, `--describe '<prose>'`. **`--plan` deliberately excluded** (plans duplicate spec signal). |
| Analysis engine | **Agent-vision only.** Tool stages PNGs + spec excerpts; SKILL drives Cursor's vision. No algorithmic diff. |
| Findings sink | **Scratch then user-curated promote.** `.parity_scout/<run-id>/findings.md` during the run; the agent curates and asks the user before any `docs/features/<id>/60-followups.md` write. |
| Screenshots per leaf per platform | **Auto scroll-until-bottom**, named `<page>-part<n>.png`. |
| Cross-platform scheduling | **Parallel per leaf.** All 3 platforms run concurrently for the same leaf; analysis is the sync barrier between leaves. |
| Missing parity on a platform | Two states (internally `status` codes in `plan.json`): **`feature_absent`** → emit single-platform conclusion "implement on `<platform>`", skip its capture, continue. **`blocked` (reason `add-capture-route`)** — equivalent to "suite_absent": feature exists but no capture route mapped. The leaf is **BLOCKED**; user must add the capture route to the registry before re-running. |
| Capture mechanism | **Reuse existing screenshot manifests** (`capture_harmony_screenshots.py`, iOS `-UITestRoute<Page>` launch args, Android `AndroidScreenScreenshotTest`). No new harnesses. |
| Naming | Tool: `tools/parity_scout/`. Skill: `.cursor/skills/parity-scout/SKILL.md`. |
| Baseline discipline | HarmonyOS working tree must be on `main` and clean (no uncommitted `harmonyos/entry/src/main/ets/**`) unless `--allow-dirty-baseline`. Baseline SHA recorded in `<run-id>/baseline.txt`. |

## 4. Architecture

### 4.1 System diagram

```
                          Cursor agent (driven by SKILL)
                                       │
        ┌───────── plan ───────── pick ───────── run ───────── promote ──────────┐
        ▼                                                                         ▼
  tools/parity_scout/        .parity_scout/<run-id>/         docs/features/<id>/
   scout.py (CLI)              plan.json                                60-followups.md
   page_suite_map.yml          picked.json                              (appended on promote)
   adapters/                   <page>/{harmony,ios,android}/*.png
     harmony.py                <page>/spec-excerpts.md
     ios.py                    <page>/next.flag      ← SKILL touches to release
     android.py                findings.md           ← agent appends per leaf
                               findings.curated.md   ← user/agent curated, fed to promote
```

### 4.2 File / folder layout

```
tools/parity_scout/
  README.md                      # operator pointer to SKILL + manifests
  scout.py                       # CLI: plan / pick / run / promote / doctor / prune
  page_suite_map.yml             # source-of-truth registry (committed)
  adapters/
    __init__.py
    harmony.py                   # wraps capture_harmony_screenshots.py per-page
    ios.py                       # wraps simctl launch + -UITestRoute<Page> + io screenshot
    android.py                   # wraps the AndroidScreenScreenshotTest path per-page
  spec_extract.py                # given a scope, return [page_ids]
  excerpts.py                    # given (spec path, page_id), slice the relevant prose
  pyproject.toml                 # pinned deps: pyyaml, ruamel.yaml, rich
  tests/                         # offline unit tests
.parity_scout/                   # committed run dirs: <run-id>/plan.json, … (see README)
  README.md
.cursor/skills/parity-scout/
  SKILL.md                       # ~150-line scheduler
```

### 4.3 Registry schema (`page_suite_map.yml`)

```yaml
pages:
  - id: home
    description: Landing screen (landscape, child-facing)
    spec_anchors:
      stable_ids: [HomeStartButton, HomeChildProfileButton, HomeVersionLabel]
      page_section_titles: ["Home", "主页"]
    harmony:
      present: true
      page_source: harmonyos/entry/src/main/ets/pages/HomePage.ets
      capture:
        kind: capture_harmony_step
        step: home                          # closure name in capture_harmony_screenshots.py
    ios:
      present: true
      page_source: ios/WordMagicGame/Features/Home/HomePage.swift
      capture:
        kind: simctl_route
        launch_args: ["-UITestResetState"]
        output_basename: home
    android:
      present: true
      page_source: android/app/src/main/java/cool/happyword/wordmagic/HomePage.kt
      capture:
        kind: android_screenshot_test
        case: home
```

Rules enforced by `scout.py plan` and the adapter dispatcher:

- `present: false` ⇒ leaf is marked `feature_absent: <platform>`. The tool emits a single-platform conclusion "implement `<page>` on `<platform>`" and **skips its adapter**. The other platforms still run for the leaf.
- `present: true && capture: null` ⇒ leaf is marked `blocked: add-capture-route`. The tool **refuses to run** that leaf (per §3 decision). The user must add the capture route, then re-invoke `scout.py run --run <id>`.
- Every `page_source` listed must exist on disk. The offline test `test_registry.py` enforces this so renamed / deleted source files fail the test instead of breaking a live run.

## 5. CLI surface — four subcommands plus `doctor` and `prune`

All commands run from repo root. Run state lives at `.parity_scout/<run-id>/`. `<run-id>` defaults to `YYYYMMDD-HHMMSS-<scope-slug>`. Every subcommand accepts `--run <id>` to bind to an existing run.

### 5.1 `scout.py plan` — decompose into a search-plan tree

```
scout.py plan --scope overall
scout.py plan --spec docs/superpowers/specs/<x>.md
scout.py plan --feature docs/features/<id>
scout.py plan --pages home,wishlist,battle
scout.py plan --suite ParentAdminFlow,WishlistFlow
scout.py plan --describe "anything touching the gift box modal"
```

Effect: writes `.parity_scout/<run-id>/plan.json`:

```json
{
  "run_id": "20260513-221530-spec-wishlist",
  "scope": {"kind": "spec", "path": "docs/superpowers/specs/2026-04-29-v0.3.9-wishlist-redemption-flow-design.md"},
  "leaves": [
    {
      "page_id": "wishlist",
      "harmony": {"status": "ok", "route": "wishlist"},
      "ios":     {"status": "ok", "route": "wishlist"},
      "android": {"status": "feature_absent"},
      "spec_excerpt_path": "<run-id>/wishlist/spec-excerpts.md"
    },
    {
      "page_id": "redemption-history",
      "harmony": {"status": "ok",      "route": "redemption-history"},
      "ios":     {"status": "ok",      "route": "redemption-history"},
      "android": {"status": "blocked", "reason": "add-capture-route"}
    }
  ]
}
```

It also prints a human tree to stdout:

```
PLAN run=20260513-221530-spec-wishlist  scope=spec:wishlist-redemption-flow-design.md
├── wishlist            harmony:ok  ios:ok  android:feature_absent
├── redemption-history  harmony:ok  ios:ok  android:BLOCKED(add-capture-route)
└── gift-box-modal      harmony:ok  ios:ok  android:ok
```

Exit codes: `0` plan written; `2` no leaves resolved (scope too narrow / ambiguous `--describe`); `3` registry parse error.

### 5.2 `scout.py pick` — record branch selection

```
scout.py pick --run <id> --branches wishlist,gift-box-modal
scout.py pick --run <id> --branches all
scout.py pick --run <id> --branches all --include-blocked
```

Effect: writes `picked.json`. Refuses to pick a `blocked` leaf unless `--include-blocked` is set. Refuses to pick a leaf where every platform is `feature_absent` (nothing to compare).

### 5.3 `scout.py run` — drive captures, leaf-by-leaf, with SKILL sync

```
scout.py run --run <id>
scout.py run --run <id> --only wishlist
scout.py run --run <id> --leaf-timeout 180
scout.py run --run <id> --allow-dirty-baseline    # bypass main-clean check
```

Per-leaf rhythm:

1. Print `LEAF START page=<id>`. Stage `wishlist/{harmony,ios,android}/` directories and `wishlist/spec-excerpts.md` (from `excerpts.py`). `wishlist/next.flag` is **not** present yet.
2. Fire all three platform adapters **in parallel**. Each adapter auto-scrolls until bottom, naming files `<page>-part<n>.png`. `feature_absent` platforms write a `MISSING.txt` stub instead of invoking their adapter. Each adapter is given up to `--leaf-timeout` seconds (default `180`); the leaf advances as soon as all three adapters have returned or timed out.
3. Print `LEAF READY page=<id> dir=.parity_scout/<run-id>/wishlist/`. **Block** on the presence of `wishlist/next.flag` (poll once per second; honor SIGINT).
4. When the SKILL's agent has appended findings for this leaf to `findings.md`, the SKILL does `touch <run-id>/<page>/next.flag`. `run` unblocks and advances to the next leaf.
5. After the last leaf, print `RUN DONE` and exit.

Exit codes: `0` all leaves attempted; `4` registry/plan mismatch; `5` non-recoverable capture infrastructure failure; `130` SIGINT.

### 5.4 `scout.py promote` — append curated findings to feature followups

```
scout.py promote --run <id> --feature 2026-04-29-v0.3.9-wishlist-redemption-flow
scout.py promote --run <id> --feature <feature-id> --findings <path>     # explicit slice
```

**Curate-by-feature contract.** A wide scope (`--scope overall`, multi-page `--spec`, etc.) may produce findings that belong to several feature folders. The curate step (§6 step 6) is therefore responsible for splitting `findings.md` into per-feature slices:

```
.parity_scout/<run-id>/
  findings.md                                  # raw, agent-appended, every leaf
  findings.curated.md                          # noise dropped
  findings.curated.<feature-id-A>.md           # written by agent during curate
  findings.curated.<feature-id-B>.md
  ...
```

`promote --feature <feature-id>` defaults to reading `findings.curated.<feature-id>.md` from the run dir. `--findings <path>` overrides the source file (useful for one-off promotion of `findings.curated.md` to a single feature). The CLI **refuses** if neither `findings.curated.<feature-id>.md` nor `--findings <path>` exists. It then appends a new dated section to `docs/features/<feature-id>/60-followups.md`:

```markdown
## Parity scout — 2026-05-13 (run 20260513-221530-spec-wishlist)

Baseline: harmonyos main @ 7a3f12e (clean)
Scope: spec:2026-04-29-v0.3.9-wishlist-redemption-flow-design.md
Leaves analysed: wishlist, gift-box-modal, redemption-history

- [ ] **wishlist (iOS)** — coin label vertically misaligned vs Harmony baseline; iOS uses sans-serif fallback.
- [ ] **gift-box-modal (Android)** — modal background uses #1A1A1A vs Harmony #0F0F12.
- [ ] **redemption-history (Android)** — feature absent; implement per spec §3.2.
```

Refuses to write if `docs/features/<feature-id>/` does not exist (the tool never creates feature folders). Items are `- [ ]` so they graft onto the SOP's parity-fix workflow.

### 5.5 `scout.py doctor` — preflight diagnostic

```
scout.py doctor
  ✓ hdc list targets → 1 target online
  ✓ xcrun simctl list devices → 'iPhone 17 Pro' available
  ✗ adb devices → no online emulator   (informational: Android leaves whose `present: true` will fail at run time unless the emulator is brought up)
  ✓ harmonyos baseline → main @ 7a3f12e clean
  ✓ registry valid (28 pages)
```

Non-gating. Informational. SKILL runs it at session start.

### 5.6 `scout.py prune` — rotate run directories

```
scout.py prune --keep 5
```

Deletes oldest `.parity_scout/<run-id>/` directories above the keep-count. Not auto-run; deliberate.

## 6. SKILL: `parity-scout/SKILL.md`

Scheduler-only, ~150 lines. Modeled on `three-platform-feature-orchestrator`.

### 6.1 Frontmatter

```yaml
name: parity-scout
description: Drives a per-feature visual + spec-anchored gap scout across HarmonyOS / iOS / Android using tools/parity_scout/. Use when asked to "find iOS / Android gaps vs HarmonyOS main", "check parity for <feature>", or "screenshot the three platforms and tell me what's different".
```

### 6.2 Flow (one full run, one user task)

1. **Inputs.** Identify a scope candidate from the user task (`--feature` / `--spec` / `--scope overall` / `--describe`); ask once if ambiguous.
2. **Doctor.** Run `scout.py doctor` and surface its output.
3. **Plan.** Run `scout.py plan ...`. If `--scope overall`, **stop and confirm with the user** because this is the expensive global mode. Otherwise present the tree in chat and ask the user which branches to pick (checkbox list). Blocked / all-feature-absent branches are shown but greyed.
4. **Pick.** Run `scout.py pick --run <id> --branches <user-selection>`. If the user selected any `blocked` leaf, **refuse to start `run`** and tell them they must add the capture route first; offer to flip into an "add the route" subtask before resuming.
5. **Per-leaf loop.** Run `scout.py run --run <id>` foreground, watched. For each `LEAF READY` line:
   1. Read the staged `spec-excerpts.md` for this page.
   2. Read each `*.png` under `<page>/<platform>/` (Cursor agent vision).
   3. Compare against spec excerpts (expected) and against HarmonyOS PNGs (baseline). The spec excerpts narrow what counts as a gap; visual-only differences not anchored by the spec are downranked.
   4. Append findings to `findings.md` under a `## <page>` heading. Items are bullet lines tagged `[harmony|ios|android]` plus a severity hint.
   5. `touch <run-id>/<page>/next.flag` to release `run`.
6. **Curate.** After `RUN DONE`, read `findings.md`, drop noise, write `findings.curated.md`. Then **group the curated items by feature folder** (each item belongs to one feature folder if it can be mapped from `page_id` + spec scope; items that map to no feature go to `findings.curated.unassigned.md`). Write `findings.curated.<feature-id>.md` for every feature touched. Show the user a one-screen summary listing each feature slice and **ask** which slices to promote ("all / none / pick").
7. **Promote.** Only on explicit user choice: run `scout.py promote --run <id> --feature <id>` once per picked slice. Show the resulting diff hunk in chat after each. Do **not** auto-commit; the user runs git themselves.

### 6.3 Guards the SKILL invokes

- `safe-command-policy` before every `scout.py` invocation; manifest is the source of truth for new flags.
- `autoloop-guard` on the per-leaf loop — if the same `LEAF READY` line repeats without `findings.md` growth, abort.
- `harmony-emulator-manage` (plus iOS / Android equivalents) as preflight when any selected leaf needs that platform's adapter.

### 6.4 Stop conditions

- `RUN DONE` + user resolved every curated feature slice (promote or skip) + (if promoted) diff hunks shown.
- Precondition refused: missing capture route on a selected leaf (the SKILL refuses before calling `scout.py run`) OR dirty Harmony baseline without `--allow-dirty-baseline` (the tool refuses) OR device unreachable preflight (the SKILL refuses via `harmony-emulator-manage` and the iOS / Android equivalents) → user told what to add; no files touched.
- `autoloop-guard` tripped → run dir preserved for inspection.

**Layering note.** Device reachability is the **SKILL's** responsibility, enforced via preflight skills. `scout.py` itself never checks for live devices; if an adapter cannot reach its target the run records `CAPTURE_FAILED.txt` for that platform and the leaf still advances (§7.2). The SKILL's preflight prevents calling `run` when reachability is known-bad up front; the in-run failure path catches mid-run device disappearance.

## 7. Failure modes and edge cases

### 7.1 Baseline discipline

- `scout.py run` calls `git rev-parse main` and `git status --porcelain harmonyos/entry/src/main/ets`. If `main` is not the current HEAD or the Harmony tree is dirty, refuse unless `--allow-dirty-baseline`.
- Baseline SHA is written to `<run-id>/baseline.txt` and included in `promote` output.

### 7.2 Per-leaf failures (graceful, recoverable)

| Failure | What `run` does | What the SKILL does |
|--|--|--|
| Adapter exits non-zero for one platform | Write `<page>/<platform>/CAPTURE_FAILED.txt` with stderr tail; continue; still emit `LEAF READY` | Treat that platform as "no observation", still report gaps for the other two, append `- [ ] CI: investigate <page> <platform> capture failure` |
| Adapter hangs past `--leaf-timeout` | SIGTERM the adapter; otherwise same as above | Same as above |
| All three adapters fail | No PNGs in `<page>/`; emit `LEAF READY` with `OBSERVATIONS_EMPTY` marker | Record leaf as "no observations" and continue |
| Device disappears mid-run | Next leaf preflight fails | Refuse next leaf, leave `<run-id>` intact for resume via `scout.py run --run <id> --only <remaining-leaves>` |

### 7.3 Cross-cutting edges

- **`--describe` ambiguity.** `spec_extract.py` resolves prose by intersecting tokens with registry `description` + `spec_anchors`. Empty intersection ⇒ `plan` exits `2` with closest candidates. > 8 matches ⇒ `plan` exits `2` listing them all; SKILL forwards.
- **Spec excerpt extraction.** Slice by `##`-level headings; keep headings whose title or body mentions any registry stable id or page section title for that page. If nothing matches, write `<!-- no spec anchors matched -->` and let the agent reason from PNGs alone (recording "spec did not constrain this leaf").
- **Concurrent `run` invocations.** Refused. `.parity_scout/.lock` is acquired with a pid stamp; stale-pid locks are force-released.
- **`promote` re-run.** Appends a fresh dated section each time; prior sections are never edited. Duplicate sections are user-resolvable via `git diff`.
- **Network.** None. All vision is local. All spec parsing is local.

## 8. Testing strategy

### 8.1 Offline unit tests (`tools/parity_scout/tests/`)

- `test_registry.py` — schema, refuse `present: true && capture: null` running silently, every `page_source` exists.
- `test_spec_extract.py` — fixture specs → expected page ids; covers `--spec`, `--feature`, `--pages`, `--suite`, `--describe`, empty / too-many branches.
- `test_excerpts.py` — fixture spec + stable ids → expected excerpt; covers the no-anchor branch.
- `test_plan_render.py` — synthetic registry + leaves → snapshot of tree printer and `plan.json`; covers ok / feature_absent / blocked mixes.
- `test_promote.py` — fake `findings.curated.md` → expected `60-followups.md` append; covers the missing-feature-folder refusal.

All offline. Run via the repo's existing Python discipline (strict warnings).

### 8.2 What unit tests do not cover

Real device captures. Adapters shell out via `subprocess`; their tests use mocks. A real-device smoke is `scout.py doctor` + `scout.py run --pages home` against live devices; humans invoke manually.

### 8.3 Integration validation

- `scout.py doctor` passes on at least one developer machine.
- One real `--pages home` run end-to-end against an emulator triple before declaring the tool done.

## 9. Integration with existing skills and manifests

### 9.1 Existing skills the SKILL invokes

| Skill | Role |
|--|--|
| `safe-command-policy` | Wraps every `scout.py` invocation. New flags must land in the manifest first. |
| `autoloop-guard` | Caps the per-leaf loop. |
| `harmony-emulator-manage` (and the iOS / Android equivalents in their manifests) | Device preflight per leaf. |

### 9.2 Existing skills modified

- `three-platform-feature-orchestrator/SKILL.md` — one small addition in Stage 3 ("Stabilization") and Stage 5 ("Parity checklist") narrative: *"If you suspect parity gaps, run `parity-scout` before signing the replication trigger / before claiming Stage 5 green."*

### 9.3 Existing manifests modified

- `.cursor/ohos-dev-commands.md` §7 "Screenshots / Visual Parity" — append one-liner pointer to `tools/parity_scout/README.md`.
- `.cursor/ios-dev-commands.md` §7 — same.
- `.cursor/android-dev-commands.md` §6 — same.

These are tiny pointer edits, not new manifests.

## 10. Risks and open questions

- **Registry maintenance burden.** Every new page must be added to `page_suite_map.yml`. Mitigated by `test_registry.py` failing when a `page_source` disappears, and by the SOP-stage hand-off (Stage 5 owner adds the page to the registry as part of parity).
- **Vision token cost.** Reading 3 PNGs per leaf for a 20-leaf overall run is large but bounded. The `--scope overall` confirmation step gives the user a chance to bail.
- **iOS `-UITestRoute<Page>` coverage.** Not all pages have a launch-arg route today. Adding one is a tiny iOS-side change; tracked via `present: true && capture: null` becoming a BLOCKED leaf, which surfaces the missing route immediately.
- **Android route gaps.** Same shape as iOS; surfaced the same way.
