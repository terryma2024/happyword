from __future__ import annotations

import json
from pathlib import Path

from .models import Gap, ScreenshotMetric

SEVERITY_ORDER = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}


def sort_gaps(gaps: list[Gap]) -> list[Gap]:
    return sorted(gaps, key=lambda gap: (SEVERITY_ORDER[gap.severity], gap.platform, gap.kind, gap.title))


def write_outputs(
    out_dir: Path,
    gaps: list[Gap],
    metrics: list[ScreenshotMetric],
    metadata: dict[str, str],
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    sorted_gaps = sort_gaps(gaps)
    (out_dir / "gaps.json").write_text(
        json.dumps(
            {
                "metadata": metadata,
                "gaps": [gap.to_dict() for gap in sorted_gaps],
                "visual_metrics": [metric.to_dict() for metric in metrics],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    (out_dir / "gaps.md").write_text(render_markdown(sorted_gaps, metrics, metadata), encoding="utf-8")


def render_markdown(gaps: list[Gap], metrics: list[ScreenshotMetric], metadata: dict[str, str]) -> str:
    lines = ["# Cross-Platform Gaps", ""]
    lines.append("## Action Items")
    if not gaps:
        lines.append("")
        lines.append("No gaps found with the selected checks.")
    for gap in gaps:
        lines.append("")
        lines.append(f"- **{gap.severity} {gap.platform} {gap.kind}**: {gap.title}")
        lines.append(f"  - Harmony: `{gap.harmony_evidence.source}` — {gap.harmony_evidence.detail}")
        lines.append(f"  - Platform: `{gap.platform_evidence.source}` — {gap.platform_evidence.detail}")
        lines.append(f"  - Fix entry: {gap.suggested_fix_entry}")
    lines.append("")
    lines.append("## Metadata")
    for key, value in metadata.items():
        lines.append(f"- `{key}`: `{value}`")
    if metrics:
        lines.append("")
        lines.append("## Visual Metrics")
        for metric in metrics:
            lines.append(
                f"- `{metric.screen}`: diff `{metric.diff_percent}%`, average delta `{metric.average_delta}`, diff `{metric.diff_path}`",
            )
    lines.append("")
    return "\n".join(lines)


def terminal_summary(gaps: list[Gap]) -> str:
    sorted_gaps = sort_gaps(gaps)
    if not sorted_gaps:
        return "No actionable parity gaps found."
    lines: list[str] = []
    for gap in sorted_gaps[:30]:
        lines.append(f"{gap.severity} {gap.platform} {gap.kind}: {gap.title}")
        lines.append(f"  fix: {gap.suggested_fix_entry}")
    if len(sorted_gaps) > 30:
        lines.append(f"... {len(sorted_gaps) - 30} more gaps written to gaps.json")
    return "\n".join(lines)
