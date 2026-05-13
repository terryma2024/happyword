from __future__ import annotations

import re
from pathlib import Path

HARMONY_ID_RE = re.compile(r"\.id\(\s*['\"]([^'\"]+)['\"]\s*\)")
IOS_ACCESSIBILITY_RE = re.compile(r"\.accessibilityIdentifier\(\s*\"([^\"]+)\"\s*\)")
ANDROID_TEST_TAG_RE = re.compile(r"\.testTag\(\s*\"([^\"]+)\"\s*\)|Modifier\.testTag\(\s*\"([^\"]+)\"\s*\)")
STRING_RE = re.compile(r"['\"]([A-Za-z][A-Za-z0-9_$:-]{2,})['\"]")


def extract_harmony_ids(source: str) -> set[str]:
    return set(HARMONY_ID_RE.findall(source))


def extract_ios_accessibility_ids(source: str) -> set[str]:
    return set(IOS_ACCESSIBILITY_RE.findall(source))


def extract_android_test_tags(source: str) -> set[str]:
    ids: set[str] = set()
    for match in ANDROID_TEST_TAG_RE.findall(source):
        ids.update(value for value in match if value)
    return ids


def extract_string_references(source: str) -> set[str]:
    return set(STRING_RE.findall(source))


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def collect_ids_from_files(paths: list[Path], extractor) -> dict[str, set[str]]:
    collected: dict[str, set[str]] = {}
    for path in paths:
        ids = extractor(read_text(path))
        if ids:
            collected[str(path)] = ids
    return collected


def collect_string_refs_from_files(paths: list[Path]) -> dict[str, set[str]]:
    collected: dict[str, set[str]] = {}
    for path in paths:
        refs = extract_string_references(read_text(path))
        if refs:
            collected[str(path)] = refs
    return collected
