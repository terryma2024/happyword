#!/usr/bin/env python3
"""
Capture HarmonyOS WordMagicGame screenshots via hdc + uitest on a connected
device or emulator. Writes PNGs under assets/screenshots/harmonyos/.

Requires: hdc on PATH, unlocked device, debug build installed
(bundle com.terryma.wordmagicgame).

Usage:
  ./scripts/capture_harmony_screenshots.py
  HDC_TARGET=127.0.0.1:5555 ./scripts/capture_harmony_screenshots.py

Optional:
  HARMONY_INSTALL_HAP=1  — hdc install the freshly built signed HAP before capture
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "assets" / "screenshots" / "harmonyos"
BUNDLE = "com.terryma.wordmagicgame"
HAP_PATH = (
    REPO_ROOT
    / "harmonyos"
    / "entry"
    / "build"
    / "default"
    / "outputs"
    / "default"
    / "entry-default-signed.hap"
)
KNOWN_PIN = "123456"

BOUNDS_RE = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def hdc_base() -> list[str]:
    t = os.environ.get("HDC_TARGET", "").strip()
    return ["hdc", "-t", t] if t else ["hdc"]


def run_shell(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        hdc_base() + ["shell"] + cmd,
        capture_output=True,
        text=True,
        check=False,
    )


def hdc_file_recv(remote: str, local: Path) -> None:
    subprocess.run(
        hdc_base() + ["file", "recv", remote, str(local)],
        capture_output=True,
        check=True,
        text=True,
    )


def start_app() -> None:
    run_shell(
        ["aa", "start", "-a", "EntryAbility", "-b", BUNDLE],
        check=False,
    )


def dump_layout() -> dict:
    remote = "/data/local/tmp/hw_layout_dump.json"
    run_shell(["uitest", "dumpLayout", "-p", remote])
    local = Path("/tmp/hw_layout_dump.json")
    hdc_file_recv(remote, local)
    return json.loads(local.read_text(encoding="utf-8"))


def bounds_center(bounds: str) -> tuple[int, int]:
    m = BOUNDS_RE.match(bounds.strip())
    if not m:
        raise ValueError(f"bad bounds: {bounds}")
    l, t, r, b = map(int, m.groups())
    return (l + r) // 2, (t + b) // 2


def bounds_height(bounds: str) -> int:
    m = BOUNDS_RE.match(bounds.strip())
    if not m:
        return 0
    l, t, r, b = map(int, m.groups())
    return b - t


def scroll_until_uncovered(
    component_id: str,
    min_height_px: int = 96,
    max_swipes: int = 22,
) -> dict:
    """
    Scroll ConfigPage-like Scroll containers until `component_id` has at least
    `min_height_px` vertical bounds — taps on 20px-tall clipped buttons are ignored
    by the system (matches ConfigFlow scrollToParentPinButton rationale).
    """
    for _ in range(max_swipes):
        layout = dump_layout()
        attrs = find_attrs(layout, component_id)
        if attrs is not None:
            h = bounds_height(attrs.get("bounds") or "")
            if h >= min_height_px:
                return attrs
        swipe_up()
    raise RuntimeError(
        f"could not uncover component with sufficient height: {component_id}",
    )


def click_uncovered(component_id: str, pause: float = 0.45) -> None:
    attrs = scroll_until_uncovered(component_id)
    cx, cy = bounds_center(attrs.get("bounds") or "")
    run_shell(["uitest", "uiInput", "click", str(cx), str(cy)])
    time.sleep(pause)


def find_attrs(tree: object, target: str) -> dict | None:
    if isinstance(tree, dict):
        attrs = tree.get("attributes")
        if isinstance(attrs, dict):
            if attrs.get("id") == target or attrs.get("key") == target:
                return attrs
        for ch in tree.get("children") or []:
            hit = find_attrs(ch, target)
            if hit is not None:
                return hit
    elif isinstance(tree, list):
        for item in tree:
            hit = find_attrs(item, target)
            if hit is not None:
                return hit
    return None


def wait_for_component(component_id: str, timeout_s: float = 12.0) -> dict:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        attrs = find_attrs(dump_layout(), component_id)
        if attrs is not None:
            return attrs
        time.sleep(0.35)
    raise RuntimeError(f"timeout waiting for component: {component_id}")


def click_id(component_id: str, pause: float = 0.35, wait_timeout: float = 12.0) -> None:
    attrs = wait_for_component(component_id, timeout_s=wait_timeout)
    b = attrs.get("bounds") or ""
    cx, cy = bounds_center(b)
    run_shell(["uitest", "uiInput", "click", str(cx), str(cy)])
    time.sleep(pause)


def click_if_present(component_id: str, pause: float = 0.35) -> bool:
    try:
        click_id(component_id, pause=pause)
        return True
    except RuntimeError:
        return False


def press_back(pause: float = 0.45) -> None:
    run_shell(["uitest", "uiInput", "keyEvent", "Back"])
    time.sleep(pause)


def swipe_up(pause: float = 0.4) -> None:
    # Landscape viewport (matches ConfigFlow ui tests).
    run_shell(["uitest", "uiInput", "swipe", "1400", "1100", "1400", "300", "600"])
    time.sleep(pause)


def swipe_down(pause: float = 0.4) -> None:
    """Scroll content upward (reveal rows above the current viewport)."""
    run_shell(["uitest", "uiInput", "swipe", "1400", "300", "1400", "1100", "600"])
    time.sleep(pause)


def swipe_portrait_up(pause: float = 0.4) -> None:
    run_shell(["uitest", "uiInput", "swipe", "360", "1000", "360", "300", "600"])
    time.sleep(pause)


def triple_click_version_label() -> None:
    layout = dump_layout()
    attrs = find_attrs(layout, "HomeVersionLabel")
    if attrs is None:
        raise RuntimeError("HomeVersionLabel not found (debug build only)")
    cx, cy = bounds_center(attrs.get("bounds") or "")
    for _ in range(3):
        run_shell(["uitest", "uiInput", "click", str(cx), str(cy)])
        time.sleep(0.06)
    time.sleep(1.2)


def screen_capture(filename: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    remote = f"/data/local/tmp/{filename}"
    run_shell(["uitest", "screenCap", "-p", remote])
    local = OUT_DIR / filename
    hdc_file_recv(remote, local)
    return local


def scroll_capture_series(prefix: str, strips: int) -> list[Path]:
    """Viewport screenshot, then swipe up (landscape) between strips."""
    out: list[Path] = []
    for i in range(strips):
        name = f"{prefix}-part{i + 1}.png"
        out.append(screen_capture(name))
        if i + 1 < strips:
            swipe_up()
    return out


def scroll_capture_portrait_series(prefix: str, strips: int) -> list[Path]:
    out: list[Path] = []
    for i in range(strips):
        name = f"{prefix}-part{i + 1}.png"
        out.append(screen_capture(name))
        if i + 1 < strips:
            swipe_portrait_up()
    return out


def ensure_pin_if_possible() -> None:
    """Best-effort: set parent PIN to KNOWN_PIN when ParentPinSetupPage is reachable."""
    try:
        start_app()
        time.sleep(5.0)
        click_id("HomeConfigButton", pause=1.5, wait_timeout=25.0)
        click_uncovered("ConfigParentPinButton", pause=2.0)
        wait_for_component("ParentPinSetupTitle", timeout_s=15.0)
        for _ in range(4):
            if find_attrs(dump_layout(), "ParentPinSetupKeypad"):
                break
            swipe_up()
        for digit in KNOWN_PIN:
            click_id(f"ParentPinSetupKey_{digit}", pause=0.12)
        time.sleep(0.35)
        for digit in KNOWN_PIN:
            click_id(f"ParentPinSetupKey_{digit}", pause=0.12)
        time.sleep(1.5)
        for _ in range(3):
            if click_if_present("ConfigCancelButton", pause=0.8):
                break
            swipe_up()
        time.sleep(0.5)
        go_home_via_back()
    except Exception as exc:
        print(f"[warn] ensure_pin_if_possible: {exc}", file=sys.stderr)


def go_home_via_back(max_steps: int = 14) -> None:
    for _ in range(max_steps):
        layout = dump_layout()
        if find_attrs(layout, "HomeStartButton"):
            return
        press_back()
    raise RuntimeError("could not reach HomePage")


def tap_pin_dialog(pin: str) -> None:
    for ch in pin:
        click_id(f"ParentPinDialogKey_{ch}", pause=0.1)
    time.sleep(1.2)


def maybe_install_hap() -> None:
    if os.environ.get("HARMONY_INSTALL_HAP", "").strip() not in ("1", "true", "yes"):
        return
    if not HAP_PATH.is_file():
        print(f"[warn] HAP missing, skip install: {HAP_PATH}", file=sys.stderr)
        return
    subprocess.run(
        hdc_base() + ["install", str(HAP_PATH)],
        check=False,
        text=True,
    )


def main() -> int:
    maybe_install_hap()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Capturing HarmonyOS screenshots →", OUT_DIR)

    # Fresh launch
    start_app()
    time.sleep(2.5)

    steps: list[tuple[str, callable]] = []

    def shot_home() -> None:
        screen_capture("home.png")

    def shot_battle_result() -> None:
        click_id("HomeStartButton", pause=1.6)
        screen_capture("battle.png")
        click_id("BattleFinishButton", pause=0.9)
        screen_capture("result.png")
        click_id("ResultHomeButton", pause=1.0)

    def shot_codex() -> None:
        click_id("HomeCodexButton", pause=1.0)
        screen_capture("monster-codex-part1.png")
        click_if_present("CodexNext", pause=0.8)
        screen_capture("monster-codex-part2.png")
        click_id("CodexBackButton", pause=0.9)

    def shot_today_and_report() -> None:
        click_id("HomePlanButton", pause=1.0)
        screen_capture("today-plan.png")
        click_id("TodayPlanReportButton", pause=1.2)
        scroll_capture_series("learning-report", 2)
        press_back()
        time.sleep(0.6)
        click_id("TodayPlanBackButton", pause=0.9)

    def shot_wishlist_history() -> None:
        click_id("HomeWishlistButton", pause=1.0)
        screen_capture("wishlist.png")
        click_id("WishlistHistoryButton", pause=1.0)
        screen_capture("redemption-history.png")
        click_id("RedemptionHistoryBackButton", pause=0.9)
        click_id("WishlistBackButton", pause=0.9)

    def shot_config_and_pack() -> None:
        click_id("HomeConfigButton", pause=1.5)
        scroll_capture_series("config", 4)
        # Long config Scroll: after repeated swipe_up we sit near the bottom;
        # PackManager entry lives mid-page — scroll back up before hunting the row.
        for _ in range(10):
            swipe_down()
        click_uncovered("ConfigPackManagerEntry", pause=1.2)
        screen_capture("pack-manager.png")
        click_id("PackManagerBack", pause=1.0)
        # Leave config — swipe to bottom area for cancel if needed
        for _ in range(4):
            if click_if_present("ConfigCancelButton", pause=0.7):
                break
            swipe_up()

    def shot_parent_pin_surface() -> None:
        click_id("HomeConfigButton", pause=1.5)
        click_uncovered("ConfigParentPinButton", pause=2.0)
        wait_for_component("ParentPinSetupTitle", timeout_s=18.0)
        for _ in range(4):
            if find_attrs(dump_layout(), "ParentPinSetupKeypad"):
                break
            swipe_up()
        screen_capture("parent-pin-setup.png")
        click_if_present("ParentPinSetupCancel", pause=1.2)
        for _ in range(3):
            if click_if_present("ConfigCancelButton", pause=0.7):
                break
            swipe_up()

    def shot_scan_binding() -> None:
        click_id("HomeConfigButton", pause=1.5)
        try:
            click_uncovered("ConfigBindParentButton", pause=1.2)
        except RuntimeError:
            print(
                "[info] ConfigBindParentButton not shown (device already bound) — skip scan-binding.png",
                file=sys.stderr,
            )
            for _ in range(4):
                if click_if_present("ConfigCancelButton", pause=0.7):
                    break
                swipe_up()
            return
        screen_capture("scan-binding.png")
        click_id("ScanBindingTopBack", pause=1.0)
        for _ in range(4):
            if click_if_present("ConfigCancelButton", pause=0.7):
                break
            swipe_up()

    def shot_parent_admin() -> None:
        click_id("HomeConfigButton", pause=1.5)
        click_uncovered("ConfigParentAdminButton", pause=1.2)
        time.sleep(0.8)
        layout = dump_layout()
        if find_attrs(layout, "ParentPinDialog"):
            tap_pin_dialog(KNOWN_PIN)
        elif find_attrs(layout, "ParentPinSetupTitle"):
            print(
                "[warn] Parent PIN not set — skipping ParentAdmin screenshots",
                file=sys.stderr,
            )
            press_back()
            for _ in range(4):
                if click_if_present("ConfigCancelButton", pause=0.7):
                    break
                swipe_up()
            return
        try:
            wait_for_component("ParentAdminTitle", timeout_s=20.0)
        except Exception as exc:
            print(
                f"[warn] ParentAdmin did not open (wrong PIN?). {exc}",
                file=sys.stderr,
            )
            go_home_via_back()
            return
        time.sleep(0.8)
        scroll_capture_portrait_series("parent-admin", 4)
        go_home_via_back()

    def shot_bound_device_if_any() -> None:
        click_id("HomeConfigButton", pause=1.5)
        try:
            click_uncovered("ConfigBoundDeviceInfoButton", pause=1.2)
        except RuntimeError:
            press_back()
            return
        screen_capture("bound-device-info.png")
        press_back()
        for _ in range(4):
            if click_if_present("ConfigCancelButton", pause=0.7):
                break
            swipe_up()

    def shot_dev_menu_and_bypass() -> None:
        go_home_via_back()
        triple_click_version_label()
        screen_capture("dev-menu.png")
        if click_if_present("DevMenuBypassSecretButton", pause=1.0):
            screen_capture("bypass-secret.png")
            click_if_present("BypassSecretPageCancelButton", pause=0.8)
        press_back()

    runners = [
        ("home", shot_home),
        ("battle+result", shot_battle_result),
        ("monster codex", shot_codex),
        ("today plan + learning report", shot_today_and_report),
        ("wishlist + redemption history", shot_wishlist_history),
        ("config + pack manager", shot_config_and_pack),
        ("parent pin setup surface", shot_parent_pin_surface),
        ("scan binding", shot_scan_binding),
        ("parent admin", shot_parent_admin),
        ("bound device info (if bound)", shot_bound_device_if_any),
        ("dev menu + bypass secret", shot_dev_menu_and_bypass),
    ]

    ensure_pin_if_possible()
    start_app()
    time.sleep(2.0)

    for label, fn in runners:
        try:
            print(f"… {label}")
            fn()
            go_home_via_back()
            start_app()
            time.sleep(1.2)
        except Exception as exc:
            print(f"[error] step '{label}': {exc}", file=sys.stderr)
            try:
                go_home_via_back()
            except Exception:
                start_app()
                time.sleep(2.0)

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
