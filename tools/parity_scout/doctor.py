"""Preflight diagnostic for parity_scout.

Non-gating: prints status for each platform and the HarmonyOS baseline.
The SKILL is responsible for refusing runs when a required device is
unreachable. This command never exits non-zero on individual probe failures.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from parity_scout.registry import load_registry


def run_doctor(registry_path: Path) -> int:
    print("scout.py doctor")
    _probe(
        "hdc list targets",
        ["hdc", "list", "targets"],
        ok_predicate=lambda out: bool(out.strip()) and "[Empty]" not in out,
    )
    _probe(
        "xcrun simctl list devices",
        ["xcrun", "simctl", "list", "devices", "available"],
        ok_predicate=lambda out: "iPhone" in out,
    )
    adb = _adb_path()
    _probe(
        "adb devices",
        [adb, "devices"],
        ok_predicate=lambda out: "device" in out and "List of devices" in out,
    )
    _probe_baseline()
    try:
        reg = load_registry(registry_path)
        print(f"  ✓ registry valid ({len(reg.pages)} pages)")
    except FileNotFoundError:
        print(f"  ✗ registry: not found at {registry_path}")
    except Exception as exc:
        print(f"  ✗ registry: {exc}")
    return 0


def _adb_path() -> str:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk:
        candidate = Path(sdk) / "platform-tools" / "adb"
        if candidate.is_file():
            return str(candidate)
    return "adb"


def _probe(label, cmd, ok_predicate):
    try:
        out = subprocess.run(
            cmd, capture_output=True, text=True, timeout=10
        ).stdout
    except FileNotFoundError:
        print(f"  ✗ {label} → command not on PATH")
        return
    except Exception as exc:
        print(f"  ✗ {label} → {exc}")
        return
    print(f"  {'✓' if ok_predicate(out) else '✗'} {label}")


def _probe_baseline():
    try:
        head = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        sha = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        dirty = subprocess.run(
            [
                "git",
                "status",
                "--porcelain",
                "harmonyos/entry/src/main/ets",
            ],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        clean = "clean" if not dirty else "DIRTY"
        mark = "✓" if head == "main" and not dirty else "✗"
        print(f"  {mark} harmonyos baseline → {head} @ {sha} {clean}")
    except Exception as exc:
        print(f"  ✗ harmonyos baseline → {exc}")
