"""One-shot CLI to publish the live `words` collection as a new WordPack.

Usage:
    cd server
    uv run python scripts/publish_pack.py [--notes "release note"] [--by username]

V0.5.3+: prefer `POST /api/v1/admin/packs/publish` from a JWT'd curl in
day-to-day operations. This script exists for emergency / first-publish
flows where the API isn't yet bootstrapped.
"""

from __future__ import annotations

import argparse
import asyncio
import sys

from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient

from app.config import get_settings
from app.models.category import Category
from app.models.pack_pointer import PackPointer
from app.models.user import User
from app.models.word import Word
from app.models.word_pack import WordPack
from app.services import pack_service
from app.services.pack_service import PackError


async def _main(notes: str | None, by: str) -> int:
    settings = get_settings()
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(settings.mongo_uri)
    try:
        await init_beanie(
            database=client[settings.mongo_db_name],
            document_models=[User, Word, Category, WordPack, PackPointer],
        )
        try:
            pack = await pack_service.publish_pack(published_by=by, notes=notes)
        except PackError as exc:
            print(f"publish-pack: REFUSED ({exc.code}): {exc.message}", file=sys.stderr)
            return 1
        print(
            f"publish-pack: OK version={pack.version} "
            f"schema_version={pack.schema_version} word_count={len(pack.words)}"
        )
        return 0
    finally:
        client.close()


if __name__ == "__main__":  # pragma: no cover
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--notes", default=None, help="Optional release note")
    parser.add_argument("--by", default="cli", help="Username to record as publisher")
    args = parser.parse_args()
    sys.exit(asyncio.run(_main(args.notes, args.by)))
