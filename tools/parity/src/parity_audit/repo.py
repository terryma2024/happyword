from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Callable

from .extractors import (
    extract_android_test_tags,
    extract_harmony_ids,
    extract_ios_accessibility_ids,
    extract_string_references,
)


def list_files(root: Path, *parts: str, suffixes: tuple[str, ...]) -> list[Path]:
    base = root.joinpath(*parts)
    if not base.exists():
        return []
    return sorted(path for path in base.rglob("*") if path.is_file() and path.suffix in suffixes)


def git_text_files(root: Path, ref: str, path_prefix: str, suffixes: tuple[str, ...]) -> dict[str, str]:
    result = subprocess.run(
        ["git", "ls-tree", "-r", "--name-only", ref, "--", path_prefix],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return {}
    files: dict[str, str] = {}
    for rel in result.stdout.splitlines():
        if not rel.endswith(suffixes):
            continue
        show = subprocess.run(
            ["git", "show", f"{ref}:{rel}"],
            cwd=root,
            capture_output=True,
            text=True,
            check=False,
        )
        if show.returncode == 0:
            files[rel] = show.stdout
    return files


def collect_working_tree(root: Path) -> dict[str, dict[str, set[str]]]:
    harmony_files = list_files(root, "harmonyos", "entry", "src", "main", "ets", suffixes=(".ets",))
    harmony_test_files = list_files(root, "harmonyos", "entry", "src", "ohosTest", suffixes=(".ets",)) + list_files(
        root,
        "harmonyos",
        "entry",
        "src",
        "test",
        suffixes=(".ets",),
    )
    ios_files = list_files(root, "ios", "WordMagicGame", suffixes=(".swift",))
    ios_test_files = list_files(root, "ios", "WordMagicGameUITests", suffixes=(".swift",)) + list_files(
        root,
        "ios",
        "WordMagicGameTests",
        suffixes=(".swift",),
    )
    android_files = list_files(root, "android", "app", "src", "main", "java", suffixes=(".kt",))
    android_test_files = list_files(root, "android", "app", "src", "androidTest", suffixes=(".kt",)) + list_files(
        root,
        "android",
        "app",
        "src",
        "test",
        suffixes=(".kt",),
    )
    return {
        "harmony_ids": collect_from_paths(harmony_files, extract_harmony_ids),
        "harmony_refs": collect_from_paths(harmony_test_files, extract_string_references),
        "ios_ids": collect_from_paths(ios_files, extract_ios_accessibility_ids),
        "ios_refs": collect_from_paths(ios_test_files, extract_string_references),
        "android_ids": collect_from_paths(android_files, extract_android_test_tags),
        "android_refs": collect_from_paths(android_test_files, extract_string_references),
    }


def collect_harmony_baseline(root: Path, baseline: str) -> dict[str, set[str]]:
    if baseline == "working-tree":
        data = collect_working_tree(root)
        return {
            "ids": flatten(data["harmony_ids"]),
            "refs": flatten(data["harmony_refs"]),
        }
    source_files = git_text_files(root, baseline, "harmonyos/entry/src/main/ets", (".ets",))
    test_files = git_text_files(root, baseline, "harmonyos/entry/src", (".ets",))
    return {
        "ids": flatten_sources(source_files, extract_harmony_ids),
        "refs": flatten_sources(test_files, extract_string_references),
    }


def collect_from_paths(paths: list[Path], extractor: Callable[[str], set[str]]) -> dict[str, set[str]]:
    collected: dict[str, set[str]] = {}
    for path in paths:
        values = extractor(path.read_text(encoding="utf-8", errors="ignore"))
        if values:
            collected[str(path)] = values
    return collected


def flatten(collected: dict[str, set[str]]) -> set[str]:
    result: set[str] = set()
    for values in collected.values():
        result.update(values)
    return result


def flatten_sources(sources: dict[str, str], extractor: Callable[[str], set[str]]) -> set[str]:
    result: set[str] = set()
    for source in sources.values():
        result.update(extractor(source))
    return result


def source_for_identifier(collected: dict[str, set[str]], identifier: str) -> str:
    for source, values in collected.items():
        if identifier in values:
            return source
    return "unknown"
