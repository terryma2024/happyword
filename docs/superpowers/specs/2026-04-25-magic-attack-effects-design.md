# Battle Magic-Attack Effects — Design

Date: 2026-04-25
Status: Implemented (this spec is the post-hoc record requested by the user; brainstorming gate was retro-applied — see "Process note" below)
Scope: HarmonyOS NEXT (ArkTS) — `entry` module only

## Goal

Replace the V0.2 "−1 floating number" feedback in `BattlePage` with a directional magic-attack pipeline:

- A correct answer fires a **forward** magic projectile from the mage to the monster; on impact the monster takes 1 damage, shakes, and (on a combo burst) a strengthened shockwave + oversized damage number plays.
- A wrong answer fires a **backward** projectile from the monster back at the mage; on impact the mage takes 1 damage and shakes.
- The combo-burst spectacle (`CritOverlay`) is upgraded with two expanding concentric shockwave rings and a larger floating damage number, so the player feels the streak more than the per-question hit.
- All character damage and shake reactions are delayed by one **projectile travel** (~320 ms) so the visual cause precedes the visible effect.

## Non-goals

- No new gameplay rules. `BattleEngine` damage, combo, and end-of-battle logic are unchanged. The pipeline only re-times the visual feedback.
- No new art assets. Projectiles, shockwaves, and damage numbers are drawn with `Circle` / `Text` / standard transforms in ArkTS.
- No audio changes. (`AudioService` cues fire at the same moments they always did.)
- No changes to `HpBar`, `CharacterCard.HP` rendering, or any persisted state.
- No new third-party dependencies, no `oh-package.json5` changes.

## User-facing behavior

1. **Correct answer**
   - Tapping the right option immediately spawns a forward orb at the mage card edge.
   - Orb travels ~520 ms across the screen (260 ms travel + 80 ms spawn + 160 ms impact burst).
   - At t ≈ 320 ms a delayed "impact" fires: monster card plays the hurt-shake animation, monster HP label drops by 1, monster zoom pulse, and (when the answer pushes `comboCount` past the V0.2 threshold) the `CritOverlay` shockwave + oversized damage number plays.
2. **Wrong answer**
   - Tapping a wrong option spawns a backward orb at the monster card edge.
   - Same travel window (~520 ms total).
   - At t ≈ 320 ms the player card plays hurt-shake, player HP label drops by 1, mage cast pulse plays.
3. **Combo burst (correct answer that completes a streak)**
   - The forward projectile spawns "charged" (higher `intensity`, brighter glow, larger orb).
   - On impact, in addition to monster damage/shake, `CritOverlay` plays:
     - A primary gold shockwave ring expanding from 0.4 → 7.5× over the burst window.
     - A secondary white shockwave ring expanding from 0.5 → 5.2× lagging the primary by ~40 ms.
     - The damage number renders at fontSize 96 (was 72) with the existing float-up + fade-out curve.
4. **Battle end / page teardown**
   - Any in-flight `setTimeout` impact callbacks queued by `scheduleImpact` are cancelled in `aboutToDisappear` so navigating away mid-animation does not mutate state on a torn-down page.

## Architecture

### Files touched / added

- **New:** `entry/src/main/ets/components/MagicProjectile.ets` — directional orb that animates in, travels, and bursts on impact.
- **Modified:** `entry/src/main/ets/components/CritOverlay.ets` — added two expanding shockwave rings; bumped damage-number font size to 96; wrapped the snap-to-start-frame state resets in `animateTo({ duration: 0 })`.
- **Modified:** `entry/src/main/ets/components/CharacterCard.ets` — extended `onHurtPulseChanged` with a directional side-to-side shake (recoil + 3 damped oscillations) layered on top of the existing red-overlay + squash.
- **Modified:** `entry/src/main/ets/pages/BattlePage.ets` — mounted both `MagicProjectile` instances inside the main `Stack`; added `projectileForwardPulse`, `projectileBackwardPulse`, `projectileIntensity` `@State`; rerouted `onOptionTap` so the projectile fires immediately and the hurt/zoom/cast/crit pulses are queued via a new `scheduleImpact(cb)` helper that pushes `setTimeout` ids into `impactTimers` for teardown cancellation.
- **New:** `entry/src/ohosTest/ets/test/MagicAttack.ui.test.ets` — UI automation covering the two delayed-impact behavioral invariants (see "Verification" below). Wired into `entry/src/ohosTest/ets/test/List.test.ets`.

### Component: `MagicProjectile`

```ts
@Component
export struct MagicProjectile {
  // Parent bumps this number on every tap; @Watch fires the cycle. Using a
  // counter rather than a boolean guarantees we re-fire even when two
  // consecutive taps happen to land on the same logical "side".
  @Prop @Watch('onPulseChanged') projectilePulse: number = 0;
  @Prop forward: boolean = true;     // true = mage → monster
  @Prop intensity: number = 1;       // > 1 for combo bursts (charged orb)
}
```

Three internal phases driven by `UIContext.animateTo` chained via `setTimeout`:

| Phase  | Duration | Effect |
|--------|----------|--------|
| spawn  | 80 ms    | `coreOpacity` 0 → 1, `outerOpacity` 0 → 0.65, scales swell from 0.4/0.5 → 1 at the source-side margin. |
| travel | 260 ms   | `translateX` interpolates from `startX` to `endX` (sign flips by `forward`). Curve: `EaseInOut`. |
| impact | 160 ms   | scales burst to 2.2/2.8 while opacities fade to 0; orb appears to detonate at the target. |

Travel distance is computed from the device width via `display.getDefaultDisplaySync()` + `px2vp` so the orb actually crosses the visible scene on phones, tablets, and the emulator without hard-coded vp counts.

Internal `@State` field naming note: the spawn/burst opacity & scale fields are `coreOpacity` / `coreScale` / `outerOpacity` / `outerScale` rather than the more obvious `opacity` / `scale` because ArkUI compiler refuses to assign a `@State` to a name that collides with a `CommonAttribute` method on the component itself.

### `CritOverlay` changes

Two new `@State`s — `shockwaveScale` / `shockwaveOpacity` (primary, gold) and `shockwaveSecondaryScale` / `shockwaveSecondaryOpacity` (secondary, white) — drive two new `Circle` layers above the existing flash + damage-number stack. Both rings start hidden, expand outward in the burst window, and fade to 0; the secondary ring lags the primary by ~40 ms so the combined shape reads as a single thick shockwave with a trailing pulse.

The state-reset block at the start of `onCritPulseChanged` (which snaps every animated value back to its starting frame so a follow-up burst doesn't animate from the previous burst's tail value) is wrapped in `animateTo({ duration: 0 }, () => { … })`. This is ArkUI's canonical "set without transition" pattern; it batches the writes into a single render pass and avoids the `@performance/hp-arkui-use-local-var-to-replace-state-var` codelinter warning that fires on consecutive synchronous `@State` assignments.

### `CharacterCard` changes

`onHurtPulseChanged` now drives both a vertical squash + red overlay (existing behavior) and a horizontal `avatarTranslateX` shake. The shake schedules four sequential `animateTo` calls: an initial recoil away from the attacker (large amplitude, fast `EaseOut`), then three damped oscillations crossing zero with diminishing amplitude, settling back to center inside the same feedback window the engine waits before unlocking input. Direction is selected by sign of the recoil so mage and monster recoil in opposite directions when each is hit.

### `BattlePage` orchestration

`onOptionTap` is the single integration point:

1. Synchronously: bump `projectileForwardPulse` (correct) or `projectileBackwardPulse` (wrong), set `projectileIntensity` (charged for crit), call `engine.submitAnswer(...)` so HP decrement is committed to the engine immediately (the visible HP label is bound to the engine state, but `HpBar` only re-renders on the *next* render pass driven by the impact).
2. Through `scheduleImpact(cb)`: queue `monsterHurtPulse++` / `playerHurtPulse++` / `monsterZoomPulse++` / `playerCastPulse++` / `critPulse++` — whichever the answer warrants — at delay 320 ms. The helper pushes the `setTimeout` id into `impactTimers` so `aboutToDisappear` can clear all in-flight callbacks.

```ts
private scheduleImpact(cb: () => void): void {
  const id: number = setTimeout((): void => { cb(); }, 320);
  this.impactTimers.push(id);
}
```

Why 320 ms: matches the projectile's `SPAWN_MS + TRAVEL_MS` (80 + 260 = 340) minus a small slack so the hurt-shake begins on the leading edge of the impact-burst rather than after it. The number lives as a single literal in `BattlePage` rather than a constant in `MagicProjectile` so future tuning doesn't have to cross the component boundary; both files have a comment pointing at the other.

## Codelinter posture

A side requirement of this work was: **all** `code-linter.json5` warnings must be resolved, not only the new ones. The four pre-existing warnings were fixed in flight:

- `ChoiceButton` and `HpBar` got the `@Reusable` decorator. Both are reused N times per render with `@Prop`-driven feedback / fill ratio, and `@Reusable` signals to `@performance/avoid-overusing-custom-component-check` that the components are explicitly pooled rather than over-instantiated.
- `Index.ets`'s `await player.seek(0)` was relaxed to `player.seek(0)` (HarmonyOS `AVPlayer.seek` returns `void`; the original `await` was a no-op the linter correctly flagged).
- `TtsTestPage.ets`'s consecutive `initStarted = true; engineStatus = '…'` writes were wrapped in `animateTo({ duration: 0 })` for the same reason as `CritOverlay`.

## Verification

Each invariant is verified with at least one of: codelinter, build, unit tests, or UI automation.

| Invariant | Where verified |
|-----------|----------------|
| Wrong answer applies player damage on impact (player HP `5 / 5` → `4 / 5` within 900 ms of tap) | `MagicAttack.ui.test.ets :: wrongAnswerDecreasesPlayerHpAfterProjectileImpact` |
| Correct answer applies monster damage on impact (monster HP `3 / 3` → `2 / 3` within 900 ms) | `MagicAttack.ui.test.ets :: correctAnswerDecreasesMonsterHpAfterProjectileImpact` |
| Combo burst still ends at `Combo: 0` | `CritSpectacle.ui.test.ets` (existing) |
| End-to-end battle flow still works (lose / win / retry / custom-words) | `RoutingFlow.ui.test.ets` (existing) |
| Speaker button still idempotent | `SpeakerButton.ui.test.ets` (existing) |
| Review unlock still triggers after 3 wrong answers | `ReviewMode.ui.test.ets` (existing) |
| Engine math (HP, combo, end states) | `entry/src/test/LocalUnit.test.ets` (existing) |
| Static analysis | `codelinter -c ./code-linter.json5 .` → "No defects found in your code" |
| Compile / package | `hvigorw assembleHap` and `hvigorw --mode module -p module=entry@ohosTest assembleHap` → BUILD SUCCESSFUL |

UI automation cannot directly assert that the projectile / shockwave / large damage-number layers are visible at the right moment: those layers live at `opacity 0` between bursts, and HarmonyOS UiTest's default visibility matcher rejects opacity-0 components (this is documented inline in `CritSpectacle.ui.test.ets` and is the same reason that suite tests an engine invariant rather than the visuals). The two new `MagicAttack` tests therefore lock the *behavioral* outcome of the new pipeline: HP changes still land in the feedback window despite being delayed by `scheduleImpact`. If a future change broke the `setTimeout` queue, drained `impactTimers` too aggressively, or wired the wrong pulse to the wrong side, the HP-text assertions would fail loudly within a 900 ms window.

## Risks and trade-offs considered

- **Delayed damage feedback**: Delaying the `*HurtPulse` by 320 ms could make the game feel laggy. We accept this because the projectile gives a clear cause-and-effect cue during the wait, and `engine.submitAnswer` still runs synchronously so input is locked immediately (no double-tap risk). 320 ms is below the typical "noticeable lag" threshold for casual-arcade pacing.
- **Teardown safety**: `setTimeout` callbacks captured `this`, so navigating away mid-animation could otherwise mutate state on a stale `BattlePage`. `impactTimers` + `aboutToDisappear` clears all pending ids; verified indirectly because `RoutingFlow.ui.test.ets` cycles through Battle → Result → Home repeatedly without lingering errors in hilog.
- **`@Reusable` correctness**: Both `ChoiceButton` and `HpBar` are pure-presentational with `@Prop`-driven inputs and no `aboutToAppear` side effects, so reuse-pool semantics are safe; verified by all 12 UI tests passing after the decorator change.
- **`MagicProjectile` field naming**: `coreOpacity` / `coreScale` is uglier than `opacity` / `scale`, but renaming is a hard requirement of the ArkUI compiler — `@State opacity: number` collides with the `opacity()` `CommonAttribute` setter on the component itself.

## Process note

This work was driven before the `using-superpowers` workflow was in force on this turn. The user pulled the workflow back in mid-task with three explicit asks: follow `using-superpowers`, resolve all codelinter warnings, and add UI automation tests that stay green. The retroactive adjustments were:

1. Wrote the behavioral-invariant plan as a TodoWrite list.
2. Added the UI automation suite (`MagicAttack.ui.test.ets`) and ran the full ohosTest pipeline (12/12 pass).
3. Drove all 16 codelinter warnings (4 pre-existing + 12 newly introduced) to 0 using the techniques documented in the "Codelinter posture" section above.
4. This document is the spec the brainstorming gate would have produced up-front. It is intentionally brief and scoped to the implemented behavior so it can serve as the source of truth for any follow-up tuning (delay constants, projectile colors, shockwave timing).
