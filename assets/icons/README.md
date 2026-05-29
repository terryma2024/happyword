# assets/icons — design source for in-app raster icons

This folder holds the **original SVG design source** for the in-app icons.
The shipped icons under `entry/src/main/resources/rawfile/icons/*.png` are
pre-rasterized 96×96 derivatives (V0.5 follow-up) — the SVGs themselves are
no longer packaged in the HAP because complex SVGs (~120 paths, 50–140 KB
each) caused intermittent placeholder flashes on `Image` remount.

## Files

| File          | Used by                     | Notes                                                |
| ------------- | --------------------------- | ---------------------------------------------------- |
| `codex.svg`   | HomePage `HomeCodexButton`  | Restored from commit `f6c87f3^`.                     |
| `gear.svg`    | HomePage `HomeConfigButton` | Restored from commit `f6c87f3^`.                     |
| `review.svg`  | HomePage `HomeReviewButton` | Restored from commit `f6c87f3^`.                     |
| `wishlist.svg`| HomePage `HomeWishlistButton` | Regenerated with Recraft V4 Vector on 2026-05-18; transparent background. |
| `spellbook.svg` | HomePage `HomeSpellbookButton` | Generated with Recraft V4 Vector on 2026-05-29; transparent background. |
| `scroll.svg`  | WishlistPage `WishlistHistoryButton` | Restored from commit `f6c87f3^`.            |
| `checkin.svg` | TodayPlanPage `TodayPlanCheckInButton` | Transparent-background check-in calendar source; rasterized to `rawfile/icons/checkin.png`. |
| `retired/wishlist-with-background-2026-05-18.svg` | Backup only | Previous wishlist icon source with off-white canvas background. |

## When to touch these

- **Re-rasterizing**: if a designer updates an SVG here, regenerate the
  matching PNG with the same dimensions used today (96×96, 3× density target):
  ```bash
  rsvg-convert -w 96 -h 96 -a assets/icons/<name>.svg \
    -o entry/src/main/resources/rawfile/icons/<name>.png
  ```
  Both the SVG (here) and the PNG (under `rawfile/`) should be committed.

- **New icons**: keep the design SVG here and ship the rasterized PNG under
  `rawfile/icons/`. Do not ship the SVG.

## Asset retention policy

Per `AGENTS.md` / `CLAUDE.md`: **do not delete resource files** when they
become unused at runtime. Move them under `assets/` (this directory tree)
instead so the design source stays available for re-rasterization, redesign,
or rollback.
