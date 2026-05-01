"""Admin stats endpoint (V0.5.7).

NOTE (V0.5.8): Admin auth temporarily removed. Anyone reachable on the
network can call these endpoints. Per-family auth returns in V0.6.
"""

from fastapi import APIRouter

from app.models.category import Category
from app.models.lesson_import_draft import LessonImportDraft
from app.models.llm_draft import LlmDraft
from app.models.user import User
from app.models.word import Word
from app.models.word_pack import WordPack
from app.schemas.admin_stats import StatsOut
from app.services import pack_service

router = APIRouter(prefix="/api/v1/admin", tags=["admin-stats"])


@router.get("/stats", response_model=StatsOut)
async def get_stats() -> StatsOut:
    user_count = await User.find_all().count()
    word_count = await Word.find(
        Word.deleted_at == None  # noqa: E711 - Beanie demands `==` for None
    ).count()
    category_count = await Category.find_all().count()
    pack_count = await WordPack.find_all().count()

    latest_pack = await pack_service.get_current_pack()
    latest_version = latest_pack.version if latest_pack is not None else None
    last_published_at = latest_pack.published_at if latest_pack is not None else None

    llm_draft_pending = await LlmDraft.find(LlmDraft.status == "pending").count()
    lesson_import_draft_pending = await LessonImportDraft.find(
        LessonImportDraft.status == "pending"
    ).count()

    return StatsOut(
        user_count=user_count,
        word_count=word_count,
        category_count=category_count,
        pack_count=pack_count,
        latest_version=latest_version,
        last_published_at=last_published_at,
        llm_draft_pending=llm_draft_pending,
        lesson_import_draft_pending=lesson_import_draft_pending,
    )
