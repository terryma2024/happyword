"""V0.8.1 — image → lesson extraction → family-pack draft rows only."""

from __future__ import annotations

import re
from datetime import UTC, datetime
from typing import Any

from app.config import get_settings
from app.models.family_pack_definition import FamilyPackDefinition  # noqa: TC001
from app.models.lesson_import_draft import LessonImportDraft  # noqa: TC001
from app.services import family_pack_service, lesson_service


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


class LessonFamilyApproveError(RuntimeError):
    """Raised when lesson approve cannot upsert all rows into the family draft."""

    def __init__(self, message: str, *, errors: list[dict[str, Any]]) -> None:
        super().__init__(message)
        self.errors = errors


async def approve_lesson_draft_for_family(
    *,
    draft: LessonImportDraft,
    family_id: str,
    reviewer: str,
) -> dict[str, Any]:
    """Approve a pending lesson draft into this family's auto lesson-import pack.

    Words are **not** written to global ``words`` / ``categories``; they are
    upserted into the family's lesson-import :class:`FamilyPackDefinition`
    draft and immediately published so bound child devices see them in
    ``collect_child_vocabulary``.
    """
    fid = family_id.strip()
    if draft.family_id.strip() != fid:
        msg = f"draft family_id mismatch: {draft.family_id!r} vs path {fid!r}"
        raise ValueError(msg)

    payload = lesson_service.effective_lesson_extracted(draft)
    now = datetime.now(tz=UTC)
    cat_id = str(payload["category_id"]).strip().lower()
    label_en = str(payload.get("label_en", cat_id))
    label_zh = str(payload.get("label_zh", cat_id))
    story_zh = payload.get("story_zh")

    definition = await family_pack_service.ensure_lesson_import_pack_definition(
        family_id=fid
    )
    draft_obj = await family_pack_service.get_or_create_draft(
        definition=definition,
        parent_user_id=family_pack_service.LESSON_IMPORT_SYSTEM_PARENT_ID,
    )
    by_id: dict[str, dict[str, Any]] = {
        str(w.get("id")): w
        for w in draft_obj.words
        if isinstance(w.get("id"), str)
    }

    rows = extracted_words_to_rows(family_id=fid, extracted=payload)
    to_apply: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []

    for row in rows:
        wid = str(row.get("word_id", ""))
        if not wid:
            continue
        mz_new = str(row.get("meaning_zh", "")).strip()
        wtxt = str(row.get("word", "")).strip().lower()
        old = by_id.get(wid)
        if old and old.get("hidden") is not True:
            old_mz = str(old.get("meaningZh", "")).strip()
            old_w = str(old.get("word", "")).strip().lower()
            if old_mz == mz_new and old_w == wtxt:
                skipped.append({"id": wid, "word": wtxt, "reason": "DUPLICATE_ID"})
                continue
        to_apply.append(row)

    if to_apply:
        settings = get_settings()
        max_w = settings.family_pack_max_words
        existing_ids = {
            str(w.get("id")) for w in draft_obj.words if isinstance(w.get("id"), str)
        }
        net_new = 0
        for row in to_apply:
            wid = str(row.get("word_id", ""))
            if wid and wid not in existing_ids:
                net_new += 1
        if len(draft_obj.words) + net_new > max_w:
            raise family_pack_service.PackFull(definition.pack_id)

        prefix = family_pack_service.CustomIdContract(family_id=fid).prefix
        for row in to_apply:
            word_id = str(row.get("word_id", ""))
            pl = {k: v for k, v in row.items() if k != "word_id"}
            family_pack_service._build_entry(
                word_id=word_id, payload=pl, custom_prefix=prefix
            )

        _draft_obj, batch_errors = await family_pack_service.batch_upsert_draft_words(
            definition=definition,
            rows=to_apply,
            parent_user_id=family_pack_service.LESSON_IMPORT_SYSTEM_PARENT_ID,
        )

        if batch_errors:
            raise LessonFamilyApproveError(
                "Lesson approve failed while upserting the family draft",
                errors=batch_errors,
            )

        await family_pack_service.publish(
            definition=definition,
            parent_user_id=family_pack_service.LESSON_IMPORT_SYSTEM_PARENT_ID,
            notes="lesson-import approve",
        )

    created = [
        {"id": str(r.get("word_id", "")), "word": str(r.get("word", "")).strip().lower()}
        for r in to_apply
        if str(r.get("word_id", ""))
    ]

    return {
        "category": {
            "id": cat_id,
            "label_en": label_en,
            "label_zh": label_zh,
            "story_zh": story_zh,
            "source_image_url": draft.source_image_url,
            "source": "lesson-import",
            "created_at": now,
            "updated_at": now,
        },
        "created_words": created,
        "skipped_words": skipped,
        "reviewer": reviewer,
    }
