"""Build a search plan from a resolved set of page ids."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from typing import Any

from parity_scout.registry import PageEntry, PlatformEntry, PlatformStatus, Registry


@dataclass(frozen=True)
class Leaf:
    page_id: str
    harmony: dict[str, Any]
    ios: dict[str, Any]
    android: dict[str, Any]
    spec_excerpt_path: str | None = None


@dataclass(frozen=True)
class PlanResult:
    run_id: str
    scope_kind: str
    scope_value: str | None
    leaves: tuple[Leaf, ...] = field(default_factory=tuple)

    def to_json(self) -> str:
        return json.dumps(
            {
                "run_id": self.run_id,
                "scope": {"kind": self.scope_kind, "value": self.scope_value},
                "leaves": [asdict(leaf) for leaf in self.leaves],
            },
            indent=2,
            sort_keys=True,
        )


def build_plan(
    reg: Registry,
    *,
    page_ids: list[str],
    run_id: str,
    scope_kind: str,
    scope_value: str | None,
) -> PlanResult:
    leaves = tuple(_leaf_for(reg.by_id(pid)) for pid in page_ids)
    return PlanResult(
        run_id=run_id,
        scope_kind=scope_kind,
        scope_value=scope_value,
        leaves=leaves,
    )


def _leaf_for(page: PageEntry) -> Leaf:
    return Leaf(
        page_id=page.id,
        harmony=_platform_summary(page.harmony, page.id),
        ios=_platform_summary(page.ios, page.id),
        android=_platform_summary(page.android, page.id),
        spec_excerpt_path=None,
    )


def _platform_summary(plat: PlatformEntry, page_id: str) -> dict[str, Any]:
    status = plat.status()
    out: dict[str, Any] = {"status": status.value}
    if status == PlatformStatus.OK:
        out["route"] = page_id
    elif status == PlatformStatus.BLOCKED:
        out["reason"] = plat.block_reason()
    return out


def render_tree(plan: PlanResult) -> str:
    lines = [
        f"PLAN run={plan.run_id}  scope={plan.scope_kind}:{plan.scope_value or '-'}",
    ]
    total = len(plan.leaves)
    for i, leaf in enumerate(plan.leaves):
        prefix = "└──" if i == total - 1 else "├──"
        h = _fmt_status(leaf.harmony)
        ios = _fmt_status(leaf.ios)
        droid = _fmt_status(leaf.android)
        lines.append(
            f"{prefix} {leaf.page_id:24s} harmony:{h}  ios:{ios}  android:{droid}"
        )
    return "\n".join(lines)


def _fmt_status(plat: dict[str, Any]) -> str:
    status = plat["status"]
    if status == "blocked":
        return f"BLOCKED({plat.get('reason', '?')})"
    return status
