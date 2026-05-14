# Wishlist page — parity scout findings

**run-id:** `20260514-091648-pages-wishlist`  
**scope:** `pages:wishlist` (no `--spec` → `wishlist/spec-excerpts.md` is placeholder)  
**baseline SHA:** see `baseline.txt` (branch was `feat/shared-parity-scout`, `run` used `--allow-dirty-baseline`)

## Evidence layout

- `wishlist/harmony/wishlist.png` — primary wishlist viewport (Harmony also produced `redemption-history.png` from the shared `wishlist+redemption` capture step; treat as sibling screen, not the wishlist leaf’s main tile).
- `wishlist/ios/wishlist.png`
- `wishlist/android/wishlist.png`

## Summary

Harmony and iOS both present **「魔法愿望单」** with **earn-toward-goal** rows (魔法币、还差 N ✨). Android presents **「愿望」** with a **different IA** (历史 / 返回, balance **28**, **兑换** buttons) and a **different reward catalog** — this reads as **product or mock-data surface drift**, not a minor skin tweak. Treat as **critical** until confirmed intentional (e.g. Android placeholder catalog vs aligned fixture).

## Gaps (by severity)

### Critical — Android vs Harmony / iOS

- **[android|harmony|ios] critical — page identity:** Android title **「愿望」** vs Harmony/iOS **「魔法愿望单」**. Registry anchors expect wishlist semantics (`HomeWishlistButton`, `WishlistHistoryButton`, section Wishlist / 魔法愿望单).
- **[android|harmony|ios] critical — interaction model:** Android rows use primary **「兑换」** (redeem-now) pink CTAs. Harmony/iOS use **progress copy** (**还差 N ✨**) toward a goal — **behavioral paradigm mismatch**.
- **[android|harmony|ios] critical — catalog / copy:** Harmony/iOS list **看 iPad 20 分钟 / 手表零钱充值 / 买一个礼物** style items. Android lists **贴纸 / 睡前故事 / 公园时间** — **no overlapping user-facing strings** in this capture; cannot claim parity until the same fixture or backend slice drives all three.

### Notable — iOS vs Harmony

- **[ios|harmony] notable — chrome:** Harmony shows **「+ 添加」** and a compact header cluster; iOS shows **「添加愿望」** and **「我的魔法币: 0」** vs Harmony **「我的魔法币: 1 ✨」** — **balance and adornment differ** (may be reset state / timing; still flag for deterministic UITest fixtures).
- **[ios|harmony] notable — list coverage:** Harmony viewport shows **three** wish rows including gift item; iOS capture shows **two** cards in frame — verify **scroll / route** lands on the same default list ordering and count.

### Nit — layout polish

- **[ios|harmony] nit:** Landscape framing vs Dynamic Island / safe area may crop header differently; compare padding after catalog alignment is fixed.

## Follow-ups

1. **Align Android wishlist route** with the same data + strings as Harmony `WishlistPage.ets` (or document intentional Android simplification in design + `page_suite_map` `feature_absent` if it is a different feature).
2. **Stabilize UITest fixtures** so 魔法币 counts match across simulators when doing visual diff.
3. Re-run with `plan --feature docs/features/<wishlist-feature-id>` (or `--spec …`) so `spec-excerpts.md` is populated and gaps are spec-anchored.
4. Optional: split Harmony capture so the wishlist leaf only pulls `wishlist.png` without bundling `redemption-history.png` into the same leaf dir (registry or script tweak — product decision).
