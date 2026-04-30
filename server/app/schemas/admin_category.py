"""Admin Category CRUD shapes (V0.5.5).

Wire format mixes camelCase incoming (matches the public pack JSON
contract) with snake_case fields in responses (consistent with
:mod:`app.schemas.admin_word`). Pydantic ``populate_by_name`` lets curl
users submit either casing.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

_ID_PATTERN = r"^[a-z0-9]+(?:-[a-z0-9]+)*$"


class CategoryCreateIn(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    id: str = Field(..., pattern=_ID_PATTERN, min_length=2, max_length=32)
    label_en: str = Field(..., alias="labelEn", min_length=1, max_length=64)
    label_zh: str = Field(..., alias="labelZh", min_length=1, max_length=64)
    story_zh: str | None = Field(None, alias="storyZh", max_length=400)


class CategoryUpdateIn(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    label_en: str | None = Field(None, alias="labelEn", min_length=1, max_length=64)
    label_zh: str | None = Field(None, alias="labelZh", min_length=1, max_length=64)
    story_zh: str | None = Field(None, alias="storyZh", max_length=400)


class CategoryOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    label_en: str
    label_zh: str
    story_zh: str | None
    source_image_url: str | None
    source: Literal["manual", "lesson-import"]
    created_at: datetime
    updated_at: datetime


class CategoryListOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    items: list[CategoryOut]
    total: int
