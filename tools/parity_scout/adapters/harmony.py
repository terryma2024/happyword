"""HarmonyOS adapter — wraps scripts/capture_harmony_screenshots.py."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from parity_scout.adapters import Adapter, AdapterResult


_REPO_ROOT = Path(__file__).resolve().parents[3]
_HARMONY_SCREENSHOT_OUT = _REPO_ROOT / "assets" / "screenshots" / "harmonyos"


class HarmonyAdapter(Adapter):
    name = "harmony"

    def capture(self, page_id, capture_spec, out_dir, timeout_s):
        step = capture_spec.get("step") or page_id
        script = _REPO_ROOT / "scripts" / "capture_harmony_screenshots.py"
        if not script.is_file():
            return AdapterResult(
                platform=self.name,
                page_id=page_id,
                out_dir=out_dir,
                success=False,
                stderr_tail="capture_harmony_screenshots.py missing",
            )
        try:
            proc = subprocess.run(
                ["python3", str(script), "--pages", step],
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            return AdapterResult(
                platform=self.name,
                page_id=page_id,
                out_dir=out_dir,
                success=False,
                stderr_tail=f"timeout after {timeout_s}s: {exc}",
            )
        if proc.returncode != 0:
            return AdapterResult(
                platform=self.name,
                page_id=page_id,
                out_dir=out_dir,
                success=False,
                stderr_tail=proc.stderr[-2000:],
            )
        # Copy newly produced harmony screenshots into out_dir. The capture
        # script writes flat PNGs (home.png, parent-admin-part1.png …) under
        # assets/screenshots/harmonyos/. We match by `step` prefix so a step
        # like "battle+result" picks up both battle.png and result.png.
        out_dir.mkdir(parents=True, exist_ok=True)
        moved = 0
        for png in _HARMONY_SCREENSHOT_OUT.glob("*.png"):
            if _png_belongs_to_step(png.stem, step):
                shutil.copy(png, out_dir / png.name)
                moved += 1
        success = moved > 0
        return AdapterResult(
            platform=self.name,
            page_id=page_id,
            out_dir=out_dir,
            success=success,
            stderr_tail="" if success else "no PNGs produced for step",
        )


def _png_belongs_to_step(stem: str, step: str) -> bool:
    """Best-effort match: 'battle+result' should pick up battle.png and result.png.

    For multi-page steps, the step key uses '+' to join the page names; we
    split on '+' and match if the file stem starts with any of the names.
    For simple steps like 'home' we match `stem == step` or
    `stem.startswith(step + '-')` (handles part1..partN suffixes).
    """
    if stem == step:
        return True
    if stem.startswith(step + "-"):
        return True
    if "+" in step:
        parts = [p.strip() for p in step.split("+") if p.strip()]
        for p in parts:
            if stem == p or stem.startswith(p + "-"):
                return True
    return False
