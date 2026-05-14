"""Per-leaf runner: fire 3 adapters in parallel, emit LEAF events, sync via next.flag."""

from __future__ import annotations

import json
import time
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FuturesTimeout
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Mapping

from parity_scout.adapters import Adapter


@dataclass(frozen=True)
class LeafRecord:
    kind: str  # "LEAF_START" | "LEAF_READY" | "RUN_DONE"
    page_id: str | None
    dir: Path | None


class Runner:
    def __init__(
        self,
        run_dir: Path,
        adapters: Mapping[str, Adapter],
        capture_specs: Mapping[str, Mapping[str, dict]],
        leaf_timeout: int = 180,
        poll_seconds: float = 1.0,
        spec_path: Path | None = None,
        registry=None,
    ) -> None:
        self.run_dir = Path(run_dir)
        self.adapters = adapters
        self.capture_specs = capture_specs
        self.leaf_timeout = leaf_timeout
        self.poll_seconds = poll_seconds
        self.spec_path = spec_path
        self.registry = registry

    def iter_events(self) -> Iterator[LeafRecord]:
        plan = json.loads((self.run_dir / "plan.json").read_text(encoding="utf-8"))
        picked = json.loads(
            (self.run_dir / "picked.json").read_text(encoding="utf-8")
        )
        wanted = set(picked["branches"])
        leaves = [leaf for leaf in plan["leaves"] if leaf["page_id"] in wanted]

        for leaf in leaves:
            page_id = leaf["page_id"]
            page_dir = self.run_dir / page_id
            page_dir.mkdir(parents=True, exist_ok=True)
            self._write_excerpts(page_id, page_dir)
            yield LeafRecord(kind="LEAF_START", page_id=page_id, dir=page_dir)
            self._fire_adapters(leaf, page_dir)
            yield LeafRecord(kind="LEAF_READY", page_id=page_id, dir=page_dir)
            self._wait_for_flag(page_dir / "next.flag")

        yield LeafRecord(kind="RUN_DONE", page_id=None, dir=None)

    def _fire_adapters(self, leaf: dict, page_dir: Path) -> None:
        cs = self.capture_specs.get(leaf["page_id"], {})
        jobs: list[tuple[str, "object"]] = []
        with ThreadPoolExecutor(max_workers=3) as ex:
            for platform in ("harmony", "ios", "android"):
                plat_dir = page_dir / platform
                plat_dir.mkdir(parents=True, exist_ok=True)
                status = leaf[platform]["status"]
                if status == "feature_absent":
                    (plat_dir / "MISSING.txt").write_text(
                        f"{leaf['page_id']}: feature_absent on {platform}\n",
                        encoding="utf-8",
                    )
                    continue
                if status == "blocked":
                    (plat_dir / "BLOCKED.txt").write_text(
                        f"{leaf['page_id']}: blocked on {platform}\n",
                        encoding="utf-8",
                    )
                    continue
                adapter = self.adapters[platform]
                spec = cs.get(platform, {})
                jobs.append(
                    (
                        platform,
                        ex.submit(
                            adapter.capture,
                            leaf["page_id"],
                            spec,
                            plat_dir,
                            self.leaf_timeout,
                        ),
                    )
                )
            for platform, fut in jobs:
                try:
                    result = fut.result(timeout=self.leaf_timeout + 5)
                except FuturesTimeout:
                    (page_dir / platform / "CAPTURE_FAILED.txt").write_text(
                        f"adapter timeout > {self.leaf_timeout}s\n",
                        encoding="utf-8",
                    )
                    continue
                if not result.success:
                    (page_dir / platform / "CAPTURE_FAILED.txt").write_text(
                        (result.stderr_tail or "unknown error") + "\n",
                        encoding="utf-8",
                    )

    def _write_excerpts(self, page_id: str, page_dir: Path) -> None:
        """Stage <page>/spec-excerpts.md so the SKILL can read it on LEAF READY."""
        target = page_dir / "spec-excerpts.md"
        if self.spec_path is None or self.registry is None:
            target.write_text("<!-- no spec scope provided -->\n", encoding="utf-8")
            return
        try:
            page = self.registry.by_id(page_id)
        except KeyError:
            target.write_text(
                f"<!-- registry missing page {page_id} -->\n", encoding="utf-8"
            )
            return
        from parity_scout.excerpts import extract_excerpt
        target.write_text(extract_excerpt(page, self.spec_path), encoding="utf-8")

    def _wait_for_flag(self, flag_path: Path) -> None:
        while not flag_path.is_file():
            time.sleep(self.poll_seconds)
