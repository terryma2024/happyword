"""Opt-in live OpenAI vision smoke test.

This test makes a real network call to OpenAI and is therefore *not*
part of the default offline pytest suite. It only runs when the env
flag ``LIVE_OPENAI=1`` is set — that gate is intentional, because the
project rule "every commit must run `uv run pytest` with 0 errors and
0 warnings" cannot tolerate a network-flaky / quota-flaky test.

To run locally:

* `LIVE_OPENAI=1 uv run pytest tests/test_llm_live_smoke.py -v -s`

The API key is read from `OPENAI_API_KEY` in the env, falling back to
`~/.env` (we don't take a runtime dep on python-dotenv just for this).

The fixture image is `tests/fixture_scan_words.jpg` — a textbook page
with a numbered "Vocabulary Preview" listing 15 clothing words. We
assert the model returns at least 10 of them, which both proves the
network path works AND that the prompt isn't dragging in section
headers / unit titles.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

EXPECTED_WORDS = {
    "shirt",
    "coat",
    "dress",
    "skirt",
    "blouse",
    "jacket",
    "suit",
    "tie",
    "belt",
    "sweater",
    "pants",
    "jeans",
    "pajamas",
    "shoes",
    "socks",
}

# Forbidden — these are unit titles / grammar topics / section banners
# that should NEVER be returned as memorisable vocabulary.
FORBIDDEN_NEEDLES = {
    "singular",
    "plural",
    "adjectives",
    "this",
    "that",
    "these",
    "those",
    "vocabulary preview",
    "shopping for clothing",
    "clothing",
    "colors",
}

FIXTURE_PATH = Path(__file__).parent / "fixture_scan_words.jpg"


def _load_key_from_dotenv() -> str | None:
    """Read OPENAI_API_KEY from ~/.env without importing python-dotenv.

    We don't take a runtime dep on python-dotenv just for opt-in tests —
    the file format we need is trivial.
    """
    env_path = Path.home() / ".env"
    if not env_path.exists():
        return None
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
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
            "LIVE_OPENAI not set — live OpenAI smoke test skipped "
            "(run with `LIVE_OPENAI=1 uv run pytest tests/test_llm_live_smoke.py -v -s`)"
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
async def test_extract_target_vocabulary_against_fixture_page(
    live_key: str,
) -> None:
    from app.services.llm_service import extract_target_vocabulary  # noqa: PLC0415

    image_bytes = FIXTURE_PATH.read_bytes()
    assert len(image_bytes) > 1000, "fixture image is suspiciously small"

    model_used, result = await extract_target_vocabulary(image_bytes, mime="image/jpeg")

    returned = {w.word.lower().strip() for w in result.words}
    matched = returned & EXPECTED_WORDS

    print(f"\n[live-smoke] model={model_used}")
    print(f"[live-smoke] returned ({len(returned)}): {sorted(returned)}")
    print(f"[live-smoke] matched  ({len(matched)}/15): {sorted(matched)}")
    if result.note:
        print(f"[live-smoke] note   : {result.note}")

    assert len(matched) >= 10, (
        f"expected >=10 of {sorted(EXPECTED_WORDS)} but model only returned {sorted(returned)}"
    )

    leaked = returned & FORBIDDEN_NEEDLES
    assert not leaked, (
        f"model returned section headers / grammar topics as vocabulary: {sorted(leaked)}"
    )
