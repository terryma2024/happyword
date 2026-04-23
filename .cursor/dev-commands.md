# Dev commands manifest (source of truth)

Read this file before running HarmonyOS build or test commands. **Do not invent `hvigorw` flags**; if a command fails, align with DevEco’s task names for the installed SDK and update this file.

- **last_verified_deveco:** (fill when confirmed, e.g. `5.0.x`)
- **project_root:** repository root (where `oh-package.json5` and `hvigorfile.ts` live)

## Conventions

- Use `hvigorw` from **project root** (assumes Hvigor wrapper is installed and available on `PATH`); add `--no-daemon` in CI or long non-interactive runs if your environment recommends it.
- **Phase order (autofix loop):** build → **codelinter** → **no-device unit** → **emulator/device** → **on-device / UI (Instrument)**.

---

## 1) Build — `harmony-build`

| Step | Command | Success signal |
|------|---------|----------------|
| Install deps | `ohpm install` | Exit 0, `oh_modules` resolvable |
| Assemble HAP (debug) | `hvigorw assembleHap` | Exit 0, `.hap` under `entry/build/...` (path may vary) |
| (Optional) single module | `hvigorw --mode module -p module=entry assembleHap` | Exit 0 |

**Working directory:** project root.

### CodeLinter (after successful build) — `harmony-codelinter`

Run **after** the HAP build step succeeds. Uses the project’s [code-linter.json5](code-linter.json5) at the repo root.

| Step | Command | Success signal |
|------|---------|----------------|
| Code check + auto-fix (recommended) | `codelinter -c ./code-linter.json5 . --fix` | Exit 0, no errors (warnings per team policy) |
| Check only (no auto-fix) | `codelinter -c ./code-linter.json5 .` | Exit 0 |
| Stricter CI-style exit (optional) | `codelinter -c ./code-linter.json5 . --fix --exit-on error` | Exit 0 |

**Working directory:** project root.

**Prerequisite:** the `codelinter` binary from **HarmonyOS / DevEco Command Line Tools** must be on `PATH` (not bundled in this repo). In-repo command reference: [docs/arkts-references/codelinter.md](docs/arkts-references/codelinter.md).

**Fix loop:** If codelinter reports issues, address them in source (re-run `codelinter` with `--fix` where supported, then manual fixes). Re-run codelinter until it passes before starting **no-device unit** tests in a full pipeline.

---

## 2) Unit test (no device) — `harmony-unit-test`

**Scope:** `entry/src/test/**` (Local / no emulator, no `hdc`).

| Command | Success signal |
|---------|----------------|
| Typical (adjust to your SDK if needed): `hvigorw -p module=entry@default test` | Exit 0, test report under `entry/build/.../reports` or console shows passed |

**Notes:**

- If your Hvigor version uses different `-p` names, copy the exact line from DevEco’s Gradle-like task for **Local Unit Test** and paste it here.
- **Device-required** or `ohosTest` cases are **not** in this step; they run after the emulator is up (section 4).

### Pre-flight: `oh_modules/` must exist at project root

**`hvigorw ... test` drives tests through the offline Previewer binary.** The Previewer loads `@ohos/hypium` from `oh_modules/` at runtime; if that directory is missing (fresh clone, new `git worktree`, or after a wipe), the test ability silently fails to register, so the Previewer never emits `OHOS_REPORT_STATUS: taskconsuming` and hvigor hangs forever in `child.stdout.on('data', ...)` waiting for it.

- **Symptom:** `UnitTestArkTS` compiles, then `GenerateUnitTestResult` prints one or more `Darwin` lines and never completes; killing hvigor leaves a `Previewer` child process reparented to init.
- **Fix:** run `ohpm install` at project root before `hvigorw ... test`. Verify `oh_modules/` exists (not only under `entry/`).
- **Zombie cleanup on hang:** `pkill -9 -f "openharmony/previewer/common/bin/Previewer"` and re-run. Leaked Previewers squat ports 40000+ and each leak adds one extra `Darwin` line via `findPort` recursion, but the real failure is still the missing `oh_modules/`.

---

## 3) Emulator / device — `harmony-emulator-manage`

| Step | Command | Success signal |
|------|---------|----------------|
| List devices | `hdc list targets` | At least one `127.0.0.1:...` or device serial when emulator/USB is ready |
| (Project-specific) start simulator | *(fill: path to emulator CLI or “start from DevEco once”)* | `hdc list targets` non-empty within timeout |

**Skip rule:** if `hdc list targets` already shows a valid target, you may **skip** starting the emulator and only **verify** connectivity.

**Working directory:** any (HDC on `PATH`).

---

## 4) UI / on-device (Instrument) — `harmony-ui-test`

**Scope:** `entry/src/ohosTest/**`, UiTest / Instrument as configured in `entry` target `ohosTest`.

| Step | Command | Success signal |
|------|---------|----------------|
| Install HAP | `hdc install <path-to-debug.hap>` | Install success in hdc output |
| On-device / Instrument test | `hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 30000 -w 180` | `TestFinished-ResultCode: 0` and `OHOS_REPORT_CODE: 0` |

**Notes:** Exact **Instrument** / **onDevice** task names depend on **DevEco / hvigor-ohos-plugin** version. Record the same command you use in DevEco’s “Run” for `ohosTest`.

---

## 5) Failure artifacts — `harmony-log-analyzer` (read in this order)

1. **Console:** last 200–400 lines of the failing command (Hvigor / `codelinter` / shell stderr+stdout). For codelinter, if `-o` was used, also open that report file.
2. **Hvigor reports:** under `entry/build/`, `**/reports/**`, `**/*test*report*`, `**/test-results/**` (glob; paths vary by version).
3. **Device / UI failure:** `hdc hilog` (or the project’s standard hilog command) **after** reproducing; filter by your app’s bundle and tag as needed.
4. **HAP path:** if install failed, re-check `.hap` path from build output.

Update this list when you find stable paths on disk for your machine.

---

## 6) Device-only tests (edge case)

If you have Instrument-style tests that are not “UI 自动化” but need `hdc`, run them in **section 4** after the device is up—not in section 2.
