"""Admin word CRUD request/response shapes (V0.5.2).

CamelCase aliasing happens in the public pack JSON serializer (V0.5.3+).
Admin endpoints stay in snake_case for ergonomic curl / scripting.
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

# kebab-case slug, e.g. "fruit-apple" / "school-supplies-pencil"
_ID_PATTERN = r"^[a-z0-9]+(?:-[a-z0-9]+)+$"
_CATEGORY_PATTERN = r"^[a-z0-9]+(?:-[a-z0-9]+)*$"


class WordCreateIn(BaseModel):
    """Body for `POST /api/v1/admin/words`."""

    model_config = ConfigDict(extra="forbid")

    id: str = Field(..., pattern=_ID_PATTERN, min_length=3, max_length=64)
    word: str = Field(..., min_length=1, max_length=64)
    meaningZh: str = Field(..., min_length=1, max_length=64)
    category: str = Field(..., pattern=_CATEGORY_PATTERN, max_length=32)
    difficulty: int = Field(..., ge=1, le=5)


class WordUpdateIn(BaseModel):
    """Body for `PUT /api/v1/admin/words/{id}` — partial merge."""

    model_config = ConfigDict(extra="forbid")

    word: str | None = Field(None, min_length=1, max_length=64)
    meaningZh: str | None = Field(None, min_length=1, max_length=64)
    category: str | None = Field(None, pattern=_CATEGORY_PATTERN, max_length=32)
    difficulty: int | None = Field(None, ge=1, le=5)


class WordOut(BaseModel):
    """Single word response shape."""

    model_config = ConfigDict(extra="forbid")

    id: str
    word: str
    meaningZh: str
    category: str
    difficulty: int
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None = None
    # V0.5.4: optional LLM-augmented fields (None until an llm_drafts row is
    # approved). Surfacing them on the admin endpoint lets curl users
    # inspect what's been merged into the word post-approval.
    distractors: list[str] | None = None
    example_sentence_en: str | None = None
    example_sentence_zh: str | None = None


class WordListOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    items: list[WordOut]
    total: int
    page: int
    size: int
