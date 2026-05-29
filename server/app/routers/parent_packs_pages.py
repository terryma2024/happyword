"""V0.8.1 — HTML vocabulary workspace under /family/{family_id}/packs."""

from __future__ import annotations

import json
from json import JSONDecodeError
from typing import TYPE_CHECKING, Any, Literal

from fastapi import APIRouter, File, Form, Path, Query, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.models.user import User, UserRole
from app.routers.parent_family_pack import _serialize_definition, _serialize_draft
from app.services import family_pack_import_service, pack_story_service
from app.services import family_pack_service as svc
from app.services.auth_service import JwtError, decode_typed_token
from app.services.llm_service import LlmCallError, LlmConfigError

if TYPE_CHECKING:
    from app.models.family_pack_definition import FamilyPackDefinition

router = APIRouter(prefix="/family", tags=["parent-packs-html"])

_MAX_IMPORT_IMAGE_BYTES = 8 * 1024 * 1024
_ACCEPTED_IMPORT_IMAGE_MIME = frozenset({"image/jpeg", "image/png", "image/webp"})
templates = Jinja2Templates(directory="app/templates")


async def _require_parent_html(request: Request) -> User | RedirectResponse:
    """Mirror `/family/{family_id}/` dashboard soft-auth (cookie missing → login redirect)."""
    cookie_token = request.cookies.get(get_settings().session_cookie_name)
    if not cookie_token:
        return RedirectResponse(url="/family/login", status_code=303)
    try:
        typed = decode_typed_token(cookie_token)
    except JwtError:
        return RedirectResponse(url="/family/login", status_code=303)
    if typed.role != "parent":
        return RedirectResponse(url="/family/login", status_code=303)
    user = await User.find_one(User.username == typed.identifier, User.role == UserRole.PARENT)
    if user is None:
        return RedirectResponse(url="/family/login", status_code=303)
    return user


async def _load_definition_or_redirect(pack_id: str, user: User) -> FamilyPackDefinition | None:
    try:
        return await svc.get_definition_for_family(
            pack_id=pack_id,
            family_id=user.family_id or "",
        )
    except svc.PackNotFound:
        return None


def _story_scene_update(
    current: dict[str, Any],
    *,
    story_en: str | None,
    story_zh: str | None,
) -> dict[str, Any]:
    scene = dict(current)
    for key, value in (("storyEn", story_en), ("storyZh", story_zh)):
        if value is None:
            continue
        clean = value.strip()
        if clean:
            scene[key] = clean
        else:
            scene.pop(key, None)
    return scene


def _draft_row_kind(row: dict[str, Any], *, prefix: str) -> str:
    """Return `hidden`, `custom`, or `global` for draft row editing UX."""
    if row.get("hidden") is True:
        return "hidden"
    wid = row.get("id")
    if isinstance(wid, str) and wid.startswith(prefix):
        return "custom"
    return "global"


async def _render_draft_edit(
    request: Request,
    *,
    user: User,
    definition: FamilyPackDefinition,
    word_id: str,
    row: dict[str, Any],
    kind: str,
    edit_error: str = "",
) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "parent/packs/draft_edit.html",
        {
            "user": user,
            "definition": _serialize_definition(definition),
            "word_id": word_id,
            "row": row,
            "kind": kind,
            "edit_error": edit_error,
        },
    )


async def _render_import_page(
    request: Request,
    *,
    user: User,
    definition: FamilyPackDefinition,
    import_error: str = "",
    import_detail: str = "",
    import_row_errors: list[dict[str, object]] | None = None,
) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "parent/packs/import.html",
        {
            "user": user,
            "definition": _serialize_definition(definition),
            "import_error": import_error,
            "import_detail": import_detail,
            "import_row_errors": import_row_errors or [],
        },
    )


async def _render_pack_detail(
    request: Request,
    *,
    user: User,
    definition: FamilyPackDefinition,
    title_error: str = "",
    title_ok: bool = False,
    publish_error: str = "",
    publish_row_errors: list[dict[str, object]] | None = None,
    batch_error: str = "",
    batch_row_errors: list[dict[str, object]] | None = None,
    add_word_error: str = "",
    split_ok: str = "",
    split_error: str = "",
) -> HTMLResponse:
    pointer, pack = await svc.current_pack(definition=definition)
    draft = await svc.get_or_create_draft(definition=definition, parent_user_id=user.username)
    return templates.TemplateResponse(
        request,
        "parent/packs/detail.html",
        {
            "user": user,
            "definition": _serialize_definition(definition),
            "pointer": pointer,
            "current_pack": pack,
            "draft": _serialize_draft(draft),
            "title_error": title_error,
            "title_ok": title_ok,
            "publish_error": publish_error,
            "publish_row_errors": publish_row_errors or [],
            "batch_error": batch_error,
            "batch_row_errors": batch_row_errors or [],
            "add_word_error": add_word_error,
            "split_ok": split_ok,
            "split_error": split_error,
            "import_ok": False,
            "import_hint": "",
        },
    )


@router.get("/{family_id}/packs/", response_class=HTMLResponse, response_model=None)
async def list_packs_page(
    request: Request, family_id: str = Path(min_length=1, max_length=128)
) -> HTMLResponse | RedirectResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definitions = await svc.list_definitions(
        family_id=user.family_id or "",
        include_archived=False,
    )
    summaries = await svc.summarize(definitions=definitions)
    return templates.TemplateResponse(
        request,
        "parent/packs/list.html",
        {
            "user": user,
            "summaries": summaries,
            "flash_ok": request.query_params.get("flash_ok"),
        },
    )


@router.get("/{family_id}/packs/new", response_class=HTMLResponse, response_model=None)
async def new_pack_page(
    request: Request, family_id: str = Path(min_length=1, max_length=128)
) -> HTMLResponse | RedirectResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    return templates.TemplateResponse(
        request,
        "parent/packs/new.html",
        {"user": user, "error": ""},
    )


@router.post("/{family_id}/packs/", response_model=None)
async def create_pack_page(
    request: Request,
    name: str = Form(...),
    description: str = Form(""),
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse | HTMLResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await svc.create_definition(
        family_id=user.family_id or "",
        name=name,
        description=description or None,
        parent_user_id=user.username,
    )
    return RedirectResponse(
        url=f"/family/{user.family_id or '_'}/packs/{definition.pack_id}", status_code=303
    )


@router.post("/{family_id}/packs/{pack_id}/metadata", response_model=None)
async def update_pack_metadata_page(
    request: Request,
    name: str = Form(...),
    storyEn: str | None = Form(None),  # noqa: N803 - HTML field keeps client scene key
    storyZh: str | None = Form(None),  # noqa: N803
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse | HTMLResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    try:
        updated = await svc.patch_definition(
            pack_id=pack_id,
            family_id=user.family_id or "",
            name=name,
            description=None,
            scene=_story_scene_update(definition.scene, story_en=storyEn, story_zh=storyZh),
        )
    except svc.NameTaken:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            title_error="name_taken",
        )
    except svc.InvalidPayload:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            title_error="invalid_name",
        )
    return RedirectResponse(
        url=f"/family/{user.family_id or '_'}/packs/{updated.pack_id}?title_ok=1",
        status_code=303,
    )


@router.post("/{family_id}/packs/{pack_id}/story/generate", response_model=None)
async def generate_pack_story_page(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse | HTMLResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    draft = await svc.get_or_create_draft(definition=definition, parent_user_id=user.username)
    try:
        _model, story = await pack_story_service.generate_pack_story(
            pack_name=definition.name,
            words=list(draft.words),
        )
    except (LlmConfigError, LlmCallError) as exc:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            title_error=str(exc),
        )
    updated_scene = _story_scene_update(
        definition.scene,
        story_en=story["storyEn"],
        story_zh=story["storyZh"],
    )
    await svc.patch_definition(
        pack_id=pack_id,
        family_id=user.family_id or "",
        name=None,
        description=None,
        scene=updated_scene,
    )
    return RedirectResponse(
        url=f"/family/{user.family_id or '_'}/packs/{pack_id}?title_ok=1",
        status_code=303,
    )


@router.post("/{family_id}/packs/{pack_id}/delete", response_model=None)
async def delete_pack_page(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is not None:
        await svc.delete_definition(
            pack_id=definition.pack_id,
            family_id=user.family_id or "",
        )
    return RedirectResponse(
        url=f"/family/{user.family_id or '_'}/packs/?flash_ok=deleted",
        status_code=303,
    )


@router.get("/{family_id}/packs/{pack_id}/import", response_class=HTMLResponse, response_model=None)
async def import_page(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    pack_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    return templates.TemplateResponse(
        request,
        "parent/packs/import.html",
        {
            "user": user,
            "definition": _serialize_definition(definition),
            "import_error": "",
            "import_detail": "",
            "import_row_errors": [],
        },
    )


@router.post("/{family_id}/packs/{pack_id}/import", response_model=None)
async def import_image_submit(
    request: Request,
    family_id: str = Path(min_length=1, max_length=128),
    pack_id: str = Path(min_length=1, max_length=128),
    image: UploadFile = File(...),
) -> RedirectResponse | HTMLResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)

    mime = (image.content_type or "").lower()
    if mime not in _ACCEPTED_IMPORT_IMAGE_MIME:
        return await _render_import_page(
            request,
            user=user,
            definition=definition,
            import_error="unsupported_type",
            import_detail=mime or "",
        )
    payload = await image.read()
    if not payload:
        return await _render_import_page(
            request,
            user=user,
            definition=definition,
            import_error="empty_file",
        )
    if len(payload) > _MAX_IMPORT_IMAGE_BYTES:
        return await _render_import_page(
            request,
            user=user,
            definition=definition,
            import_error="too_large",
            import_detail=str(len(payload)),
        )

    try:
        (
            _src,
            _model,
            imported_count,
            _draft,
            errors,
        ) = await family_pack_import_service.import_image_to_draft(
            definition=definition,
            payload=payload,
            mime=mime,
            parent_user_id=user.username,
        )
    except LlmConfigError as exc:
        return await _render_import_page(
            request,
            user=user,
            definition=definition,
            import_error="llm_config",
            import_detail=str(exc),
        )
    except LlmCallError as exc:
        return await _render_import_page(
            request,
            user=user,
            definition=definition,
            import_error="llm_call",
            import_detail=str(exc),
        )

    if imported_count == 0 and errors:
        return await _render_import_page(
            request,
            user=user,
            definition=definition,
            import_error="batch_errors",
            import_row_errors=[dict(e) for e in errors],
        )

    if imported_count == 0:
        return RedirectResponse(
            url=f"/family/{user.family_id or '_'}/packs/{pack_id}?import_hint=no_words",
            status_code=303,
        )

    return RedirectResponse(
        url=f"/family/{user.family_id or '_'}/packs/{pack_id}?import_ok=1",
        status_code=303,
    )


@router.post("/{family_id}/packs/{pack_id}/publish", response_model=None)
async def publish_page(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
    notes: str = Form(""),
) -> RedirectResponse | HTMLResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    try:
        definition = await svc.get_definition_for_family(
            pack_id=pack_id,
            family_id=user.family_id or "",
        )
    except svc.PackNotFound:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    try:
        await svc.publish(definition=definition, parent_user_id=user.username, notes=notes or None)
    except svc.EmptyPack:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            publish_error="empty_pack",
        )
    except svc.WordLimitExceeded:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            publish_error="word_limit",
        )
    except svc.DraftValidationFailed as exc:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            publish_error="validation",
            publish_row_errors=list(exc.errors),
        )
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303)


@router.post("/{family_id}/packs/{pack_id}/rollback", response_model=None)
async def rollback_pack_page(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    try:
        await svc.rollback(definition=definition)
    except svc.NoPreviousVersion:
        return RedirectResponse(
            url=f"/family/{user.family_id or '_'}/packs/{pack_id}/versions?rollback_err=no_prev",
            status_code=303,
        )
    return RedirectResponse(
        url=f"/family/{user.family_id or '_'}/packs/{pack_id}/versions", status_code=303
    )


@router.post("/{family_id}/packs/{pack_id}/draft/add-custom", response_model=None)
async def draft_add_custom_word(
    request: Request,
    suffix: str = Form(...),
    word: str = Form(...),
    meaning_zh: str = Form(...),
    category: str = Form(...),
    difficulty: int = Form(...),
    example_en: str = Form(""),
    example_zh: str = Form(""),
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    prefix = svc.CustomIdContract(family_id=user.family_id or "").prefix
    clean_suffix = suffix.strip()
    if len(clean_suffix) == 0:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            add_word_error="suffix_required",
        )
    word_id = f"{prefix}{clean_suffix}"
    payload_ac: dict[str, Any] = {
        "source": "custom",
        "word": word.strip(),
        "meaning_zh": meaning_zh.strip(),
        "category": category.strip(),
        "difficulty": int(difficulty),
    }
    if example_en.strip():
        payload_ac["example_en"] = example_en.strip()
    if example_zh.strip():
        payload_ac["example_zh"] = example_zh.strip()
    try:
        await svc.upsert_draft_word(
            definition=definition,
            word_id=word_id,
            payload=payload_ac,
            parent_user_id=user.username,
        )
    except svc.PackFull:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            add_word_error="pack_full",
        )
    except svc.InvalidPayload:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            add_word_error="invalid_payload",
        )
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303)


@router.post("/{family_id}/packs/{pack_id}/draft/delete-word", response_model=None)
async def draft_delete_word(
    request: Request,
    word_id: str = Form(...),
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    await svc.remove_draft_word(
        definition=definition,
        word_id=word_id,
        parent_user_id=user.username,
    )
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303)


@router.post("/{family_id}/packs/{pack_id}/draft/batch-delete", response_model=None)
async def draft_batch_delete_words(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    form = await request.form()
    seen: set[str] = set()
    word_ids: list[str] = []
    for raw in form.getlist("word_ids"):
        word_id = str(raw).strip()
        if word_id and word_id not in seen:
            seen.add(word_id)
            word_ids.append(word_id)
    for word_id in word_ids:
        await svc.remove_draft_word(
            definition=definition,
            word_id=word_id,
            parent_user_id=user.username,
        )
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303)


@router.post("/{family_id}/packs/{pack_id}/draft/split", response_model=None)
async def draft_split_words(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)

    form = await request.form()
    seen: set[str] = set()
    word_ids: list[str] = []
    for raw in form.getlist("word_ids"):
        word_id = str(raw).strip()
        if word_id and word_id not in seen:
            seen.add(word_id)
            word_ids.append(word_id)
    mode = str(form.get("mode", "copy")).strip()
    new_name = str(form.get("new_name", "")).strip()
    new_description_raw = str(form.get("new_description", "")).strip()
    new_description = new_description_raw or None
    split_mode: Literal["copy", "move"] = "move" if mode == "move" else "copy"

    try:
        result = await svc.split_draft_to_new_pack(
            source_definition=definition,
            word_ids=word_ids,
            new_name=new_name,
            new_description=new_description,
            mode=split_mode,
            parent_user_id=user.username,
        )
    except (svc.InvalidPayload, svc.DraftWordNotFound, svc.NameTaken, svc.WordLimitExceeded) as exc:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            split_error=getattr(exc, "code", "INVALID_PAYLOAD"),
        )

    split_url = (
        f"/family/{user.family_id or '_'}/packs/"
        f"{result.new_definition.pack_id}?split_ok={result.mode}"
    )
    return RedirectResponse(url=split_url, status_code=303)


@router.post("/{family_id}/packs/{pack_id}/draft/batch-json", response_model=None)
async def draft_batch_json(
    request: Request,
    batch_json: str = Form(...),
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    try:
        parsed = json.loads(batch_json)
    except JSONDecodeError:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            batch_error="invalid_json",
        )
    rows = parsed.get("rows") if isinstance(parsed, dict) else None
    if not isinstance(rows, list):
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            batch_error="rows_missing",
        )
    clean_rows: list[dict[str, object]] = []
    for item in rows:
        if isinstance(item, dict):
            clean_rows.append(dict(item))
    _draft, errors = await svc.batch_upsert_draft_words(
        definition=definition,
        rows=clean_rows,
        parent_user_id=user.username,
    )
    if errors:
        return await _render_pack_detail(
            request,
            user=user,
            definition=definition,
            batch_error="row_errors",
            batch_row_errors=list(errors),
        )
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303)


@router.get(
    "/{family_id}/packs/{pack_id}/draft/edit", response_class=HTMLResponse, response_model=None
)
async def draft_edit_page(
    request: Request,
    word_id: str = Query(..., min_length=1),
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    draft = await svc.get_or_create_draft(definition=definition, parent_user_id=user.username)
    row: dict[str, Any] | None = None
    for w in draft.words:
        if isinstance(w, dict) and str(w.get("id")) == word_id:
            row = dict(w)
            break
    if row is None:
        return RedirectResponse(
            url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303
        )
    prefix = svc.CustomIdContract(family_id=user.family_id or "").prefix
    kind = _draft_row_kind(row, prefix=prefix)
    return await _render_draft_edit(
        request,
        user=user,
        definition=definition,
        word_id=word_id,
        row=row,
        kind=kind,
    )


@router.post("/{family_id}/packs/{pack_id}/draft/edit", response_model=None)
async def draft_edit_submit(
    request: Request,
    word_id: str = Form(...),
    action: str = Form(""),
    word: str = Form(""),
    meaning_zh: str = Form(""),
    category: str = Form(""),
    difficulty: str = Form(""),
    example_en: str = Form(""),
    example_zh: str = Form(""),
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> RedirectResponse | HTMLResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    draft = await svc.get_or_create_draft(definition=definition, parent_user_id=user.username)
    row: dict[str, Any] | None = None
    for w in draft.words:
        if isinstance(w, dict) and str(w.get("id")) == word_id:
            row = dict(w)
            break
    if row is None:
        return RedirectResponse(
            url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303
        )
    prefix = svc.CustomIdContract(family_id=user.family_id or "").prefix
    kind = _draft_row_kind(row, prefix=prefix)

    if kind == "hidden":
        if action.strip() != "unhide":
            return await _render_draft_edit(
                request,
                user=user,
                definition=definition,
                word_id=word_id,
                row=row,
                kind=kind,
                edit_error="请使用「恢复为全局词条」按钮取消隐藏。",
            )
        payload_h: dict[str, Any] = {"source": "global"}
        try:
            await svc.upsert_draft_word(
                definition=definition,
                word_id=word_id,
                payload=payload_h,
                parent_user_id=user.username,
            )
        except svc.InvalidPayload as exc:
            return await _render_draft_edit(
                request,
                user=user,
                definition=definition,
                word_id=word_id,
                row=row,
                kind=kind,
                edit_error=str(exc),
            )
        return RedirectResponse(
            url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303
        )

    if kind == "custom":
        diff_raw = difficulty.strip()
        if not diff_raw.isdigit():
            return await _render_draft_edit(
                request,
                user=user,
                definition=definition,
                word_id=word_id,
                row=row,
                kind=kind,
                edit_error="难度须为 1–5 的整数。",
            )
        diff_i = int(diff_raw)
        if diff_i < 1 or diff_i > 5:
            return await _render_draft_edit(
                request,
                user=user,
                definition=definition,
                word_id=word_id,
                row=row,
                kind=kind,
                edit_error="难度须为 1–5 的整数。",
            )
        payload = {
            "source": "custom",
            "word": word.strip(),
            "meaning_zh": meaning_zh.strip(),
            "category": category.strip(),
            "difficulty": diff_i,
        }
        if example_en.strip():
            payload["example_en"] = example_en.strip()
        if example_zh.strip():
            payload["example_zh"] = example_zh.strip()
        try:
            await svc.upsert_draft_word(
                definition=definition,
                word_id=word_id,
                payload=payload,
                parent_user_id=user.username,
            )
        except svc.InvalidPayload as exc:
            return await _render_draft_edit(
                request,
                user=user,
                definition=definition,
                word_id=word_id,
                row=row,
                kind=kind,
                edit_error=str(exc),
            )
        return RedirectResponse(
            url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303
        )

    # global — optional field overrides
    payload = {"source": "global"}
    if word.strip():
        payload["word"] = word.strip()
    if meaning_zh.strip():
        payload["meaning_zh"] = meaning_zh.strip()
    if category.strip():
        payload["category"] = category.strip()
    diff_g = difficulty.strip()
    if diff_g.isdigit():
        dg = int(diff_g)
        if 1 <= dg <= 5:
            payload["difficulty"] = dg
    if example_en.strip():
        payload["example_en"] = example_en.strip()
    if example_zh.strip():
        payload["example_zh"] = example_zh.strip()
    try:
        await svc.upsert_draft_word(
            definition=definition,
            word_id=word_id,
            payload=payload,
            parent_user_id=user.username,
        )
    except svc.InvalidPayload as exc:
        return await _render_draft_edit(
            request,
            user=user,
            definition=definition,
            word_id=word_id,
            row=row,
            kind=kind,
            edit_error=str(exc),
        )
    return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs/{pack_id}", status_code=303)


@router.get(
    "/{family_id}/packs/{pack_id}/versions", response_class=HTMLResponse, response_model=None
)
async def versions_page(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    pointer, _snap_pack = await svc.current_pack(definition=definition)
    snapshots = await svc.list_versions(definition=definition)
    rollback_err = request.query_params.get("rollback_err", "")
    return templates.TemplateResponse(
        request,
        "parent/packs/versions.html",
        {
            "user": user,
            "definition": _serialize_definition(definition),
            "pointer": pointer,
            "snapshots": snapshots,
            "rollback_err": rollback_err,
        },
    )


@router.get("/{family_id}/packs/{pack_id}", response_class=HTMLResponse, response_model=None)
async def detail_page(
    request: Request,
    pack_id: str = Path(min_length=1, max_length=128),
    family_id: str = Path(min_length=1, max_length=128),
) -> HTMLResponse | RedirectResponse:
    _ = family_id
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url=f"/family/{user.family_id or '_'}/packs", status_code=303)
    pointer, pack = await svc.current_pack(definition=definition)
    draft = await svc.get_or_create_draft(definition=definition, parent_user_id=user.username)
    import_ok = request.query_params.get("import_ok") == "1"
    import_hint = request.query_params.get("import_hint", "")
    title_ok = request.query_params.get("title_ok") == "1"
    split_ok = request.query_params.get("split_ok", "")
    return templates.TemplateResponse(
        request,
        "parent/packs/detail.html",
        {
            "user": user,
            "definition": _serialize_definition(definition),
            "pointer": pointer,
            "current_pack": pack,
            "draft": _serialize_draft(draft),
            "title_error": "",
            "title_ok": title_ok,
            "publish_error": "",
            "publish_row_errors": [],
            "batch_error": "",
            "batch_row_errors": [],
            "add_word_error": "",
            "split_ok": split_ok,
            "split_error": "",
            "import_ok": import_ok,
            "import_hint": import_hint,
        },
    )
