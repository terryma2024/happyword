from datetime import UTC, datetime
from typing import Annotated

from beanie import Document, Indexed
from pydantic import Field


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


class Word(Document):
    # Override Beanie's PydanticObjectId-typed id with a stable string slug.
    id: Annotated[str, Indexed(unique=True)]  # type: ignore[assignment]
    word: str
    meaningZh: str
    category: Annotated[str, Indexed()]
    difficulty: int
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)

    class Settings:
        name = "words"
