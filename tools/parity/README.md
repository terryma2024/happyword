# HappyWord Parity Gap Finder

Local `uv`-managed tool for finding actionable iOS and Android gaps against the HarmonyOS baseline.

## Usage

```sh
uv run --project tools/parity parity-gap \
  --baseline origin/main \
  --out /private/tmp/happyword-gaps
```

Useful variants:

```sh
# Refresh the remote baseline first.
uv run --project tools/parity parity-gap --fetch --baseline origin/main --out /private/tmp/happyword-gaps

# Visual-only audit from existing screenshots.
uv run --project tools/parity parity-gap --kind visual --out /private/tmp/happyword-gaps

# Behavior-only audit from selected expected-behavior docs.
uv run --project tools/parity parity-gap --kind behavior --doc-path docs/superpowers/specs/<spec>.md --out /private/tmp/happyword-gaps

# Draft a doc search plan before using spec/plan clues.
uv run --project tools/parity parity-gap --plan-doc-scope --out /private/tmp/happyword-gaps

# Use a specific expected-behavior source.
uv run --project tools/parity parity-gap --doc-path docs/superpowers/specs/<spec>.md --out /private/tmp/happyword-gaps

# Global spec/plan search. Use only when explicitly requested.
uv run --project tools/parity parity-gap --doc-scope overall --out /private/tmp/happyword-gaps

# Try live simulator/emulator capture before visual analysis.
uv run --project tools/parity parity-gap --capture ios,android --out /private/tmp/happyword-gaps

# Make the command fail when P0/P1/P2 gaps exist.
uv run --project tools/parity parity-gap --fail-on P1 --out /private/tmp/happyword-gaps
```

The terminal output is the primary action list. `gaps.json`, `gaps.md`, and `visual-diffs/`
are evidence artifacts for agents and humans.
