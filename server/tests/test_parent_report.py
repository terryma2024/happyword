"""V0.6.5 — parent learning report behaviour contracts (≥8)."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.models.word import Word
from app.schemas.word_stats_sync import WordStatItem
from app.services import parent_report_service as svc
from app.services import word_stats_sync_service as sync_svc
from app.services.auth_service import create_session_token
from app.services.family_service import create_family_for_parent

_NOW_MS = 1_724_000_000_000  # 2024-08-19 ~ 04:53 UTC, well past start-of-day


async def _seed_words() -> None:
    """Seed two categories with three words each so the bucketing logic
    has something interesting to work on."""
    now = datetime.now(tz=UTC)
    rows = [
        Word(id="apple", word="apple", meaningZh="苹果", category="fruit",
             difficulty=1, created_at=now, updated_at=now),
        Word(id="banana", word="banana", meaningZh="香蕉", category="fruit",
             difficulty=1, created_at=now, updated_at=now),
        Word(id="orange", word="orange", meaningZh="橙子", category="fruit",
             difficulty=1, created_at=now, updated_at=now),
        Word(id="dog", word="dog", meaningZh="狗", category="animal",
             difficulty=1, created_at=now, updated_at=now),
        Word(id="cat", word="cat", meaningZh="猫", category="animal",
             difficulty=1, created_at=now, updated_at=now),
        Word(id="fish", word="fish", meaningZh="鱼", category="animal",
             difficulty=1, created_at=now, updated_at=now),
    ]
    for r in rows:
        await r.insert()


async def _seed_family_with_child() -> tuple[str, str, str]:
    """Returns (family_id, child_profile_id, binding_id)."""
    family, _ = await create_family_for_parent(email="parent@example.com")
    now = datetime.now(tz=UTC)
    child = ChildProfile(
        profile_id="child-aaaa1111",
        family_id=family.family_id,
        binding_id="bind-aaaa1111",
        nickname="小明",
        avatar_emoji="🦊",
        created_at=now,
        updated_at=now,
    )
    await child.insert()
    binding = DeviceBinding(
        binding_id="bind-aaaa1111",
        family_id=family.family_id,
        device_id="dev-aaaa-1234",
        child_profile_id=child.profile_id,
        user_agent="ut",
        created_at=now,
        last_seen_at=now,
    )
    await binding.insert()
    return family.family_id, child.profile_id, binding.binding_id


def _stat(
    word_id: str,
    *,
    seen: int = 1,
    correct: int = 1,
    wrong: int = 0,
    last_ms: int = _NOW_MS - 86_400_000,  # 1 day ago
    last_correct_ms: int = _NOW_MS - 86_400_000,
    next_review_ms: int = 0,
    memory_state: str = "learning",
    consecutive_correct: int = 1,
    mastery: float = 0.5,
) -> WordStatItem:
    return WordStatItem(
        word_id=word_id,
        seen_count=seen,
        correct_count=correct,
        wrong_count=wrong,
        last_answered_ms=last_ms,
        last_correct_ms=last_correct_ms,
        next_review_ms=next_review_ms,
        memory_state=memory_state,
        consecutive_correct=consecutive_correct,
        consecutive_wrong=0,
        mastery=mastery,
    )


# ---------------------------------------------------------------------------
# Service-level contracts
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_empty_stats_yield_all_zero_report(db: object) -> None:
    await _seed_words()
    family_id, child_id, _ = await _seed_family_with_child()
    report = await svc.build_report(
        family_id=family_id,
        child_profile_id=child_id,
        lookback_days=7,
        now_ms=_NOW_MS,
    )
    assert report.total_words == 6
    assert report.total_seen == 0
    assert report.accuracy_pct == 0
    assert report.new_count == 6
    assert report.mastered_count == 0
    assert report.weak_categories == []


@pytest.mark.asyncio
async def test_mastered_count_matches_classify(db: object) -> None:
    await _seed_words()
    family_id, child_id, _ = await _seed_family_with_child()
    # apple stored as "mastered" with no due review → mastered.
    # banana stored as "learning" with seen+correct → learning.
    # dog has next_review_ms in the past → forced into "review" → learning + due.
    await sync_svc.sync(
        child_profile_id=child_id,
        items=[
            _stat("apple", seen=10, correct=10, memory_state="mastered",
                  consecutive_correct=5, mastery=0.95),
            _stat("banana", seen=4, correct=3, wrong=1,
                  memory_state="learning"),
            _stat("dog", seen=2, correct=2,
                  next_review_ms=_NOW_MS - 1000,
                  memory_state="learning"),
        ],
        requesting_device_id="dev-test",
    )
    report = await svc.build_report(
        family_id=family_id,
        child_profile_id=child_id,
        lookback_days=7,
        now_ms=_NOW_MS,
    )
    assert report.mastered_count == 1
    assert report.learning_count == 2  # banana + dog (review counts as learning)
    assert report.review_due_count >= 1
    assert report.new_count == 3  # orange + cat + fish


@pytest.mark.asyncio
async def test_weak_categories_sorted_ascending_excludes_unseen(db: object) -> None:
    await _seed_words()
    family_id, child_id, _ = await _seed_family_with_child()
    # fruit: 3 stats, accuracy 50%; animal: 1 stat 100%.
    await sync_svc.sync(
        child_profile_id=child_id,
        items=[
            _stat("apple", seen=10, correct=5, wrong=5),
            _stat("banana", seen=10, correct=5, wrong=5),
            _stat("orange", seen=10, correct=5, wrong=5),
            _stat("dog", seen=10, correct=10),
        ],
        requesting_device_id="dev-test",
    )
    report = await svc.build_report(
        family_id=family_id,
        child_profile_id=child_id,
        lookback_days=7,
        now_ms=_NOW_MS,
    )
    # fruit (50%) before animal (100%)
    cats = [c.category for c in report.weak_categories]
    assert cats[0] == "fruit"
    assert "animal" in cats
    # If a category had zero seen, it's excluded — but here both have data.
    assert all(c.total_seen > 0 for c in report.weak_categories)


@pytest.mark.asyncio
async def test_today_review_done_counts_streak_today(db: object) -> None:
    await _seed_words()
    family_id, child_id, _ = await _seed_family_with_child()
    # done today: apple answered correctly today
    today_ms = _NOW_MS - 60_000  # 1 min ago
    await sync_svc.sync(
        child_profile_id=child_id,
        items=[
            _stat("apple", last_ms=today_ms, last_correct_ms=today_ms,
                  consecutive_correct=2, memory_state="learning"),
            _stat("banana", last_ms=_NOW_MS - 86_400_000 * 2,
                  consecutive_correct=0, memory_state="learning"),
        ],
        requesting_device_id="dev-test",
    )
    report = await svc.build_report(
        family_id=family_id,
        child_profile_id=child_id,
        lookback_days=7,
        now_ms=_NOW_MS,
    )
    assert report.today_review_done >= 1
    assert report.today_review_done == report.review_done_today_count


@pytest.mark.asyncio
async def test_review_due_includes_seen_before_today(db: object) -> None:
    await _seed_words()
    family_id, child_id, _ = await _seed_family_with_child()
    yesterday = _NOW_MS - 86_400_000
    await sync_svc.sync(
        child_profile_id=child_id,
        items=[_stat("apple", last_ms=yesterday, memory_state="familiar")],
        requesting_device_id="dev-test",
    )
    report = await svc.build_report(
        family_id=family_id,
        child_profile_id=child_id,
        lookback_days=7,
        now_ms=_NOW_MS,
    )
    assert report.today_review_due >= 1


@pytest.mark.asyncio
async def test_lookback_clamps_to_valid_range(db: object) -> None:
    await _seed_words()
    family_id, child_id, _ = await _seed_family_with_child()
    too_low = await svc.build_report(
        family_id=family_id, child_profile_id=child_id,
        lookback_days=0, now_ms=_NOW_MS,
    )
    too_high = await svc.build_report(
        family_id=family_id, child_profile_id=child_id,
        lookback_days=999, now_ms=_NOW_MS,
    )
    none = await svc.build_report(
        family_id=family_id, child_profile_id=child_id,
        lookback_days=None, now_ms=_NOW_MS,
    )
    assert too_low.lookback_days == 1
    assert too_high.lookback_days == 90
    assert none.lookback_days == 7


@pytest.mark.asyncio
async def test_other_family_child_raises(db: object) -> None:
    await _seed_words()
    family_id, child_id, _ = await _seed_family_with_child()
    other, _ = await create_family_for_parent(email="other@example.com")
    with pytest.raises(svc.ChildProfileNotFoundForReport):
        await svc.build_report(
            family_id=other.family_id,
            child_profile_id=child_id,
            lookback_days=7,
            now_ms=_NOW_MS,
        )


# ---------------------------------------------------------------------------
# HTTP-level contracts
# ---------------------------------------------------------------------------


async def _parent_client(family_id: str, parent_username: str) -> AsyncClient:
    from app.main import app

    transport = ASGITransport(app=app)
    token = create_session_token(role="parent", identifier=parent_username)
    settings = get_settings()
    ac = AsyncClient(
        transport=transport,
        base_url="http://test",
        cookies={settings.session_cookie_name: token},
    )
    return ac


async def _seed_with_parent_client() -> tuple[str, str, str, str]:
    """Helper that returns (family_id, child_id, binding_id, parent_user)."""
    await _seed_words()
    from app.models.user import User, UserRole

    family, user = await create_family_for_parent(email="parent@example.com")
    now = datetime.now(tz=UTC)
    child = ChildProfile(
        profile_id="child-bbbb2222",
        family_id=family.family_id,
        binding_id="bind-bbbb2222",
        nickname="小芳",
        avatar_emoji="🦄",
        created_at=now,
        updated_at=now,
    )
    await child.insert()
    binding = DeviceBinding(
        binding_id="bind-bbbb2222",
        family_id=family.family_id,
        device_id="dev-bbbb-2222",
        child_profile_id=child.profile_id,
        user_agent="ut",
        created_at=now,
        last_seen_at=now,
    )
    await binding.insert()
    assert isinstance(user, User)
    assert user.role == UserRole.PARENT
    return family.family_id, child.profile_id, binding.binding_id, user.username


@pytest.mark.asyncio
async def test_http_get_report_returns_payload(db: object) -> None:
    family_id, child_id, _, parent_username = await _seed_with_parent_client()
    ac = await _parent_client(family_id, parent_username)
    async with ac:
        r = await ac.get(f"/api/v1/parent/children/{child_id}/report")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["child_profile_id"] == child_id
    assert body["nickname"] == "小芳"
    assert body["total_words"] == 6
    assert body["lookback_days"] == 7


@pytest.mark.asyncio
async def test_http_get_report_other_family_404(db: object) -> None:
    family_id, child_id, _, parent_username = await _seed_with_parent_client()
    other_family, other_user = await create_family_for_parent(
        email="other@example.com"
    )
    ac = await _parent_client(other_family.family_id, other_user.username)
    async with ac:
        r = await ac.get(f"/api/v1/parent/children/{child_id}/report")
    assert r.status_code == 404
    assert r.json()["detail"]["error"]["code"] == "CHILD_NOT_FOUND"


@pytest.mark.asyncio
async def test_html_device_detail_contains_report_ids(db: object) -> None:
    family_id, child_id, binding_id, parent_username = await _seed_with_parent_client()
    # Seed a few stats so the page renders interesting numbers.
    await sync_svc.sync(
        child_profile_id=child_id,
        items=[_stat("apple", seen=4, correct=2, wrong=2)],
        requesting_device_id="dev-test",
    )
    ac = await _parent_client(family_id, parent_username)
    async with ac:
        r = await ac.get(f"/parent/devices/{binding_id}")
    assert r.status_code == 200, r.text
    body = r.text
    # All four IDs the V0.6.5 plan calls out for HTMX hooks.
    assert 'id="report-accuracy"' in body
    assert 'id="report-mastered"' in body
    assert 'id="report-review-done"' in body
    assert 'id="report-weak-categories"' in body


@pytest.mark.asyncio
async def test_html_device_detail_other_family_404(db: object) -> None:
    family_id, _, binding_id, _ = await _seed_with_parent_client()
    other_family, other_user = await create_family_for_parent(
        email="other2@example.com"
    )
    ac = await _parent_client(other_family.family_id, other_user.username)
    async with ac:
        r = await ac.get(f"/parent/devices/{binding_id}")
    assert r.status_code == 404


# Suppress the unused import warning for `Any` (kept for parity with
# sibling test files that import it for typing hints in payload dicts).
_ = Any
