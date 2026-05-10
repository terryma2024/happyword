from __future__ import annotations

import json
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
