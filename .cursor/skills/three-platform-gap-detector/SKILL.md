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

## Counterpart Availability Strategy

For each iOS or Android counterpart in scope, decide whether the feature exists before trying to force a simulator probe.

1. If the scoped feature, page, control, or behavior is absent on iOS/Android, record a direct `missing_flow` or `missing_feature` gap with source/spec/screenshot evidence. Do not write a UI test just to prove absence.
2. If the feature exists but no UI test route, stable id, or screenshot path can exercise it, record the probe blocker as `test_coverage_gap`, add the smallest UI Test case needed to reach and observe that existing feature, then continue the detector run.
3. Test-only additions must only expose or verify existing behavior for probing. They must not implement missing product behavior, redesign UI, or close the gap they are meant to detect.
4. After adding a detector-enabling UI Test, rerun the single affected suite/page probe and classify gaps from the new evidence before moving on.

## Boundaries

- Do not edit app product source, implement missing features, create fix commits, or open PRs.
- Only edit UI tests when the counterpart feature already exists and the detector is blocked by missing automation.
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
