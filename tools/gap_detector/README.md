# Three-Platform Gap Detector

This tool finds iOS and Android behavior or UI parity gaps against the latest HarmonyOS baseline. It does not fix gaps, edit app source, open PRs, or create implementation patches.

## Modes

- Scoped: pass a feature folder, spec, plan, page, or suite path with `--scope`.
- Overall: pass `--scope overall`. Overall mode is expensive and must go through user selection before simulator/device runs.
- Ambiguous: pass an empty or unknown scope to receive candidate paths for user selection.

## Commands

```sh
python3 -m tools.gap_detector plan --scope docs/features/<feature-id> --run-name feature-check
python3 -m tools.gap_detector plan --scope overall --run-name overall-plan
python3 -m tools.gap_detector run --manifest .gap-detector/runs/feature-check/manifest.yaml --probe <probe-id>
python3 -m tools.gap_detector classify --run .gap-detector/runs/feature-check
```

`run` defaults to dry-run command printing. Add `--execute` only when the target simulator/device is ready and the user expects local commands to run.

## Artifacts

Runs live under `.gap-detector/runs/<run-name>/`:

```text
.gap-detector/runs/<run-name>/
  manifest.yaml
  gaps.yaml
  probes/<probe>/<platform>/
```

The artifact directory is gitignored. Later workflows can copy selected evidence into tracked docs when needed.

## Expected Behavior Sources

The detector reads specs, plans, feature docs, stable IDs, existing UI tests, screenshots, and command manifests. Screenshots are evidence, not the only source of truth.
