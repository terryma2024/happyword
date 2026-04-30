"""Admin word CRUD endpoints (V0.5.2).

Soft-delete model: `DELETE` sets `deleted_at` and is the only way a word
exits the public pack JSON. Listings exclude soft-deleted rows by default;
operators can opt in via `?include_deleted=true` for audit / undo flows.
"""

from datetime import UTC, datetime

from beanie.operators import RegEx
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.deps import current_admin_user
from app.models.user import User
from app.models.word import Word
from app.schemas.admin_word import (
    WordCreateIn,
    WordListOut,
    WordOut,
    WordUpdateIn,
)

router = APIRouter(prefix="/api/v1/admin/words", tags=["admin-words"])


def _to_out(w: Word) -> WordOut:
    return WordOut(
        id=w.id,
        word=w.word,
        meaningZh=w.meaningZh,
        category=w.category,
        difficulty=w.difficulty,
        created_at=w.created_at,
        updated_at=w.updated_at,
        deleted_at=w.deleted_at,
        distractors=w.distractors,
        example_sentence_en=w.example_sentence_en,
        example_sentence_zh=w.example_sentence_zh,
    )


@router.get("", response_model=WordListOut)
async def list_words(
    _admin: User = Depends(current_admin_user),
    category: str | None = Query(None, max_length=32),
    difficulty: int | None = Query(None, ge=1, le=5),
    q: str | None = Query(None, max_length=64),
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=500),
    include_deleted: bool = Query(False),
) -> WordListOut:
    query: dict[str, object] = {}
    if not include_deleted:
        query["deleted_at"] = None
    if category is not None:
        query["category"] = category
    if difficulty is not None:
        query["difficulty"] = difficulty

    find = Word.find(query)
    if q:
        # Case-insensitive partial match on the English headword. Beanie's
        # RegEx wraps a Mongo `$regex` filter; no risk of injection because
        # the user input is escaped by motor's BSON layer.
        find = find.find(RegEx(Word.word, pattern=q, options="i"))

    total = await find.count()
    items = await find.skip((page - 1) * size).limit(size).to_list()
    return WordListOut(
        items=[_to_out(w) for w in items],
        total=total,
        page=page,
        size=size,
    )


@router.get("/{word_id}", response_model=WordOut)
async def get_word(
    word_id: str,
    _admin: User = Depends(current_admin_user),
    include_deleted: bool = Query(False),
) -> WordOut:
    w = await Word.find_one(Word.id == word_id)
    if w is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": {"code": "WORD_NOT_FOUND", "message": f"No word with id={word_id!r}"}},
        )
    if w.deleted_at is not None and not include_deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": {"code": "WORD_NOT_FOUND", "message": f"No word with id={word_id!r}"}},
        )
    return _to_out(w)


@router.post("", response_model=WordOut, status_code=status.HTTP_201_CREATED)
async def create_word(
    body: WordCreateIn,
    _admin: User = Depends(current_admin_user),
) -> WordOut:
    existing = await Word.find_one(Word.id == body.id)
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error": {
                    "code": "DUPLICATE_ID",
                    "message": f"Word with id={body.id!r} already exists",
                }
            },
        )
    now = datetime.now(tz=UTC)
    w = Word(
        id=body.id,
        word=body.word,
        meaningZh=body.meaningZh,
        category=body.category,
        difficulty=body.difficulty,
        created_at=now,
        updated_at=now,
    )
    await w.insert()
    return _to_out(w)


@router.put("/{word_id}", response_model=WordOut)
async def update_word(
    word_id: str,
    body: WordUpdateIn,
    _admin: User = Depends(current_admin_user),
) -> WordOut:
    w = await Word.find_one(Word.id == word_id)
    if w is None or w.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": {"code": "WORD_NOT_FOUND", "message": f"No word with id={word_id!r}"}},
        )
    patch = body.model_dump(exclude_unset=True)
    for k, v in patch.items():
        setattr(w, k, v)
    w.updated_at = datetime.now(tz=UTC)
    await w.save()
    return _to_out(w)


@router.delete("/{word_id}", status_code=status.HTTP_204_NO_CONTENT)
async def soft_delete_word(
    word_id: str,
    _admin: User = Depends(current_admin_user),
) -> None:
    w = await Word.find_one(Word.id == word_id)
    if w is None or w.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": {
                    "code": "WORD_NOT_FOUND",
                    "message": f"No active word with id={word_id!r}",
                }
            },
        )
    w.deleted_at = datetime.now(tz=UTC)
    w.updated_at = w.deleted_at
    await w.save()
