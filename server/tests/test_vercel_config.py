"""Deployment config regressions that block server preview E2E."""

from __future__ import annotations

import json
from pathlib import Path

_SERVER_ROOT = Path(__file__).resolve().parents[1]


def test_vercel_extract_pending_cron_is_every_minute() -> None:
    """Lesson extraction cron runs once per minute (requires Vercel Pro — Hobby caps at daily)."""
    config = json.loads((_SERVER_ROOT / "vercel.json").read_text(encoding="utf-8"))
    crons = config.get("crons", [])
    assert len(crons) == 1
    assert crons[0]["path"] == "/api/v1/admin/cron/extract-pending"
    assert crons[0]["schedule"] == "* * * * *"


def test_vercel_config_uses_fastapi_framework_preset() -> None:
    """The FastAPI preset rejects legacy per-file function config here."""
    config = json.loads((_SERVER_ROOT / "vercel.json").read_text(encoding="utf-8"))

    assert "functions" not in config
