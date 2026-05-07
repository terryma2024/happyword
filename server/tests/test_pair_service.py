"""V0.6.2 — pair_service: create / redeem / cancel / expire unit tests."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.models.pair_token import PairToken, PairTokenStatus


async def _seed_parent(email: str = "p@example.com") -> tuple[str, str]:
    from app.services.family_service import create_family_for_parent

    family, user = await create_family_for_parent(email=email)
    return family.family_id, user.username


@pytest.mark.asyncio
async def test_create_pair_returns_pending_token(db: object) -> None:
    from app.services.pair_service import create_pair

    family_id, parent_id = await _seed_parent()
    pt = await create_pair(family_id=family_id, parent_id=parent_id)
    assert pt.status == PairTokenStatus.PENDING
    assert len(pt.token) == 32
    assert pt.token.isalnum()
    assert len(pt.short_code) == 6 and pt.short_code.isdigit()
    assert pt.family_id == family_id
    rows = await PairToken.find(PairToken.family_id == family_id).to_list()
    assert len(rows) == 1


@pytest.mark.asyncio
async def test_create_pair_short_code_is_unique(
    db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    """If a short_code collision happens (extremely rare), the service retries
    until a unique one is found."""
    from app.services import pair_service

    family_id, parent_id = await _seed_parent()
    counter = {"i": 0}

    def fake_short() -> str:
        counter["i"] += 1
        return ["123456", "123456", "654321"][counter["i"] - 1]

    monkeypatch.setattr(pair_service, "_generate_short_code", fake_short)
    p1 = await pair_service.create_pair(family_id=family_id, parent_id=parent_id)
    p2 = await pair_service.create_pair(family_id=family_id, parent_id=parent_id)
    assert p1.short_code != p2.short_code


@pytest.mark.asyncio
async def test_redeem_token_creates_binding_and_child_profile(db: object) -> None:
    from app.services.pair_service import create_pair, redeem

    family_id, parent_id = await _seed_parent()
    pt = await create_pair(family_id=family_id, parent_id=parent_id)
    binding, child, device_token = await redeem(
        token=pt.token, device_id="dev-aaaa-bbbb", user_agent="WordMagic/0.6.2"
    )
    assert binding.family_id == family_id
    assert binding.device_id == "dev-aaaa-bbbb"
    assert binding.binding_id.startswith("bind-")
    assert binding.user_agent == "WordMagic/0.6.2"
    assert binding.revoked_at is None
    assert child.binding_id == binding.binding_id
    assert child.family_id == family_id
    assert child.profile_id.startswith("child-")
    assert child.nickname == "宝贝"
    assert isinstance(device_token, str) and device_token.count(".") == 2  # JWT shape

    refreshed = await PairToken.get(pt.id)
    assert refreshed is not None
    assert refreshed.status == PairTokenStatus.REDEEMED
    assert refreshed.redeemed_binding_id == binding.binding_id


@pytest.mark.asyncio
async def test_redeem_by_short_code_works(db: object) -> None:
    from app.services.pair_service import create_pair, redeem

    family_id, parent_id = await _seed_parent()
    pt = await create_pair(family_id=family_id, parent_id=parent_id)
    binding, _child, _token = await redeem(
        short_code=pt.short_code, device_id="dev-x", user_agent="ua"
    )
    assert binding.binding_id.startswith("bind-")


@pytest.mark.asyncio
async def test_redeem_expired_raises_token_expired(
    db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import pair_service
    from app.services.pair_service import PairTokenExpired, create_pair, redeem

    family_id, parent_id = await _seed_parent()
    pt = await create_pair(family_id=family_id, parent_id=parent_id)
    real_now = datetime.now(tz=UTC)
    monkeypatch.setattr(
        pair_service, "_utcnow", lambda: real_now + timedelta(minutes=10)
    )
    with pytest.raises(PairTokenExpired):
        await redeem(token=pt.token, device_id="dev", user_agent="ua")
    refreshed = await PairToken.get(pt.id)
    assert refreshed is not None
    assert refreshed.status == PairTokenStatus.EXPIRED


@pytest.mark.asyncio
async def test_redeem_already_used_raises_token_redeemed(db: object) -> None:
    from app.services.pair_service import (
        PairTokenAlreadyRedeemed,
        create_pair,
        redeem,
    )

    family_id, parent_id = await _seed_parent()
    pt = await create_pair(family_id=family_id, parent_id=parent_id)
    await redeem(token=pt.token, device_id="dev1", user_agent="ua")
    with pytest.raises(PairTokenAlreadyRedeemed):
        await redeem(token=pt.token, device_id="dev2", user_agent="ua")


@pytest.mark.asyncio
async def test_redeem_unknown_token_raises_invalid(db: object) -> None:
    from app.services.pair_service import PairTokenInvalid, redeem

    with pytest.raises(PairTokenInvalid):
        await redeem(token="0" * 32, device_id="dev", user_agent="ua")


@pytest.mark.asyncio
async def test_cancel_pending_token(db: object) -> None:
    from app.services.pair_service import (
        PairTokenInvalid,
        cancel,
        create_pair,
        redeem,
    )

    family_id, parent_id = await _seed_parent()
    pt = await create_pair(family_id=family_id, parent_id=parent_id)
    cancelled = await cancel(token=pt.token, family_id=family_id)
    assert cancelled.status == PairTokenStatus.CANCELLED
    with pytest.raises(PairTokenInvalid):
        await redeem(token=pt.token, device_id="d", user_agent="ua")


@pytest.mark.asyncio
async def test_redeem_same_device_same_family_revokes_old_binding(db: object) -> None:
    """Re-binding the same device under the same family should revoke the old
    binding row and reuse the same child_profile_id (preserving learning state).
    """
    from app.services.pair_service import create_pair, redeem

    family_id, parent_id = await _seed_parent()
    pt1 = await create_pair(family_id=family_id, parent_id=parent_id)
    binding1, child1, _ = await redeem(
        token=pt1.token, device_id="dev-shared", user_agent="ua"
    )
    pt2 = await create_pair(family_id=family_id, parent_id=parent_id)
    binding2, child2, _ = await redeem(
        token=pt2.token, device_id="dev-shared", user_agent="ua"
    )
    assert binding1.binding_id != binding2.binding_id
    refreshed = await DeviceBinding.find_one(
        DeviceBinding.binding_id == binding1.binding_id
    )
    assert refreshed is not None
    assert refreshed.revoked_at is not None
    assert child2.profile_id == child1.profile_id  # preserved


@pytest.mark.asyncio
async def test_redeem_same_device_different_family_creates_new_child(
    db: object,
) -> None:
    """Cross-family rebind must NOT leak the previous child profile."""
    from app.services.pair_service import create_pair, redeem

    fam_a, parent_a = await _seed_parent("a@example.com")
    fam_b, parent_b = await _seed_parent("b@example.com")
    pt_a = await create_pair(family_id=fam_a, parent_id=parent_a)
    pt_b = await create_pair(family_id=fam_b, parent_id=parent_b)
    _, child_a, _ = await redeem(
        token=pt_a.token, device_id="dev-cross", user_agent="ua"
    )
    binding_b, child_b, _ = await redeem(
        token=pt_b.token, device_id="dev-cross", user_agent="ua"
    )
    assert child_b.profile_id != child_a.profile_id
    assert binding_b.family_id == fam_b
    profiles = await ChildProfile.find().to_list()
    assert len(profiles) == 2


@pytest.mark.asyncio
async def test_expire_old_marks_pending_past_expiry(
    db: object, monkeypatch: pytest.MonkeyPatch
) -> None:
    from app.services import pair_service
    from app.services.pair_service import create_pair, expire_old

    family_id, parent_id = await _seed_parent()
    pt = await create_pair(family_id=family_id, parent_id=parent_id)
    real_now = datetime.now(tz=UTC)
    monkeypatch.setattr(
        pair_service, "_utcnow", lambda: real_now + timedelta(minutes=10)
    )
    n = await expire_old()
    assert n == 1
    refreshed = await PairToken.get(pt.id)
    assert refreshed is not None
    assert refreshed.status == PairTokenStatus.EXPIRED
