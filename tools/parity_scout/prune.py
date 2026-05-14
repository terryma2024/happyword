"""Rotate .parity_scout/<run-id>/ directories, keeping the newest N."""

from __future__ import annotations

import shutil
from pathlib import Path


def run_prune(run_root: Path, keep: int) -> int:
    run_root = Path(run_root)
    if not run_root.is_dir():
        print("kept 0, pruned 0")
        return 0
    dirs = sorted(
        (d for d in run_root.iterdir() if d.is_dir()),
        key=lambda d: d.stat().st_mtime,
        reverse=True,
    )
    keep = max(keep, 0)
    kept = dirs[:keep]
    pruned = dirs[keep:]
    for d in pruned:
        shutil.rmtree(d, ignore_errors=True)
    print(f"kept {len(kept)}, pruned {len(pruned)}")
    return 0
