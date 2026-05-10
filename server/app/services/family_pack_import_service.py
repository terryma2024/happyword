"""V0.8.1 — image → lesson extraction → family-pack draft rows only."""

from __future__ import annotations

import re
from typing import Any

from app.models.family_pack_definition import FamilyPackDefinition
from app.services import family_pack_service
from app.services import lesson_service


def _slug_word(word: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", "-", word.strip().lower()).strip("-")
    return cleaned or "word"


async def upload_family_pack_image(payload: bytes, mime: str) -> str:
    return await lesson_service.upload_lesson_image(payload, mime)


async def extract_family_pack_image(payload: bytes, mime: str) -> tuple[str, dict[str, Any]]:
    return await lesson_service.extract_lesson_payload(payload, mime)


def extracted_words_to_rows(*, family_id: str, extracted: dict[str, Any]) -> list[dict[str, Any]]:
    """Map lesson-style vision JSON into batch-upsert rows."""
    cat_id = str(extracted.get("category_id") or "custom").strip().lower()
    cat_obj = extracted.get("category")
    if isinstance(cat_obj, dict) and isinstance(cat_obj.get("id"), str):
        cat_id = str(cat_obj["id"]).strip().lower()
    words_raw = extracted.get("words", [])
    if not isinstance(words_raw, list):
        return []

    prefix = family_pack_service.CustomIdContract(family_id=family_id).prefix
    rows: list[dict[str, Any]] = []
    for item in words_raw:
        if not isinstance(item, dict):
            continue
        word = item.get("word")
        meaning = item.get("meaningZh") or item.get("meaning_zh")
        if not isinstance(word, str) or not isinstance(meaning, str):
            continue
        difficulty = item.get("difficulty", 1)
        category_val = item.get("category")
        row: dict[str, Any] = {
            "word_id": f"{prefix}{_slug_word(word)}",
            "source": "custom",
            "word": word.strip(),
            "meaning_zh": meaning.strip(),
            "category": category_val if isinstance(category_val, str) else cat_id,
            "difficulty": difficulty if isinstance(difficulty, int) else 1,
        }
        ex_en = item.get("example_en") or item.get("exampleEn")
        ex_zh = item.get("example_zh") or item.get("exampleZh")
        nested_ex = item.get("example")
        if isinstance(nested_ex, dict):
            if ex_en is None:
                ex_en = nested_ex.get("en")
            if ex_zh is None:
                ex_zh = nested_ex.get("zh")
        if isinstance(ex_en, str) and ex_en.strip():
            row["example_en"] = ex_en.strip()
        if isinstance(ex_zh, str) and ex_zh.strip():
            row["example_zh"] = ex_zh.strip()
        rows.append(row)
    return rows


async def import_image_to_draft(
    *,
    definition: FamilyPackDefinition,
    payload: bytes,
    mime: str,
    parent_user_id: str,
) -> tuple[str, str, int, object, list[dict[str, Any]]]:
    source_image_url = await upload_family_pack_image(payload, mime)
    model_name, extracted = await extract_family_pack_image(payload, mime)
    rows = extracted_words_to_rows(family_id=definition.family_id, extracted=extracted)
    draft, errors = await family_pack_service.batch_upsert_draft_words(
        definition=definition,
        rows=rows,
        parent_user_id=parent_user_id,
    )
    imported = len(rows) - len(errors)
    return source_image_url, model_name, imported, draft, errors
