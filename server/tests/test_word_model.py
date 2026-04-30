from datetime import UTC, datetime

import pytest

from app.models.word import Word


def test_word_id_field_has_no_explicit_indexed_annotation() -> None:
    """Regression guard: declaring ``Indexed(unique=True)`` on a field that maps
    to MongoDB's ``_id`` triggers ``InvalidIndexSpecificationOption`` on real
    MongoDB Atlas (``_id`` is always implicitly unique). ``mongomock-motor``
    does **not** enforce this rule, which is why this is the only test that
    catches a regression before deploy.
    """
    metadata = list(getattr(Word.model_fields["id"], "metadata", []))
    offenders = [
        m
        for m in metadata
        if type(m).__name__ == "Indexed" or getattr(m, "__name__", "") == "Indexed"
    ]
    assert not offenders, (
        "Word.id must NOT carry an Indexed(...) annotation. MongoDB rejects "
        "duplicate unique indexes on _id (InvalidIndexSpecificationOption)."
    )


@pytest.mark.asyncio
async def test_insert_and_query_by_category(db: object) -> None:
    now = datetime.now(tz=UTC)
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()
    await Word(
        id="place-school",
        word="school",
        meaningZh="学校",
        category="place",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()

    fruits = await Word.find(Word.category == "fruit").to_list()
    assert len(fruits) == 1
    assert fruits[0].word == "apple"


@pytest.mark.asyncio
async def test_word_id_is_unique(db: object) -> None:
    now = datetime.now(tz=UTC)
    await Word(
        id="fruit-apple",
        word="apple",
        meaningZh="苹果",
        category="fruit",
        difficulty=1,
        created_at=now,
        updated_at=now,
    ).insert()
    with pytest.raises(Exception):
        await Word(
            id="fruit-apple",
            word="apple",
            meaningZh="苹果",
            category="fruit",
            difficulty=1,
            created_at=now,
            updated_at=now,
        ).insert()
