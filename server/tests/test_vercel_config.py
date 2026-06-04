"""Deployment config regressions that block server preview E2E."""

from __future__ import annotations

import json
from pathlib import Path

_SERVER_ROOT = Path(__file__).resolve().parents[1]
_VERCEL_JSON = _SERVER_ROOT / "vercel.json"


def test_vercel_json_under_server_directory_matches_dashboard_root() -> None:
    """Production project uses **Root Directory = ``server``** (see
    ``.cursor/rules/vercel-root-directory.mdc``). Vercel then reads only
    ``server/vercel.json`` — not a file at the Git repository root.
    """
    assert _VERCEL_JSON.is_file()


def test_vercel_extract_pending_cron_is_every_minute() -> None:
    """Lesson extraction cron runs once per minute (requires Vercel Pro — Hobby caps at daily)."""
    config = json.loads(_VERCEL_JSON.read_text(encoding="utf-8"))
    crons = config.get("crons", [])
    assert len(crons) == 1
    assert crons[0]["path"] == "/api/v1/admin/cron/extract-pending"
    assert crons[0]["schedule"] == "* * * * *"


def test_vercel_git_deployments_are_disabled() -> None:
    """CloudBase owns production deploys now. Vercel remains attached only for
    the legacy ``happyword.cool`` 301 endpoint, so GitHub commits must not create
    Vercel deployments.
    """
    config = json.loads(_VERCEL_JSON.read_text(encoding="utf-8"))
    de = config.get("git", {}).get("deploymentEnabled")
    assert de is False


def test_vercel_config_uses_fastapi_framework_preset() -> None:
    """FastAPI via ``@vercel/python`` must not use legacy ``builds``.

    Do **not** add a ``functions`` map for ``api/index.py`` + ``maxDuration``:
    the Python framework preset builds a function bundle whose names do not
    match that path, so Vercel fails the deployment with "pattern … doesn't
    match any Serverless Functions". Set **Function max duration** (e.g. 60s
    on Pro) in the Vercel project dashboard instead.
    """
    config = json.loads(_VERCEL_JSON.read_text(encoding="utf-8"))

    assert "builds" not in config
    assert "functions" not in config
