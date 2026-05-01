"""V0.6.3 — service-level tests for family_pack_service.

Mirrors the server contracts ≥18 listed in the V0.6 plan §V0.6.3.
The HTTP layer is covered separately in `test_family_pack_routes.py`.
"""

from __future__ import annotations

from typing import Any, cast

import pytest

from app.services import family_pack_service as svc
from app.services.family_service import create_family_for_parent


async def _new_family(email: str = "fp@example.com") -> tuple[str, str]:
    family, user = await create_family_for_parent(email=email)
    return family.family_id, user.username


def _custom_word(family_id: str, slug: str) -> str:
    return f"fam-{family_id.removeprefix('fam-')[:8]}-{slug}"


def _custom_payload(*, slug: str = "apple") -> dict[str, Any]:
    return {
        "source": "custom",
        "word": "apple",
        "meaning_zh": "苹果",
        "category": "fruit",
        "difficulty": 2,
    }


def _global_payload() -> dict[str, Any]:
    return {"source": "global"}


def _hidden_payload() -> dict[str, Any]:
    return {"source": "hidden"}


# ---------------------------------------------------------------------------
# Definitions / metadata (contracts 1–7)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_create_definition_returns_pack_id(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id,
        name="三年级第三单元",
        description=None,
        parent_user_id=parent,
    )
    assert d.pack_id.startswith("pck-")
    assert len(d.pack_id) == len("pck-") + 8


@pytest.mark.asyncio
async def test_create_definition_duplicate_active_name_409(db: object) -> None:
    family_id, parent = await _new_family()
    await svc.create_definition(
        family_id=family_id, name="水果", description=None, parent_user_id=parent
    )
    with pytest.raises(svc.NameTaken):
        await svc.create_definition(
            family_id=family_id,
            name="水果",
            description=None,
            parent_user_id=parent,
        )


@pytest.mark.asyncio
async def test_create_after_archive_reuses_name(db: object) -> None:
    family_id, parent = await _new_family()
    first = await svc.create_definition(
        family_id=family_id, name="水果", description=None, parent_user_id=parent
    )
    await svc.archive(pack_id=first.pack_id, family_id=family_id)
    again = await svc.create_definition(
        family_id=family_id, name="水果", description=None, parent_user_id=parent
    )
    assert again.pack_id != first.pack_id


@pytest.mark.asyncio
async def test_list_default_excludes_archived(db: object) -> None:
    family_id, parent = await _new_family()
    a = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    b = await svc.create_definition(
        family_id=family_id, name="B", description=None, parent_user_id=parent
    )
    await svc.archive(pack_id=a.pack_id, family_id=family_id)
    visible = await svc.list_definitions(
        family_id=family_id, include_archived=False
    )
    all_packs = await svc.list_definitions(
        family_id=family_id, include_archived=True
    )
    assert {p.pack_id for p in visible} == {b.pack_id}
    assert {p.pack_id for p in all_packs} == {a.pack_id, b.pack_id}


@pytest.mark.asyncio
async def test_patch_updates_name_and_description(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="orig", description=None, parent_user_id=parent
    )
    upd = await svc.patch_definition(
        pack_id=d.pack_id, family_id=family_id, name="renamed", description="desc"
    )
    assert upd.name == "renamed"
    assert upd.description == "desc"
    # mongomock-motor strips tz info on round-trip; just assert presence.
    assert upd.updated_at is not None


@pytest.mark.asyncio
async def test_archive_then_unarchive(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    arch = await svc.archive(pack_id=d.pack_id, family_id=family_id)
    assert arch.state.value == "archived"
    assert arch.archived_at is not None
    un = await svc.unarchive(pack_id=d.pack_id, family_id=family_id)
    assert un.state.value == "active"
    assert un.archived_at is None


@pytest.mark.asyncio
async def test_get_definition_for_other_family_raises_pack_not_found(
    db: object,
) -> None:
    family_id_a, parent_a = await _new_family("a@example.com")
    family_id_b, _parent_b = await _new_family("b@example.com")
    d = await svc.create_definition(
        family_id=family_id_a,
        name="A's pack",
        description=None,
        parent_user_id=parent_a,
    )
    with pytest.raises(svc.PackNotFound):
        await svc.get_definition_for_family(
            pack_id=d.pack_id, family_id=family_id_b
        )


# ---------------------------------------------------------------------------
# Draft (contracts 8–13)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_upsert_global_word_appends(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    draft = await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    assert len(draft.words) == 1
    assert draft.words[0]["id"] == "apple"


@pytest.mark.asyncio
async def test_upsert_custom_word_requires_family_prefix(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    with pytest.raises(svc.InvalidPayload):
        await svc.upsert_draft_word(
            definition=d,
            word_id="naked-id",
            payload=_custom_payload(),
            parent_user_id=parent,
        )
    proper_id = _custom_word(family_id, "apple")
    draft = await svc.upsert_draft_word(
        definition=d,
        word_id=proper_id,
        payload=_custom_payload(slug="apple"),
        parent_user_id=parent,
    )
    assert draft.words[0]["id"] == proper_id
    assert draft.words[0]["meaningZh"] == "苹果"


@pytest.mark.asyncio
async def test_upsert_hidden_word_marks_hidden(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    draft = await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_hidden_payload(),
        parent_user_id=parent,
    )
    assert draft.words[0] == {"id": "apple", "hidden": True}


@pytest.mark.asyncio
async def test_upsert_at_word_limit_409(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    for i in range(50):
        await svc.upsert_draft_word(
            definition=d,
            word_id=f"global-{i}",
            payload=_global_payload(),
            parent_user_id=parent,
        )
    with pytest.raises(svc.PackFull):
        await svc.upsert_draft_word(
            definition=d,
            word_id="global-50",
            payload=_global_payload(),
            parent_user_id=parent,
        )


@pytest.mark.asyncio
async def test_upsert_at_limit_existing_word_in_place_update(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    for i in range(50):
        await svc.upsert_draft_word(
            definition=d,
            word_id=f"global-{i}",
            payload=_global_payload(),
            parent_user_id=parent,
        )
    draft = await svc.upsert_draft_word(
        definition=d,
        word_id="global-0",
        payload=_hidden_payload(),
        parent_user_id=parent,
    )
    assert len(draft.words) == 50
    target = next(w for w in draft.words if w["id"] == "global-0")
    assert target == {"id": "global-0", "hidden": True}


@pytest.mark.asyncio
async def test_remove_draft_word_idempotent(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="x",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    after = await svc.remove_draft_word(
        definition=d, word_id="x", parent_user_id=parent
    )
    assert len(after.words) == 0
    again = await svc.remove_draft_word(
        definition=d, word_id="x", parent_user_id=parent
    )
    assert len(again.words) == 0


# ---------------------------------------------------------------------------
# Publish / rollback / versions (contracts 14–20)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_publish_empty_draft_409(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    with pytest.raises(svc.EmptyPack):
        await svc.publish(definition=d, parent_user_id=parent, notes=None)


@pytest.mark.asyncio
async def test_publish_first_version_creates_pointer(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    snap = await svc.publish(definition=d, parent_user_id=parent, notes="first")
    assert snap.version == 1
    pointer, _pack = await svc.current_pack(definition=d)
    assert pointer is not None
    assert pointer.current_version == 1
    assert pointer.previous_version is None


@pytest.mark.asyncio
async def test_publish_twice_advances_version_and_pointer(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes=None)
    await svc.upsert_draft_word(
        definition=d,
        word_id="banana",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    snap2 = await svc.publish(definition=d, parent_user_id=parent, notes=None)
    assert snap2.version == 2
    pointer, pack = await svc.current_pack(definition=d)
    assert pointer is not None and pack is not None
    assert pointer.current_version == 2
    assert pointer.previous_version == 1
    ids = sorted(w["id"] for w in pack.words)
    assert ids == ["apple", "banana"]


@pytest.mark.asyncio
async def test_rollback_swaps_pointer(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes=None)
    await svc.upsert_draft_word(
        definition=d,
        word_id="banana",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes=None)
    pointer = await svc.rollback(definition=d)
    assert pointer.current_version == 1
    assert pointer.previous_version == 2
    _pointer, pack = await svc.current_pack(definition=d)
    assert pack is not None
    ids = sorted(w["id"] for w in pack.words)
    assert ids == ["apple"]


@pytest.mark.asyncio
async def test_rollback_with_no_previous_409(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes=None)
    with pytest.raises(svc.NoPreviousVersion):
        await svc.rollback(definition=d)


@pytest.mark.asyncio
async def test_list_versions_orders_desc(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes="v1")
    await svc.upsert_draft_word(
        definition=d,
        word_id="banana",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes="v2")
    versions = await svc.list_versions(definition=d)
    assert [s.version for s in versions] == [2, 1]


# ---------------------------------------------------------------------------
# Child merged JSON (contracts 21–27)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_collect_merged_empty_when_no_published(db: object) -> None:
    family_id, _ = await _new_family()
    slices, etag = await svc.collect_merged(family_id=family_id)
    assert slices == []
    # Even empty, ETag is deterministic.
    assert etag.startswith('"') and etag.endswith('"')


@pytest.mark.asyncio
async def test_collect_merged_two_packs(db: object) -> None:
    family_id, parent = await _new_family()
    d1 = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    d2 = await svc.create_definition(
        family_id=family_id, name="B", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d1, word_id="apple", payload=_global_payload(), parent_user_id=parent
    )
    await svc.publish(definition=d1, parent_user_id=parent, notes=None)
    await svc.upsert_draft_word(
        definition=d2, word_id="banana", payload=_global_payload(), parent_user_id=parent
    )
    await svc.publish(definition=d2, parent_user_id=parent, notes=None)
    slices, etag = await svc.collect_merged(family_id=family_id)
    assert len(slices) == 2
    pack_ids = sorted(s.pack_id for s in slices)
    assert pack_ids == sorted([d1.pack_id, d2.pack_id])
    assert etag != svc._etag_from_pairs([])


@pytest.mark.asyncio
async def test_etag_changes_when_archive(db: object) -> None:
    family_id, parent = await _new_family()
    d1 = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    d2 = await svc.create_definition(
        family_id=family_id, name="B", description=None, parent_user_id=parent
    )
    for d in (d1, d2):
        await svc.upsert_draft_word(
            definition=d,
            word_id="apple",
            payload=_global_payload(),
            parent_user_id=parent,
        )
        await svc.publish(definition=d, parent_user_id=parent, notes=None)
    _, etag_before = await svc.collect_merged(family_id=family_id)
    await svc.archive(pack_id=d1.pack_id, family_id=family_id)
    _, etag_after = await svc.collect_merged(family_id=family_id)
    assert etag_before != etag_after


@pytest.mark.asyncio
async def test_etag_deterministic_across_calls(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes=None)
    _, etag_a = await svc.collect_merged(family_id=family_id)
    _, etag_b = await svc.collect_merged(family_id=family_id)
    assert etag_a == etag_b


@pytest.mark.asyncio
async def test_archived_pack_excluded_from_merged(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes=None)
    await svc.archive(pack_id=d.pack_id, family_id=family_id)
    slices, _ = await svc.collect_merged(family_id=family_id)
    assert slices == []


@pytest.mark.asyncio
async def test_summarize_reflects_unpublished_changes(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    sum0 = await svc.summarize(definitions=[d])
    assert sum0[0].draft_word_count == 0
    assert sum0[0].has_unpublished_changes is False
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    sum1 = await svc.summarize(definitions=[d])
    assert sum1[0].draft_word_count == 1
    assert sum1[0].has_unpublished_changes is True
    await svc.publish(definition=d, parent_user_id=parent, notes=None)
    sum2 = await svc.summarize(definitions=[d])
    assert sum2[0].current_word_count == 1
    assert sum2[0].has_unpublished_changes is False


@pytest.mark.asyncio
async def test_summarize_uses_draft_after_publish_then_edit(db: object) -> None:
    family_id, parent = await _new_family()
    d = await svc.create_definition(
        family_id=family_id, name="A", description=None, parent_user_id=parent
    )
    await svc.upsert_draft_word(
        definition=d,
        word_id="apple",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    await svc.publish(definition=d, parent_user_id=parent, notes=None)
    await svc.upsert_draft_word(
        definition=d,
        word_id="banana",
        payload=_global_payload(),
        parent_user_id=parent,
    )
    summaries = await svc.summarize(definitions=[d])
    assert summaries[0].current_word_count == 1
    assert summaries[0].draft_word_count == 2
    assert summaries[0].has_unpublished_changes is True


def test_custom_id_contract_prefix() -> None:
    contract = svc.CustomIdContract(family_id="fam-12345678")
    assert contract.prefix == "fam-12345678-"
    # When the family_id passed in is just the 8-hex part (defensive coding):
    assert (
        cast("svc.CustomIdContract", svc.CustomIdContract(family_id="abcdef01")).prefix
        == "fam-abcdef01-"
    )
