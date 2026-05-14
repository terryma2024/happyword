"""Slice a spec markdown into the prose relevant to a given page."""

from __future__ import annotations

import re
from pathlib import Path

from parity_scout.registry import PageEntry


def extract_excerpt(page: PageEntry, spec_path: Path) -> str:
    text = Path(spec_path).read_text(encoding="utf-8")
    sections = _split_by_h2(text)
    needles = (
        list(page.spec_anchors.stable_ids)
        + list(page.spec_anchors.page_section_titles)
        + [page.id]
    )
    keep: list[str] = []
    for heading, body in sections:
        haystack = heading + "\n" + body
        if any(n and n in haystack for n in needles):
            keep.append(f"## {heading}\n{body}")
    if not keep:
        return f"<!-- no spec anchors matched for page={page.id} -->\n"
    return "\n".join(keep).strip() + "\n"


def _split_by_h2(text: str) -> list[tuple[str, str]]:
    """Return [(heading_text, body_text), ...] split on '## ' headings."""
    parts: list[tuple[str, str]] = []
    matches = list(re.finditer(r"^##\s+(.+?)\s*$", text, re.MULTILINE))
    if not matches:
        return parts
    for i, m in enumerate(matches):
        heading = m.group(1)
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[start:end].strip("\n")
        parts.append((heading, body))
    return parts
