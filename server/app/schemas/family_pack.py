"""V0.6.3 — Pydantic wire schemas for the family-pack API.

Mirrors spec §6.3. All inbound shapes are strict (Pydantic v2 forbids extra
fields by default in our routers); outbound shapes have stable snake_case
keys to match the rest of the V0.6 wire contract.
"""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 — pydantic needs runtime type
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field

# ---------------------------------------------------------------------------
# Inbound — definitions
# ---------------------------------------------------------------------------


class FamilyPackCreateIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str, Field(min_length=1, max_length=32)]
    description: Annotated[str | None, Field(default=None, max_length=200)]


class FamilyPackPatchIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: Annotated[str | None, Field(default=None, min_length=1, max_length=32)]
    description: Annotated[str | None, Field(default=None, max_length=200)]


class FamilyPackPublishIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    notes: Annotated[str | None, Field(default=None, max_length=500)]


class FamilyPackDraftWordIn(BaseModel):
    """Body of `PUT /api/v1/parent/family-packs/{id}/draft/words/{word_id}`.

    `source` selects the entry shape:
    - `global`: this draft pulls (or re-pulls) a global admin word; only the
      `id` (the path param) matters; server stores the latest global view.
    - `custom`: parent supplies the full entry. The path `word_id` MUST
      start with `fam-<family_id_8>-` (validated by the service).
    - `hidden`: parent wants this global id hidden; we persist
      `{ id: <word_id>, hidden: true }` only.
    """

    model_config = ConfigDict(extra="forbid")

    source: Literal["global", "custom", "hidden"]
    word: Annotated[str | None, Field(default=None, min_length=1, max_length=64)]
    meaning_zh: Annotated[str | None, Field(default=None, min_length=1, max_length=128)]
    category: Annotated[str | None, Field(default=None, min_length=1, max_length=64)]
    difficulty: Annotated[int | None, Field(default=None, ge=1, le=5)]
    distractors: list[str] | None = None
    example_en: Annotated[str | None, Field(default=None, max_length=200)]
    example_zh: Annotated[str | None, Field(default=None, max_length=200)]
    illustration_url: Annotated[str | None, Field(default=None, max_length=500)]
    audio_url: Annotated[str | None, Field(default=None, max_length=500)]


# ---------------------------------------------------------------------------
# Outbound
# ---------------------------------------------------------------------------


class FamilyPackDefinitionOut(BaseModel):
    pack_id: str
    family_id: str
    name: str
    description: str | None
    state: Literal["active", "archived"]
    created_at: datetime
    updated_at: datetime
    archived_at: datetime | None
    created_by_parent_id: str


class FamilyPackPointerOut(BaseModel):
    current_version: int
    previous_version: int | None
    updated_at: datetime


class FamilyPackVersionListItem(BaseModel):
    version: int
    published_at: datetime
    word_count: int
    notes: str | None


class FamilyPackListItem(BaseModel):
    definition: FamilyPackDefinitionOut
    pointer: FamilyPackPointerOut | None
    current_word_count: int  # 0 when no published version yet
    draft_word_count: int
    has_unpublished_changes: bool


class FamilyPackListOut(BaseModel):
    items: list[FamilyPackListItem]


class FamilyPackDraftOut(BaseModel):
    pack_id: str
    words: list[dict[str, Any]]
    word_count: int
    max_words: int
    updated_at: datetime


class FamilyPackDetailOut(BaseModel):
    definition: FamilyPackDefinitionOut
    pointer: FamilyPackPointerOut | None
    current_pack: dict[str, Any] | None
    draft: FamilyPackDraftOut


class FamilyPackPublishOut(BaseModel):
    pack_id: str
    version: int
    schema_version: int
    word_count: int
    published_at: datetime
    published_by_parent_id: str
    notes: str | None


class FamilyPackRollbackOut(BaseModel):
    pack_id: str
    current_version: int
    previous_version: int | None


class FamilyPackVersionListOut(BaseModel):
    items: list[FamilyPackVersionListItem]


# Child-facing merged JSON


class FamilyPackEntryInMerged(BaseModel):
    pack_id: str
    name: str
    version: int
    schema_version: int
    words: list[dict[str, Any]]


class FamilyPacksMergedOut(BaseModel):
    schema_version: int
    family_id: str
    merged_at: datetime
    packs: list[FamilyPackEntryInMerged]
