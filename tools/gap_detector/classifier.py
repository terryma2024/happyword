from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from .evidence import EvidenceIndex
from .manifest import Probe


class GapCategory(str, Enum):
    MISSING_FLOW = "missing_flow"
    BEHAVIOR_DRIFT = "behavior_drift"
    MISSING_STABLE_ID = "missing_stable_id"
    STYLE_DRIFT = "style_drift"
    SCREENSHOT_MISSING = "screenshot_missing"
    TEST_COVERAGE_GAP = "test_coverage_gap"
    CONTRACT_DRIFT = "contract_drift"
    MANUAL_GATE = "manual_gate"


class Severity(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


@dataclass(frozen=True)
class GapItem:
    id: str
    probe: str
    platform: str
    severity: Severity
    category: GapCategory
    expected: str
    observed: str
    evidence: dict[str, str] = field(default_factory=dict)
    downstream_hint: str = ""
    status: str = "open"

    def to_dict(self) -> dict[str, object]:
        return {
            "id": self.id,
            "probe": self.probe,
            "platform": self.platform,
            "severity": self.severity.value,
            "category": self.category.value,
            "expected": self.expected,
            "observed": self.observed,
            "evidence": self.evidence,
            "downstream_hint": self.downstream_hint,
            "status": self.status,
        }


def classify_probe(probe: Probe, evidence_by_platform: dict[str, EvidenceIndex]) -> tuple[GapItem, ...]:
    gaps: list[GapItem] = []
    for platform in sorted(probe.runners):
        evidence = evidence_by_platform.get(platform, EvidenceIndex(probe_id=probe.id, platform=platform))
        for stable_id in probe.expected.stable_ids:
            if not evidence.contains_stable_id(stable_id):
                gaps.append(
                    GapItem(
                        id=f"gap-{probe.id}-{platform}-missing-stable-id-{len(gaps) + 1:03d}",
                        probe=probe.id,
                        platform=platform,
                        severity=Severity.HIGH,
                        category=GapCategory.MISSING_STABLE_ID,
                        expected=f"Stable id {stable_id} is present on {platform}.",
                        observed=f"Stable id {stable_id} was not found in {platform} evidence.",
                        evidence=_evidence_paths(evidence),
                        downstream_hint=f"Create a {platform} parity follow-up; detector does not edit app source.",
                    )
                )
        if probe.expected.style_refs and not evidence.has_screenshot():
            gaps.append(
                GapItem(
                    id=f"gap-{probe.id}-{platform}-screenshot-missing-{len(gaps) + 1:03d}",
                    probe=probe.id,
                    platform=platform,
                    severity=Severity.MEDIUM,
                    category=GapCategory.SCREENSHOT_MISSING,
                    expected=f"{platform} screenshot evidence exists for {probe.page}.",
                    observed=f"No screenshot file was indexed for {platform} probe {probe.id}.",
                    evidence=_evidence_paths(evidence),
                    downstream_hint="Re-run this detector probe with screenshot capture enabled before remediation planning.",
                )
            )
    return tuple(gaps)


def _evidence_paths(evidence: EvidenceIndex) -> dict[str, str]:
    paths: dict[str, str] = {}
    if evidence.screenshot is not None:
        paths["screenshot"] = str(evidence.screenshot)
    if evidence.log_path is not None:
        paths["log"] = str(evidence.log_path)
    return paths
