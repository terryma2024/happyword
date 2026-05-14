import json
import threading
import time
from pathlib import Path

from parity_scout.adapters import AdapterResult
from parity_scout.registry import load_registry
from parity_scout.runner import Runner


class _FakeAdapter:
    def __init__(self, name, success=True, delay=0.0):
        self.name = name
        self._success = success
        self._delay = delay

    def capture(self, page_id, capture_spec, out_dir, timeout_s):
        time.sleep(self._delay)
        out_dir.mkdir(parents=True, exist_ok=True)
        if self._success:
            (out_dir / f"{page_id}-part1.png").write_bytes(b"PNG")
        return AdapterResult(
            platform=self.name,
            page_id=page_id,
            out_dir=out_dir,
            success=self._success,
            stderr_tail="" if self._success else "boom",
        )


def _drain(runner, run_dir, autorelease_leaves=True):
    events: list[str] = []

    def consume():
        for ev in runner.iter_events():
            events.append(ev.kind)
            if autorelease_leaves and ev.kind == "LEAF_READY":
                (run_dir / ev.page_id / "next.flag").touch()

    t = threading.Thread(target=consume)
    t.start()
    t.join(timeout=10)
    return events


def test_run_emits_leaf_ready_and_blocks_on_next_flag(tmp_path):
    run_dir = tmp_path / "r1"
    run_dir.mkdir()
    plan = {
        "run_id": "r1",
        "scope": {"kind": "pages", "value": "home"},
        "leaves": [
            {
                "page_id": "home",
                "harmony": {"status": "ok", "route": "home"},
                "ios": {"status": "ok", "route": "home"},
                "android": {"status": "feature_absent"},
            }
        ],
    }
    (run_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    (run_dir / "picked.json").write_text(
        json.dumps({"branches": ["home"]}), encoding="utf-8"
    )

    adapters = {
        "harmony": _FakeAdapter("harmony"),
        "ios": _FakeAdapter("ios"),
        "android": _FakeAdapter("android"),
    }
    capture_specs = {
        "home": {
            "harmony": {"step": "home"},
            "ios": {"output_basename": "home"},
            "android": {"case": "home"},
        }
    }
    runner = Runner(run_dir, adapters, capture_specs, leaf_timeout=5)
    events = _drain(runner, run_dir)

    assert "LEAF_START" in events
    assert "LEAF_READY" in events
    assert events[-1] == "RUN_DONE"

    home_dir = run_dir / "home"
    assert (home_dir / "harmony" / "home-part1.png").is_file()
    assert (home_dir / "android" / "MISSING.txt").is_file()


def test_run_failed_adapter_still_emits_leaf_ready(tmp_path):
    run_dir = tmp_path / "r2"
    run_dir.mkdir()
    plan = {
        "run_id": "r2",
        "scope": {"kind": "pages", "value": "home"},
        "leaves": [
            {
                "page_id": "home",
                "harmony": {"status": "ok", "route": "home"},
                "ios": {"status": "ok", "route": "home"},
                "android": {"status": "ok", "route": "home"},
            }
        ],
    }
    (run_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    (run_dir / "picked.json").write_text(
        json.dumps({"branches": ["home"]}), encoding="utf-8"
    )
    adapters = {
        "harmony": _FakeAdapter("harmony"),
        "ios": _FakeAdapter("ios", success=False),
        "android": _FakeAdapter("android"),
    }
    capture_specs = {
        "home": {
            "harmony": {"step": "home"},
            "ios": {"output_basename": "home"},
            "android": {"case": "home"},
        }
    }
    runner = Runner(run_dir, adapters, capture_specs, leaf_timeout=5)
    events = _drain(runner, run_dir)

    assert "LEAF_READY" in events
    assert (run_dir / "home" / "ios" / "CAPTURE_FAILED.txt").is_file()


def test_runner_writes_spec_excerpts_when_provided(tmp_path, fixtures_dir):
    run_dir = tmp_path / "r3"
    run_dir.mkdir()
    spec_path = fixtures_dir / "specs" / "wishlist_design.md"
    plan = {
        "run_id": "r3",
        "scope": {"kind": "spec", "value": str(spec_path)},
        "leaves": [
            {
                "page_id": "home",
                "harmony": {"status": "ok", "route": "home"},
                "ios": {"status": "ok", "route": "home"},
                "android": {"status": "feature_absent"},
            }
        ],
    }
    (run_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    (run_dir / "picked.json").write_text(
        json.dumps({"branches": ["home"]}), encoding="utf-8"
    )

    adapters = {
        "harmony": _FakeAdapter("harmony"),
        "ios": _FakeAdapter("ios"),
        "android": _FakeAdapter("android"),
    }
    capture_specs = {
        "home": {
            "harmony": {"step": "home"},
            "ios": {"output_basename": "home"},
            "android": {"case": "home"},
        }
    }
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    runner = Runner(
        run_dir,
        adapters,
        capture_specs,
        leaf_timeout=5,
        spec_path=Path(plan["scope"]["value"]),
        registry=reg,
    )
    _drain(runner, run_dir)

    excerpts = (run_dir / "home" / "spec-excerpts.md").read_text(encoding="utf-8")
    assert "User flows" in excerpts
    assert "HomeStartButton" in excerpts


def test_runner_writes_placeholder_when_no_spec(tmp_path):
    run_dir = tmp_path / "r4"
    run_dir.mkdir()
    plan = {
        "run_id": "r4",
        "scope": {"kind": "pages", "value": "home"},
        "leaves": [
            {
                "page_id": "home",
                "harmony": {"status": "ok", "route": "home"},
                "ios": {"status": "ok", "route": "home"},
                "android": {"status": "ok", "route": "home"},
            }
        ],
    }
    (run_dir / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    (run_dir / "picked.json").write_text(
        json.dumps({"branches": ["home"]}), encoding="utf-8"
    )
    adapters = {
        "harmony": _FakeAdapter("harmony"),
        "ios": _FakeAdapter("ios"),
        "android": _FakeAdapter("android"),
    }
    capture_specs = {
        "home": {
            "harmony": {"step": "home"},
            "ios": {"output_basename": "home"},
            "android": {"case": "home"},
        }
    }
    runner = Runner(run_dir, adapters, capture_specs, leaf_timeout=5)
    _drain(runner, run_dir)

    body = (run_dir / "home" / "spec-excerpts.md").read_text(encoding="utf-8")
    assert "no spec scope provided" in body
