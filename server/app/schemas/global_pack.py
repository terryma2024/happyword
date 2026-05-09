"""V0.6.5 — wire schemas for /api/v1/admin/global-packs/** and the public
/api/v1/public/global-packs/latest.json endpoint."""

from __future__ import annotations

from datetime import datetime  # noqa: TC003 — pydantic v2 needs this at runtime
from typing import Any

from pydantic import BaseModel, Field


class GlobalPackCreateIn(BaseModel):
    name: str
    description: str | None = None
    scene: dict[str, Any] = Field(default_factory=dict)
    pack_id: str | None = None


class GlobalPackPatchIn(BaseModel):
    name: str | None = None
    description: str | None = None
    scene: dict[str, Any] | None = None


class GlobalPackDefinitionOut(BaseModel):
    pack_id: str
    name: str
    description: str | None = None
    scene: dict[str, Any] = Field(default_factory=dict)
    state: str
    created_at: datetime
    updated_at: datetime
    archived_at: datetime | None = None
    # V0.6.5 — wire shape names this for the admin context. Underlying field
    # in `FamilyPackDefinition` is `created_by_parent_id` (re-used via the
    # global-family sentinel). The router serializer maps the two.
    created_by_admin_id: str


class GlobalPackDraftWordIn(BaseModel):
    id: str
    word: str
    meaningZh: str  # noqa: N815 — wire schema is camelCase by spec contract
    category: str
    difficulty: int
    distractors: list[str] | None = None
    exampleEn: str | None = None  # noqa: N815
    exampleZh: str | None = None  # noqa: N815
    illustrationUrl: str | None = None  # noqa: N815
    audioUrl: str | None = None  # noqa: N815


class GlobalPackPublishIn(BaseModel):
    notes: str | None = None


class GlobalPackVersionOut(BaseModel):
    version: int
    schema_version: int
    word_count: int
    published_at: datetime
    notes: str | None = None


class GlobalPackPointerOut(BaseModel):
    pack_id: str
    current_version: int
    previous_version: int | None = None
    updated_at: datetime


class GlobalPackEntryInMerged(BaseModel):
    pack_id: str
    name: str
    description: str | None = None
    scene: dict[str, Any] = Field(default_factory=dict)
    version: int
    schema_version: int
    published_at: datetime
    words: list[dict[str, Any]]


class GlobalPacksLatestOut(BaseModel):
    schema_version: int
    merged_at: datetime
    packs: list[GlobalPackEntryInMerged]
