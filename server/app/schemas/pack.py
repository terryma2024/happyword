from datetime import datetime

from pydantic import BaseModel


class PackWord(BaseModel):
    id: str
    word: str
    meaningZh: str
    category: str
    difficulty: int


class PackResponse(BaseModel):
    version: int
    schema_version: int = 1
    published_at: datetime
    words: list[PackWord]
