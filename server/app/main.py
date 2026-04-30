import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from beanie import init_beanie
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient

from app.config import get_settings
from app.models.user import User
from app.models.word import Word


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    client: AsyncIOMotorClient = AsyncIOMotorClient(settings.mongo_uri)
    await init_beanie(
        database=client[settings.mongo_db_name],
        document_models=[User, Word],
    )
    app.state.mongo_client = client
    try:
        yield
    finally:
        client.close()


app = FastAPI(title="happyword-server", version="0.5.1", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[get_settings().cors_allow_origins] if get_settings().cors_allow_origins else [],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/v1/health")
async def health() -> dict[str, object]:
    return {"ok": True, "ts": int(time.time())}
