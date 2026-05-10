"""V0.8.1 — HTML vocabulary workspace under /parent/packs."""

from __future__ import annotations

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.models.family_pack_definition import FamilyPackDefinition
from app.models.user import User, UserRole
from app.routers.parent_family_pack import _serialize_definition, _serialize_draft
from app.services import family_pack_service as svc
from app.services.auth_service import JwtError, decode_typed_token

router = APIRouter(prefix="/parent/packs", tags=["parent-packs-html"])
templates = Jinja2Templates(directory="app/templates")


async def _require_parent_html(request: Request) -> User | RedirectResponse:
    """Mirror `/parent/` dashboard soft-auth (cookie missing → login redirect)."""
    cookie_token = request.cookies.get(get_settings().session_cookie_name)
    if not cookie_token:
        return RedirectResponse(url="/parent/login", status_code=303)
    try:
        typed = decode_typed_token(cookie_token)
    except JwtError:
        return RedirectResponse(url="/parent/login", status_code=303)
    if typed.role != "parent":
        return RedirectResponse(url="/parent/login", status_code=303)
    user = await User.find_one(
        User.username == typed.identifier, User.role == UserRole.PARENT
    )
    if user is None:
        return RedirectResponse(url="/parent/login", status_code=303)
    return user


async def _load_definition_or_redirect(
    pack_id: str, user: User
) -> FamilyPackDefinition | None:
    try:
        return await svc.get_definition_for_family(
            pack_id=pack_id,
            family_id=user.family_id or "",
        )
    except svc.PackNotFound:
        return None


@router.get("", response_class=HTMLResponse, response_model=None)
async def list_packs_page(request: Request) -> HTMLResponse | RedirectResponse:
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
        {"user": user, "summaries": summaries},
    )


@router.get("/new", response_class=HTMLResponse, response_model=None)
async def new_pack_page(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    return templates.TemplateResponse(
        request,
        "parent/packs/new.html",
        {"user": user, "error": ""},
    )


@router.post("", response_model=None)
async def create_pack_page(
    request: Request,
    name: str = Form(...),
    description: str = Form(""),
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
    return RedirectResponse(url=f"/parent/packs/{definition.pack_id}", status_code=303)


@router.get("/{pack_id}/import", response_class=HTMLResponse, response_model=None)
async def import_page(
    request: Request,
    pack_id: str,
) -> HTMLResponse | RedirectResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url="/parent/packs", status_code=303)
    return templates.TemplateResponse(
        request,
        "parent/packs/import.html",
        {"user": user, "definition": _serialize_definition(definition)},
    )


@router.post("/{pack_id}/publish", response_model=None)
async def publish_page(
    request: Request,
    pack_id: str,
    notes: str = Form(""),
) -> RedirectResponse:
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
        return RedirectResponse(url="/parent/packs", status_code=303)
    try:
        await svc.publish(
            definition=definition, parent_user_id=user.username, notes=notes or None
        )
    except (svc.EmptyPack, svc.WordLimitExceeded):
        pass
    return RedirectResponse(url=f"/parent/packs/{pack_id}", status_code=303)


@router.get("/{pack_id}/versions", response_class=HTMLResponse, response_model=None)
async def versions_page(
    request: Request,
    pack_id: str,
) -> HTMLResponse | RedirectResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url="/parent/packs", status_code=303)
    snapshots = await svc.list_versions(definition=definition)
    return templates.TemplateResponse(
        request,
        "parent/packs/versions.html",
        {
            "user": user,
            "definition": _serialize_definition(definition),
            "snapshots": snapshots,
        },
    )


@router.get("/{pack_id}", response_class=HTMLResponse, response_model=None)
async def detail_page(
    request: Request,
    pack_id: str,
) -> HTMLResponse | RedirectResponse:
    gate = await _require_parent_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    user = gate
    definition = await _load_definition_or_redirect(pack_id, user)
    if definition is None:
        return RedirectResponse(url="/parent/packs", status_code=303)
    pointer, pack = await svc.current_pack(definition=definition)
    draft = await svc.get_or_create_draft(
        definition=definition, parent_user_id=user.username
    )
    return templates.TemplateResponse(
        request,
        "parent/packs/detail.html",
        {
            "user": user,
            "definition": _serialize_definition(definition),
            "pointer": pointer,
            "current_pack": pack,
            "draft": _serialize_draft(draft),
        },
    )
