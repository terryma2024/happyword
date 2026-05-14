# parity_scout

Three-platform UI / behavior parity gap scout. **Driver:** [`.cursor/skills/parity-scout/SKILL.md`](../../.cursor/skills/parity-scout/SKILL.md). **Design:** [`docs/superpowers/specs/2026-05-13-parity-scout-design.md`](../../docs/superpowers/specs/2026-05-13-parity-scout-design.md). **Plan:** [`docs/superpowers/plans/2026-05-13-parity-scout.md`](../../docs/superpowers/plans/2026-05-13-parity-scout.md).

## CLI

```bash
python3 tools/parity_scout/scout.py plan    --scope overall
python3 tools/parity_scout/scout.py plan    --spec docs/superpowers/specs/<x>.md
python3 tools/parity_scout/scout.py plan    --feature docs/features/<id>
python3 tools/parity_scout/scout.py plan    --pages home,wishlist
python3 tools/parity_scout/scout.py plan    --suite ParentAdminFlow
python3 tools/parity_scout/scout.py plan    --describe "..."
python3 tools/parity_scout/scout.py pick    --run <id> --branches home,wishlist
python3 tools/parity_scout/scout.py run     --run <id>
python3 tools/parity_scout/scout.py promote --run <id> --feature <feature-id>
python3 tools/parity_scout/scout.py doctor
python3 tools/parity_scout/scout.py prune   --keep 5
```

Run from repo root. **Run artifacts** (plan, screenshots, `findings.md`, …) live under **`.parity_scout/<run-id>/`** — the run id is the **task key** for later alignment work; commit that folder when you want the evidence in git. Registry is `tools/parity_scout/page_suite_map.yml`.

## Environment

- **Android:** If `adb devices` lists more than one device, set `ANDROID_SERIAL` (e.g. `export ANDROID_SERIAL=emulator-5556`) before `scout.py run` so the adapter uses `adb -s …`.

## Tests

```bash
cd tools/parity_scout && uv run pytest
```

## Manifest references

- HarmonyOS: [`.cursor/ohos-dev-commands.md`](../../.cursor/ohos-dev-commands.md)
- iOS: [`.cursor/ios-dev-commands.md`](../../.cursor/ios-dev-commands.md)
- Android: [`.cursor/android-dev-commands.md`](../../.cursor/android-dev-commands.md)
