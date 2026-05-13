"""Resolve a scope input to a list of registry page ids."""

from __future__ import annotations

from pathlib import Path

from parity_scout.registry import PageEntry, Registry


class ScopeError(Exception):
    """Raised when a scope cannot be resolved to any page."""


_VALID_KINDS = {"overall", "spec", "feature", "pages", "suite", "describe"}


def resolve_scope(reg: Registry, *, kind: str, value: str | None) -> list[str]:
    if kind not in _VALID_KINDS:
        raise ScopeError(f"unknown scope kind: {kind!r}")
    if kind == "overall":
        return [p.id for p in reg.pages]
    if kind == "pages":
        return _resolve_pages(reg, value or "")
    if kind == "suite":
        # Until the registry carries a per-platform `suite:` field, we accept
        # suite names equal to page ids. The CLI surface stays stable; the
        # data model will grow when actual suite-to-page mapping is wired in.
        return _resolve_pages(reg, value or "")
    if kind in {"spec", "feature"}:
        return _resolve_from_markdown(reg, value)
    if kind == "describe":
        return _resolve_from_describe(reg, value or "")
    raise ScopeError(f"unhandled scope kind: {kind!r}")


def _resolve_pages(reg: Registry, value: str) -> list[str]:
    ids = [v.strip() for v in value.split(",") if v.strip()]
    valid = {p.id for p in reg.pages}
    for i in ids:
        if i not in valid:
            raise ScopeError(f"unknown page id: {i!r}")
    return ids


def _read_markdown(value: str | None) -> str:
    if not value:
        raise ScopeError("path required for spec/feature scope")
    path = Path(value)
    if path.is_dir():
        candidates = sorted(path.glob("*.md"))
        if not candidates:
            raise ScopeError(f"feature folder {path} has no markdown files")
        return "\n\n".join(p.read_text(encoding="utf-8") for p in candidates)
    return path.read_text(encoding="utf-8")


def _resolve_from_markdown(reg: Registry, value: str | None) -> list[str]:
    text = _read_markdown(value)
    hits: list[str] = []
    for page in reg.pages:
        if _page_matches_text(page, text):
            hits.append(page.id)
    return hits


def _resolve_from_describe(reg: Registry, prose: str) -> list[str]:
    hits: list[str] = []
    for page in reg.pages:
        if _page_matches_text(page, prose):
            hits.append(page.id)
    return hits


def _page_matches_text(page: PageEntry, text: str) -> bool:
    if not text:
        return False
    for sid in page.spec_anchors.stable_ids:
        if sid and sid in text:
            return True
    for title in page.spec_anchors.page_section_titles:
        if title and title in text:
            return True
    if page.id and page.id in text:
        return True
    return False
