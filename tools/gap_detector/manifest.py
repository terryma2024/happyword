from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ScopeRecord:
    mode: str
    input: str
    baseline_branch: str
    selected_paths: tuple[str, ...] = ()
    skipped_paths: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class SourceRecord:
    docs: tuple[str, ...] = ()
    tests: dict[str, tuple[str, ...]] = field(default_factory=dict)


@dataclass(frozen=True)
class ExpectedProbeState:
    behavior: tuple[str, ...] = ()
    stable_ids: tuple[str, ...] = ()
    style_refs: tuple[str, ...] = ()


@dataclass(frozen=True)
class PlatformRunner:
    suite: str = ""
    case: str = ""
    route: str = ""


@dataclass(frozen=True)
class Probe:
    id: str
    page: str
    expected: ExpectedProbeState = field(default_factory=ExpectedProbeState)
    runners: dict[str, PlatformRunner] = field(default_factory=dict)
    classify_as: tuple[str, ...] = ()
    status: str = "pending"


@dataclass(frozen=True)
class Manifest:
    scope: ScopeRecord
    sources: SourceRecord = field(default_factory=SourceRecord)
    probes: tuple[Probe, ...] = ()

    def with_probe_status(self, probe_id: str, status: str) -> Manifest:
        probes = tuple(
            replace(probe, status=status) if probe.id == probe_id else probe
            for probe in self.probes
        )
        if probes == self.probes:
            raise ValueError(f"probe not found: {probe_id}")
        return replace(self, probes=probes)


def save_manifest(manifest: Manifest, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(_manifest_to_dict(manifest), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_manifest(source: Path) -> Manifest:
    data = json.loads(source.read_text(encoding="utf-8"))
    return _manifest_from_dict(data)


def _manifest_to_dict(manifest: Manifest) -> dict[str, Any]:
    return asdict(manifest)


def _manifest_from_dict(data: dict[str, Any]) -> Manifest:
    return Manifest(
        scope=ScopeRecord(
            mode=data["scope"]["mode"],
            input=data["scope"]["input"],
            baseline_branch=data["scope"]["baseline_branch"],
            selected_paths=tuple(data["scope"].get("selected_paths", ())),
            skipped_paths=dict(data["scope"].get("skipped_paths", {})),
        ),
        sources=SourceRecord(
            docs=tuple(data.get("sources", {}).get("docs", ())),
            tests={
                platform: tuple(paths)
                for platform, paths in data.get("sources", {}).get("tests", {}).items()
            },
        ),
        probes=tuple(_probe_from_dict(item) for item in data.get("probes", ())),
    )


def _probe_from_dict(data: dict[str, Any]) -> Probe:
    expected = data.get("expected", {})
    return Probe(
        id=data["id"],
        page=data["page"],
        expected=ExpectedProbeState(
            behavior=tuple(expected.get("behavior", ())),
            stable_ids=tuple(expected.get("stable_ids", ())),
            style_refs=tuple(expected.get("style_refs", ())),
        ),
        runners={
            platform: PlatformRunner(
                suite=runner.get("suite", ""),
                case=runner.get("case", ""),
                route=runner.get("route", ""),
            )
            for platform, runner in data.get("runners", {}).items()
        },
        classify_as=tuple(data.get("classify_as", ())),
        status=data.get("status", "pending"),
    )
