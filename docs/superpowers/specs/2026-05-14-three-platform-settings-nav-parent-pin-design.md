# Three-platform settings navigation and parent-PIN policy

**Date:** 2026-05-14  
**Status:** Approved for implementation (clarifications merged)  
**Scope:** HarmonyOS, iOS, Android — unified UX and behavior.

## Summary

Introduce a **shared top chrome** per platform (circular back chevron top-left, optional actions top-right). Rework **settings/config** into two sections with **immediate persistence** (no Cancel/Save). Tighten **parent-PIN** usage: redemption without PIN; add/remove custom wishes with PIN and hidden when PIN unset; unbind confirmation and parent admin entry still PIN-gated. After **successful parent binding**, automatically prompt **parent PIN setup**; **parent admin** entry is hidden until a 6-digit PIN exists.

## 1. Shared navigation chrome (per platform)

- **Leading:** Circular control, **left arrow only** (no “返回” or “Back” label). Tap pops the current screen (`router.back` / dismiss / `popBackStack`).
- **Trailing:** Reserved for page-specific actions (e.g. Save on screens that still need explicit commit — **not** config after this change).
- **Implementation:** One reusable component (or composable pattern) per codebase so new pages default to the same bar.

**Rollout:** All full-screen product pages that currently show a text back button or ad-hoc top row should migrate to this chrome (Harmony `pages/*.ets`, iOS SwiftUI feature roots, Android composable screens).

## 2. Config / settings page

### 2.1 Persistence

- Remove **取消** and **保存**.
- Every change to game fields updates the canonical `GameConfig` (same merge as today’s save path: `AppStorage` + disk persistence). Leaving the page does not “revert” unsaved work because there is no draft-only mode.

### 2.2 Layout — upper section: 游戏配置

Section title **游戏配置**. Rows in this **exact order**:

1. 玩家血量  
2. 怪物血量  
3. 怪物数量  
4. 倒计时  
5. 发音播放  
6. **题型选择** (`enabledQuestionTypes`; label stays 题型选择 — “提醒选择” was a typo)  
7. 我的词包 (entry to pack manager)

### 2.3 Layout — lower section: 家长配置

Section title **家长配置**. When the device **is bound** to a parent account, rows in this **exact order**:

1. 家长账号  
2. 家长密码  
3. 学习记录 (cloud sync row)  
4. 管理后台  

When **not bound**, show **only** the 家长账号 row (bind / scan entry). **Do not show** 家长密码, 学习记录, or 管理后台.

### 2.4 Top chrome on config

- Leading: circular back.
- Trailing: empty unless a future explicit action is required (none for config).

## 3. Parent PIN policy matrix

| Flow | Parent PIN |
|------|------------|
| **礼品 / 申请兑换** (redeem wish) | **Not required** |
| **添加自定义愿望** | **Required**; open PIN dialog on confirm path |
| **删除自定义愿望** | **Required**; open PIN dialog on confirm path |
| **添加 / 删除自定义** when PIN **not** set (length ≠ 6) | **Do not show** UI affordances for add/remove custom (same as “feature not available until PIN configured”) |
| **解除设备绑定** (unbind) | **Required** (confirmation gate) |
| **进入管理后台** | **Required** |

Harmony reference today: `WishlistPage` uses `PinIntent` for redeem / add-custom / remove-custom — redeem drops PIN; add/remove keep PIN and are gated on PIN presence.

## 4. Post-binding and admin visibility

- After **binding succeeds** (e.g. `ScanBindingPage` reaches bound / completion callback), **automatically** navigate to **parent PIN setup** (same as `ParentPinSetupPage` flow).
- **管理后台** row: visible only when **bound** **and** parent PIN is **configured** (6 digits). If PIN missing after bind, user is steered by the auto setup flow; until PIN exists, admin entry **must not** appear.

## 5. Platform execution order

1. **HarmonyOS** — implement chrome + config + wishlist + binding flow; update `ohosTest` and any layout IDs that tests assert on (e.g. removal of Config Save/Cancel buttons).
2. **iOS** — replicate in `ConfigView`, binding stack, wishlist feature parity.
3. **Android** — replicate in matching composables; update instrumented tests (e.g. config visibility, flows).

## 6. Out of scope

- Changing server-side auth for admin (local PIN gate remains as today).
- Redesigning pack manager or battle UI beyond adopting the shared top chrome where applicable.

## 7. Clarifications log (2026-05-14)

- User: Add/remove custom wishes **still** require parent PIN; if PIN not set, **hide** add/remove custom affordances.
- User: Prefer **shared chrome component per platform**.
- User: Game section row is **题型选择**, not “提醒选择”.
