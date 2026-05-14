"""Append a curated findings slice to a feature's 60-followups.md."""

from __future__ import annotations

import datetime as dt
from pathlib import Path


class PromoteError(Exception):
    pass


def promote_curated_findings(
    *,
    findings: Path,
    feature_dir: Path,
    run_id: str,
    baseline_line: str,
    scope_line: str,
    leaves_line: str,
    today: dt.date | None = None,
) -> Path:
    feature_dir = Path(feature_dir)
    if not feature_dir.is_dir():
        raise PromoteError(f"feature folder missing: {feature_dir}")
    findings = Path(findings)
    if not findings.is_file():
        raise PromoteError(f"findings file missing: {findings}")
    body = findings.read_text(encoding="utf-8").strip("\n")
    bullets = [ln for ln in body.splitlines() if ln.lstrip().startswith("- [")]
    if not bullets:
        raise PromoteError("findings file has no '- [ ]' items")
    today = today or dt.date.today()
    section = (
        f"\n## Parity scout — {today.isoformat()} (run {run_id})\n\n"
        f"Baseline: {baseline_line}\n"
        f"Scope: {scope_line}\n"
        f"Leaves analysed: {leaves_line}\n\n"
        + "\n".join(bullets)
        + "\n"
    )
    followups = feature_dir / "60-followups.md"
    if followups.is_file():
        existing = followups.read_text(encoding="utf-8").rstrip("\n") + "\n"
    else:
        existing = "# Followups\n"
    followups.write_text(existing + section, encoding="utf-8")
    return followups
