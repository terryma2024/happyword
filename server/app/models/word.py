from datetime import UTC, datetime
from typing import Annotated

from beanie import Document, Indexed
from pydantic import Field


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


class Word(Document):
    id: Annotated[str, Indexed(unique=True)]
    word: str
    meaningZh: str
    category: Annotated[str, Indexed()]
    difficulty: int
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)

    class Settings:
        name = "words"
