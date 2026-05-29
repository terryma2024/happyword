"""Generate short bilingual stories for vocabulary pack scene metadata."""

from __future__ import annotations

import json
from typing import Any

from app.services import llm_providers
from app.services.llm_service import LlmCallError

PACK_STORY_TIMEOUT_SECONDS = 30.0
_WORD_PREVIEW_LIMIT = 24


def _compact_word(item: dict[str, Any]) -> dict[str, Any]:
    compact: dict[str, Any] = {}
    for src, dst in (
        ("word", "word"),
        ("meaningZh", "meaning_zh"),
        ("meaning_zh", "meaning_zh"),
        ("category", "category"),
        ("difficulty", "difficulty"),
    ):
        value = item.get(src)
        if value is not None and dst not in compact:
            compact[dst] = value
    return compact


def build_pack_story_prompt(*, pack_name: str, words: list[dict[str, Any]]) -> str:
    preview = [_compact_word(w) for w in words[:_WORD_PREVIEW_LIMIT]]
    return (
        "Write a tiny fairy-tale intro for a children's English vocabulary pack.\n"
        "Return only valid JSON with exactly this shape:\n"
        '{"story_en":"...","story_zh":"..."}\n'
        "Rules:\n"
        "- story_en: English only, one sentence, 8-18 words, warm and concrete.\n"
        "- story_zh: Chinese only, one sentence, 20-60 Chinese characters.\n"
        "- Match the pack theme and sampled words; do not list vocabulary mechanically.\n"
        "- The server will store these values as scene.storyEn and scene.storyZh.\n\n"
        f"Pack name: {pack_name.strip() or 'Vocabulary Pack'}\n"
        f"Sample words JSON: {json.dumps(preview, ensure_ascii=False)}"
    )


def _story_string(payload: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    joined = ", ".join(keys)
    raise LlmCallError(f"LLM story payload is missing {joined}")


async def generate_pack_story(
    *,
    pack_name: str,
    words: list[dict[str, Any]],
) -> tuple[str, dict[str, str]]:
    prompt = build_pack_story_prompt(pack_name=pack_name, words=words)
    model, payload = await llm_providers.generate_json_text_with_provider(
        prompt=prompt,
        timeout_seconds=PACK_STORY_TIMEOUT_SECONDS,
    )
    return (
        model,
        {
            "storyEn": _story_string(payload, "storyEn", "story_en"),
            "storyZh": _story_string(payload, "storyZh", "story_zh"),
        },
    )
