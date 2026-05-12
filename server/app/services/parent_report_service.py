"""V0.6.5 — server-side mirror of `LearningReportBuilder`.

Pure function `build_report` over `(child_profile_id, lookback_days,
now_ms)`. Data sources:

- Published global/family packs — the current pack library visible to the child.
- `Word` collection — legacy fallback before default global packs are published.
- `SyncedWordStat` — the cloud copy of LearningRecorder per-word stats,
  populated by V0.6.4 sync endpoint.

Bucketing rules mirror the client's `MemoryScheduler.classify`:

1. `next_review_ms > 0 AND next_review_ms <= now_ms`  → **review** (due)
2. else fall through to `memory_state` ∈ {new, learning, familiar,
   mastered}.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta, timezone
from typing import Any

from app.models.child_profile import ChildProfile
from app.models.synced_word_stat import SyncedWordStat
from app.models.word import Word
from app.schemas.parent_report import (
    CategoryReportOut,
    ChildReportOut,
    PackReportOut,
)
from app.services import family_pack_service, global_pack_service

LOOKBACK_DAYS_MIN = 1
LOOKBACK_DAYS_MAX = 90
LOOKBACK_DAYS_DEFAULT = 7

# Legacy category labels retained for old API fields.
_CATEGORY_DISPLAY_NAMES: dict[str, str] = {
    "fruit": "水果",
    "place": "地点",
    "home": "家庭",
    "animal": "动物",
    "ocean": "海洋",
}

_DEFAULT_PACKS: tuple[tuple[str, str, str], ...] = (
    ("fruit-forest", "Fruit Forest", "fruit"),
    ("school-castle", "School Castle", "place"),
    ("home-cottage", "Home Cottage", "home"),
    ("animal-safari", "Animal Safari", "animal"),
    ("ocean-realm", "Ocean Realm", "ocean"),
)
_DEFAULT_PACK_ORDER: dict[str, int] = {
    pack_id: idx for idx, (pack_id, _name, _category) in enumerate(_DEFAULT_PACKS)
}


def describe_category(category: str) -> str:
    return _CATEGORY_DISPLAY_NAMES.get(category, category)


@dataclass
class _CategoryBucket:
    category: str
    total_seen: int = 0
    total_correct: int = 0


@dataclass
class _PackBucket:
    pack_id: str
    name: str
    word_ids: list[str] = field(default_factory=list)
    total_seen: int = 0
    total_correct: int = 0
    active: bool = False


class ChildProfileNotFoundForReport(Exception):
    """Raised when the requested child profile does not belong to the
    requesting family (or has been soft-deleted)."""


# Local TZ used by both client + server to determine "today". We use
# Asia/Shanghai as the default deployment region; if a parent later
# overrides their timezone in V0.6.7, the report endpoint can pass the
# right value through `now_ms` already pre-shifted.
def _start_of_today_ms(now_ms: int, tz_offset_minutes: int = 8 * 60) -> int:
    tz = timezone(timedelta(minutes=tz_offset_minutes))
    now_local = datetime.fromtimestamp(now_ms / 1000.0, tz=tz)
    sod_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    return int(sod_local.timestamp() * 1000)


def _classify(stat: SyncedWordStat, now_ms: int) -> str:
    """Return one of: 'new', 'learning', 'review', 'familiar', 'mastered'.

    Keeps the same rule as `MemoryScheduler.classify`: a non-zero
    `next_review_ms` that has elapsed forces `review` regardless of the
    persisted memory_state."""
    if stat.next_review_ms > 0 and stat.next_review_ms <= now_ms:
        return "review"
    state = stat.memory_state.lower() if stat.memory_state else "new"
    if state in {"new", "learning", "familiar", "mastered"}:
        return state
    return "new"


def clamp_lookback(lookback_days: int | None) -> int:
    if lookback_days is None:
        return LOOKBACK_DAYS_DEFAULT
    if lookback_days < LOOKBACK_DAYS_MIN:
        return LOOKBACK_DAYS_MIN
    if lookback_days > LOOKBACK_DAYS_MAX:
        return LOOKBACK_DAYS_MAX
    return lookback_days


def _word_id_from_pack_entry(entry: dict[str, Any]) -> str | None:
    if entry.get("hidden") is True:
        return None
    word_id = entry.get("id")
    if isinstance(word_id, str) and word_id:
        return word_id
    return None


def _bucket_from_pack_words(
    *, pack_id: str, name: str, words: list[dict[str, Any]], active: bool = False
) -> _PackBucket:
    seen: set[str] = set()
    word_ids: list[str] = []
    for entry in words:
        word_id = _word_id_from_pack_entry(entry)
        if word_id is None or word_id in seen:
            continue
        seen.add(word_id)
        word_ids.append(word_id)
    return _PackBucket(pack_id=pack_id, name=name, word_ids=word_ids, active=active)


def _legacy_default_pack_buckets(words: list[Word]) -> list[_PackBucket]:
    """Fallback for databases not yet migrated to global pack definitions."""
    by_category: dict[str, list[dict[str, Any]]] = {}
    for w in words:
        by_category.setdefault(w.category, []).append({"id": w.id})

    buckets: list[_PackBucket] = []
    known_categories: set[str] = set()
    for pack_id, name, category in _DEFAULT_PACKS:
        known_categories.add(category)
        buckets.append(
            _bucket_from_pack_words(
                pack_id=pack_id,
                name=name,
                words=by_category.get(category, []),
                active=True,
            )
        )

    for category in sorted(set(by_category) - known_categories):
        buckets.append(
            _bucket_from_pack_words(
                pack_id=f"legacy-{category}",
                name=describe_category(category),
                words=by_category[category],
                active=True,
            )
        )
    return buckets


def _merge_pack_buckets(buckets: list[_PackBucket]) -> list[_PackBucket]:
    merged: dict[str, _PackBucket] = {}
    for bucket in buckets:
        # Same id follows PackLibrary's override model: later source layers
        # replace the earlier pack content while retaining deterministic order.
        if bucket.pack_id in merged:
            bucket.active = merged[bucket.pack_id].active or bucket.active
        merged[bucket.pack_id] = bucket
    indexed = list(enumerate(merged.values()))
    indexed.sort(
        key=lambda item: (
            _DEFAULT_PACK_ORDER.get(item[1].pack_id, len(_DEFAULT_PACK_ORDER)),
            item[0],
        )
    )
    return [bucket for _idx, bucket in indexed]


async def _collect_pack_buckets(
    *, family_id: str, legacy_words: list[Word]
) -> list[_PackBucket]:
    global_slices, _global_etag = await global_pack_service.collect_merged()
    family_slices, _family_etag = await family_pack_service.collect_merged(
        family_id=family_id
    )

    buckets: list[_PackBucket] = []
    if global_slices:
        for s in global_slices:
            buckets.append(
                _bucket_from_pack_words(
                    pack_id=s.pack_id,
                    name=s.name,
                    words=s.words,
                    active=s.pack_id in _DEFAULT_PACK_ORDER,
                )
            )
    else:
        buckets.extend(_legacy_default_pack_buckets(legacy_words))

    for s in family_slices:
        buckets.append(
            _bucket_from_pack_words(
                pack_id=s.pack_id,
                name=s.name,
                words=s.words,
            )
        )
    return _merge_pack_buckets(buckets)


async def build_report(
    *,
    family_id: str,
    child_profile_id: str,
    lookback_days: int | None,
    now_ms: int,
) -> ChildReportOut:
    """Build a `ChildReportOut` for the given child profile.

    Raises `ChildProfileNotFoundForReport` if the child does not belong
    to `family_id` (404 from the router).
    """
    profile = await ChildProfile.find_one(
        ChildProfile.profile_id == child_profile_id,
        ChildProfile.family_id == family_id,
        ChildProfile.deleted_at == None,  # noqa: E711
    )
    if profile is None:
        raise ChildProfileNotFoundForReport(child_profile_id)

    clamped_lookback = clamp_lookback(lookback_days)
    start_of_today_ms = _start_of_today_ms(now_ms)

    # Legacy word pool is still used as a fallback until the default
    # global packs have been published in every environment.
    words = await Word.find(
        Word.deleted_at == None,  # noqa: E711
    ).to_list()
    pack_buckets = await _collect_pack_buckets(
        family_id=family_id,
        legacy_words=words,
    )
    known_word_ids: set[str] = set()
    for bucket in pack_buckets:
        known_word_ids.update(bucket.word_ids)
    total_words = len(known_word_ids)

    # Cloud-copy stats for the child.
    stats = await SyncedWordStat.find(
        SyncedWordStat.child_profile_id == child_profile_id,
    ).to_list()
    stat_by_word_id: dict[str, SyncedWordStat] = {s.word_id: s for s in stats}

    # Last server sync = max updated_at across all stats. None if
    # nothing has ever synced.
    last_synced_at: datetime | None = None
    for s in stats:
        if s.updated_at is not None and (
            last_synced_at is None or s.updated_at > last_synced_at
        ):
            last_synced_at = s.updated_at

    cat_map: dict[str, _CategoryBucket] = {}
    for w in words:
        cat_map.setdefault(w.category, _CategoryBucket(category=w.category))

    total_seen = 0
    total_correct = 0
    new_from_stats = 0
    learning_count = 0
    familiar_count = 0
    mastered_count = 0
    review_due = 0
    review_done_today = 0

    for stat in stats:
        if stat.word_id not in known_word_ids:
            continue
        total_seen += stat.seen_count
        total_correct += stat.correct_count
        state = _classify(stat, now_ms)
        if state == "new":
            new_from_stats += 1
        elif state == "mastered":
            mastered_count += 1
        elif state == "familiar":
            familiar_count += 1
        elif state == "review":
            review_due += 1
            learning_count += 1
        else:
            learning_count += 1
        # Widen review-pool: any seen-before-today, non-new word counts
        # toward "review reach" so the bar reflects total surface area.
        is_reviewable = (
            stat.seen_count > 0 and stat.last_answered_ms < start_of_today_ms
        )
        if (
            is_reviewable
            and stat.last_answered_ms >= 0
            and state != "new"
            and state != "review"
        ):
            review_due += 1
        if (
            stat.last_answered_ms >= start_of_today_ms
            and stat.consecutive_correct > 0
        ):
            review_done_today += 1

    unseen_in_library = len(known_word_ids - set(stat_by_word_id))
    new_count = new_from_stats + unseen_in_library
    accuracy_pct = round(total_correct * 100 / total_seen) if total_seen > 0 else 0

    packs: list[PackReportOut] = []
    for bucket in pack_buckets:
        for word_id in bucket.word_ids:
            stat = stat_by_word_id.get(word_id)
            if stat is None:
                continue
            bucket.total_seen += stat.seen_count
            bucket.total_correct += stat.correct_count
        acc = (
            round(bucket.total_correct * 100 / bucket.total_seen)
            if bucket.total_seen > 0
            else 0
        )
        # Client includes active packs even with no data; server cannot see
        # device-local selection, so it exposes all current visible packs.
        packs.append(
            PackReportOut(
                pack_id=bucket.pack_id,
                name=bucket.name,
                total_seen=bucket.total_seen,
                total_correct=bucket.total_correct,
                accuracy_pct=acc,
                active=bucket.active,
            )
        )

    for w in words:
        bucket = cat_map[w.category]
        stat = stat_by_word_id.get(w.id)
        if stat is None:
            continue
        bucket.total_seen += stat.seen_count
        bucket.total_correct += stat.correct_count

    cats: list[CategoryReportOut] = []
    for bucket in cat_map.values():
        acc = (
            round(bucket.total_correct * 100 / bucket.total_seen)
            if bucket.total_seen > 0
            else 0
        )
        cats.append(
            CategoryReportOut(
                category=bucket.category,
                display_name=describe_category(bucket.category),
                total_seen=bucket.total_seen,
                total_correct=bucket.total_correct,
                accuracy_pct=acc,
            )
        )

    weak_cats = _pick_weak_categories(cats, 3)
    weak_packs = _pick_weak_packs(packs, 3)

    review_completion_pct = (
        round(review_done_today * 100 / max(review_due, review_done_today))
        if max(review_due, review_done_today) > 0
        else 0
    )

    return ChildReportOut(
        child_profile_id=profile.profile_id,
        nickname=profile.nickname,
        total_words=total_words,
        total_seen=total_seen,
        total_correct=total_correct,
        accuracy_pct=accuracy_pct,
        new_count=new_count,
        learning_count=learning_count,
        familiar_count=familiar_count,
        mastered_count=mastered_count,
        review_due_count=review_due,
        review_done_today_count=review_done_today,
        review_completion_pct=review_completion_pct,
        packs=packs,
        weak_packs=weak_packs,
        categories=cats,
        weak_categories=weak_cats,
        today_review_done=review_done_today,
        today_review_due=review_due,
        lookback_days=clamped_lookback,
        generated_at=datetime.now(tz=UTC),
        last_synced_at=last_synced_at,
    )


def _pick_weak_categories(
    cats: list[CategoryReportOut], n: int
) -> list[CategoryReportOut]:
    """Sort categories by accuracy ASC, skip empty buckets, take ≤ n."""
    eligible = [c for c in cats if c.total_seen > 0]
    eligible.sort(key=lambda c: c.accuracy_pct)
    return eligible[:n]


def _pick_weak_packs(
    packs: list[PackReportOut], n: int
) -> list[PackReportOut]:
    """Sort packs by accuracy ASC, skip empty buckets, take ≤ n."""
    eligible = [p for p in packs if p.total_seen > 0]
    eligible.sort(key=lambda p: p.accuracy_pct)
    return eligible[:n]
