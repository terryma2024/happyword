"""V0.6.5 — seed 5 default global packs from existing categories + words.

Idempotent: pack_ids that already exist (under the global family_id
sentinel) are skipped. Words are pulled from the existing `Word`
collection by category, then upserted into the draft + immediately
published as version 1 of each pack. Re-running the script is a no-op
once the 5 packs are present.

Per spec §5.3 + §10.1, this writes `FamilyPackDefinition` rows with
`family_id = GLOBAL_PACK_FAMILY_ID`. No new collections are introduced.

Usage (after MONGODB_URI is set):

    cd server && uv run python -m scripts.migrate_global_packs_v0_6_5
"""

from __future__ import annotations

import asyncio
import sys
from typing import Any

from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient

from app.config import get_settings
from app.models.category import Category
from app.models.family_pack_definition import FamilyPackDefinition
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.models.user import User
from app.models.word import Word
from app.services import global_pack_service as svc
from app.services.family_pack_service import GLOBAL_PACK_FAMILY_ID

# Scene metadata for each seed pack. Mirrors what the HarmonyOS client
# rawfiles ship in `entry/src/main/resources/rawfile/data/builtin/*.json`.
# Editing one place is fine for v0.6.5; a follow-up could load from the
# rawfile to keep them strictly in sync.
DEFAULT_PACKS: list[tuple[str, str, str, str, dict[str, Any]]] = [
    (
        "fruit-forest",
        "Fruit Forest",
        "Sweet apples and pears",
        "fruit",
        {
            "bgPrimary": "#FFF6E0",
            "bgAccent": "#FFD27A",
            "bossName": "Orchard Sentinel",
            "bossCandidates": [4, 5, 6, 12, 13, 14, 15, 16, 21, 22, 86, 87, 88, 89, 90, 91, 92, 93, 94],
            "monsterPlan": {"weights": [1, 2, 3]},
            "storyZh": "森林深处藏着甜蜜的果实和守护它们的精灵。",
        },
    ),
    (
        "school-castle",
        "School Castle",
        "Books and classrooms",
        "place",
        {
            "bgPrimary": "#E8F1FF",
            "bgAccent": "#7DA3D8",
            "bossName": "Headmaster Quill",
            "bossCandidates": [7, 8, 23, 24, 25, 26, 27, 28, 29, 30, 95, 96, 97, 98, 99, 100],
            "monsterPlan": {"weights": [1, 2, 3]},
            "storyZh": "知识城堡里有勤奋的小怪兽们和它们的考试题。",
        },
    ),
    (
        "home-cottage",
        "Home Cottage",
        "Cozy rooms and chores",
        "home",
        {
            "bgPrimary": "#FFF0EE",
            "bgAccent": "#F4A6A0",
            "bossName": "Tidy Granny",
            "bossCandidates": [9, 18, 19, 20, 39, 40, 87, 88, 95, 96, 97, 98, 99, 100],
            "monsterPlan": {"weights": [1, 2, 3]},
            "storyZh": "温暖的小屋里，每件家具都有自己的故事。",
        },
    ),
    (
        "animal-safari",
        "Animal Safari",
        "Beasts of the savanna",
        "animal",
        {
            "bgPrimary": "#F2F7E8",
            "bgAccent": "#9CC07B",
            "bossName": "Lion King",
            "bossCandidates": [6, 9, 31, 32, 33, 34, 35, 36, 37, 38, 47, 48, 49, 50],
            "monsterPlan": {"weights": [1, 2, 3]},
            "storyZh": "草原上的勇敢动物等待着小冒险家。",
        },
    ),
    (
        "ocean-realm",
        "Ocean Realm",
        "Deep-sea creatures",
        "ocean",
        {
            "bgPrimary": "#E8F4F8",
            "bgAccent": "#6EB7CC",
            "bossName": "Sea Sovereign",
            "bossCandidates": [10, 11, 51, 52, 53, 54, 55, 56, 57, 58, 59],
            "monsterPlan": {"weights": [1, 2, 3]},
            "storyZh": "深海王国的统治者守护着秘密的海洋之书。",
        },
    ),
]


async def seed_default_global_packs(
    *, admin_id: str = "seed-bot"
) -> dict[str, Any]:
    created = 0
    published = 0
    for pack_id, name, description, category, scene in DEFAULT_PACKS:
        existing = await FamilyPackDefinition.find_one(
            FamilyPackDefinition.family_id == GLOBAL_PACK_FAMILY_ID,
            FamilyPackDefinition.pack_id == pack_id,
        )
        if existing is not None:
            continue
        await svc.create_definition(
            name=name,
            admin_id=admin_id,
            pack_id=pack_id,
            description=description,
            scene=scene,
        )
        # Pull non-test words for this category. The publish guard already
        # drops `category=='test'` for global packs but we filter early
        # too so the draft stays clean.
        words = await Word.find(
            Word.category == category, Word.deleted_at == None  # noqa: E711
        ).to_list()
        for w in words:
            if w.category == "test":
                continue
            entry: dict[str, Any] = {
                "id": w.id,
                "word": w.word,
                "meaningZh": w.meaningZh,
                "category": w.category,
                "difficulty": w.difficulty,
            }
            # Optional rich metadata if the source word has it.
            # Word.* uses snake_case; entry shape (consumed by global_pack
            # service) accepts either case, but we standardize on camelCase
            # to match the runtime wire shape.
            for src, dst in (
                ("distractors", "distractors"),
                ("example_sentence_en", "exampleEn"),
                ("example_sentence_zh", "exampleZh"),
                ("illustration_url", "illustrationUrl"),
                ("audio_url", "audioUrl"),
            ):
                value = getattr(w, src, None)
                if value:
                    entry[dst] = value
            await svc.upsert_draft_word(
                pack_id=pack_id, admin_id=admin_id, entry=entry
            )
        try:
            await svc.publish(
                pack_id=pack_id, admin_id=admin_id, notes="v0.6.5 seed"
            )
            published += 1
        except svc.EmptyPack:
            # No words for this category yet; the pack stays at version 0
            # (definition only). Re-running once words are seeded will
            # publish it. Don't crash — we still want the other packs
            # to land.
            pass
        created += 1
    return {"created": created, "published": published}


async def _main() -> None:
    settings = get_settings()
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(
        settings.mongo_uri
    )
    try:
        await init_beanie(
            database=client[settings.mongo_db_name],
            document_models=[
                User,
                Category,
                Word,
                FamilyPackDefinition,
                FamilyPackDraft,
                FamilyPackPointer,
                FamilyWordPack,
            ],
        )
        summary = await seed_default_global_packs()
        print(f"migrate_global_packs_v0_6_5: {summary}")
    finally:
        client.close()


if __name__ == "__main__":  # pragma: no cover - manual ops entry
    try:
        asyncio.run(_main())
    except KeyboardInterrupt:
        sys.exit(130)
