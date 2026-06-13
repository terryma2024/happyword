// Pure sizing math for character sprites. Free of `cc` imports so vitest can
// exercise it (cc-side files under assets/scripts are not importable by the
// test runner — same split as resolutionPolicy.ts).

export interface ContentSize {
    width: number;
    height: number;
}

/// Size a (possibly trimmed) sprite frame to fit inside fitWidth x fitHeight
/// while preserving the TRUE visible-content aspect ratio. `raw*` is the
/// original (untrimmed) frame size; `trim*` is the visible (trimmed) content
/// rect. The content is scaled by the full-frame fit scale so it occupies the
/// same fraction of the box as native scaledToFit on the full square art.
/// Degrades to the full box when the frame is untrimmed (trim* === raw*).
export function fitTrimmedContentSize(
    rawWidth: number, rawHeight: number,
    trimWidth: number, trimHeight: number,
    fitWidth: number, fitHeight: number,
): ContentSize {
    const fullScale = Math.min(fitWidth / rawWidth, fitHeight / rawHeight);
    return { width: trimWidth * fullScale, height: trimHeight * fullScale };
}
