// Adaptive resolution policy for the shared Cocos battle scene.
// Pure TS — no `cc` imports; the cc component (BattleSceneController) calls
// these helpers and applies the resulting policy + offset via cc APIs.
//
// ## Policy math
//
// Design resolution: 1565×720, aspect ratio ≈ 2.174 (iPhone 16 Pro landscape).
//
// FIXED_HEIGHT pins the design HEIGHT to the physical height:
//   visibleWidth  = designWidth  (or wider on taller-than-design screens)
//   visibleHeight = designHeight (always 720 in design space)
//   → correct for wide phones; left/right content is visible or naturally wider.
//
// FIXED_WIDTH pins the design WIDTH to the physical width:
//   visibleWidth  = designWidth  (always 1565 in design space)
//   visibleHeight = designWidth × (screenH / screenW)  — taller than 720 on 3:2
//   → correct for squarish tablets; top/bottom edges extend in design space.
//
// Rule: if screenAspect < designAspect (squarish screen) → FIXED_WIDTH,
//       otherwise                                         → FIXED_HEIGHT.
// Exact design aspect is treated as FIXED_HEIGHT (≥ comparison).
//
// ## topStatusOffsetY math
//
// Under FIXED_HEIGHT the top of the visible area is always at +360 (designHeight/2)
// in design space, and the status bar sits at layout.topStatusY = 308, which is
// 52 units below the visible top — correct.
//
// Under FIXED_WIDTH the visible height in design space becomes:
//   visibleH = designWidth × (screenH / screenW)
// which is > 720 on squarish screens. The visible top edge is at +visibleH/2.
// The status bar must stay ~52 units below the VISIBLE top, so its Y must
// become:  visibleH/2 - 52  (= designHeight/2 - 52 + extraH/2)
//
// The offset added to layout.topStatusY (308) is:
//   offset = (visibleH - designHeight) / 2  =  (designWidth × screenH/screenW - designHeight) / 2
//
// This offset is > 0 (moves node upward since Y grows upward in Cocos).

export type ResolutionPolicyChoice = 'fixedHeight' | 'fixedWidth';

/**
 * Choose the optimal Cocos resolution policy for the given screen and design.
 *
 * @param screenW  Physical screen width in pixels (e.g. screen.windowSize.width).
 * @param screenH  Physical screen height in pixels.
 * @param designW  Design resolution width (layout.designWidth = 1565).
 * @param designH  Design resolution height (layout.designHeight = 720).
 * @returns 'fixedHeight' when the screen is at least as wide as the design aspect,
 *          'fixedWidth'  when the screen is squarish / portrait-ish relative to
 *          the design aspect.
 */
export function choosePolicy(
    screenW: number,
    screenH: number,
    designW: number,
    designH: number,
): ResolutionPolicyChoice {
    // Aspect ratios: larger value = wider screen.
    // screenW/screenH >= designW/designH  →  wide enough → FIXED_HEIGHT
    // Cross-multiply to avoid floating-point division issues.
    return screenW * designH >= designW * screenH ? 'fixedHeight' : 'fixedWidth';
}

/** Combined policy decision — what BattleSceneController applies on load AND
 * on every window resize (e.g. HarmonyOS freeform window maximised, or the
 * surface growing once safe-area expansion takes effect). Recomputing from
 * the CURRENT window size is what keeps the top bar hugging the visible top
 * edge instead of overshooting it with a stale offset. */
export function resolvePolicyAndOffset(
    screenW: number,
    screenH: number,
    designW: number,
    designH: number,
): { policy: ResolutionPolicyChoice; topOffsetY: number } {
    const policy = choosePolicy(screenW, screenH, designW, designH);
    return { policy, topOffsetY: topStatusOffsetY(policy, screenW, screenH, designW, designH) };
}

/**
 * Y-offset (in design-space units, positive = up) to add to the base
 * `layout.topStatusY` constant so the status bar always hugs the visible
 * top edge regardless of the resolution policy.
 *
 * @param policy   The policy chosen by `choosePolicy`.
 * @param screenW  Physical screen width.
 * @param screenH  Physical screen height.
 * @param designW  Design resolution width.
 * @param designH  Design resolution height.
 * @returns 0 under fixedHeight (no adjustment needed).
 *          Positive delta under fixedWidth — half the extra visible height
 *          that exceeds the design height.
 */
export function topStatusOffsetY(
    policy: ResolutionPolicyChoice,
    screenW: number,
    screenH: number,
    designW: number,
    designH: number,
): number {
    if (policy === 'fixedHeight') {
        return 0;
    }
    // Under FIXED_WIDTH: visibleHeight in design space = designW * (screenH / screenW).
    const visibleH = designW * (screenH / screenW);
    return (visibleH - designH) / 2;
}
