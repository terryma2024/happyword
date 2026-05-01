import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from beanie import init_beanie
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient

from app.config import get_settings
from app.models.category import Category
from app.models.lesson_import_draft import LessonImportDraft
from app.models.llm_draft import LlmDraft
from app.models.pack_pointer import PackPointer
from app.models.user import User, UserRole
from app.models.word import Word
from app.models.word_pack import WordPack
from app.routers import admin_assets as admin_assets_router
from app.routers import admin_categories as admin_categories_router
from app.routers import admin_drafts as admin_drafts_router
from app.routers import admin_lessons as admin_lessons_router
from app.routers import admin_llm as admin_llm_router
from app.routers import admin_packs as admin_packs_router
from app.routers import admin_stats as admin_stats_router
from app.routers import admin_words as admin_words_router
from app.routers import auth as auth_router
from app.routers import public_packs as public_packs_router
from app.services.auth_service import hash_password
from app.services.category_service import seed_manual_categories


async def bootstrap_admin_user(username: str, password: str) -> None:
    """Idempotent: create the admin row only if username does not exist."""
    existing = await User.find_one(User.username == username)
    if existing is not None:
        return
    await User(
        username=username,
        password_hash=hash_password(password),
        role=UserRole.ADMIN,
        created_at=datetime.now(tz=UTC),
    ).insert()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(settings.mongo_uri)
    await init_beanie(
        database=client[settings.mongo_db_name],
        document_models=[
            User,
            Word,
            WordPack,
            PackPointer,
            LlmDraft,
            Category,
            LessonImportDraft,
        ],
    )
    app.state.mongo_client = client
    await bootstrap_admin_user(
        username=settings.admin_bootstrap_user,
        password=settings.admin_bootstrap_pass,
    )
    # V0.5.5 startup hook: idempotently seed the 5 manual category rows
    # so legacy regions still have a category metadata row even before
    # any lesson-import lands.
    await seed_manual_categories()
    try:
        yield
    finally:
        client.close()


app = FastAPI(title="happyword-server", version="0.5.1", lifespan=lifespan)

# CORS read from env directly — get_settings() can't run at module load
# because pytest collection imports app.main before fixtures inject env.
_cors_origins = [
    o.strip() for o in os.environ.get("CORS_ALLOW_ORIGINS", "*").split(",") if o.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins or ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router.router)
app.include_router(public_packs_router.router)
app.include_router(admin_llm_router.router)
app.include_router(admin_words_router.router)
app.include_router(admin_packs_router.router)
app.include_router(admin_drafts_router.router)
app.include_router(admin_categories_router.router)
app.include_router(admin_lessons_router.router)
app.include_router(admin_assets_router.router)
app.include_router(admin_stats_router.router)
