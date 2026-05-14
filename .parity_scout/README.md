# Parity scout — committed run artifacts

Each **scout run** is one subdirectory named by the **run id** (task key), e.g. `20260514-084557-pages-config`. That id is printed by `python3 tools/parity_scout/scout.py plan …` as `run-id:` and passed to `pick` / `run` / `promote` via `--run`.

## What to commit

When you want screenshots and gap notes to ride along in git (for later alignment / repair work), add the whole run folder:

- `plan.json`, `picked.json`, `baseline.txt`
- `<page_id>/harmony/`, `ios/`, `android/` — PNG evidence (and optional `CAPTURE_FAILED.txt` / `MISSING.txt`)
- `<page_id>/spec-excerpts.md`
- `findings.md`, `findings.curated*.md` — analysis and curated slices

`next.flag` is only used during `scout.py run` to unblock the runner; you may omit it from commits or leave it — harmless.

## Local-only

- **`.parity_scout/.lock`** — PID lock while `run` is active; listed in `.gitignore`, never commit.

See also: [`tools/parity_scout/README.md`](../tools/parity_scout/README.md), [`.cursor/skills/parity-scout/SKILL.md`](../.cursor/skills/parity-scout/SKILL.md).
