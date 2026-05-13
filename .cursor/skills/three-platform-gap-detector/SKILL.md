---
name: three-platform-gap-detector
description: Use when investigating iOS or Android parity gaps against the HarmonyOS baseline in WordMagicGame, especially when comparing behavior, UI style, stable IDs, screenshots, specs, plans, or three-platform feature docs.
---

# Three-Platform Gap Detector

Use this skill to find iOS and Android gaps against the latest HarmonyOS baseline. This is an evidence workflow, not a repair workflow.

## Start

1. Resolve scope from the user request.
2. Do not run `overall` unless the user explicitly requests it.
3. If the request is ambiguous, generate a search-path plan and ask the user to choose paths.
4. Use latest HarmonyOS on `main` or `origin/main` as the baseline.
5. Read specs, plans, feature docs, and existing tests before judging screenshots.

## Run Discipline

1. Build or update a probe manifest before running simulators.
2. Run one suite/page probe batch at a time.
3. Capture evidence: screenshots, UI tree or accessibility evidence, command logs, test output, and source docs.
4. After each batch, classify findings into the gap queue before continuing.
5. Stop at evidence-backed gap findings.

## Boundaries

- Do not edit app source, create fix commits, or open PRs.
- Do not treat screenshots as the only source of truth.
- Do not silently skip missing counterpart suites; record a `test_coverage_gap`.
- Do not force manual-only debug paths into automated UI suites; record `manual_gate`.

## Commands

```sh
python3 -m tools.gap_detector plan --scope <feature-or-spec-or-page> --run-name <name>
python3 -m tools.gap_detector plan --scope overall --run-name <name>
python3 -m tools.gap_detector run --manifest .gap-detector/runs/<name>/manifest.yaml --probe <probe-id>
python3 -m tools.gap_detector classify --run .gap-detector/runs/<name>
```

Use `run --execute` only when the user expects local platform commands to run and the required simulator/device is ready.

## Handoff

If the user wants to fix a gap, hand off to the applicable feature or bugfix workflow with the gap queue item as input.
