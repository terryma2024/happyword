"""Policy checks for the preview E2E pytest runner."""

from __future__ import annotations

import ast
from pathlib import Path


def _is_pytest_mark_anyio(node: ast.AST) -> bool:
    return (
        isinstance(node, ast.Attribute)
        and node.attr == "anyio"
        and isinstance(node.value, ast.Attribute)
        and node.value.attr == "mark"
        and isinstance(node.value.value, ast.Name)
        and node.value.value.id == "pytest"
    )


def test_e2e_tests_do_not_mix_anyio_with_pytest_asyncio_auto_mode() -> None:
    """E2E async tests are driven by pytest-asyncio's configured auto mode."""
    e2e_dir = Path(__file__).resolve().parent / "e2e"
    offenders: list[str] = []

    for path in sorted(e2e_dir.glob("test_*_e2e.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.AsyncFunctionDef) and any(
                _is_pytest_mark_anyio(decorator) for decorator in node.decorator_list
            ):
                offenders.append(f"{path.relative_to(e2e_dir.parent)}::{node.name}")

    assert offenders == []
