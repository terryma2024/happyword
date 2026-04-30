"""Category seed + lookup helpers (V0.5.5)."""

from datetime import UTC, datetime

from app.models.category import Category

# Five legacy regions baked into the V0.4.x client. We seed them as
# `manual` source so the new pack-JSON `categories[]` contract keeps
# working for existing region cards even before any lesson-import lands.
# `story_zh` is intentionally None — admins can backfill via PUT later.
_MANUAL_SEEDS: tuple[tuple[str, str, str], ...] = (
    ("fruit", "Fruit", "水果"),
    ("place", "Places", "地点"),
    ("home", "Home", "家"),
    ("animal", "Animals", "动物"),
    ("ocean", "Ocean", "海洋"),
)


async def seed_manual_categories() -> tuple[int, int]:
    """Idempotently upsert the 5 manual category rows.

    Returns ``(inserted, skipped)``. Pre-existing rows are NEVER
    overwritten — admins may have edited story_zh / labels and we
    don't want startup to clobber that.
    """
    now = datetime.now(tz=UTC)
    existing_ids = {c.id async for c in Category.find_all()}
    inserted = 0
    skipped = 0
    for cid, en, zh in _MANUAL_SEEDS:
        if cid in existing_ids:
            skipped += 1
            continue
        await Category(
            id=cid,
            label_en=en,
            label_zh=zh,
            source="manual",
            created_at=now,
            updated_at=now,
        ).insert()
        inserted += 1
    return inserted, skipped
