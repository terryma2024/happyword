"""Admin pack publish/rollback request/response shapes (V0.5.3)."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PublishIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    notes: str | None = Field(None, max_length=500)


class PublishOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    version: int
    schema_version: int
    word_count: int
    published_at: datetime
    published_by: str
    notes: str | None = None


class RollbackOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    current_version: int
    previous_version: int | None


class PointerOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    current_version: int
    previous_version: int | None
    published_at: datetime | None = None


class PackListItem(BaseModel):
    model_config = ConfigDict(extra="forbid")
    version: int
    schema_version: int
    published_at: datetime
    published_by: str
    word_count: int
    notes: str | None = None


class PackListOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    items: list[PackListItem]
    total: int
    page: int
    size: int


class PackDetailOut(BaseModel):
    """Full word_pack document (admin only — used by /admin/packs/{version})."""

    model_config = ConfigDict(extra="forbid")
    version: int
    schema_version: int
    published_at: datetime
    published_by: str
    notes: str | None = None
    words: list[dict[str, object]]
    categories: list[dict[str, object]] | None = None
