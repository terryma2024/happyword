"""V0.8.2 — server-rendered system administrator console under `/admin/`."""

from __future__ import annotations

import re
from datetime import UTC, datetime
from typing import Any, Literal
from urllib.parse import quote

from fastapi import APIRouter, File, Form, Query, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates

from app.config import get_settings
from app.deps import clear_admin_session_cookie, set_admin_session_cookie
from app.models.device_binding import DeviceBinding
from app.models.family_pack_definition import FamilyPackDefinition
from app.models.feedback import UserFeedback
from app.models.user import User, UserRole
from app.services import admin_console_service as acs
from app.services import family_pack_service as fps
from app.services import feedback_service, pack_story_service, spellbook_cover_service
from app.services import global_pack_service as gps
from app.services.admin_audit_service import record_admin_action
from app.services.admin_console_overview_service import (
    build_admin_overview,
    format_audit_timestamp,
)
from app.services.auth_service import (
    JwtError,
    create_session_token,
    decode_typed_token,
    verify_password,
)
from app.services.image_generation_providers import (
    IMAGE_PROVIDER_SPECS,
    effective_image_provider_status,
    image_provider_options,
    is_effective_image_provider_configured,
    test_image_provider_connectivity,
)
from app.services.llm_providers import (
    LESSON_PROVIDER_SPECS,
    effective_lesson_provider_status,
    is_effective_lesson_provider_configured,
    lesson_provider_options,
    test_lesson_provider_connectivity,
)
from app.services.llm_service import LlmCallError, LlmConfigError
from app.services.system_config_service import (
    set_image_provider_override,
    set_llm_provider_override,
)

router = APIRouter(
    prefix="/admin",
    tags=["admin-web"],
    include_in_schema=False,
)

templates = Jinja2Templates(directory="app/templates")

PAGE_SIZE = 25


def _pagination(total: int, page: int, page_size: int) -> tuple[list[int], int, int]:
    total_pages = max(1, (total + page_size - 1) // page_size)
    page_clamped = min(max(1, page), total_pages)
    nums = list(range(1, total_pages + 1))
    return nums, total_pages, page_clamped


async def _require_admin_html(request: Request) -> User | RedirectResponse:
    settings = get_settings()
    cookie_token = request.cookies.get(settings.admin_session_cookie_name)
    if not cookie_token:
        return RedirectResponse(url="/admin/login", status_code=303)
    try:
        typed = decode_typed_token(cookie_token)
    except JwtError:
        return RedirectResponse(url="/admin/login", status_code=303)
    if typed.role != "admin":
        return RedirectResponse(url="/admin/login", status_code=303)
    user = await User.find_one(
        User.username == typed.identifier,
        User.role == UserRole.ADMIN,
    )
    if user is None or user.password_hash is None:
        return RedirectResponse(url="/admin/login", status_code=303)
    return user


def _redirect_if_authenticated(request: Request) -> RedirectResponse | None:
    settings = get_settings()
    cookie_token = request.cookies.get(settings.admin_session_cookie_name)
    if not cookie_token:
        return None
    try:
        typed = decode_typed_token(cookie_token)
    except JwtError:
        return None
    if typed.role != "admin":
        return None
    return RedirectResponse(url="/admin/", status_code=303)


def _flash_map_parents(request: Request) -> str | None:
    err = request.query_params.get("flash_err")
    if err == "not_found":
        return "未找到该家长用户。"
    return err


def _flash_map_devices(request: Request) -> tuple[str | None, str | None]:
    ok = request.query_params.get("flash_ok")
    msgs = {"revoked": "已撤销设备绑定。", "restored": "已恢复设备绑定。"}
    err = request.query_params.get("flash_err")
    return (msgs.get(ok) if ok else None, err)


def _flash_map_family(request: Request) -> tuple[str | None, str | None]:
    ok = request.query_params.get("flash_ok")
    msgs = {
        "unarchived": "已恢复词包为活跃状态。",
        "rolled_back": "已回滚家庭词包指针。",
        "deleted": "已删除家庭词包。",
        "copied_global": "已复制家庭词包为新的全局词包草稿。",
        "copied_family": "已复制家庭词包给目标家庭。",
        "story_saved": "已保存词包 story。",
        "story_generated": "已生成新的词包 story。",
        "cover_generated": "已生成魔法书封面。",
    }
    err = request.query_params.get("flash_err")
    return (msgs.get(ok) if ok else None, err)


def _flash_map_global(request: Request) -> tuple[str | None, str | None]:
    ok = request.query_params.get("flash_ok")
    imported = request.query_params.get("imported_count")
    msgs = {
        "published": "已发布新的平台词条快照（WordPack）。",
        "rolled_back": "已回滚平台词条快照指针。",
        "definition_created": "已创建新的全局词包定义（gpk）。",
        "gpk_published": "已将该词包的草稿发布为新版本。",
        "gpk_rolled_back": "已回滚该词包的发布指针。",
        "gpk_deleted": "已删除全局词包。",
        "draft_saved": "已保存草稿词条。",
        "draft_deleted": "已删除草稿词条。",
        "gpk_split_copy": "已复制所选草稿词条到新的全局词包。",
        "gpk_split_move": "已移动所选草稿词条到新的全局词包。",
        "story_saved": "已保存词包 story。",
        "story_generated": "已生成新的词包 story。",
    }
    err = request.query_params.get("flash_err")
    if ok == "image_imported" and imported is not None:
        return (f"图片已解析并写入草稿（成功导入 {imported} 条）。", err)
    return (msgs.get(ok) if ok else None, err)


def _flash_map_feedback(request: Request) -> tuple[str | None, str | None]:
    ok = request.query_params.get("flash_ok")
    msgs = {
        "replied": "已回复用户反馈。",
        "deleted": "已删除用户反馈。",
    }
    err = request.query_params.get("flash_err")
    err_msgs = {
        "not_found": "未找到该反馈。",
        "invalid_reply": "回复内容不能为空，且不能超过 4000 字。",
    }
    return (msgs.get(ok) if ok else None, err_msgs.get(err, err) if err else None)


def _global_pack_detail_url(
    pack_id: str,
    *,
    flash_ok: str | None = None,
    flash_err: str | None = None,
    imported_count: int | str | None = None,
) -> str:
    base = f"/admin/global-packs/packs/{pack_id}"
    qs: list[str] = []
    if flash_ok:
        qs.append(f"flash_ok={flash_ok}")
    if imported_count is not None:
        qs.append(f"imported_count={imported_count}")
    if flash_err:
        qs.append(f"flash_err={quote(flash_err)}")
    return f"{base}?{'&'.join(qs)}" if qs else base


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


async def _load_admin_family_pack_definition(pack_id: str) -> FamilyPackDefinition | None:
    return await FamilyPackDefinition.find_one(
        {
            "pack_id": pack_id,
            "family_id": {"$ne": fps.GLOBAL_PACK_FAMILY_ID},
        }
    )


async def _vision_import_configured() -> bool:
    return await is_effective_lesson_provider_configured()


async def _cover_generation_configured() -> bool:
    return await is_effective_image_provider_configured()


def _flash_err_for_vision_import(exc: BaseException) -> str:
    if isinstance(exc, LlmConfigError):
        return "LLM Provider 未配置或不可用。请到系统配置页面检查当前模型和密钥。"
    return str(exc)


def _flash_map_system_config(request: Request) -> tuple[str | None, str | None]:
    ok = request.query_params.get("flash_ok")
    err = request.query_params.get("flash_err")
    detail = request.query_params.get("detail")
    tested = request.query_params.get("tested_llm_provider")
    ok_msgs = {
        "llm_provider_updated": "已更新课程解析模型。",
        "llm_provider_connected": "连通性测试通过。",
        "image_provider_updated": "已更新魔法书封面生成模型。",
        "image_provider_connected": "封面生成模型配置检查通过。",
    }
    err_msgs = {
        "invalid_llm_provider": "请选择一个支持的课程解析模型。",
        "llm_provider_connectivity_failed": "连通性测试失败，模型未生效。",
        "invalid_image_provider": "请选择一个支持的封面生成模型。",
        "image_provider_connectivity_failed": "封面生成模型配置检查失败，模型未生效。",
    }
    ok_msg = ok_msgs.get(ok) if ok else None
    if ok == "llm_provider_connected" and tested in LESSON_PROVIDER_SPECS:
        ok_msg = f"{LESSON_PROVIDER_SPECS[tested].display_name} 连通性测试通过。"
    if ok == "image_provider_connected" and tested in IMAGE_PROVIDER_SPECS:
        ok_msg = f"{IMAGE_PROVIDER_SPECS[tested].display_name} 配置检查通过。"
    err_msg = err_msgs.get(err, err) if err else None
    if err == "llm_provider_connectivity_failed" and detail:
        err_msg = f"{err_msg}（{detail}）"
    if err == "image_provider_connectivity_failed" and detail:
        err_msg = f"{err_msg}（{detail}）"
    return (ok_msg, err_msg)


def _existing_global_draft_word_ids(words: list[dict[str, Any]]) -> set[str]:
    return {str(w["id"]) for w in words if isinstance(w.get("id"), str) and w["id"]}


def _allocate_global_word_id(english: str, existing: set[str]) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", english.strip().lower()).strip("-") or "word"
    if base not in existing:
        return base
    n = 2
    while f"{base}-{n}" in existing:
        n += 1
    return f"{base}-{n}"


def _build_global_draft_entry_from_form(
    *,
    word_id: str,
    word: str,
    meaning_zh: str,
    category: str,
    difficulty: int,
    example_en: str,
    example_zh: str,
    distractors_csv: str,
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "id": word_id.strip(),
        "source": "custom",
        "word": word.strip(),
        "meaningZh": meaning_zh.strip(),
        "category": category.strip(),
        "difficulty": difficulty,
    }
    ex_en = example_en.strip()
    ex_zh = example_zh.strip()
    if ex_en:
        entry["exampleEn"] = ex_en
    if ex_zh:
        entry["exampleZh"] = ex_zh
    parts = [x.strip() for x in distractors_csv.split(",") if x.strip()]
    if parts:
        entry["distractors"] = parts
    return entry


def _find_draft_word(words: list[dict[str, Any]], word_id: str) -> dict[str, Any] | None:
    for w in words:
        if str(w.get("id")) == word_id:
            return w
    return None


# --- login / logout / dashboard ------------------------------------------------


@router.get("/login", response_class=HTMLResponse, response_model=None)
async def admin_login_page(request: Request) -> HTMLResponse | RedirectResponse:
    early = _redirect_if_authenticated(request)
    if early is not None:
        return early
    return templates.TemplateResponse(request, "admin/login.html", {"error": None})


@router.post("/login", response_class=HTMLResponse, response_model=None)
async def admin_login_post(
    request: Request,
    username: str = Form(...),
    password: str = Form(...),
) -> HTMLResponse | RedirectResponse:
    early = _redirect_if_authenticated(request)
    if early is not None:
        return early

    user = await User.find_one(User.username == username.strip())
    if (
        user is None
        or user.role != UserRole.ADMIN
        or user.password_hash is None
        or not verify_password(password, user.password_hash)
    ):
        return templates.TemplateResponse(
            request,
            "admin/login.html",
            {"error": "用户名或密码错误。"},
            status_code=401,
        )

    settings = get_settings()
    expires_in = settings.admin_session_expire_hours * 3600
    token = create_session_token(
        role="admin",
        identifier=user.username,
        expires_in=expires_in,
    )
    user.last_login_at = datetime.now(tz=UTC)
    await user.save()
    redirect = RedirectResponse(url="/admin/", status_code=303)
    set_admin_session_cookie(redirect, token)
    return redirect


@router.post("/logout", response_model=None)
async def admin_logout() -> RedirectResponse:
    out = RedirectResponse(url="/admin/login", status_code=303)
    clear_admin_session_cookie(out)
    return out


@router.get("/", response_class=HTMLResponse, response_model=None)
async def admin_dashboard(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    overview = await build_admin_overview()
    return templates.TemplateResponse(
        request,
        "admin/dashboard.html",
        {
            "admin_user": gate,
            "overview": overview,
            "audit_ts": format_audit_timestamp,
        },
    )


# --- system config -------------------------------------------------------------


@router.get("/system-config", response_class=HTMLResponse, response_model=None)
async def admin_system_config_page(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    flash_ok, flash_err = _flash_map_system_config(request)
    return templates.TemplateResponse(
        request,
        "admin/system_config.html",
        {
            "admin_user": gate,
            "flash_ok": flash_ok,
            "flash_err": flash_err,
            "provider_options": lesson_provider_options(),
            "current_provider": await effective_lesson_provider_status(),
            "image_provider_options": image_provider_options(),
            "current_image_provider": await effective_image_provider_status(),
        },
    )


@router.post("/system-config/llm-provider", response_model=None)
async def admin_system_config_llm_provider_post(
    request: Request,
    llm_provider: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    provider_id = llm_provider.strip()
    if provider_id not in LESSON_PROVIDER_SPECS:
        return RedirectResponse(
            url="/admin/system-config?flash_err=invalid_llm_provider",
            status_code=303,
        )
    try:
        await test_lesson_provider_connectivity(provider_id=provider_id)
    except (LlmConfigError, LlmCallError) as exc:
        return RedirectResponse(
            url=(
                "/admin/system-config?flash_err=llm_provider_connectivity_failed"
                f"&detail={quote(str(exc))}"
            ),
            status_code=303,
        )
    await set_llm_provider_override(provider_id=provider_id, updated_by=gate.username)
    await record_admin_action(
        admin_username=gate.username,
        action="system_config.update_llm_provider",
        target_collection="system_config",
        target_id="llm_provider",
        payload_summary={"llm_provider": provider_id},
    )
    return RedirectResponse(
        url="/admin/system-config?flash_ok=llm_provider_updated",
        status_code=303,
    )


@router.post("/system-config/llm-provider/test", response_model=None)
async def admin_system_config_llm_provider_test_post(
    request: Request,
    llm_provider: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    provider_id = llm_provider.strip()
    if provider_id not in LESSON_PROVIDER_SPECS:
        return RedirectResponse(
            url="/admin/system-config?flash_err=invalid_llm_provider",
            status_code=303,
        )
    try:
        await test_lesson_provider_connectivity(provider_id=provider_id)
    except (LlmConfigError, LlmCallError) as exc:
        return RedirectResponse(
            url=(
                "/admin/system-config?flash_err=llm_provider_connectivity_failed"
                f"&detail={quote(str(exc))}"
            ),
            status_code=303,
        )
    return RedirectResponse(
        url=(
            "/admin/system-config?flash_ok=llm_provider_connected"
            f"&tested_llm_provider={quote(provider_id)}"
        ),
        status_code=303,
    )


@router.post("/system-config/image-provider", response_model=None)
async def admin_system_config_image_provider_post(
    request: Request,
    image_provider: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    provider_id = image_provider.strip()
    if provider_id not in IMAGE_PROVIDER_SPECS:
        return RedirectResponse(
            url="/admin/system-config?flash_err=invalid_image_provider",
            status_code=303,
        )
    try:
        await test_image_provider_connectivity(provider_id=provider_id)
    except (LlmConfigError, LlmCallError) as exc:
        return RedirectResponse(
            url=(
                "/admin/system-config?flash_err=image_provider_connectivity_failed"
                f"&detail={quote(str(exc))}"
            ),
            status_code=303,
        )
    await set_image_provider_override(provider_id=provider_id, updated_by=gate.username)
    await record_admin_action(
        admin_username=gate.username,
        action="system_config.update_image_provider",
        target_collection="system_config",
        target_id="image_provider",
        payload_summary={"image_provider": provider_id},
    )
    return RedirectResponse(
        url="/admin/system-config?flash_ok=image_provider_updated",
        status_code=303,
    )


@router.post("/system-config/image-provider/test", response_model=None)
async def admin_system_config_image_provider_test_post(
    request: Request,
    image_provider: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    provider_id = image_provider.strip()
    if provider_id not in IMAGE_PROVIDER_SPECS:
        return RedirectResponse(
            url="/admin/system-config?flash_err=invalid_image_provider",
            status_code=303,
        )
    try:
        await test_image_provider_connectivity(provider_id=provider_id)
    except (LlmConfigError, LlmCallError) as exc:
        return RedirectResponse(
            url=(
                "/admin/system-config?flash_err=image_provider_connectivity_failed"
                f"&detail={quote(str(exc))}"
            ),
            status_code=303,
        )
    return RedirectResponse(
        url=(
            "/admin/system-config?flash_ok=image_provider_connected"
            f"&tested_image_provider={quote(provider_id)}"
        ),
        status_code=303,
    )


# --- feedback ------------------------------------------------------------------


@router.get("/feedback", response_class=HTMLResponse, response_model=None)
async def admin_feedback_list(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    flash_ok, flash_err = _flash_map_feedback(request)
    rows = await feedback_service.list_feedback_for_admin()
    return templates.TemplateResponse(
        request,
        "admin/feedback.html",
        {
            "admin_user": gate,
            "feedback_items": rows,
            "flash_ok": flash_ok,
            "flash_err": flash_err,
        },
    )


@router.post("/feedback/{feedback_id}/reply", response_model=None)
async def admin_feedback_reply(
    request: Request,
    feedback_id: str,
    reply: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        row = await feedback_service.reply_to_feedback(
            feedback_id=feedback_id,
            admin_username=gate.username,
            reply=reply,
        )
    except ValueError:
        return RedirectResponse(
            url="/admin/feedback?flash_err=invalid_reply",
            status_code=303,
        )
    if row is None:
        return RedirectResponse(url="/admin/feedback?flash_err=not_found", status_code=303)
    await record_admin_action(
        admin_username=gate.username,
        action="user_feedback.reply",
        target_collection="user_feedback",
        target_id=feedback_id,
        payload_summary={"parent_user_id": row.parent_user_id},
    )
    return RedirectResponse(url="/admin/feedback?flash_ok=replied", status_code=303)


@router.post("/feedback/{feedback_id}/delete", response_model=None)
async def admin_feedback_delete(request: Request, feedback_id: str) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    row = await UserFeedback.find_one(UserFeedback.feedback_id == feedback_id)
    if row is None:
        return RedirectResponse(url="/admin/feedback?flash_err=not_found", status_code=303)
    await row.delete()
    await record_admin_action(
        admin_username=gate.username,
        action="user_feedback.delete",
        target_collection="user_feedback",
        target_id=feedback_id,
        payload_summary={"parent_user_id": row.parent_user_id},
    )
    return RedirectResponse(url="/admin/feedback?flash_ok=deleted", status_code=303)


# --- parents -------------------------------------------------------------------


@router.get("/parents", response_class=HTMLResponse, response_model=None)
async def admin_parents_list(
    request: Request,
    q: str | None = Query(None),
    page: int = Query(1, ge=1),
) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    flash_err = _flash_map_parents(request)
    parents, total = await acs.search_parent_users(q=q, page=page, page_size=PAGE_SIZE)
    page_nums, total_pages, page_use = _pagination(total, page, PAGE_SIZE)
    if page_use != page:
        parents, total = await acs.search_parent_users(q=q, page=page_use, page_size=PAGE_SIZE)
    return templates.TemplateResponse(
        request,
        "admin/parents_list.html",
        {
            "admin_user": gate,
            "parents": parents,
            "q": q or "",
            "page": page_use,
            "total_pages": total_pages,
            "page_nums": page_nums,
            "flash_err": flash_err,
        },
    )


@router.get("/parents/{username}", response_class=HTMLResponse, response_model=None)
async def admin_parent_detail(request: Request, username: str) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    flash_ok = request.query_params.get("flash_ok")
    ok_map = {"suspended": "已暂停该家长登录。", "restored": "已恢复该家长登录。"}
    user_o, family, bindings, _profiles, packs = await acs.load_parent_detail(username=username)
    if user_o is None:
        return RedirectResponse(url="/admin/parents?flash_err=not_found", status_code=303)
    return templates.TemplateResponse(
        request,
        "admin/parent_detail.html",
        {
            "admin_user": gate,
            "user": user_o,
            "family": family,
            "bindings": bindings,
            "packs": packs,
            "flash_ok": ok_map.get(flash_ok) if flash_ok else None,
            "flash_err": request.query_params.get("flash_err"),
        },
    )


@router.post("/parents/{username}/suspend", response_model=None)
async def admin_parent_suspend(
    request: Request, username: str, reason: str = Form(...)
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_suspend_parent(
            admin_username=gate.username,
            parent_username=username,
            reason=reason,
        )
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/parents/{username}?flash_err={quote(str(e))}",
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(url="/admin/parents?flash_err=not_found", status_code=303)
    return RedirectResponse(
        url=f"/admin/parents/{username}?flash_ok=suspended", status_code=303
    )


@router.post("/parents/{username}/restore", response_model=None)
async def admin_parent_restore(
    request: Request, username: str, reason: str = Form(...)
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_restore_parent(
            admin_username=gate.username,
            parent_username=username,
            reason=reason,
        )
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/parents/{username}?flash_err={quote(str(e))}",
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(url="/admin/parents?flash_err=not_found", status_code=303)
    return RedirectResponse(
        url=f"/admin/parents/{username}?flash_ok=restored", status_code=303
    )


# --- devices -------------------------------------------------------------------


@router.get("/devices", response_class=HTMLResponse, response_model=None)
async def admin_devices_list(
    request: Request,
    q: str | None = Query(None),
    page: int = Query(1, ge=1),
) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    flash_ok, flash_err = _flash_map_devices(request)
    bindings, total = await acs.search_device_bindings(
        q=q, page=page, page_size=PAGE_SIZE
    )
    page_nums, total_pages, page_use = _pagination(total, page, PAGE_SIZE)
    if page_use != page:
        bindings, total = await acs.search_device_bindings(
            q=q, page=page_use, page_size=PAGE_SIZE
        )
    return templates.TemplateResponse(
        request,
        "admin/devices_list.html",
        {
            "admin_user": gate,
            "bindings": bindings,
            "q": q or "",
            "page": page_use,
            "total_pages": total_pages,
            "page_nums": page_nums,
            "flash_ok": flash_ok,
            "flash_err": flash_err,
        },
    )


@router.get("/devices/{binding_id}/revoke", response_class=HTMLResponse, response_model=None)
async def admin_device_revoke_form(
    request: Request, binding_id: str
) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    binding = await DeviceBinding.find_one(DeviceBinding.binding_id == binding_id)
    if binding is None:
        return RedirectResponse(url="/admin/devices?flash_err=not_found", status_code=303)
    return templates.TemplateResponse(
        request,
        "admin/device_revoke.html",
        {"admin_user": gate, "binding": binding, "error": None},
    )


@router.post("/devices/{binding_id}/revoke", response_model=None)
async def admin_device_revoke_post(
    request: Request,
    binding_id: str,
    reason: str = Form(...),
) -> RedirectResponse | HTMLResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    binding = await DeviceBinding.find_one(DeviceBinding.binding_id == binding_id)
    if binding is None:
        return RedirectResponse(url="/admin/devices?flash_err=not_found", status_code=303)
    try:
        await acs.admin_revoke_device_binding(
            admin_username=gate.username,
            binding_id=binding_id,
            reason=reason,
        )
    except ValueError as e:
        return templates.TemplateResponse(
            request,
            "admin/device_revoke.html",
            {"admin_user": gate, "binding": binding, "error": str(e)},
            status_code=400,
        )
    return RedirectResponse(url="/admin/devices?flash_ok=revoked", status_code=303)


@router.get("/devices/{binding_id}/restore", response_class=HTMLResponse, response_model=None)
async def admin_device_restore_form(
    request: Request, binding_id: str
) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    binding = await DeviceBinding.find_one(DeviceBinding.binding_id == binding_id)
    if binding is None:
        return RedirectResponse(url="/admin/devices?flash_err=not_found", status_code=303)
    return templates.TemplateResponse(
        request,
        "admin/device_restore.html",
        {"admin_user": gate, "binding": binding, "error": None},
    )


@router.post("/devices/{binding_id}/restore", response_model=None)
async def admin_device_restore_post(
    request: Request,
    binding_id: str,
    reason: str = Form(...),
) -> RedirectResponse | HTMLResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    binding = await DeviceBinding.find_one(DeviceBinding.binding_id == binding_id)
    if binding is None:
        return RedirectResponse(url="/admin/devices?flash_err=not_found", status_code=303)
    try:
        await acs.admin_restore_device_binding(
            admin_username=gate.username,
            binding_id=binding_id,
            reason=reason,
        )
    except ValueError as e:
        return templates.TemplateResponse(
            request,
            "admin/device_restore.html",
            {"admin_user": gate, "binding": binding, "error": str(e)},
            status_code=400,
        )
    return RedirectResponse(url="/admin/devices?flash_ok=restored", status_code=303)


# --- global packs ------------------------------------------------------------


@router.get("/global-packs", response_class=HTMLResponse, response_model=None)
async def admin_global_packs_page(request: Request) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    flash_ok, flash_err = _flash_map_global(request)
    ctx = await acs.load_global_pack_console_context()
    pointer = ctx["pointer"]
    current = ctx["current_pack"]
    pack_rows = await acs.list_global_pack_definitions_with_summary(include_archived=True)
    return templates.TemplateResponse(
        request,
        "admin/global_packs.html",
        {
            "admin_user": gate,
            "pointer": pointer,
            "current_pack": current,
            "current_word_count": ctx["current_word_count"],
            "pack_rows": pack_rows,
            "flash_ok": flash_ok,
            "flash_err": flash_err,
        },
    )


_MAX_GLOBAL_IMPORT_IMAGE_BYTES = 8 * 1024 * 1024
_ACCEPTED_GLOBAL_IMPORT_MIME = frozenset({"image/jpeg", "image/png", "image/webp"})


@router.post("/global-packs/create", response_model=None)
async def admin_global_pack_create_post(
    request: Request,
    name: str = Form(...),
    description: str = Form(""),
    pack_id: str = Form(""),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        d = await acs.admin_create_global_pack_definition(
            admin_username=gate.username,
            name=name,
            description=description,
            pack_id=pack_id or None,
        )
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    return RedirectResponse(
        url=_global_pack_detail_url(
            d.pack_id,
            flash_ok="definition_created",
        ),
        status_code=303,
    )


@router.post("/global-packs/import-image", response_model=None)
async def admin_global_pack_import_image_post(
    request: Request,
    pack_id: str = Form(...),
    image: UploadFile = File(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    mime = (image.content_type or "").lower()
    if mime not in _ACCEPTED_GLOBAL_IMPORT_MIME:
        err = "不支持的图片类型，请上传 JPEG、PNG 或 WebP。"
        return RedirectResponse(
            url=_global_pack_detail_url(
                pid,
                flash_err=err,
            )
            if pid
            else f"/admin/global-packs?flash_err={quote(err)}",
            status_code=303,
        )
    payload = await image.read()
    if not payload:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err="上传的文件为空。")
            if pid
            else f"/admin/global-packs?flash_err={quote('上传的文件为空。')}",
            status_code=303,
        )
    if len(payload) > _MAX_GLOBAL_IMPORT_IMAGE_BYTES:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err="图片过大，请压缩后重试。")
            if pid
            else f"/admin/global-packs?flash_err={quote('图片过大，请压缩后重试。')}",
            status_code=303,
        )
    try:
        source_url, model_name, imported, _draft, errs = await gps.import_image_to_draft(
            pack_id=pid,
            admin_id=gate.username,
            payload=payload,
            mime=mime,
        )
    except gps.PackNotFound:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包编号。')}",
            status_code=303,
        )
    except LlmConfigError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=_flash_err_for_vision_import(exc)),
            status_code=303,
        )
    except LlmCallError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=_flash_err_for_vision_import(exc)),
            status_code=303,
        )

    await record_admin_action(
        admin_username=gate.username,
        action="global_pack.import_image",
        target_collection="family_pack_definitions",
        target_id=pid,
        payload_summary={
            "imported_count": imported,
            "error_count": len(errs),
            "model": model_name,
            "source_image_url": source_url,
            "via": "admin_html",
        },
    )
    return RedirectResponse(
        url=_global_pack_detail_url(
            pid,
            flash_ok="image_imported",
            imported_count=imported,
            flash_err=(
                f"部分行未写入（{len(errs)} 条），请在此页继续编辑或重试。" if errs else None
            ),
        ),
        status_code=303,
    )


@router.post("/global-packs/publish", response_model=None)
async def admin_global_publish_post(
    request: Request,
    notes: str = Form(""),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_publish_global_pack(
            admin_username=gate.username,
            notes=notes,
        )
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    return RedirectResponse(url="/admin/global-packs?flash_ok=published", status_code=303)


@router.post("/global-packs/rollback", response_model=None)
async def admin_global_rollback_post(request: Request, reason: str = Form(...)) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_rollback_global_pack(admin_username=gate.username, reason=reason)
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    return RedirectResponse(url="/admin/global-packs?flash_ok=rolled_back", status_code=303)


@router.get("/global-packs/packs/{pack_id}", response_class=HTMLResponse, response_model=None)
async def admin_global_pack_detail_page(
    request: Request,
    pack_id: str,
) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        detail = await acs.load_global_pack_definition_console(pack_id=pack_id)
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    flash_ok, flash_err = _flash_map_global(request)
    vision_ready = await _vision_import_configured()
    cover_ready = await _cover_generation_configured()
    draft_words = sorted(
        detail["draft_words"], key=lambda w: str(w.get("id", ""))
    )
    return templates.TemplateResponse(
        request,
        "admin/global_pack_detail.html",
        {
            "admin_user": gate,
            "pack_id": pack_id,
            "definition": detail["definition"],
            "draft_words": draft_words,
            "draft_word_count": detail["draft_word_count"],
            "pointer": detail["pointer"],
            "published_word_count": detail["published_word_count"],
            "published_version": detail["published_version"],
            "flash_ok": flash_ok,
            "flash_err": flash_err,
            "vision_import_ready": vision_ready,
            "cover_generation_ready": cover_ready,
        },
    )


@router.post("/global-packs/packs/{pack_id}/import-image", response_model=None)
async def admin_global_pack_detail_import_image_post(
    request: Request,
    pack_id: str,
    image: UploadFile = File(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    mime = (image.content_type or "").lower()
    if mime not in _ACCEPTED_GLOBAL_IMPORT_MIME:
        return RedirectResponse(
            url=_global_pack_detail_url(
                pid,
                flash_err="不支持的图片类型，请上传 JPEG、PNG 或 WebP。",
            ),
            status_code=303,
        )
    payload = await image.read()
    if not payload:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err="上传的文件为空。"),
            status_code=303,
        )
    if len(payload) > _MAX_GLOBAL_IMPORT_IMAGE_BYTES:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err="图片过大，请压缩后重试。"),
            status_code=303,
        )
    try:
        source_url, model_name, imported, _draft, errs = await gps.import_image_to_draft(
            pack_id=pid,
            admin_id=gate.username,
            payload=payload,
            mime=mime,
        )
    except gps.PackNotFound:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包编号。')}",
            status_code=303,
        )
    except LlmConfigError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=_flash_err_for_vision_import(exc)),
            status_code=303,
        )
    except LlmCallError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=_flash_err_for_vision_import(exc)),
            status_code=303,
        )

    await record_admin_action(
        admin_username=gate.username,
        action="global_pack.import_image",
        target_collection="family_pack_definitions",
        target_id=pid,
        payload_summary={
            "imported_count": imported,
            "error_count": len(errs),
            "model": model_name,
            "source_image_url": source_url,
            "via": "admin_html_detail",
        },
    )
    return RedirectResponse(
        url=_global_pack_detail_url(
            pid,
            flash_ok="image_imported",
            imported_count=imported,
            flash_err=(
                f"部分行未写入（{len(errs)} 条），请在此页继续编辑或重试。" if errs else None
            ),
        ),
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/metadata", response_model=None)
async def admin_global_pack_metadata_post(
    request: Request,
    pack_id: str,
    name: str = Form(...),
    description: str = Form(""),
    storyEn: str | None = Form(None),  # noqa: N803 - HTML field keeps scene key
    storyZh: str | None = Form(None),  # noqa: N803
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    try:
        current = await gps.get_definition(pack_id=pid)
        await gps.patch_definition(
            pack_id=pid,
            admin_id=gate.username,
            name=name,
            description=description,
            scene=_story_scene_update(current.scene, story_en=storyEn, story_zh=storyZh),
        )
    except (gps.PackNotFound, gps.NameTaken, gps.InvalidPayload) as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(exc)),
            status_code=303,
        )
    await record_admin_action(
        admin_username=gate.username,
        action="global_pack.metadata_update",
        target_collection="family_pack_definitions",
        target_id=pid,
        payload_summary={"via": "admin_html"},
    )
    return RedirectResponse(
        url=_global_pack_detail_url(pid, flash_ok="story_saved"),
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/story/generate", response_model=None)
async def admin_global_pack_story_generate_post(
    request: Request,
    pack_id: str,
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    try:
        detail = await acs.load_global_pack_definition_console(pack_id=pid)
        definition = detail["definition"]
        _model, story = await pack_story_service.generate_pack_story(
            pack_name=definition.name,
            words=list(detail["draft_words"]),
        )
        await gps.patch_definition(
            pack_id=pid,
            admin_id=gate.username,
            name=None,
            description=None,
            scene=_story_scene_update(
                definition.scene,
                story_en=story["storyEn"],
                story_zh=story["storyZh"],
            ),
        )
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    except (gps.PackNotFound, LlmConfigError, LlmCallError) as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(exc)),
            status_code=303,
        )
    await record_admin_action(
        admin_username=gate.username,
        action="global_pack.story_generate",
        target_collection="family_pack_definitions",
        target_id=pid,
        payload_summary={"via": "admin_html"},
    )
    return RedirectResponse(
        url=_global_pack_detail_url(pid, flash_ok="story_generated"),
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/cover/generate", response_model=None)
async def admin_global_pack_cover_generate_post(
    request: Request,
    pack_id: str,
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    try:
        detail = await acs.load_global_pack_definition_console(pack_id=pid)
        definition = detail["definition"]
        _model, cover_url, _updated = (
            await spellbook_cover_service.generate_and_attach_spellbook_cover(
                definition=definition,
                words=list(detail["draft_words"]),
            )
        )
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    except (gps.PackNotFound, LlmConfigError, LlmCallError) as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(exc)),
            status_code=303,
        )
    await record_admin_action(
        admin_username=gate.username,
        action="global_pack.spellbook_cover_generate",
        target_collection="family_pack_definitions",
        target_id=pid,
        payload_summary={"via": "admin_html", "spellbook_cover_url": cover_url},
    )
    return RedirectResponse(
        url=_global_pack_detail_url(pid, flash_ok="cover_generated"),
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/publish-definition", response_model=None)
async def admin_global_pack_publish_definition_post(
    request: Request,
    pack_id: str,
    notes: str = Form(""),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    try:
        await acs.admin_publish_global_pack_definition(
            admin_username=gate.username,
            pack_id=pid,
            notes=notes,
        )
    except ValueError as e:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(e)),
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    return RedirectResponse(
        url=_global_pack_detail_url(pid, flash_ok="gpk_published"),
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/rollback-definition", response_model=None)
async def admin_global_pack_rollback_definition_post(
    request: Request,
    pack_id: str,
    reason: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    try:
        await acs.admin_rollback_global_pack_definition(
            admin_username=gate.username,
            pack_id=pid,
            reason=reason,
        )
    except ValueError as e:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(e)),
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    return RedirectResponse(
        url=_global_pack_detail_url(pid, flash_ok="gpk_rolled_back"),
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/delete", response_model=None)
async def admin_global_pack_delete_definition_post(
    request: Request,
    pack_id: str,
    reason: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    try:
        await acs.admin_delete_global_pack_definition(
            admin_username=gate.username,
            pack_id=pid,
            reason=reason,
        )
    except ValueError as e:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(e)),
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    return RedirectResponse(
        url="/admin/global-packs?flash_ok=gpk_deleted",
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/draft/create", response_model=None)
async def admin_global_pack_draft_create_post(
    request: Request,
    pack_id: str,
    word: str = Form(...),
    meaning_zh: str = Form(...),
    category: str = Form(...),
    difficulty: int = Form(1, ge=1, le=5),
    example_en: str = Form(""),
    example_zh: str = Form(""),
    distractors: str = Form(""),
    custom_word_id: str = Form(""),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    try:
        detail = await acs.load_global_pack_definition_console(pack_id=pid)
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    existing = _existing_global_draft_word_ids(detail["draft_words"])
    custom = (custom_word_id or "").strip()
    if custom:
        if custom in existing:
            return RedirectResponse(
                url=_global_pack_detail_url(
                    pid, flash_err=f"词条 ID「{custom}」已存在，请换一个或使用编辑。"
                ),
                status_code=303,
            )
        new_id = custom
    else:
        new_id = _allocate_global_word_id(word, existing)
    entry = _build_global_draft_entry_from_form(
        word_id=new_id,
        word=word,
        meaning_zh=meaning_zh,
        category=category,
        difficulty=difficulty,
        example_en=example_en,
        example_zh=example_zh,
        distractors_csv=distractors,
    )
    try:
        await gps.upsert_draft_word(
            pack_id=pid, admin_id=gate.username, entry=entry
        )
    except gps.GlobalPackError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(exc)),
            status_code=303,
        )
    return RedirectResponse(
        url=_global_pack_detail_url(pid, flash_ok="draft_saved"),
        status_code=303,
    )


@router.get(
    "/global-packs/packs/{pack_id}/draft/edit",
    response_class=HTMLResponse,
    response_model=None,
)
async def admin_global_pack_draft_edit_page(
    request: Request,
    pack_id: str,
    word_id: str = Query(..., min_length=1),
) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    wid = word_id.strip()
    try:
        detail = await acs.load_global_pack_definition_console(pack_id=pid)
    except LookupError:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    row = _find_draft_word(detail["draft_words"], wid)
    if row is None:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err="未找到该草稿词条。"),
            status_code=303,
        )
    flash_err_edit = request.query_params.get("flash_err")
    return templates.TemplateResponse(
        request,
        "admin/global_pack_draft_word_edit.html",
        {
            "admin_user": gate,
            "pack_id": pid,
            "definition": detail["definition"],
            "word_id": wid,
            "row": row,
            "flash_err": flash_err_edit,
        },
    )


@router.post("/global-packs/packs/{pack_id}/draft/save", response_model=None)
async def admin_global_pack_draft_save_post(
    request: Request,
    pack_id: str,
    word_id: str = Form(...),
    word: str = Form(...),
    meaning_zh: str = Form(...),
    category: str = Form(...),
    difficulty: int = Form(1, ge=1, le=5),
    example_en: str = Form(""),
    example_zh: str = Form(""),
    distractors: str = Form(""),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    wid = word_id.strip()
    entry = _build_global_draft_entry_from_form(
        word_id=wid,
        word=word,
        meaning_zh=meaning_zh,
        category=category,
        difficulty=difficulty,
        example_en=example_en,
        example_zh=example_zh,
        distractors_csv=distractors,
    )
    try:
        await gps.upsert_draft_word(
            pack_id=pid, admin_id=gate.username, entry=entry
        )
    except gps.GlobalPackError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(exc)),
            status_code=303,
        )
    return RedirectResponse(
        url=_global_pack_detail_url(pid, flash_ok="draft_saved"),
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/draft/delete", response_model=None)
async def admin_global_pack_draft_delete_post(
    request: Request,
    pack_id: str,
    word_id: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
    wid = word_id.strip()
    try:
        await gps.remove_draft_word(
            pack_id=pid, admin_id=gate.username, word_id=wid
        )
    except gps.GlobalPackError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(exc)),
            status_code=303,
        )
    return RedirectResponse(
        url=_global_pack_detail_url(pid, flash_ok="draft_deleted"),
        status_code=303,
    )


@router.post("/global-packs/packs/{pack_id}/draft/split", response_model=None)
async def admin_global_pack_draft_split_post(
    request: Request,
    pack_id: str,
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    pid = pack_id.strip()
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
    desc_raw = str(form.get("new_description", "")).strip()
    new_description = desc_raw or None
    split_mode: Literal["copy", "move"] = "move" if mode == "move" else "copy"

    try:
        result = await gps.split_draft_to_new_pack(
            pack_id=pid,
            admin_id=gate.username,
            word_ids=word_ids,
            new_name=new_name,
            new_description=new_description,
            mode=split_mode,
        )
    except gps.PackNotFound:
        return RedirectResponse(
            url=f"/admin/global-packs?flash_err={quote('未找到该全局词包。')}",
            status_code=303,
        )
    except gps.GlobalPackError as exc:
        return RedirectResponse(
            url=_global_pack_detail_url(pid, flash_err=str(exc)),
            status_code=303,
        )

    await record_admin_action(
        admin_username=gate.username,
        action="global_pack.draft_split",
        target_collection="family_pack_definitions",
        target_id=pid,
        payload_summary={
            "source_pack_id": pid,
            "new_pack_id": result.new_definition.pack_id,
            "mode": result.mode,
            "selected_count": result.selected_word_count,
            "via": "admin_html_detail",
        },
    )
    return RedirectResponse(
        url=_global_pack_detail_url(
            result.new_definition.pack_id,
            flash_ok=f"gpk_split_{result.mode}",
        ),
        status_code=303,
    )


# --- family packs ------------------------------------------------------------


@router.get("/family-packs", response_class=HTMLResponse, response_model=None)
async def admin_family_packs_list(
    request: Request,
    q: str | None = Query(None),
    page: int = Query(1, ge=1),
) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    flash_ok, flash_err = _flash_map_family(request)
    definitions, total = await acs.search_family_pack_definitions(
        q=q, page=page, page_size=PAGE_SIZE
    )
    page_nums, total_pages, page_use = _pagination(total, page, PAGE_SIZE)
    if page_use != page:
        definitions, total = await acs.search_family_pack_definitions(
            q=q, page=page_use, page_size=PAGE_SIZE
        )
    return templates.TemplateResponse(
        request,
        "admin/family_packs_list.html",
        {
            "admin_user": gate,
            "definitions": definitions,
            "q": q or "",
            "page": page_use,
            "total_pages": total_pages,
            "page_nums": page_nums,
            "flash_ok": flash_ok,
            "flash_err": flash_err,
        },
    )


@router.post("/family-packs/{pack_id}/metadata", response_model=None)
async def admin_family_pack_metadata_post(
    request: Request,
    pack_id: str,
    name: str = Form(...),
    description: str = Form(""),
    storyEn: str | None = Form(None),  # noqa: N803
    storyZh: str | None = Form(None),  # noqa: N803
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    definition = await _load_admin_family_pack_definition(pack_id)
    if definition is None:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    try:
        await fps.patch_definition(
            pack_id=definition.pack_id,
            family_id=definition.family_id,
            name=name,
            description=description,
            scene=_story_scene_update(definition.scene, story_en=storyEn, story_zh=storyZh),
        )
    except (fps.NameTaken, fps.InvalidPayload) as exc:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(exc))}",
            status_code=303,
        )
    await record_admin_action(
        admin_username=gate.username,
        action="family_pack.metadata_update",
        target_collection="family_pack_definitions",
        target_id=definition.pack_id,
        payload_summary={"family_id": definition.family_id, "via": "admin_html"},
    )
    return RedirectResponse(url="/admin/family-packs?flash_ok=story_saved", status_code=303)


@router.post("/family-packs/{pack_id}/story/generate", response_model=None)
async def admin_family_pack_story_generate_post(
    request: Request,
    pack_id: str,
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    definition = await _load_admin_family_pack_definition(pack_id)
    if definition is None:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    draft = await fps.get_or_create_draft(definition=definition, parent_user_id=gate.username)
    try:
        _model, story = await pack_story_service.generate_pack_story(
            pack_name=definition.name,
            words=list(draft.words),
        )
        await fps.patch_definition(
            pack_id=definition.pack_id,
            family_id=definition.family_id,
            name=None,
            description=None,
            scene=_story_scene_update(
                definition.scene,
                story_en=story["storyEn"],
                story_zh=story["storyZh"],
            ),
        )
    except (LlmConfigError, LlmCallError) as exc:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(exc))}",
            status_code=303,
        )
    await record_admin_action(
        admin_username=gate.username,
        action="family_pack.story_generate",
        target_collection="family_pack_definitions",
        target_id=definition.pack_id,
        payload_summary={"family_id": definition.family_id, "via": "admin_html"},
    )
    return RedirectResponse(url="/admin/family-packs?flash_ok=story_generated", status_code=303)


@router.post("/family-packs/{pack_id}/unarchive", response_model=None)
async def admin_family_unarchive_post(
    request: Request,
    pack_id: str,
    reason: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_family_pack_unarchive(
            admin_username=gate.username,
            pack_id=pack_id,
            reason=reason,
        )
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    return RedirectResponse(url="/admin/family-packs?flash_ok=unarchived", status_code=303)


@router.post("/family-packs/{pack_id}/rollback", response_model=None)
async def admin_family_rollback_post(
    request: Request,
    pack_id: str,
    reason: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_family_pack_rollback(
            admin_username=gate.username,
            pack_id=pack_id,
            reason=reason,
        )
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    return RedirectResponse(url="/admin/family-packs?flash_ok=rolled_back", status_code=303)


@router.post("/family-packs/{pack_id}/delete", response_model=None)
async def admin_family_delete_post(
    request: Request,
    pack_id: str,
    reason: str = Form(...),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_family_pack_delete(
            admin_username=gate.username,
            pack_id=pack_id,
            reason=reason,
        )
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    except LookupError:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    return RedirectResponse(url="/admin/family-packs?flash_ok=deleted", status_code=303)


@router.post("/family-packs/{pack_id}/copy-to-global", response_model=None)
async def admin_family_copy_to_global_post(
    request: Request,
    pack_id: str,
    reason: str = Form(...),
    delete_source: str | None = Form(None),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_family_pack_copy(
            admin_username=gate.username,
            source_pack_id=pack_id,
            target_kind="global",
            target_family_id=None,
            delete_source=delete_source is not None,
            reason=reason,
        )
    except LookupError:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    return RedirectResponse(url="/admin/family-packs?flash_ok=copied_global", status_code=303)


@router.post("/family-packs/{pack_id}/copy-to-family", response_model=None)
async def admin_family_copy_to_family_post(
    request: Request,
    pack_id: str,
    target_family_id: str = Form(...),
    reason: str = Form(...),
    delete_source: str | None = Form(None),
) -> RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    try:
        await acs.admin_family_pack_copy(
            admin_username=gate.username,
            source_pack_id=pack_id,
            target_kind="family",
            target_family_id=target_family_id,
            delete_source=delete_source is not None,
            reason=reason,
        )
    except LookupError:
        return RedirectResponse(url="/admin/family-packs?flash_err=not_found", status_code=303)
    except ValueError as e:
        return RedirectResponse(
            url=f"/admin/family-packs?flash_err={quote(str(e))}",
            status_code=303,
        )
    return RedirectResponse(url="/admin/family-packs?flash_ok=copied_family", status_code=303)


# --- audit logs ---------------------------------------------------------------


@router.get("/audit-logs", response_class=HTMLResponse, response_model=None)
async def admin_audit_logs_page(
    request: Request,
    q: str | None = Query(None),
    page: int = Query(1, ge=1),
) -> HTMLResponse | RedirectResponse:
    gate = await _require_admin_html(request)
    if isinstance(gate, RedirectResponse):
        return gate
    logs, total = await acs.search_audit_logs(q_action=q, page=page, page_size=PAGE_SIZE)
    page_nums, total_pages, page_use = _pagination(total, page, PAGE_SIZE)
    if page_use != page:
        logs, total = await acs.search_audit_logs(q_action=q, page=page_use, page_size=PAGE_SIZE)
    return templates.TemplateResponse(
        request,
        "admin/audit_logs.html",
        {
            "admin_user": gate,
            "logs": logs,
            "q": q or "",
            "page": page_use,
            "total_pages": total_pages,
            "page_nums": page_nums,
            "audit_ts": format_audit_timestamp,
        },
    )
