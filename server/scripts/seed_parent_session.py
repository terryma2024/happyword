#!/usr/bin/env python3
"""Seed a local parent account and print a `wm_session` JWT for cookie login.

Gmail OTP needs SMTP_USERNAME — until that is set, use this script:

  cd server && uv run python scripts/seed_parent_session.py

Then in the browser (Chrome): DevTools → Application → Cookies →
http://localhost:8000 → Add cookie Name `wm_session`, Value <printed token>,
Path `/`, SameSite Lax. Reload `/parent/packs`.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient

from app.config import get_settings
from app.models.audit_log import AuditLog
from app.models.category import Category
from app.models.child_profile import ChildProfile
from app.models.cloud_wishlist_item import CloudWishlistItem
from app.models.device_binding import DeviceBinding
from app.models.email_verification import EmailVerification
from app.models.family import Family
from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.models.lesson_import_draft import LessonImportDraft
from app.models.llm_draft import LlmDraft
from app.models.pack_pointer import PackPointer
from app.models.pair_token import PairToken
from app.models.parent_inbox_msg import ParentInboxMsg
from app.models.redemption_request import RedemptionRequest
from app.models.synced_word_stat import SyncedWordStat
from app.models.user import User
from app.models.word import Word
from app.models.word_pack import WordPack
from app.services.auth_service import create_session_token
from app.services.family_service import create_family_for_parent

_DOCUMENT_MODELS = [
    User,
    Word,
    WordPack,
    PackPointer,
    LlmDraft,
    Category,
    LessonImportDraft,
    Family,
    EmailVerification,
    PairToken,
    DeviceBinding,
    ChildProfile,
    FamilyPackDefinition,
    FamilyPackDraft,
    FamilyPackPointer,
    FamilyWordPack,
    SyncedWordStat,
    CloudWishlistItem,
    RedemptionRequest,
    ParentInboxMsg,
    AuditLog,
]


async def _run(email: str) -> None:
    settings = get_settings()
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(
        settings.mongo_uri
    )
    await init_beanie(
        database=client[settings.mongo_db_name],
        document_models=_DOCUMENT_MODELS,
    )
    try:
        _family, user = await create_family_for_parent(email=email)
        token = create_session_token(role="parent", identifier=user.username)
        print(f"Seeded parent: email={user.email} user_id={user.username}")
        print(
            "Set cookie wm_session on http://localhost:8000 to this JWT value "
            "(Application → Cookies → Add):"
        )
        print(token)
    finally:
        client.close()


def main() -> None:
    email = sys.argv[1] if len(sys.argv) > 1 else "demo@local.dev"
    asyncio.run(_run(email))


if __name__ == "__main__":
    main()
