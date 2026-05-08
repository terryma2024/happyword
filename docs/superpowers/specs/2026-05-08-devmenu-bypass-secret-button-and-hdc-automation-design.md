# DevMenu: Bypass secret entry + HDC automation (design)

## Summary

Add a **BypassSecret** button to `DevMenuPage` (left of “Refresh manifest”). The button opens a dedicated entry page for the Vercel “Protection Bypass for Automation” secret (existing feature), showing the current value state when already saved. Preview environment cards keep the current behaviour: **if no secret is saved, prompt**; **if saved, switch immediately** without prompting.

Add a host-side script that, after installing the app on a connected emulator/device, uses `hdc` UI automation to open the BypassSecret entry page and fill it from `~/.env` key `VERCEL_AUTOMATION_BYPASS_SECRET`, then saves.

## Goals

- Make the bypass secret easy to find/edit (top-level button).
- Keep existing Preview-card gate: missing secret → prompt; present secret → no prompt.
- Provide deterministic device setup via script (no manual copy/paste).
- Keep debug/release safety: DevMenu remains **debug-only** entry surface.

## Non-goals

- No new secret storage keys (reuse existing `BackendEnv.KEY_BYPASS_SECRET`).
- No changes to server endpoints or deployment protection behaviour.
- No attempt to `hdc file send` into application sandbox (blocked by SELinux in this project’s emulator matrix).

## Current state (as of `versionName=0.6.0`)

- `entry/src/main/ets/pages/DevMenuPage.ets`
  - Has Preview-card gate: if `env=PREVIEW` and cached secret is empty → opens `BypassSecretDialog`.
  - Has “Edit Vercel bypass secret” button that only appears when a secret is already present.
- Secret persistence:
  - `entry/src/main/ets/services/BackendEnv.ets` provides `loadBypassSecret()` / `saveBypassSecret()`.
  - Secret mirrored into AppStorage key `BACKEND_BYPASS_SECRET_CACHE_KEY` (defined in `RemoteWordPackConfig.ets`) for synchronous header attachment.
- Header attachment:
  - `entry/src/main/ets/services/BackendHeaders.ets` (and helper `buildVercelBypassHeader`) uses `x-vercel-protection-bypass` for Preview env.

## UX / behaviour

### DevMenu header

In the header row of `DevMenuPage`:

- `Back` … title … **`BypassSecret`** … `Refresh manifest`
- The new button is disabled while `applying` (mirrors card disable) and while manifest is refreshing is optional; recommended: disable only while `applying`.

### Bypass secret entry page

New page: `pages/BypassSecretPage.ets` (name can vary but must be routed from DevMenu).

Requirements:

- Shows title “Bypass secret”.
- Shows an input:
  - If a secret exists: input is pre-filled (type `Password`) OR show masked state with an “Edit” toggle.
  - For simplicity and parity with existing dialog, **pre-fill the existing secret** in the input, but keep password masking.
- Shows a primary “Save” button:
  - Trims whitespace.
  - Rejects empty string.
  - Calls `saveBypassSecret(trimmed)` and returns to DevMenu (router.back).
- Shows a secondary “Cancel” button → back without writing.
- Exposes stable ids for UI automation:
  - `BypassSecretPageTitle`
  - `BypassSecretPageInput`
  - `BypassSecretPageSaveButton`
  - `BypassSecretPageCancelButton`

### Preview card switching

No change in semantics:

- If `bypassSecret` is empty and user taps a Preview card → show prompt (dialog).
- If `bypassSecret` is non-empty → apply immediately, no prompt.

We will ensure that:

- After saving via the new page, `DevMenuPage` updates its local `@State bypassSecret` (either by re-hydrating on `aboutToAppear` or by an explicit callback/param on return).

## Data model / persistence

Reuse existing storage:

- Pref key: `BackendEnv.KEY_BYPASS_SECRET`
- AppStorage mirror key: `BACKEND_BYPASS_SECRET_CACHE_KEY`
- API header: `x-vercel-protection-bypass`

No new keys are introduced.

## HDC automation script

New script (repo-root): `scripts/setup_bypass_secret_on_device.sh`

Responsibilities:

1. **Read secret** from host `~/.env`:
   - Parse `VERCEL_AUTOMATION_BYPASS_SECRET=...`
   - Fail with clear error if missing/empty.
   - Never echo the secret back to stdout.
2. **Verify device target**
   - Run `hdc list targets`
   - If multiple targets: require `HDC_TARGET` env var or `--target` flag (align with existing `scripts/run_ui_tests.sh` pattern).
3. **(Optional) install step**
   - Script assumes the user has already installed the app, but can provide an `--install` mode mirroring existing install commands if desired later.
4. **Navigate UI and save**
   - Wake/unlock if needed (reuse patterns from `scripts/run_ui_tests.sh` where possible).
   - Open `DevMenuPage`:
     - Launch app (bundle: `com.terryma.wordmagicgame`).
     - Perform triple-tap on version label to enter DevMenu (existing debug feature).
   - Tap `BypassSecret` button in header.
   - Fill `BypassSecretPageInput` with the secret.
   - Tap `BypassSecretPageSaveButton`.
   - Verify success (one of):
     - Return to DevMenu and the “Edit …” button appears, OR
     - A toast “Bypass secret saved” (if we keep that toast), OR
     - Input retains non-empty value on re-open.

Implementation note:

- Use `hdc shell uitest` commands (same toolchain already used in `scripts/run_ui_tests.sh`).
- Prefer selecting by component id (ids listed above) instead of coordinates.

## Versioning

- Update `AppScope/app.json5`:
  - Increment patch `versionName`: `0.6.0` → `0.6.1`
  - `versionCode`: leave unchanged unless project policy requires bump (not indicated by current docs).

## Testing strategy

- **ohosTest UI** (device/emulator):
  - Extend or add a small suite to:
    - Enter DevMenu (triple-tap) → tap `BypassSecret` → input text → save → ensure DevMenu reflects the saved state.
  - Keep tests stable via ids (no coordinate taps).
- Manual smoke:
  - Confirm Preview-card tap does not prompt when secret present.
  - Confirm prompt appears when secret cleared (optional).

## Risks / mitigations

- **UI automation flakiness** (timing, focus):
  - Use ids, add short delays after navigation, avoid coordinate clicks.
  - Keep script steps minimal and retry only idempotent steps (e.g., find component then click).
- **Secret leakage**:
  - Script must not print secret; redact in logs.
  - Input uses `Password` masking already in dialog; keep same in page.

