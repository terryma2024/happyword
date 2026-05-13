from __future__ import annotations

import re
import json
from dataclasses import dataclass
from pathlib import Path

from .extractors import extract_android_test_tags, extract_harmony_ids, extract_ios_accessibility_ids, extract_string_references

BEHAVIOR_WORDS = (
    "must",
    "should",
    "expected",
    "preserve",
    "replicate",
    "mirror",
    "parity",
    "same",
    "必须",
    "应该",
    "保持",
    "复刻",
    "一致",
    "预期",
)


@dataclass(frozen=True)
class DocClue:
    identifier: str
    kind: str
    path: str
    line: int
    snippet: str

    @property
    def evidence_text(self) -> str:
        return f"{self.path}:{self.line}: {self.snippet}"


DOC_BRANCHES = (
    ("docs/superpowers/specs", "Superpowers specs: expected behavior and design rationale"),
    ("docs/superpowers/plans", "Superpowers plans: implementation intent and verification steps"),
    ("docs/features", "Per-feature lifecycle docs: frozen design, trigger, replica plans, parity checklist"),
)


def collect_doc_clues(repo_root: Path, paths: list[Path] | None = None, overall: bool = False) -> dict[str, list[DocClue]]:
    clues: dict[str, list[DocClue]] = {}
    for path in _doc_paths(repo_root, paths, overall):
        _collect_file_clues(repo_root, path, clues)
    return clues


def build_doc_search_plan(repo_root: Path) -> dict[str, list[str]]:
    plan: dict[str, list[str]] = {}
    for branch, _description in DOC_BRANCHES:
        base = repo_root / branch
        if not base.exists():
            continue
        files = sorted(
            str(path.relative_to(repo_root))
            for path in base.rglob("*.md")
            if path.is_file()
        )
        if files:
            plan[branch] = files
    return plan


def write_doc_search_plan(repo_root: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    plan = build_doc_search_plan(repo_root)
    (out_dir / "doc-search-plan.json").write_text(
        json.dumps(plan, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    lines = ["# Doc Search Plan", ""]
    lines.append("Choose the smallest relevant paths before running doc-clue gap analysis.")
    lines.append("Use `--doc-scope overall` only when the user explicitly asks for global search.")
    for branch, files in plan.items():
        description = dict(DOC_BRANCHES).get(branch, "")
        lines.append("")
        lines.append(f"## {branch}")
        if description:
            lines.append(description)
        lines.append("")
        for file in files:
            lines.append(f"- `{file}`")
    lines.append("")
    (out_dir / "doc-search-plan.md").write_text("\n".join(lines), encoding="utf-8")


def clue_for_identifier(clues: dict[str, list[DocClue]], identifier: str) -> DocClue | None:
    candidates = clues.get(identifier, [])
    if not candidates:
        return None
    return sorted(candidates, key=lambda clue: (0 if clue.kind == "behavior" else 1, clue.path, clue.line))[0]


def _collect_file_clues(repo_root: Path, path: Path, clues: dict[str, list[DocClue]]) -> None:
    rel = str(path.relative_to(repo_root))
    for index, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), start=1):
        identifiers = _identifiers_from_line(line)
        if not identifiers:
            continue
        kind = _line_kind(line)
        snippet = _clean_snippet(line)
        for identifier in identifiers:
            clues.setdefault(identifier, []).append(DocClue(identifier, kind, rel, index, snippet))


def _identifiers_from_line(line: str) -> set[str]:
    ids = set()
    ids.update(extract_harmony_ids(line))
    ids.update(extract_ios_accessibility_ids(line))
    ids.update(extract_android_test_tags(line))
    ids.update(
        token
        for token in extract_string_references(line)
        if re.search(r"[A-Z]", token) and len(token) >= 6
    )
    ids.update(re.findall(r"\b[A-Z][A-Za-z0-9_]*(?:Button|Screen|Page|Dialog|Input|Switch|Marker|Label|Toast|Title|Row|Area|Card|Badge)\b", line))
    return ids


def _looks_behavioral(line: str) -> bool:
    lowered = line.lower()
    return any(word in lowered for word in BEHAVIOR_WORDS)


def _line_kind(line: str) -> str:
    explicit_id = bool(extract_harmony_ids(line) or extract_ios_accessibility_ids(line) or extract_android_test_tags(line))
    if explicit_id:
        return "stable_id"
    return "behavior" if _looks_behavioral(line) else "stable_id"


def _clean_snippet(line: str) -> str:
    return re.sub(r"\s+", " ", line.strip()).strip("- ")


def _doc_paths(repo_root: Path, paths: list[Path] | None, overall: bool) -> list[Path]:
    if overall:
        resolved: list[Path] = []
        for branch, _description in DOC_BRANCHES:
            base = repo_root / branch
            if base.exists():
                resolved.extend(sorted(path for path in base.rglob("*.md") if path.is_file()))
        return resolved
    if not paths:
        return []
    resolved = []
    for path in paths:
        candidate = path if path.is_absolute() else repo_root / path
        if candidate.is_file() and candidate.suffix == ".md":
            resolved.append(candidate)
    return sorted(resolved)
