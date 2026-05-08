"""Opt-in live OpenAI vision test for `lesson_service.extract_lesson_payload`.

Mirrors `test_llm_live_smoke.py`: gated behind ``LIVE_OPENAI=1`` and
reads ``OPENAI_API_KEY`` from the env or ``~/.env`` (no python-dotenv
runtime dep). Skipped by default so CI / `uv run pytest` stay green
without quota burn or network flakiness.

To run locally:

    LIVE_OPENAI=1 uv run pytest tests/test_lesson_service_live.py -v -s

This is the only test that actually exercises the production
``response_format=json_object`` prompt against a real textbook page —
without it, prompt regressions (like the V0.7 missing-"json"-token
bug, see PR #49) only surface in production. The shared offline
guard in ``test_lesson_service.py`` covers the static contract; this
file covers the dynamic one (does the model actually return the new
``example_en`` field, are the cloze sentences usable, …).

Fixture: ``entry/src/ohosTest/resources/rawfile/lesson_import_fixture.jpg``
— same image the HarmonyOS UI test ships, so this test mirrors what
real users upload.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import AsyncIterator


# Path traversal: tests/ → server/ → repo-root → entry/…
FIXTURE_PATH = (
    Path(__file__).parent.parent.parent
    / "entry"
    / "src"
    / "ohosTest"
    / "resources"
    / "rawfile"
    / "lesson_import_fixture.jpg"
)


def _load_key_from_dotenv() -> str | None:
    """Read OPENAI_API_KEY from ~/.env without importing python-dotenv."""
    env_path = Path.home() / ".env"
    if not env_path.exists():
        return None
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        if key.strip() == "OPENAI_API_KEY":
            return value.strip().strip('"').strip("'") or None
    return None


def _resolve_live_key() -> str | None:
    direct = os.environ.get("OPENAI_API_KEY", "").strip()
    if direct:
        return direct
    return _load_key_from_dotenv()


@pytest.fixture
async def live_key(monkeypatch: pytest.MonkeyPatch) -> AsyncIterator[str]:
    if os.environ.get("LIVE_OPENAI", "").strip() not in {"1", "true", "yes"}:
        pytest.skip(
            "LIVE_OPENAI not set — live OpenAI lesson test skipped "
            "(run with `LIVE_OPENAI=1 uv run pytest "
            "tests/test_lesson_service_live.py -v -s`)"
        )
    key = _resolve_live_key()
    if not key:
        pytest.skip("LIVE_OPENAI=1 but no OPENAI_API_KEY in env or ~/.env")
    # Override the autouse `_env` fixture which sets the key to "".
    monkeypatch.setenv("OPENAI_API_KEY", key)
    from app.config import get_settings  # noqa: PLC0415
    from app.services import llm_service  # noqa: PLC0415

    get_settings.cache_clear()
    await llm_service.reset_openai_client()
    try:
        yield key
    finally:
        # Close the live httpx pool so pytest's filterwarnings=["error"]
        # doesn't trip on ResourceWarning at interpreter exit.
        await llm_service.reset_openai_client()
        get_settings.cache_clear()


@pytest.mark.asyncio
async def test_extract_lesson_payload_live(live_key: str) -> None:  # noqa: ARG001
    """Run the production prompt against the textbook fixture and assert
    the returned payload obeys the new schema:

      * top-level `category_id` / `label_en` / `label_zh` / `words`
      * each word has `word` / `meaningZh` / `difficulty` /
        `example_en`
      * `example_en` is a 5–15 word sentence and contains the
        headword (case-insensitive) so it works as a cloze prompt
    """
    from app.services.lesson_service import extract_lesson_payload  # noqa: PLC0415

    assert FIXTURE_PATH.exists(), f"fixture missing: {FIXTURE_PATH}"
    image_bytes = FIXTURE_PATH.read_bytes()
    assert len(image_bytes) > 1000, "fixture image is suspiciously small"

    model_used, payload = await extract_lesson_payload(image_bytes, "image/jpeg")

    print(f"\n[lesson-live] model={model_used}")
    print(f"[lesson-live] category_id={payload.get('category_id')!r}")
    print(f"[lesson-live] label_en={payload.get('label_en')!r}")
    print(f"[lesson-live] label_zh={payload.get('label_zh')!r}")
    print(f"[lesson-live] story_zh={payload.get('story_zh')!r}")
    print(
        "[lesson-live] payload (pretty):\n"
        + json.dumps(payload, ensure_ascii=False, indent=2)
    )

    # Top-level shape contract.
    assert isinstance(payload, dict)
    assert isinstance(payload.get("category_id"), str) and payload["category_id"]
    assert isinstance(payload.get("label_en"), str) and payload["label_en"]
    assert isinstance(payload.get("label_zh"), str) and payload["label_zh"]
    words = payload.get("words")
    assert isinstance(words, list) and words, "expected non-empty `words` array"

    # Per-word contract — including the new `example_en` field.
    bad_examples: list[str] = []
    for entry in words:
        assert isinstance(entry, dict)
        word = entry.get("word")
        meaning_zh = entry.get("meaningZh")
        difficulty = entry.get("difficulty")
        example_en = entry.get("example_en")

        assert isinstance(word, str) and word, f"missing word in {entry!r}"
        assert isinstance(meaning_zh, str) and meaning_zh, (
            f"missing meaningZh in {entry!r}"
        )
        assert isinstance(difficulty, int), f"non-int difficulty in {entry!r}"
        assert 1 <= difficulty <= 5, f"difficulty out of 1..5 in {entry!r}"
        assert isinstance(example_en, str) and example_en, (
            f"missing example_en in {entry!r}"
        )

        # Cloze quality checks: 5–15 words and the headword appears in
        # the sentence so it can be blanked. We collect failures rather
        # than aborting on the first so the printed report is useful.
        token_count = len(re.findall(r"[A-Za-z']+", example_en))
        if not (4 <= token_count <= 16):
            bad_examples.append(
                f"length: word={word!r} count={token_count} sentence={example_en!r}"
            )
        # Word boundary match so "cat" doesn't accidentally pass on
        # "category". Allow simple plural / -s / -ed / -ing inflection.
        pattern = re.compile(
            rf"\b{re.escape(word)}(?:s|es|ed|ing|d)?\b",
            flags=re.IGNORECASE,
        )
        if not pattern.search(example_en):
            bad_examples.append(
                f"missing-word: word={word!r} sentence={example_en!r}"
            )

    if bad_examples:
        print("[lesson-live] cloze-quality issues:")
        for issue in bad_examples:
            print(f"  - {issue}")

    # Be permissive on the cloze-quality assertion so noisy model
    # output doesn't false-fail this opt-in smoke; gate hard at >25%
    # bad rate which would indicate a real prompt regression.
    threshold = max(1, len(words) // 4)
    assert len(bad_examples) <= threshold, (
        f"too many cloze-quality issues "
        f"({len(bad_examples)} > threshold {threshold} of {len(words)} words):"
        f"\n" + "\n".join(bad_examples)
    )
