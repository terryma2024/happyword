from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


def test_shared_openapi_contract_is_current() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        [sys.executable, "../tools/contracts/check_contracts.py"],
        cwd=repo_root / "server",
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr or result.stdout


def test_shared_fixtures_are_valid_json() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    for path in sorted((repo_root / "shared" / "fixtures").rglob("*.json")):
        json.loads(path.read_text(encoding="utf-8"))


def test_structured_error_codes_are_documented() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    source_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (repo_root / "server" / "app").rglob("*.py")
    )
    codes = set(re.findall(r'"code":\s*"([A-Z][A-Z0-9_]+)"', source_text))
    codes.update(re.findall(r"\bcode\s*=\s*\"([A-Z][A-Z0-9_]+)\"", source_text))
    docs = (repo_root / "shared" / "contracts" / "errors" / "error-codes.md").read_text(
        encoding="utf-8"
    )
    missing = sorted(code for code in codes if f"`{code}`" not in docs)
    assert missing == []
