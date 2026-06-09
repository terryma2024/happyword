"""E2E coverage for HTTP features backed by LLM services.

These tests hit the deployed app over HTTP, including auth/session and Mongo
side effects, but use the request-scoped E2E LLM stub so they remain
deterministic and do not spend model quota.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from bson import ObjectId

from tests.e2e._utils.auth import admin_headers
from tests.e2e._utils.llm_stub import llm_stub_headers

if TYPE_CHECKING:
    import httpx

    from tests.e2e._utils.auth import ParentSession
    from tests.e2e._utils.db import MongoDB

_CRON_PATH = "/api/v1/admin/cron/extract-pending"
_MODEL = "e2e-llm-stub"


def _strip_env(name: str) -> str:
    return os.environ.get(name, "").strip()


def _fixture_jpg_bytes() -> bytes:
    path = Path(__file__).resolve().parent / "_fixtures/lesson_import_fixture.jpg"
    if not path.exists():
        pytest.skip(f"fixture image not found: {path}")
    return path.read_bytes()


def _assert_stub_words(words: list[dict[str, object]]) -> None:
    by_word = {str(item.get("word")): item for item in words}
    assert by_word["apple"]["meaningZh"] == "苹果"
    assert by_word["banana"]["meaningZh"] == "香蕉"


@pytest.mark.e2e
def test_scan_words_uses_stubbed_llm(http: httpx.Client) -> None:
    resp = http.post(
        "/api/v1/admin/llm/scan-words",
        headers=llm_stub_headers(),
        files={"image": ("lesson_import_fixture.jpg", _fixture_jpg_bytes(), "image/jpeg")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["model"] == _MODEL
    assert body["result"]["words"] == [
        {"word": "apple", "gloss_zh": "苹果"},
        {"word": "banana", "gloss_zh": "香蕉"},
    ]


@pytest.mark.e2e
def test_admin_word_drafts_use_stubbed_llm(
    http: httpx.Client,
    admin_token: str,
    run_id: str,
) -> None:
    word_id = f"e2e-{run_id}-llm-draft-apple"
    headers = admin_headers(admin_token) | llm_stub_headers()
    create = http.post(
        "/api/v1/admin/words",
        headers=admin_headers(admin_token),
        json={
            "id": word_id,
            "word": "apple",
            "meaningZh": "苹果",
            "category": "fruit",
            "difficulty": 1,
        },
    )
    assert create.status_code == 201, create.text

    distractors = http.post(
        f"/api/v1/admin/words/{word_id}/generate-distractors",
        headers=headers,
    )
    assert distractors.status_code == 201, distractors.text
    distractor_body = distractors.json()
    assert distractor_body["model"] == _MODEL
    assert distractor_body["content"]["distractors"] == ["pear", "grape", "orange"]

    example = http.post(
        f"/api/v1/admin/words/{word_id}/generate-example",
        headers=headers,
    )
    assert example.status_code == 201, example.text
    example_body = example.json()
    assert example_body["model"] == _MODEL
    assert example_body["content"] == {"en": "I eat an apple.", "zh": "我吃一个苹果。"}


@pytest.mark.e2e
def test_family_pack_import_image_uses_stubbed_llm(
    http: httpx.Client,
    parent: ParentSession,
    run_id: str,
) -> None:
    create = http.post(
        "/api/v1/family/_/family-packs",
        json={"name": f"E2E {run_id} llm import"},
    )
    assert create.status_code == 201, create.text
    pack_id = create.json()["pack_id"]

    imported = http.post(
        f"/api/v1/family/_/family-packs/{pack_id}/import-image",
        headers=llm_stub_headers(),
        files={"image": ("lesson_import_fixture.jpg", _fixture_jpg_bytes(), "image/jpeg")},
    )
    assert imported.status_code == 201, imported.text
    body = imported.json()
    assert body["model"] == _MODEL
    assert body["source_image_url"].startswith("stub://e2e/llm/")
    assert body["imported_count"] == 2
    assert body["draft"]["word_count"] == 2
    _assert_stub_words(body["draft"]["words"])

    detail = http.get(f"/api/v1/family/_/family-packs/{pack_id}")
    assert detail.status_code == 200, detail.text
    scene = detail.json()["definition"]["scene"]
    assert scene["storyEn"] == "Apple and banana open a tiny market."
    assert scene["storyZh"] == "苹果和香蕉开了一间小小集市。"


@pytest.mark.e2e
async def test_lesson_import_cron_uses_stubbed_llm(
    http: httpx.Client,
    mongo: MongoDB,
    run_id: str,
) -> None:
    cron_secret = _strip_env("E2E_CRON_SECRET")
    if not cron_secret:
        pytest.skip("E2E_CRON_SECRET is not set (must match target CRON_SECRET)")

    family_id = f"fam-e2e-llm-{run_id[:8]}"
    await mongo["lesson_import_drafts"].delete_many({"status": "extracting"})

    created = http.post(
        f"/api/v1/family/{family_id}/lessons/import",
        headers=llm_stub_headers(),
        files={"image": ("lesson_import_fixture.jpg", _fixture_jpg_bytes(), "image/jpeg")},
    )
    assert created.status_code == 201, created.text
    draft_id = created.json()["id"]
    assert created.json()["source_image_url"].startswith("stub://e2e/llm/")

    cron = http.post(
        _CRON_PATH,
        headers={"Authorization": f"Bearer {cron_secret}"} | llm_stub_headers(),
    )
    assert cron.status_code == 200, cron.text
    assert cron.json() == {"claimed": 1, "succeeded": 1, "failed": 0}

    fetched = http.get(f"/api/v1/family/{family_id}/lesson-drafts/{draft_id}")
    assert fetched.status_code == 200, fetched.text
    body = fetched.json()
    assert body["status"] == "pending"
    assert body["model"] == _MODEL
    assert body["extract_attempts"] == 1
    assert ObjectId.is_valid(draft_id)
    _assert_stub_words(body["extracted"]["words"])
