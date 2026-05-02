"""V0.6.3 — Family pack service.

Implements the parent-side CRUD + publish/rollback flow plus the
child-facing merged JSON helper. All operations are scoped by
`family_id`; cross-family access is the router's responsibility (it
returns 404 PACK_NOT_FOUND on miss to avoid leaking pack existence).
"""

from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Iterable

from beanie.odm.enums import SortDirection

from app.config import get_settings
from app.models.family_pack_definition import FamilyPackDefinition, FamilyPackState
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack

GLOBAL_PACK_SCHEMA_VERSION: int = 5


class FamilyPackError(Exception):
    """Base for service errors translated to HTTP responses by routers."""

    code: str = "FAMILY_PACK_ERROR"


class PackNotFound(FamilyPackError):
    code = "PACK_NOT_FOUND"


class NameTaken(FamilyPackError):
    code = "NAME_TAKEN"


class PackFull(FamilyPackError):
    code = "PACK_FULL"


class EmptyPack(FamilyPackError):
    code = "EMPTY_PACK"


class WordLimitExceeded(FamilyPackError):
    code = "WORD_LIMIT_EXCEEDED"


class NoPreviousVersion(FamilyPackError):
    code = "NO_PREVIOUS_VERSION"


class InvalidPayload(FamilyPackError):
    code = "INVALID_PAYLOAD"


@dataclass(frozen=True)
class CustomIdContract:
    """Helper holding the `fam-<family_id_8>-` custom-id contract."""

    family_id: str

    @property
    def prefix(self) -> str:
        # family_id is "fam-<8hex>"; spec uses the 8-hex slice as the second segment.
        return f"fam-{self.family_id.removeprefix('fam-')[:8]}-"


def _utcnow() -> datetime:
    return datetime.now(tz=UTC)


def _gen_pack_id() -> str:
    return f"pck-{secrets.token_hex(4)}"


# ---------------------------------------------------------------------------
# Definition CRUD
# ---------------------------------------------------------------------------


async def create_definition(
    *,
    family_id: str,
    name: str,
    description: str | None,
    parent_user_id: str,
) -> FamilyPackDefinition:
    name = name.strip()
    if len(name) == 0:
        raise InvalidPayload("name must not be blank")

    # Active uniqueness within the family. (Beanie has no partial unique
    # index helper here; we check explicitly. Race condition tolerated —
    # at worst a duplicate would surface to the parent and be retryable.)
    existing = await FamilyPackDefinition.find(
        FamilyPackDefinition.family_id == family_id,
        FamilyPackDefinition.name == name,
        FamilyPackDefinition.state == FamilyPackState.ACTIVE,
    ).first_or_none()
    if existing is not None:
        raise NameTaken(name)

    now = _utcnow()
    pack_id = _gen_pack_id()
    definition = FamilyPackDefinition(
        pack_id=pack_id,
        family_id=family_id,
        name=name,
        description=description,
        state=FamilyPackState.ACTIVE,
        created_at=now,
        updated_at=now,
        created_by_parent_id=parent_user_id,
    )
    await definition.insert()
    return definition


async def get_definition_for_family(
    *, pack_id: str, family_id: str
) -> FamilyPackDefinition:
    """Strict family-scoped lookup. Raises `PackNotFound` if the pack does
    not exist OR belongs to a different family — never leaks existence."""
    definition = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == pack_id,
        FamilyPackDefinition.family_id == family_id,
    )
    if definition is None:
        raise PackNotFound(pack_id)
    return definition


async def patch_definition(
    *,
    pack_id: str,
    family_id: str,
    name: str | None,
    description: str | None,
) -> FamilyPackDefinition:
    definition = await get_definition_for_family(pack_id=pack_id, family_id=family_id)

    if name is not None:
        name_clean = name.strip()
        if len(name_clean) == 0:
            raise InvalidPayload("name must not be blank")
        if name_clean != definition.name:
            clash = await FamilyPackDefinition.find(
                FamilyPackDefinition.family_id == family_id,
                FamilyPackDefinition.name == name_clean,
                FamilyPackDefinition.state == FamilyPackState.ACTIVE,
            ).first_or_none()
            if clash is not None and clash.pack_id != pack_id:
                raise NameTaken(name_clean)
            definition.name = name_clean

    if description is not None:
        definition.description = description

    definition.updated_at = _utcnow()
    await definition.save()
    return definition


async def archive(*, pack_id: str, family_id: str) -> FamilyPackDefinition:
    definition = await get_definition_for_family(pack_id=pack_id, family_id=family_id)
    if definition.state == FamilyPackState.ARCHIVED:
        return definition
    definition.state = FamilyPackState.ARCHIVED
    definition.archived_at = _utcnow()
    definition.updated_at = definition.archived_at
    await definition.save()
    return definition


async def unarchive(*, pack_id: str, family_id: str) -> FamilyPackDefinition:
    definition = await get_definition_for_family(pack_id=pack_id, family_id=family_id)
    if definition.state == FamilyPackState.ACTIVE:
        return definition
    # Guard against name conflicts with another active pack that has since
    # adopted the name. We surface NAME_TAKEN so the parent can rename
    # before unarchiving.
    clash = await FamilyPackDefinition.find(
        FamilyPackDefinition.family_id == family_id,
        FamilyPackDefinition.name == definition.name,
        FamilyPackDefinition.state == FamilyPackState.ACTIVE,
    ).first_or_none()
    if clash is not None and clash.pack_id != pack_id:
        raise NameTaken(definition.name)
    definition.state = FamilyPackState.ACTIVE
    definition.archived_at = None
    definition.updated_at = _utcnow()
    await definition.save()
    return definition


async def list_definitions(
    *, family_id: str, include_archived: bool
) -> list[FamilyPackDefinition]:
    if include_archived:
        rows = await FamilyPackDefinition.find(
            FamilyPackDefinition.family_id == family_id,
            sort=[("updated_at", SortDirection.DESCENDING)],
        ).to_list()
    else:
        rows = await FamilyPackDefinition.find(
            FamilyPackDefinition.family_id == family_id,
            FamilyPackDefinition.state == FamilyPackState.ACTIVE,
            sort=[("updated_at", SortDirection.DESCENDING)],
        ).to_list()
    return rows


# ---------------------------------------------------------------------------
# Draft management
# ---------------------------------------------------------------------------


async def get_or_create_draft(
    *, definition: FamilyPackDefinition, parent_user_id: str
) -> FamilyPackDraft:
    draft = await FamilyPackDraft.find_one(
        FamilyPackDraft.pack_definition_id == definition.pack_id
    )
    if draft is not None:
        return draft
    now = _utcnow()
    draft = FamilyPackDraft(
        pack_definition_id=definition.pack_id,
        family_id=definition.family_id,
        words=[],
        updated_at=now,
        updated_by_parent_id=parent_user_id,
    )
    await draft.insert()
    return draft


def _build_entry(
    *, word_id: str, payload: dict[str, Any], custom_prefix: str
) -> dict[str, Any]:
    source = payload["source"]
    if source == "hidden":
        return {"id": word_id, "hidden": True}
    if source == "custom":
        if not word_id.startswith(custom_prefix):
            raise InvalidPayload(f"custom id must start with '{custom_prefix}'")
        word = payload.get("word")
        meaning_zh = payload.get("meaning_zh")
        category = payload.get("category")
        difficulty = payload.get("difficulty")
        if not isinstance(word, str) or not isinstance(meaning_zh, str):
            raise InvalidPayload("custom entry needs `word` and `meaning_zh`")
        if not isinstance(category, str) or not isinstance(difficulty, int):
            raise InvalidPayload("custom entry needs `category` and `difficulty`")
        entry: dict[str, Any] = {
            "id": word_id,
            "word": word,
            "meaningZh": meaning_zh,
            "category": category,
            "difficulty": difficulty,
        }
        for src, dst in (
            ("distractors", "distractors"),
            ("example_en", "exampleEn"),
            ("example_zh", "exampleZh"),
            ("illustration_url", "illustrationUrl"),
            ("audio_url", "audioUrl"),
        ):
            value = payload.get(src)
            if value is not None:
                entry[dst] = value
        return entry
    # source == "global"
    if word_id.startswith(custom_prefix):
        raise InvalidPayload("global source cannot use a `fam-` id")
    # Parent may also override individual fields when sourcing from global.
    entry = {"id": word_id}
    if isinstance(payload.get("word"), str):
        entry["word"] = payload["word"]
    if isinstance(payload.get("meaning_zh"), str):
        entry["meaningZh"] = payload["meaning_zh"]
    if isinstance(payload.get("category"), str):
        entry["category"] = payload["category"]
    if isinstance(payload.get("difficulty"), int):
        entry["difficulty"] = payload["difficulty"]
    return entry


async def upsert_draft_word(
    *,
    definition: FamilyPackDefinition,
    word_id: str,
    payload: dict[str, Any],
    parent_user_id: str,
) -> FamilyPackDraft:
    settings = get_settings()
    draft = await get_or_create_draft(
        definition=definition, parent_user_id=parent_user_id
    )

    existing_idx = next(
        (i for i, w in enumerate(draft.words) if w.get("id") == word_id), None
    )
    if existing_idx is None and len(draft.words) >= settings.family_pack_max_words:
        raise PackFull(
            f"draft already at limit {settings.family_pack_max_words}"
        )

    custom_prefix = CustomIdContract(family_id=definition.family_id).prefix
    entry = _build_entry(
        word_id=word_id, payload=payload, custom_prefix=custom_prefix
    )

    if existing_idx is None:
        draft.words.append(entry)
    else:
        draft.words[existing_idx] = entry

    draft.updated_at = _utcnow()
    draft.updated_by_parent_id = parent_user_id
    await draft.save()

    # Bump the definition's updated_at so the list view sorts recently-edited
    # packs to the top.
    definition.updated_at = draft.updated_at
    await definition.save()
    return draft


async def remove_draft_word(
    *,
    definition: FamilyPackDefinition,
    word_id: str,
    parent_user_id: str,
) -> FamilyPackDraft:
    draft = await get_or_create_draft(
        definition=definition, parent_user_id=parent_user_id
    )
    before = len(draft.words)
    draft.words = [w for w in draft.words if w.get("id") != word_id]
    if len(draft.words) == before:
        # No-op delete is fine (idempotent).
        return draft
    draft.updated_at = _utcnow()
    draft.updated_by_parent_id = parent_user_id
    await draft.save()
    definition.updated_at = draft.updated_at
    await definition.save()
    return draft


# ---------------------------------------------------------------------------
# Publish / rollback / versions
# ---------------------------------------------------------------------------


async def publish(
    *,
    definition: FamilyPackDefinition,
    parent_user_id: str,
    notes: str | None,
) -> FamilyWordPack:
    settings = get_settings()
    draft = await get_or_create_draft(
        definition=definition, parent_user_id=parent_user_id
    )
    if len(draft.words) == 0:
        raise EmptyPack(definition.pack_id)
    if len(draft.words) > settings.family_pack_max_words:
        raise WordLimitExceeded(definition.pack_id)

    pointer = await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == definition.pack_id
    )
    next_version = 1 if pointer is None else pointer.current_version + 1

    now = _utcnow()
    snapshot = FamilyWordPack(
        pack_definition_id=definition.pack_id,
        family_id=definition.family_id,
        version=next_version,
        words=list(draft.words),
        schema_version=GLOBAL_PACK_SCHEMA_VERSION,
        published_at=now,
        published_by_parent_id=parent_user_id,
        notes=notes,
    )
    await snapshot.insert()

    if pointer is None:
        pointer = FamilyPackPointer(
            pack_definition_id=definition.pack_id,
            family_id=definition.family_id,
            current_version=next_version,
            previous_version=None,
            updated_at=now,
        )
        await pointer.insert()
    else:
        pointer.previous_version = pointer.current_version
        pointer.current_version = next_version
        pointer.updated_at = now
        await pointer.save()

    definition.updated_at = now
    await definition.save()
    return snapshot


async def rollback(
    *, definition: FamilyPackDefinition
) -> FamilyPackPointer:
    pointer = await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == definition.pack_id
    )
    if pointer is None or pointer.previous_version is None:
        raise NoPreviousVersion(definition.pack_id)
    pointer.previous_version, pointer.current_version = (
        pointer.current_version,
        pointer.previous_version,
    )
    pointer.updated_at = _utcnow()
    await pointer.save()
    definition.updated_at = pointer.updated_at
    await definition.save()
    return pointer


async def list_versions(*, definition: FamilyPackDefinition) -> list[FamilyWordPack]:
    return await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == definition.pack_id,
        sort=[("version", SortDirection.DESCENDING)],
    ).to_list()


async def current_pack(
    *, definition: FamilyPackDefinition
) -> tuple[FamilyPackPointer | None, FamilyWordPack | None]:
    pointer = await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == definition.pack_id
    )
    if pointer is None:
        return None, None
    pack = await FamilyWordPack.find_one(
        FamilyWordPack.pack_definition_id == definition.pack_id,
        FamilyWordPack.version == pointer.current_version,
    )
    return pointer, pack


# ---------------------------------------------------------------------------
# Child merged JSON
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MergedSlice:
    pack_id: str
    name: str
    version: int
    schema_version: int
    words: list[dict[str, Any]]


async def collect_merged(
    *, family_id: str
) -> tuple[list[MergedSlice], str]:
    """Return active-and-published packs + the deterministic ETag.

    ETag is `"sha256({pack_id}:{version}|...)"` over sorted (pack_id, version)
    pairs so the client can revalidate cheaply with HEAD/If-None-Match.
    """
    definitions = await FamilyPackDefinition.find(
        FamilyPackDefinition.family_id == family_id,
        FamilyPackDefinition.state == FamilyPackState.ACTIVE,
    ).to_list()
    by_pack_id: dict[str, FamilyPackDefinition] = {d.pack_id: d for d in definitions}
    if not by_pack_id:
        return [], _etag_from_pairs([])

    pointers = await FamilyPackPointer.find(
        FamilyPackPointer.family_id == family_id,
    ).to_list()
    pointer_by_pack: dict[str, FamilyPackPointer] = {
        p.pack_definition_id: p
        for p in pointers
        if p.pack_definition_id in by_pack_id
    }
    if not pointer_by_pack:
        return [], _etag_from_pairs([])

    slices: list[MergedSlice] = []
    pairs: list[tuple[str, int]] = []
    for pack_id, pointer in pointer_by_pack.items():
        pack = await FamilyWordPack.find_one(
            FamilyWordPack.pack_definition_id == pack_id,
            FamilyWordPack.version == pointer.current_version,
        )
        if pack is None:
            continue
        definition = by_pack_id[pack_id]
        slices.append(
            MergedSlice(
                pack_id=pack_id,
                name=definition.name,
                version=pack.version,
                schema_version=pack.schema_version,
                words=list(pack.words),
            )
        )
        pairs.append((pack_id, pack.version))
    slices.sort(key=lambda s: s.pack_id)
    return slices, _etag_from_pairs(pairs)


def _etag_from_pairs(pairs: Iterable[tuple[str, int]]) -> str:
    sorted_pairs = sorted(pairs, key=lambda p: (p[0], p[1]))
    fingerprint = "|".join(f"{pid}:{ver}" for pid, ver in sorted_pairs)
    digest = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest()
    return f'"{digest}"'


# ---------------------------------------------------------------------------
# Helpers used by the parent list view
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PackSummary:
    definition: FamilyPackDefinition
    pointer: FamilyPackPointer | None
    current_word_count: int
    draft_word_count: int
    has_unpublished_changes: bool


async def summarize(
    *, definitions: list[FamilyPackDefinition]
) -> list[PackSummary]:
    out: list[PackSummary] = []
    for d in definitions:
        pointer, pack = await current_pack(definition=d)
        draft = await FamilyPackDraft.find_one(
            FamilyPackDraft.pack_definition_id == d.pack_id
        )
        current_count = len(pack.words) if pack is not None else 0
        draft_count = 0 if draft is None else len(draft.words)
        if pack is None:
            has_changes = draft_count > 0
        else:
            has_changes = (
                draft is None
                or draft.words != pack.words
            )
        out.append(
            PackSummary(
                definition=d,
                pointer=pointer,
                current_word_count=current_count,
                draft_word_count=draft_count,
                has_unpublished_changes=has_changes,
            )
        )
    return out
