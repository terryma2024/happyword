"""E2E: lesson import fast-path + manual cron tick.

Contract:
- POST /api/v1/admin/lessons/import returns quickly with status="extracting".
- POST /api/v1/admin/cron/extract-pending (authorized) processes one extracting
  draft and flips it to either "pending" (success) or "extract_failed" (terminal).

This test is written to be re-entrant:
- It deletes any pre-existing extracting drafts in the E2E database up-front so
  the cron tick deterministically claims the draft we just created.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    import httpx

    from tests.e2e._utils.db import MongoDB

_CRON_PATH = "/api/v1/admin/cron/extract-pending"
_IMPORT_PATH = "/api/v1/admin/lessons/import"
_DRAFT_PATH_TMPL = "/api/v1/admin/lesson-drafts/{draft_id}"


def _strip_env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _fixture_jpg_bytes() -> bytes:
    # Keep server E2E fixtures self-contained (avoid coupling to client tests).
    path = Path(__file__).resolve().parent / "_fixtures/lesson_import_fixture.jpg"
    if not path.exists():
        pytest.skip(f"fixture image not found: {path}")
    return path.read_bytes()


@pytest.mark.e2e
async def test_import_then_trigger_extract_pending_is_reentrant(
    http: httpx.Client,
    mongo: MongoDB,
) -> None:
    cron_secret = _strip_env("E2E_CRON_SECRET")
    if not cron_secret:
        pytest.skip("E2E_CRON_SECRET is not set (must match Vercel env CRON_SECRET)")

    # Ensure a deterministic queue: the cron tick always claims the oldest
    # attempts==0 row, so clear any leftovers from previous runs.
    await mongo["lesson_import_drafts"].delete_many({"status": "extracting"})

    img = _fixture_jpg_bytes()
    resp = http.post(
        _IMPORT_PATH,
        files={
            "image": ("lesson_import_fixture.jpg", img, "image/jpeg"),
        },
    )
    assert resp.status_code == 201, resp.text
    draft = resp.json()
    draft_id = draft["id"]
    assert draft["status"] == "extracting"

    cron = http.post(
        _CRON_PATH,
        headers={"Authorization": f"Bearer {cron_secret}"},
    )
    assert cron.status_code == 200, cron.text
    summary = cron.json()
    assert summary["claimed"] == 1, summary

    fetched = http.get(_DRAFT_PATH_TMPL.format(draft_id=draft_id))
    assert fetched.status_code == 200, fetched.text
    fetched_draft = fetched.json()
    assert fetched_draft["id"] == draft_id
    assert fetched_draft["extract_attempts"] == 1
    assert fetched_draft["status"] in {"pending", "extract_failed"}, fetched_draft

