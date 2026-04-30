import time
from datetime import UTC, datetime

from fastapi import APIRouter

from app.models.word import Word
from app.schemas.pack import PackResponse, PackWord

router = APIRouter(prefix="/api/v1", tags=["public"])


@router.get("/health")
async def health() -> dict[str, object]:
    return {"ok": True, "ts": int(time.time())}


@router.get("/packs/latest.json", response_model=PackResponse)
async def latest_pack() -> PackResponse:
    """V0.5.1: real-time pack from `words` collection. V0.5.3 will switch to snapshot."""
    rows = await Word.find_all().to_list()
    words = [
        PackWord(
            id=w.id,
            word=w.word,
            meaningZh=w.meaningZh,
            category=w.category,
            difficulty=w.difficulty,
        )
        for w in rows
    ]
    return PackResponse(
        version=1,
        schema_version=1,
        published_at=datetime.now(tz=UTC),
        words=words,
    )
