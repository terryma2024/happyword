"""V0.6.3 — Family pack service.

Implements the parent-side CRUD + publish/rollback flow plus the
child-facing merged JSON helper. All operations are scoped by
`family_id`; cross-family access is the router's responsibility (it
returns 404 PACK_NOT_FOUND on miss to avoid leaking pack existence).
"""

from __future__ import annotations

import hashlib
import json
import secrets
from dataclasses import dataclass
from dataclasses import field as dataclasses_field
from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any, Literal

if TYPE_CHECKING:
    from collections.abc import Iterable

from beanie.odm.enums import SortDirection

from app.config import get_settings
from app.models.family_pack_definition import FamilyPackDefinition, FamilyPackState
from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.services import pack_service

GLOBAL_PACK_SCHEMA_VERSION: int = 5

# V0.6.5 — global packs reuse this stack with a reserved family_id sentinel.
# Real Family.id values are 24-char ObjectId hex strings, so the
# underscore-padded literal cannot collide. See spec §5.3 + §11.
GLOBAL_PACK_FAMILY_ID: str = "__global__"

# Synthetic parent user id for automated lesson-import approvals (native path).
LESSON_IMPORT_SYSTEM_PARENT_ID = "lesson-import"


def lesson_import_pack_id(family_id: str) -> str:
    """Stable pack_id for the per-family auto-managed lesson-import pack."""
    fid = family_id.strip()
    digest = hashlib.sha256(f"lesson-import|{fid}".encode()).hexdigest()[:10]
    return f"pck-{digest}-li"


async def ensure_lesson_import_pack_definition(*, family_id: str) -> FamilyPackDefinition:
    """Return the singleton lesson-import pack for ``family_id``, creating it if needed."""
    fid = family_id.strip()
    pack_id = lesson_import_pack_id(fid)
    existing = await FamilyPackDefinition.find_one(
        FamilyPackDefinition.pack_id == pack_id,
        FamilyPackDefinition.family_id == fid,
    )
    if existing is not None:
        return existing
    return await create_definition(
        family_id=fid,
        name="Lesson imports",
        description="Words from approved textbook photo imports (auto-managed).",
        parent_user_id=LESSON_IMPORT_SYSTEM_PARENT_ID,
        pack_id=pack_id,
    )


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


class DraftWordNotFound(FamilyPackError):
    code = "DRAFT_WORD_NOT_FOUND"

    def __init__(self, missing_word_ids: list[str]) -> None:
        self.missing_word_ids = missing_word_ids
        joined = ", ".join(missing_word_ids)
        super().__init__(f"draft word(s) not found: {joined}")


class DraftValidationFailed(FamilyPackError):
    code = "DRAFT_VALIDATION_FAILED"

    def __init__(self, errors: list[dict[str, Any]]) -> None:
        self.errors = errors
        super().__init__(f"{len(errors)} draft row(s) invalid for publish")


@dataclass(frozen=True)
class CustomIdContract:
    """Helper holding the `fam-<family_id_8>-` custom-id contract."""

    family_id: str

    @property
    def prefix(self) -> str:
        # family_id is "fam-<8hex>"; spec uses the 8-hex slice as the second segment.
        return f"fam-{self.family_id.removeprefix('fam-')[:8]}-"


@dataclass(frozen=True)
class DraftSplitResult:
    source_definition: FamilyPackDefinition
    new_definition: FamilyPackDefinition
    source_draft: FamilyPackDraft
    new_draft: FamilyPackDraft
    selected_word_count: int
    mode: Literal["copy", "move"]


@dataclass(frozen=True)
class FamilyPackDeleteSummary:
    pack_id: str
    family_id: str
    deleted_definition_count: int
    deleted_draft_count: int
    deleted_version_count: int
    deleted_pointer_count: int


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
    scene: dict[str, Any] | None = None,
    pack_id: str | None = None,
) -> FamilyPackDefinition:
    """Create a new pack definition.

    V0.6.5 additive params (always optional, never break v0.6.4 callers):
    - `scene`: per-pack scene metadata for the battle screen. Defaults to
      empty dict; family packs always omit, global packs (caller passes
      `family_id == GLOBAL_PACK_FAMILY_ID`) populate it.
    - `pack_id`: caller-supplied id (e.g. `gpk-fruit-forest` for global
      packs). Defaults to the legacy `_gen_pack_id()` shape `pck-<8hex>`.
    """
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
    resolved_pack_id = pack_id or _gen_pack_id()
    definition = FamilyPackDefinition(
        pack_id=resolved_pack_id,
        family_id=family_id,
        name=name,
        description=description,
        scene=scene or {},
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
    scene: dict[str, Any] | None = None,
) -> FamilyPackDefinition:
    """Patch a pack definition.

    V0.6.5 — `scene` is additive: caller passes the new dict to fully
    replace the stored value, or leaves it `None` to keep the current one.
    """
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

    if scene is not None:
        definition.scene = scene

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


async def delete_definition(*, pack_id: str, family_id: str) -> FamilyPackDeleteSummary:
    definition = await get_definition_for_family(pack_id=pack_id, family_id=family_id)
    draft_count = await FamilyPackDraft.find(
        FamilyPackDraft.pack_definition_id == pack_id,
        FamilyPackDraft.family_id == family_id,
    ).count()
    version_count = await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == pack_id,
        FamilyWordPack.family_id == family_id,
    ).count()
    pointer_count = await FamilyPackPointer.find(
        FamilyPackPointer.pack_definition_id == pack_id,
        FamilyPackPointer.family_id == family_id,
    ).count()

    await FamilyPackDraft.find(
        FamilyPackDraft.pack_definition_id == pack_id,
        FamilyPackDraft.family_id == family_id,
    ).delete()
    await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == pack_id,
        FamilyWordPack.family_id == family_id,
    ).delete()
    await FamilyPackPointer.find(
        FamilyPackPointer.pack_definition_id == pack_id,
        FamilyPackPointer.family_id == family_id,
    ).delete()
    await definition.delete()

    return FamilyPackDeleteSummary(
        pack_id=pack_id,
        family_id=family_id,
        deleted_definition_count=1,
        deleted_draft_count=draft_count,
        deleted_version_count=version_count,
        deleted_pointer_count=pointer_count,
    )


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
    """Validate + normalise a single draft word entry.

    V0.6.5 — `custom_prefix=""` short-circuits the `fam-<8hex>-` enforcement
    so admins authoring global packs can use natural ids like `fruit-apple`.
    The caller (`upsert_draft_word`) passes an empty prefix when the
    definition's `family_id == GLOBAL_PACK_FAMILY_ID`.
    """
    source = payload["source"]
    if source == "hidden":
        return {"id": word_id, "hidden": True}
    if source == "custom":
        if custom_prefix and not word_id.startswith(custom_prefix):
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
    if custom_prefix and word_id.startswith(custom_prefix):
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
    # V0.6.5 — global packs (admin-authored) frequently carry full metadata
    # (translations, audio, illustration, distractors). Propagate optional
    # fields onto the published entry so child clients can render them.
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

    if definition.family_id == GLOBAL_PACK_FAMILY_ID:
        # V0.6.5 — global packs use natural word ids; bypass the fam-prefix
        # contract so admin authoring stays ergonomic.
        custom_prefix = ""
    else:
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


async def batch_upsert_draft_words(
    *,
    definition: FamilyPackDefinition,
    rows: list[dict[str, Any]],
    parent_user_id: str,
) -> tuple[FamilyPackDraft, list[dict[str, Any]]]:
    """Apply many draft upserts; collect per-row errors without aborting."""
    errors: list[dict[str, Any]] = []
    draft = await get_or_create_draft(
        definition=definition, parent_user_id=parent_user_id
    )

    for idx, row in enumerate(rows):
        word_id = str(row.get("word_id", ""))
        payload = {k: v for k, v in row.items() if k != "word_id"}
        try:
            draft = await upsert_draft_word(
                definition=definition,
                word_id=word_id,
                payload=payload,
                parent_user_id=parent_user_id,
            )
        except FamilyPackError as exc:
            errors.append(
                {
                    "row_index": idx,
                    "word_id": word_id,
                    "code": exc.code,
                    "message": str(exc),
                }
            )
    return draft, errors


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


def _unique_nonblank_word_ids(word_ids: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for raw in word_ids:
        word_id = str(raw).strip()
        if not word_id or word_id in seen:
            continue
        seen.add(word_id)
        out.append(word_id)
    return out


async def split_draft_to_new_pack(
    *,
    source_definition: FamilyPackDefinition,
    word_ids: list[str],
    new_name: str,
    new_description: str | None,
    mode: Literal["copy", "move"],
    parent_user_id: str,
    new_pack_id: str | None = None,
) -> DraftSplitResult:
    if mode not in ("copy", "move"):
        raise InvalidPayload("mode must be 'copy' or 'move'")

    selected_ids = _unique_nonblank_word_ids(word_ids)
    if not selected_ids:
        raise InvalidPayload("word_ids must not be empty")

    source_draft = await get_or_create_draft(
        definition=source_definition,
        parent_user_id=parent_user_id,
    )
    source_ids = {
        str(w.get("id"))
        for w in source_draft.words
        if isinstance(w.get("id"), str)
    }
    missing = [word_id for word_id in selected_ids if word_id not in source_ids]
    if missing:
        raise DraftWordNotFound(missing)

    selected_id_set = set(selected_ids)
    selected_words = [
        dict(word)
        for word in source_draft.words
        if isinstance(word.get("id"), str) and word["id"] in selected_id_set
    ]

    settings = get_settings()
    if len(selected_words) > settings.family_pack_max_words:
        raise WordLimitExceeded(
            f"split selection exceeds {settings.family_pack_max_words}-word cap"
        )

    new_definition = await create_definition(
        family_id=source_definition.family_id,
        name=new_name,
        description=new_description,
        parent_user_id=parent_user_id,
        pack_id=new_pack_id,
    )
    now = _utcnow()
    new_draft = FamilyPackDraft(
        pack_definition_id=new_definition.pack_id,
        family_id=new_definition.family_id,
        words=selected_words,
        updated_at=now,
        updated_by_parent_id=parent_user_id,
    )
    await new_draft.insert()
    new_definition.updated_at = now
    await new_definition.save()

    if mode == "move":
        source_draft.words = [
            word
            for word in source_draft.words
            if not (
                isinstance(word.get("id"), str)
                and word["id"] in selected_id_set
            )
        ]
        source_draft.updated_at = now
        source_draft.updated_by_parent_id = parent_user_id
        await source_draft.save()
        source_definition.updated_at = now
        await source_definition.save()

    return DraftSplitResult(
        source_definition=source_definition,
        new_definition=new_definition,
        source_draft=source_draft,
        new_draft=new_draft,
        selected_word_count=len(selected_words),
        mode=mode,
    )


# ---------------------------------------------------------------------------
# Publish / rollback / versions
# ---------------------------------------------------------------------------


def _publish_validation_errors_for_family(
    *,
    family_id: str,
    words: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Block publish when custom (`fam-…-`) draft rows are incomplete."""
    prefix = CustomIdContract(family_id=family_id).prefix
    out: list[dict[str, Any]] = []
    for idx, w in enumerate(words):
        wid = w.get("id")
        if not isinstance(wid, str) or not wid:
            out.append(
                {
                    "row_index": idx,
                    "word_id": "",
                    "message": "each entry needs a string id",
                }
            )
            continue
        if w.get("hidden") is True:
            continue
        if not wid.startswith(prefix):
            continue
        word = w.get("word")
        mz = w.get("meaningZh")
        cat = w.get("category")
        diff = w.get("difficulty")
        if not isinstance(word, str) or not word.strip():
            out.append(
                {
                    "row_index": idx,
                    "word_id": wid,
                    "message": "custom entry needs non-empty English word",
                }
            )
            continue
        if not isinstance(mz, str) or not mz.strip():
            out.append(
                {
                    "row_index": idx,
                    "word_id": wid,
                    "message": "custom entry needs non-empty Chinese meaning",
                }
            )
            continue
        if not isinstance(cat, str) or not cat.strip():
            out.append(
                {
                    "row_index": idx,
                    "word_id": wid,
                    "message": "custom entry needs category",
                }
            )
            continue
        if not isinstance(diff, int) or diff < 1 or diff > 5:
            out.append(
                {
                    "row_index": idx,
                    "word_id": wid,
                    "message": "custom entry needs difficulty 1–5",
                }
            )
            continue
    return out


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

    if definition.family_id != GLOBAL_PACK_FAMILY_ID:
        row_errors = _publish_validation_errors_for_family(
            family_id=definition.family_id,
            words=draft.words,
        )
        if row_errors:
            raise DraftValidationFailed(row_errors)

    # V0.6.5 — global packs (family_id sentinel) never publish words tagged
    # with `category=='test'`. Family packs keep the legacy permissive
    # behaviour because parent-side test categories are intentional study
    # material on a per-child basis. See spec §11 "test contamination".
    if definition.family_id == GLOBAL_PACK_FAMILY_ID:
        snapshot_words = [w for w in draft.words if w.get("category") != "test"]
        if not snapshot_words:
            raise EmptyPack(
                f"global pack {definition.pack_id} has no non-test words"
            )
    else:
        snapshot_words = list(draft.words)

    pointer = await FamilyPackPointer.find_one(
        FamilyPackPointer.pack_definition_id == definition.pack_id
    )
    next_version = 1 if pointer is None else pointer.current_version + 1

    now = _utcnow()
    snapshot = FamilyWordPack(
        pack_definition_id=definition.pack_id,
        family_id=definition.family_id,
        version=next_version,
        words=snapshot_words,
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
    # V0.6.5 — additive fields used by the public global-pack endpoint
    # (and by the parent merged JSON if it ever wants to render scene/desc).
    description: str | None = None
    scene: dict[str, Any] = dataclasses_field(default_factory=dict)
    published_at: datetime | None = None


async def collect_merged(
    *, family_id: str
) -> tuple[list[MergedSlice], str]:
    """Return active-and-published packs + the deterministic ETag.

    ETag fingerprints the published pack ids/versions plus display metadata
    carried by latest JSON responses, so clients re-fetch when a pack is
    renamed without publishing a new word version.
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
                description=definition.description,
                scene=dict(definition.scene),
                published_at=pack.published_at,
            )
        )
    slices.sort(key=lambda s: s.pack_id)
    return slices, _etag_from_slices(slices)


def _etag_from_pairs(pairs: Iterable[tuple[str, int]]) -> str:
    sorted_pairs = sorted(pairs, key=lambda p: (p[0], p[1]))
    fingerprint = "|".join(f"{pid}:{ver}" for pid, ver in sorted_pairs)
    digest = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest()
    return f'"{digest}"'


def _etag_from_slices(slices: Iterable[MergedSlice]) -> str:
    fingerprint_rows: list[dict[str, Any]] = []
    for s in sorted(slices, key=lambda row: (row.pack_id, row.version)):
        fingerprint_rows.append(
            {
                "pack_id": s.pack_id,
                "version": s.version,
                "schema_version": s.schema_version,
                "name": s.name,
                "description": s.description or "",
                "scene": s.scene,
                "published_at": s.published_at.isoformat()
                if s.published_at is not None
                else "",
            }
        )
    fingerprint = json.dumps(
        fingerprint_rows,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    digest = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest()
    return f'"{digest}"'


def _merge_words(
    global_words: list[dict[str, Any]], family_slices: list[MergedSlice]
) -> list[dict[str, Any]]:
    """Apply global baseline, then family overlays (hide / override)."""
    merged: dict[str, dict[str, Any]] = {}
    for word in global_words:
        word_id = word.get("id")
        if isinstance(word_id, str):
            merged[word_id] = dict(word)
    for family_slice in family_slices:
        for word in family_slice.words:
            word_id = word.get("id")
            if not isinstance(word_id, str):
                continue
            if word.get("hidden") is True:
                merged.pop(word_id, None)
                continue
            merged[word_id] = dict(word)
    return [merged[k] for k in sorted(merged)]


def _child_etag(*, global_version: int, family_fingerprint: str) -> str:
    raw = f"global:{global_version}|family:{family_fingerprint}"
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    return f'"{digest}"'


@dataclass(frozen=True)
class ChildMergedVocabulary:
    schema_version: int
    family_id: str
    global_version: int
    family_versions: dict[str, int]
    words: list[dict[str, Any]]
    slices: list[MergedSlice]
    etag: str


async def collect_child_vocabulary(*, family_id: str) -> ChildMergedVocabulary:
    """Merge published global pack JSON with this family's published packs."""
    global_version, global_payload = await pack_service.get_current_pack_payload()
    family_slices, fam_only_etag = await collect_merged(family_id=family_id)
    family_versions = {s.pack_id: s.version for s in family_slices}
    global_words = list(global_payload.get("words", []))
    words = _merge_words(global_words=global_words, family_slices=family_slices)
    gv = int(global_payload.get("version", global_version))
    schema_version = max(
        [int(global_payload.get("schema_version", GLOBAL_PACK_SCHEMA_VERSION))]
        + [s.schema_version for s in family_slices],
    )
    return ChildMergedVocabulary(
        schema_version=schema_version,
        family_id=family_id,
        global_version=gv,
        family_versions=family_versions,
        words=words,
        slices=family_slices,
        etag=_child_etag(global_version=gv, family_fingerprint=fam_only_etag),
    )


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
