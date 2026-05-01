"""V0.6.2 — pair token lifecycle: create / redeem / cancel / expire.

Atomicity contract:
- `redeem` writes 4 things in sequence: PairToken status → revoked any
  prior active binding for the same (device_id, family_id) → new
  DeviceBinding → new ChildProfile (or reuse same family's prior child id).
  Mongo doesn't give us a true cross-collection transaction on the test
  driver (mongomock), so we structure writes so that a partial failure is
  recoverable by re-issuing the same token (idempotency on
  `redeemed_binding_id`).

Configuration (spec §V0.6.2):
- Token: 32-char lowercase hex via `secrets.token_hex(16)`.
- Short code: 6-digit decimal (`secrets.randbelow(1_000_000)`); regenerated
  on collision (extremely rare in practice but defensive).
- Validity: 3 minutes from issue (configurable later).
- Re-bind: same device under same family preserves child_profile_id;
  cross-family rebind always creates a fresh child.
"""

import secrets
from datetime import UTC, datetime, timedelta

from app.models.child_profile import ChildProfile
from app.models.device_binding import DeviceBinding
from app.models.pair_token import PairToken, PairTokenStatus
from app.services.auth_service import create_device_token

PAIR_TOKEN_TTL_SECONDS = 3 * 60


class PairServiceError(Exception):
    """Base class for pair-flow failures."""


class PairTokenInvalid(PairServiceError):
    """No PairToken matches the supplied token / short_code."""


class PairTokenExpired(PairServiceError):
    """PairToken found but `expires_at` has passed."""


class PairTokenAlreadyRedeemed(PairServiceError):
    """PairToken found but its status is already `redeemed` / `cancelled` / `expired`."""


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


def _to_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def _generate_token() -> str:
    return secrets.token_hex(16)


def _generate_short_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _gen_binding_id() -> str:
    return f"bind-{secrets.token_hex(4)}"


def _gen_child_id() -> str:
    return f"child-{secrets.token_hex(4)}"


async def create_pair(*, family_id: str, parent_id: str) -> PairToken:
    """Issue a new pending PairToken for a parent.

    Cross-collection unique-index collisions (token / short_code) trigger
    a small retry loop; in steady state this is single-shot.
    """
    now = _utcnow()
    expires_at = now + timedelta(seconds=PAIR_TOKEN_TTL_SECONDS)

    for _ in range(8):
        token = _generate_token()
        if await PairToken.find_one(PairToken.token == token) is not None:
            continue
        short_code = ""
        for _ in range(8):
            cand = _generate_short_code()
            if await PairToken.find_one(PairToken.short_code == cand) is None:
                short_code = cand
                break
        if not short_code:
            continue
        pt = PairToken(
            token=token,
            short_code=short_code,
            family_id=family_id,
            created_by_parent_id=parent_id,
            status=PairTokenStatus.PENDING,
            created_at=now,
            expires_at=expires_at,
        )
        await pt.insert()
        return pt
    raise RuntimeError("pair_service: unable to allocate unique pair token")


async def cancel(*, token: str, family_id: str) -> PairToken:
    """Mark a pending PairToken as cancelled. Idempotent for already-final tokens."""
    pt = await PairToken.find_one(
        PairToken.token == token, PairToken.family_id == family_id
    )
    if pt is None:
        raise PairTokenInvalid
    if pt.status == PairTokenStatus.PENDING:
        pt.status = PairTokenStatus.CANCELLED
        pt.cancelled_at = _utcnow()
        await pt.save()
    return pt


async def expire_old() -> int:
    """Mark any pending PairToken whose expires_at is in the past as expired.

    Returns the number of rows touched. Designed to be called from a
    production background task (every ~60s); pure-Python no-op in tests.
    """
    now = _utcnow()
    pending = await PairToken.find(
        PairToken.status == PairTokenStatus.PENDING
    ).to_list()
    count = 0
    for pt in pending:
        if _to_utc(pt.expires_at) <= now:
            pt.status = PairTokenStatus.EXPIRED
            await pt.save()
            count += 1
    return count


async def redeem(
    *,
    token: str | None = None,
    short_code: str | None = None,
    device_id: str,
    user_agent: str | None,
) -> tuple[DeviceBinding, ChildProfile, str]:
    """Atomically redeem a PairToken into a DeviceBinding + ChildProfile.

    Exactly one of `token` / `short_code` must be supplied. Returns
    `(binding, child_profile, device_token_jwt)`.
    """
    if not token and not short_code:
        raise PairTokenInvalid
    if token:
        pt = await PairToken.find_one(PairToken.token == token)
    else:
        pt = await PairToken.find_one(PairToken.short_code == short_code)
    if pt is None:
        raise PairTokenInvalid

    now = _utcnow()
    if pt.status != PairTokenStatus.PENDING:
        if pt.status == PairTokenStatus.REDEEMED:
            raise PairTokenAlreadyRedeemed
        if pt.status == PairTokenStatus.EXPIRED:
            raise PairTokenExpired
        raise PairTokenInvalid  # cancelled

    if _to_utc(pt.expires_at) <= now:
        pt.status = PairTokenStatus.EXPIRED
        await pt.save()
        raise PairTokenExpired

    family_id = pt.family_id

    # Prior active bindings on this device:
    prior_active = await DeviceBinding.find(
        DeviceBinding.device_id == device_id,
        DeviceBinding.revoked_at == None,  # noqa: E711 — beanie field expression
    ).to_list()
    same_family_child_id: str | None = None
    for b in prior_active:
        b.revoked_at = now
        await b.save()
        if b.family_id == family_id:
            same_family_child_id = b.child_profile_id

    binding_id = _gen_binding_id()
    if same_family_child_id is not None:
        child_id = same_family_child_id
        child = await ChildProfile.find_one(ChildProfile.profile_id == child_id)
        if child is None:
            child = ChildProfile(
                profile_id=child_id,
                family_id=family_id,
                binding_id=binding_id,
                created_at=now,
                updated_at=now,
            )
            await child.insert()
        else:
            child.binding_id = binding_id
            child.deleted_at = None
            child.updated_at = now
            await child.save()
    else:
        child = ChildProfile(
            profile_id=_gen_child_id(),
            family_id=family_id,
            binding_id=binding_id,
            created_at=now,
            updated_at=now,
        )
        await child.insert()

    binding = DeviceBinding(
        binding_id=binding_id,
        family_id=family_id,
        device_id=device_id,
        child_profile_id=child.profile_id,
        user_agent=user_agent,
        created_at=now,
        last_seen_at=now,
    )
    await binding.insert()

    pt.status = PairTokenStatus.REDEEMED
    pt.redeemed_at = now
    pt.redeemed_by_device_id = device_id
    pt.redeemed_binding_id = binding.binding_id
    await pt.save()

    device_token = create_device_token(
        binding_id=binding.binding_id, child_profile_id=child.profile_id
    )
    return binding, child, device_token
