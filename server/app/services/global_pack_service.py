"""V0.6.5 — Thin wrapper around family_pack_service for global packs.

Hides the `family_id=GLOBAL_PACK_FAMILY_ID` sentinel from admin-side
callers and forces a `gpk-` prefix for newly minted pack ids so the
source layer is recognizable. All persistence lives in the underlying
family-pack stack; this module is purely sugar.
"""

from __future__ import annotations

from dataclasses import dataclass
import secrets
from typing import TYPE_CHECKING, Any, Literal

from app.models.family_pack_draft import FamilyPackDraft
from app.models.family_pack_pointer import FamilyPackPointer
from app.models.family_word_pack import FamilyWordPack
from app.services import family_pack_import_service
from app.services import family_pack_service as fps

if TYPE_CHECKING:
    from app.models.family_pack_definition import FamilyPackDefinition

GLOBAL_PACK_FAMILY_ID = fps.GLOBAL_PACK_FAMILY_ID
GlobalPackError = fps.FamilyPackError
PackNotFound = fps.PackNotFound
EmptyPack = fps.EmptyPack
WordLimitExceeded = fps.WordLimitExceeded
NoPreviousVersion = fps.NoPreviousVersion
InvalidPayload = fps.InvalidPayload
NameTaken = fps.NameTaken
MergedSlice = fps.MergedSlice
DraftSplitResult = fps.DraftSplitResult
DraftWordNotFound = fps.DraftWordNotFound


def _gen_pack_id() -> str:
    return f"gpk-{secrets.token_hex(4)}"


@dataclass(frozen=True)
class GlobalPackDeleteSummary:
    pack_id: str
    deleted_definition_count: int
    deleted_draft_count: int
    deleted_version_count: int
    deleted_pointer_count: int


async def create_definition(
    *,
    name: str,
    admin_id: str,
    description: str | None = None,
    scene: dict[str, Any] | None = None,
    pack_id: str | None = None,
) -> FamilyPackDefinition:
    return await fps.create_definition(
        family_id=GLOBAL_PACK_FAMILY_ID,
        parent_user_id=admin_id,
        name=name,
        description=description,
        scene=scene or {},
        pack_id=pack_id or _gen_pack_id(),
    )


async def get_definition(*, pack_id: str) -> FamilyPackDefinition:
    return await fps.get_definition_for_family(
        family_id=GLOBAL_PACK_FAMILY_ID, pack_id=pack_id
    )


async def list_definitions(
    *, include_archived: bool = False
) -> list[FamilyPackDefinition]:
    return await fps.list_definitions(
        family_id=GLOBAL_PACK_FAMILY_ID, include_archived=include_archived
    )


async def patch_definition(
    *,
    pack_id: str,
    admin_id: str,
    name: str | None = None,
    description: str | None = None,
    scene: dict[str, Any] | None = None,
) -> FamilyPackDefinition:
    """Patch a global pack definition.

    `admin_id` is accepted for symmetry with `create_definition` and to
    keep callers prepared for an audit-trail expansion later. The
    underlying `fps.patch_definition` does not currently consume it.
    """
    _ = admin_id
    return await fps.patch_definition(
        family_id=GLOBAL_PACK_FAMILY_ID,
        pack_id=pack_id,
        name=name,
        description=description,
        scene=scene,
    )


async def archive(*, pack_id: str) -> FamilyPackDefinition:
    return await fps.archive(
        family_id=GLOBAL_PACK_FAMILY_ID, pack_id=pack_id
    )


async def unarchive(*, pack_id: str) -> FamilyPackDefinition:
    return await fps.unarchive(
        family_id=GLOBAL_PACK_FAMILY_ID, pack_id=pack_id
    )


async def get_or_create_draft(
    *, pack_id: str, admin_id: str
) -> FamilyPackDraft:
    definition = await get_definition(pack_id=pack_id)
    return await fps.get_or_create_draft(
        definition=definition, parent_user_id=admin_id
    )


async def upsert_draft_word(
    *, pack_id: str, admin_id: str, entry: dict[str, Any]
) -> FamilyPackDraft:
    """Translate camelCase admin-friendly entry shape to family_pack_service's
    snake_case payload contract (defaulting `source='global'`)."""
    definition = await get_definition(pack_id=pack_id)
    word_id = entry["id"]
    payload: dict[str, Any] = {
        "source": entry.get("source", "global"),
        "word": entry.get("word"),
        "meaning_zh": entry.get("meaningZh") or entry.get("meaning_zh"),
        "category": entry.get("category"),
        "difficulty": entry.get("difficulty"),
    }
    for src_camel, dst_snake in (
        ("distractors", "distractors"),
        ("exampleEn", "example_en"),
        ("exampleZh", "example_zh"),
        ("illustrationUrl", "illustration_url"),
        ("audioUrl", "audio_url"),
    ):
        v = entry.get(src_camel)
        if v is None:
            v = entry.get(dst_snake)
        if v is not None:
            payload[dst_snake] = v
    return await fps.upsert_draft_word(
        definition=definition,
        word_id=word_id,
        payload=payload,
        parent_user_id=admin_id,
    )


async def remove_draft_word(
    *, pack_id: str, admin_id: str, word_id: str
) -> FamilyPackDraft:
    definition = await get_definition(pack_id=pack_id)
    return await fps.remove_draft_word(
        definition=definition,
        word_id=word_id,
        parent_user_id=admin_id,
    )


async def split_draft_to_new_pack(
    *,
    pack_id: str,
    admin_id: str,
    word_ids: list[str],
    new_name: str,
    new_description: str | None,
    mode: Literal["copy", "move"],
) -> DraftSplitResult:
    definition = await get_definition(pack_id=pack_id)
    return await fps.split_draft_to_new_pack(
        source_definition=definition,
        word_ids=word_ids,
        new_name=new_name,
        new_description=new_description,
        mode=mode,
        parent_user_id=admin_id,
        new_pack_id=_gen_pack_id(),
    )


async def publish(
    *, pack_id: str, admin_id: str, notes: str | None = None
) -> FamilyWordPack:
    definition = await get_definition(pack_id=pack_id)
    return await fps.publish(
        definition=definition, parent_user_id=admin_id, notes=notes
    )


async def rollback(*, pack_id: str) -> FamilyPackPointer:
    definition = await get_definition(pack_id=pack_id)
    return await fps.rollback(definition=definition)


async def list_versions(*, pack_id: str) -> list[FamilyWordPack]:
    definition = await get_definition(pack_id=pack_id)
    return await fps.list_versions(definition=definition)


async def delete_definition(*, pack_id: str) -> GlobalPackDeleteSummary:
    definition = await get_definition(pack_id=pack_id)
    draft_count = await FamilyPackDraft.find(
        FamilyPackDraft.pack_definition_id == pack_id,
        FamilyPackDraft.family_id == GLOBAL_PACK_FAMILY_ID,
    ).count()
    version_count = await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == pack_id,
        FamilyWordPack.family_id == GLOBAL_PACK_FAMILY_ID,
    ).count()
    pointer_count = await FamilyPackPointer.find(
        FamilyPackPointer.pack_definition_id == pack_id,
        FamilyPackPointer.family_id == GLOBAL_PACK_FAMILY_ID,
    ).count()

    await FamilyPackDraft.find(
        FamilyPackDraft.pack_definition_id == pack_id,
        FamilyPackDraft.family_id == GLOBAL_PACK_FAMILY_ID,
    ).delete()
    await FamilyWordPack.find(
        FamilyWordPack.pack_definition_id == pack_id,
        FamilyWordPack.family_id == GLOBAL_PACK_FAMILY_ID,
    ).delete()
    await FamilyPackPointer.find(
        FamilyPackPointer.pack_definition_id == pack_id,
        FamilyPackPointer.family_id == GLOBAL_PACK_FAMILY_ID,
    ).delete()
    await definition.delete()

    return GlobalPackDeleteSummary(
        pack_id=pack_id,
        deleted_definition_count=1,
        deleted_draft_count=draft_count,
        deleted_version_count=version_count,
        deleted_pointer_count=pointer_count,
    )


async def current_pack(
    *, pack_id: str
) -> tuple[FamilyPackPointer | None, FamilyWordPack | None]:
    definition = await get_definition(pack_id=pack_id)
    return await fps.current_pack(definition=definition)


async def collect_merged() -> tuple[list[fps.MergedSlice], str]:
    return await fps.collect_merged(family_id=GLOBAL_PACK_FAMILY_ID)


async def import_image_to_draft(
    *,
    pack_id: str,
    admin_id: str,
    payload: bytes,
    mime: str,
) -> tuple[str, str, int, FamilyPackDraft, list[dict[str, Any]]]:
    """Vision-parse an image and upsert extracted rows into the pack draft."""
    definition = await get_definition(pack_id=pack_id)
    return await family_pack_import_service.import_image_to_draft(
        definition=definition,
        payload=payload,
        mime=mime,
        parent_user_id=admin_id,
    )
