# parity_scout — config leaf

- **run-id:** `20260514-000551-pages-config`
- **scope:** `pages:config`
- **baseline:** used `--allow-dirty-baseline` (worktree not on `main`; gaps below are still useful for UI parity, not for “vs main” sign-off).

## Environment

- **[ios] critical:** `simctl` failed — CoreSimulatorService / simdiskimaged connection refused (see `config/ios/CAPTURE_FAILED.txt`). **No iOS PNG** in this run; re-run `scout.py run` on a Mac with a healthy Xcode Simulator outside sandbox/CI.
- **[harmony] ok:** Multiple scroll parts under `config/harmony/*.png`.
- **[android] ok:** `config/android/config-landscape.png`.

## Config page — Harmony vs Android (vision, no spec excerpt)

Scope was `--pages` only → `spec-excerpts.md` is placeholder; anchors from registry: `HomeConfigButton`, `ConfigParentPinButton`, `ConfigParentAdminButton`, sections Config / 游戏设置.

- **[harmony|android] notable — copy / IA:** Harmony title reads **「游戏设置」** (centered header style in part1); Android screenshot title reads **「设置」** with **「返回首页」** top-right. Same feature bucket but **different primary label and chrome** vs baseline.
- **[harmony|android] notable — layout system:** Harmony uses **flat rows** (label + inline steppers / pill chips for 倒计时 / 发音播放 / 我的词包). Android uses **stacked white cards** on cream background for the same numeric rows. Expect **spacing, hierarchy, and tap targets** to differ from Harmony baseline even when values match.
- **[harmony|android] notable — vertical coverage:** Harmony capture includes **倒计时、发音播放、我的词包** and (in later scroll parts) parent / cloud rows. Android artifact is a **single full-screen `config-landscape.png`** that in this run shows mainly **玩家血量 / 怪物血量 / 怪物数量** — other sections may be off-screen or not included in this one frame. Treat as **capture parity risk**: Android may need an additional scroll capture or a dedicated route for full config parity.
- **[ios] blocked this run:** Cannot compare iOS visuals until Simulator works.

## Follow-up (human)

1. Fix local Simulator (`killall Simulator` / reboot / Xcode repair), then:

   `python3 tools/parity_scout/scout.py run --run 20260514-000551-pages-config --allow-dirty-baseline`

   (or new `plan` + `pick` + `run` on `main` without `--allow-dirty-baseline` for sign-off.)

2. Optionally re-plan with `--spec docs/features/<id>/00-design.md` so `spec-excerpts.md` is non-empty and gaps are spec-anchored.
