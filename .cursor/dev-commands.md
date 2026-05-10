# Dev commands manifest (source of truth)

Read this file before running HarmonyOS build or test commands. **Do not invent `hvigorw` flags**; if a command fails, align with DevEco’s task names for the installed SDK and update this file.

- **last_verified_deveco:** (fill when confirmed, e.g. `5.0.x`)
- **repo_root:** repository root (`<repo-root>`)
- **harmony_project_root:** `harmonyos/` (where `oh-package.json5`, `build-profile.json5`, and `hvigorfile.ts` live)

## Conventions

- Use `hvigorw` from **harmony_project_root** (`harmonyos/`; assumes Hvigor wrapper is installed and available on `PATH`); add `--no-daemon` in CI or long non-interactive runs if your environment recommends it.
- **Phase order (autofix loop):** build → **codelinter** → **no-device unit** → **emulator/device** → **on-device / UI (Instrument)**.

---

## 1) Build — `harmony-build`

| Step | Command | Success signal |
|------|---------|----------------|
| Install deps | `cd harmonyos && ohpm install` | Exit 0, `harmonyos/oh_modules` resolvable |
| Assemble HAP (debug) | `cd harmonyos && hvigorw assembleHap` | Exit 0, `.hap` under `harmonyos/entry/build/...` (path may vary) |
| (Optional) single module | `cd harmonyos && hvigorw -p module=entry@default assembleHap` or `cd harmonyos && hvigorw --mode module -p module=entry assembleHap` | Exit 0 |

**Working directory:** `harmonyos/`.

### ArkTS compiler warnings (mandatory)

The `:CompileArkTS` step must emit **zero** `ArkTS:WARN` lines before a Harmony-side change is considered merge-ready. Typical causes: deprecated module-level `router` / `getContext`, legacy `@kit.CoreFileKit` picker types, `ImagePacker.packing`, etc. Migrate to `this.getUIContext().getRouter()`, `this.getUIContext().getHostContext()`, `@kit.MediaLibraryKit` / `photoAccessHelper`, `ImagePacker#packToData`, and related SDK replacements.

**Verify:** after assembleHap, `cd harmonyos && hvigorw ... 2>&1 | grep 'ArkTS:WARN'` must print nothing (exit code 1 from grep is OK). Agents fix warnings at the source; do not silence the compiler for convenience.

### CodeLinter (after successful build) — `harmony-codelinter`

Run **after** the HAP build step succeeds. Uses the Harmony project’s `harmonyos/code-linter.json5`.

| Step | Command | Success signal |
|------|---------|----------------|
| Code check + auto-fix (recommended) | `cd harmonyos && codelinter -c ./code-linter.json5 . --fix` | Exit 0, no errors (warnings per team policy) |
| Check only (no auto-fix) | `cd harmonyos && codelinter -c ./code-linter.json5 .` | Exit 0 |
| Stricter CI-style exit (optional) | `cd harmonyos && codelinter -c ./code-linter.json5 . --fix --exit-on error` | Exit 0 |

**Working directory:** `harmonyos/`.

**Prerequisite:** the `codelinter` binary from **HarmonyOS / DevEco Command Line Tools** must be on `PATH` (not bundled in this repo). In-repo command reference: [docs/arkts-references/codelinter.md](docs/arkts-references/codelinter.md).

**Fix loop:** If codelinter reports issues, address them in source (re-run `codelinter` with `--fix` where supported, then manual fixes). Re-run codelinter until it passes before starting **no-device unit** tests in a full pipeline.

---

## 2) Unit test (no device) — `harmony-unit-test`

**Scope:** `harmonyos/entry/src/test/**` (Local / no emulator, no `hdc`).

| Command | Success signal |
|---------|----------------|
| Typical (adjust to your SDK if needed): `cd harmonyos && hvigorw -p module=entry@default test` | Exit 0, test report under `harmonyos/entry/build/.../reports` or console shows passed |

**Notes:**

- If your Hvigor version uses different `-p` names, copy the exact line from DevEco’s Gradle-like task for **Local Unit Test** and paste it here.
- **Device-required** or `ohosTest` cases are **not** in this step; they run after the emulator is up (section 4).

### Pre-flight: `harmonyos/oh_modules/` must exist at the Harmony project root

**`hvigorw ... test` drives tests through the offline Previewer binary.** The Previewer loads `@ohos/hypium` from `oh_modules/` at runtime; if that directory is missing (fresh clone, new `git worktree`, or after a wipe), the test ability silently fails to register, so the Previewer never emits `OHOS_REPORT_STATUS: taskconsuming` and hvigor hangs forever in `child.stdout.on('data', ...)` waiting for it.

- **Symptom:** `UnitTestArkTS` compiles, then `GenerateUnitTestResult` prints one or more `Darwin` lines and never completes; killing hvigor leaves a `Previewer` child process reparented to init.
- **Fix:** run `cd harmonyos && ohpm install` before `hvigorw ... test`. Verify `harmonyos/oh_modules/` exists (not only under `harmonyos/entry/`).
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

**Scope:** `harmonyos/entry/src/ohosTest/**`, UiTest / Instrument as configured in `entry` target `ohosTest`.

| Step | Command | Success signal |
|------|---------|----------------|
| Install HAP | `hdc install harmonyos/entry/build/default/outputs/default/entry-default-signed.hap` | Install success in hdc output |
| On-device / Instrument test (recommended) | `scripts/run_ui_tests.sh` (boots the local mock + sets up `hdc rport` + runs `aa test`) | `TestFinished-ResultCode: 0` and `OHOS_REPORT_CODE: 0` |
| Raw command (no mock) | `hdc shell aa test -b com.terryma.wordmagicgame -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000 -w 1800` | Same — but flows that hit `/api/v1/...` will fail because the test harness rewrites the base URL to `http://127.0.0.1:8123` |

**Mock UI server (V0.5.8+):**

The ohosTest harness in `harmonyos/entry/src/ohosTest/ets/test/List.test.ets` writes the
AppStorage key `serverBaseUrlOverride = http://127.0.0.1:8123` in `testsuite()`,
which `RemoteWordPackConfig.effectiveServerBaseUrl()` reads on every API client
construction. Production / release builds **never** write this key, so they
keep hitting `https://happyword.cool`. The orchestrator
`scripts/run_ui_tests.sh` is responsible for:

1. Booting `server/mock_ui_server.py` on host port 8123 (no MongoDB; fixed
   fixtures only — see the file's module docstring for the endpoint list).
   The pack-sync fixture mirrors the production
   `harmonyos/entry/src/main/resources/rawfile/data/words_v1.json` 50-word catalog
   so that `configSyncFlowUiTest`'s manual sync overwrites the on-device
   cache with a vocabulary that downstream gameplay suites
   (`FillLetterFlow`, `SpellQuestionFlow`, `ReviewMode`, `MagicAttack`)
   still recognise. The lesson-draft seed (`ui-mock-draft-001`) is
   pending on every boot so `pendingListShowsMockedDraft` and
   `tapReviewLinkOpensReviewPageWithMockedDraft` stay deterministic.

   ohosTest bundles two test-fixture images into
   `harmonyos/entry/src/ohosTest/resources/rawfile/`:

   - `lesson_import_fixture.jpg` — V0.5.8 lesson-import flow.
     `tapPickGalleryUploadsAndShowsImported` reads it via
     `Context.createModuleContext('entry_test').resourceManager.getRawFileContent`,
     writes the bytes into the app sandbox at
     `<appCtx.tempDir>/lesson_import_fixture.jpg`, and points the
     `LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY` AppStorage key at that path.
     `RealPhotoPickerAdapter.{selectGallery,selectCamera}` short-
     circuits on the override and returns the path directly.
   - `scan_binding_qr_fixture.png` — V0.6.x scan-binding 「📷 从图库选择二维码」
     flow. Generated by `tools/generate_scan_binding_qr_fixture.py` (uses
     `qrcode[pil]` from `server/`'s uv environment) — encodes the URL
     `https://happyword.cool/p/uitestqr01`.
     `pickQrFromGalleryRedeemsAndFlipsToBound` writes TWO override keys:
     `SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY` (consumed by the shared
     `RealPhotoPickerAdapter` from `services/PhotoPickerService.ets`) and
     `SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY` (consumed by
     `RealBarcodeImageDecoder` to bypass `@kit.ScanKit.detectBarcode.decode`,
     which is unstable on the OpenHarmony emulator against app-sandbox
     URIs). Both constants live in `services/BarcodeImageDecoder.ets`.

   We do NOT use `hdc file send` for either fixture because HarmonyOS
   NEXT's selinux blocks the bundle UID from reading every shell-writable
   path (`/data/local/tmp/*`, `/storage/media/100/local/files/`, the
   bundle's own `el2/.../files/` debug sandbox).
2. Running `hdc rport tcp:8123 tcp:8123` so the device's loopback resolves
   to the host's mock.
3. Running `hdc shell aa test ...` with a 60s per-test timeout (parent-admin
   flows fan out across launchApp → PIN → navigate → refresh → scroll →
   typeInto and need ~35-45s in cold start).
4. Tearing down: kill the mock process, drop the rport mapping.

If you skip the script and run `aa test` directly, the test harness still
sets the override URL — but with no mock listening the HTTP-driven flows
(`ParentAdminFlow`, `LessonDraftReviewFlow`, `PackManagerFlow`) will all fail. To run the
suite from DevEco's "Run" UI, start the mock and rport mapping by hand
first:

```sh
(cd server && uv run python mock_ui_server.py) &
hdc rport tcp:8123 tcp:8123
```

then trigger the test from DevEco. Tear down with `kill %1` and
`hdc fport rm "tcp:8123 tcp:8123"` when done.

**Notes:** Exact **Instrument** / **onDevice** task names depend on **DevEco / hvigor-ohos-plugin** version. Record the same command you use in DevEco’s “Run” for `ohosTest`.

---

## 5) Failure artifacts — `harmony-log-analyzer` (read in this order)

1. **Console:** last 200–400 lines of the failing command (Hvigor / `codelinter` / shell stderr+stdout). For codelinter, if `-o` was used, also open that report file.
2. **Hvigor reports:** under `harmonyos/entry/build/`, `**/reports/**`, `**/*test*report*`, `**/test-results/**` (glob; paths vary by version).
3. **Device / UI failure:** `hdc hilog` (or the project’s standard hilog command) **after** reproducing; filter by your app’s bundle and tag as needed.
4. **HAP path:** if install failed, re-check `.hap` path from build output.

Update this list when you find stable paths on disk for your machine.

---

## 6) Device-only tests (edge case)

If you have Instrument-style tests that are not “UI 自动化” but need `hdc`, run them in **section 4** after the device is up—not in section 2.
