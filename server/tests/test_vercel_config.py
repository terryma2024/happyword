"""Deployment config regressions that block server preview E2E."""

from __future__ import annotations

import json
import re
from pathlib import Path

_SERVER_ROOT = Path(__file__).resolve().parents[1]
_SINGLE_CRON_VALUE = re.compile(r"^\d+$")


def test_vercel_crons_are_hobby_compatible() -> None:
    """Vercel Hobby preview deploys reject cron jobs that run more than daily."""
    config = json.loads((_SERVER_ROOT / "vercel.json").read_text(encoding="utf-8"))

    for cron in config.get("crons", []):
        schedule = cron["schedule"]
        fields = schedule.split()
        assert len(fields) == 5
        minute, hour = fields[:2]
        assert _SINGLE_CRON_VALUE.match(minute), f"{schedule} runs more than daily"
        assert _SINGLE_CRON_VALUE.match(hour), f"{schedule} runs more than daily"
