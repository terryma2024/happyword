"""Local mock server for HarmonyOS UI automation tests (V0.5.8+).

Why
---
The on-device UI tests in ``entry/src/ohosTest`` exercise these flows
that previously made live HTTP requests to ``https://happyword.vercel.app``:

* ``ConfigPage`` — pack-sync round-trip (``GET /api/v1/packs/latest.json``).
* ``ParentAdminPage`` — stats + pending lesson drafts + publish notes
  + photo import (``GET /api/v1/admin/stats``, ``GET /admin/lesson-drafts``,
  ``POST /admin/packs/publish``, ``POST /admin/lessons/import``).
* ``LessonDraftReviewPage`` — load / patch / approve / reject lesson drafts.
* (V0.6) ``ScanBindingPage`` / ``ConfigPage`` parent-account row —
  short-code redeem (``POST /api/v1/pair/redeem``) and device unbind
  (``POST /api/v1/child/unbind``). Cloud sync / wishlist / redemption
  endpoints are also stubbed so that any cold-start network call from a
  bound device returns deterministic empty payloads.

Hitting prod from a flaky emulator network produces non-deterministic
failures and pollutes the prod database. This mock is the deterministic
counterpart: a single-file FastAPI app with **no MongoDB**, no LLM, no
auth — every endpoint returns a fixed-shape fixture or echoes the
request back.

Deployment posture
------------------
* Bound to ``127.0.0.1:8123`` by default. Never expose this on a public
  interface — there is no auth.
* Reached from the HarmonyOS emulator via ``hdc rport tcp:8123 tcp:8123``,
  which makes the device's loopback ``127.0.0.1:8123`` route back to the
  host process. ``scripts/run_ui_tests.sh`` is the canonical orchestrator.
* The override URL on the client is written by
  ``entry/src/ohosTest/ets/test/List.test.ets`` (``AppStorage.setOrCreate``
  with key ``serverBaseUrlOverride``). Production never writes that key,
  so release builds keep hitting Vercel.

Usage (run from ``server/`` so the project's ``uv`` venv is picked up)::

    uv run python mock_ui_server.py                # default port (8123)
    uv run python mock_ui_server.py --port 9001    # custom port
"""

from __future__ import annotations

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Header, HTTPException, Response, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Production catalog mirror
# ---------------------------------------------------------------------------
# Mirror the rawfile catalog so that when `configSyncFlowUiTest` taps the
# manual sync button on ConfigPage, the WordPackSyncService overwrites
# the on-device cache with the SAME 50 words the gameplay tests
# (FillLetterFlow, SpellQuestionFlow, ReviewMode, MagicAttack, ...)
# already expect. Without this the synced cache would shrink to a
# 4-word fixture and downstream battle suites would fail to find words
# like 'orange' or 'TV' in their hard-coded WORD_ZH/WORD_EN tables.
#
# The catalog file is committed under
# `entry/src/main/resources/rawfile/data/words_v1.json` and is part of
# the production app bundle, so loading it here keeps the mock and the
# device catalog in lockstep — change one, change the other.
_PROD_CATALOG_PATH: Path = (
    Path(__file__).resolve().parent.parent
    / "entry"
    / "src"
    / "main"
    / "resources"
    / "rawfile"
    / "data"
    / "words_v1.json"
)


def _load_prod_catalog_words() -> list[dict[str, Any]]:
    """Read the production catalog and return its words array.

    Falls back to a small inline 4-word list if the catalog file is not
    on disk (e.g. running this module from outside the repo). The
    fallback is intentional — the mock is a developer convenience and
    must not crash when invoked from a fresh checkout that hasn't
    fetched the catalog yet.
    """
    try:
        with _PROD_CATALOG_PATH.open(encoding="utf-8") as fh:
            data: dict[str, Any] = json.load(fh)
    except FileNotFoundError:
        return [
            {"id": "fixture_apple", "word": "apple", "meaningZh": "苹果",
             "category": "fixture_fruit", "difficulty": 1},
            {"id": "fixture_banana", "word": "banana", "meaningZh": "香蕉",
             "category": "fixture_fruit", "difficulty": 1},
            {"id": "fixture_cherry", "word": "cherry", "meaningZh": "樱桃",
             "category": "fixture_fruit", "difficulty": 2},
            {"id": "fixture_dog", "word": "dog", "meaningZh": "狗",
             "category": "fixture_animal", "difficulty": 1},
        ]
    words: list[dict[str, Any]] = data.get("words", [])
    return words

# ---------------------------------------------------------------------------
# Fixture data
# ---------------------------------------------------------------------------

PACK_VERSION: int = 1
PACK_ETAG: str = f'"{PACK_VERSION}"'
PACK_PUBLISHED_AT: str = "2026-04-30T12:00:00+00:00"

# Pack payload mirrors `server/app/schemas/pack.py::PackResponse`. The
# words list is the SAME 50 entries the production app ships in
# `rawfile/data/words_v1.json` so that ConfigSyncFlow's manual sync
# overwrites the on-device cache with a catalog that downstream
# gameplay tests still recognise. See `_load_prod_catalog_words` above
# for why this matters.
FIXTURE_PACK_PAYLOAD: dict[str, Any] = {
    "version": PACK_VERSION,
    "schema_version": 5,
    "published_at": PACK_PUBLISHED_AT,
    "words": _load_prod_catalog_words(),
}

# Shape mirrors server/app/schemas/admin_lesson.py::LessonDraftOut.
FIXTURE_DRAFT_ID: str = "ui-mock-draft-001"
FIXTURE_DRAFT_CATEGORY_ID: str = "ui-mock-cat-001"


def _fresh_draft(draft_id: str = FIXTURE_DRAFT_ID) -> dict[str, Any]:
    """Return a brand-new pending draft with stable shape.

    `source_image_url` is intentionally empty so
    `LessonDraftReviewPage.bodyCard` skips the thumbnail Image (it only
    renders when `source_image_url.length > 0`). On the portrait
    emulator the 60% × 4:3 thumbnail otherwise eats enough vertical
    space to push the first word row off-screen, which would make
    UiTest's `assertComponentExist(visible:true)` flag the toggle as
    missing. Real production drafts always have a valid HTTPS URL —
    this is a test-only short-circuit.
    """
    return {
        "id": draft_id,
        "source_image_url": "",
        "extracted": {
            "category_id": FIXTURE_DRAFT_CATEGORY_ID,
            "label_en": "Mock Lesson",
            "label_zh": "模拟课文",
            "story_zh": None,
            "words": [
                {"word": "apple", "meaningZh": "苹果", "difficulty": 1},
                {"word": "banana", "meaningZh": "香蕉", "difficulty": 1},
                {"word": "cherry", "meaningZh": "樱桃", "difficulty": 2},
            ],
        },
        "edited_extracted": None,
        "status": "pending",
        "created_at": "2026-04-30T12:00:00+00:00",
        "reviewed_at": None,
        "reviewer": None,
        "model": "ui-mock",
        "prompt_version": 1,
        "approval_summary": None,
    }


# ---------------------------------------------------------------------------
# In-memory state
# ---------------------------------------------------------------------------

# Module-level mutable maps. Reset between test runs by restarting the
# process — every UI test invocation starts a fresh mock instance.
_drafts: dict[str, dict[str, Any]] = {}
_published_versions: list[int] = [PACK_VERSION]

# V0.6 binding state. The mock accepts any 6-digit short code or any
# non-empty token, mints a deterministic device JWT, and tracks the
# binding so subsequent /child/* calls can be authorized.
_PAIR_BINDING_ID: str = "ui-mock-bind-001"
_PAIR_FAMILY_ID: str = "ui-mock-fam-001"
_PAIR_CHILD_PROFILE_ID: str = "ui-mock-child-001"
_PAIR_NICKNAME: str = "测试宝贝"
_PAIR_AVATAR_EMOJI: str = "🦁"
_PAIR_DEVICE_TOKEN: str = "ui-mock-device-jwt"
_active_bindings: set[str] = set()


def _reset_state() -> None:
    """Re-seed module state between integration tests.

    The CLI calls this implicitly via app startup. Tests that import
    the app directly (none today) can call it explicitly to get a
    deterministic baseline.
    """
    _drafts.clear()
    _drafts[FIXTURE_DRAFT_ID] = _fresh_draft()
    _published_versions.clear()
    _published_versions.append(PACK_VERSION)
    _active_bindings.clear()


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------


def _now_iso() -> str:
    """Return current time in ISO-8601 with timezone (mock pretends UTC)."""
    return datetime.now(UTC).isoformat()


class PublishIn(BaseModel):
    notes: str | None = None


class PairRedeemIn(BaseModel):
    """Mirror of server `PairRedeemIn`. Either token or short_code is required."""

    device_id: str
    token: str | None = None
    short_code: str | None = None


def _is_authorized(authorization: str | None) -> bool:
    """Return True if the Bearer token matches the active mock device JWT.

    The mock keeps things permissive — any well-formed Bearer header
    that matches the minted token (`_PAIR_DEVICE_TOKEN`) and corresponds
    to an active binding is accepted. Test ergonomics matter more than
    crypto: real auth is exercised by the server pytest suite.
    """
    if authorization is None or not authorization.startswith("Bearer "):
        return False
    token = authorization[len("Bearer "):]
    return token == _PAIR_DEVICE_TOKEN and _PAIR_BINDING_ID in _active_bindings


def create_app() -> FastAPI:
    """Build the mock FastAPI app.

    Kept as a factory so the orchestrator script can import a fresh
    instance with reset state per run, and so future hooks (per-test
    overrides, fault injection) have a single hook point.
    """
    # Seed the state at app construction. We deliberately do **not**
    # use the deprecated ``@app.on_event("startup")`` API — FastAPI
    # emits a DeprecationWarning for it which the project-wide pytest
    # filterwarnings = ["error"] policy would surface. Resetting at
    # construction is equivalent for the mock because every UI test
    # run launches a fresh process.
    _reset_state()

    app = FastAPI(
        title="HappyWord Mock UI Server",
        version="0.5.8-mock",
        description=(
            "Deterministic stand-in for happyword.vercel.app used by "
            "HarmonyOS ohosTest UI automation. Localhost only — no auth."
        ),
    )

    # ------------------------------------------------------------------
    # Public endpoints
    # ------------------------------------------------------------------

    @app.get("/api/v1/health")
    async def health() -> dict[str, Any]:
        return {"ok": True, "mock": True, "ts": _now_iso()}

    @app.get("/api/v1/packs/latest.json")
    async def latest_pack(
        if_none_match: str | None = Header(None, alias="If-None-Match"),
    ) -> Response:
        if if_none_match is not None and if_none_match == PACK_ETAG:
            return Response(status_code=304, headers={"ETag": PACK_ETAG})
        body = json.dumps(FIXTURE_PACK_PAYLOAD, ensure_ascii=False)
        return Response(
            status_code=200,
            content=body,
            media_type="application/json",
            headers={"ETag": PACK_ETAG},
        )

    # ------------------------------------------------------------------
    # Admin: stats
    # ------------------------------------------------------------------

    @app.get("/api/v1/admin/stats")
    async def admin_stats() -> dict[str, Any]:
        pending_count = sum(1 for d in _drafts.values() if d["status"] == "pending")
        return {
            "user_count": 1,
            "word_count": len(FIXTURE_PACK_PAYLOAD["words"]),
            "category_count": 1,
            "pack_count": len(_published_versions),
            "latest_version": _published_versions[-1] if _published_versions else None,
            "last_published_at": PACK_PUBLISHED_AT,
            "llm_draft_pending": 0,
            "lesson_import_draft_pending": pending_count,
        }

    # ------------------------------------------------------------------
    # Admin: pack publish
    # ------------------------------------------------------------------

    @app.post("/api/v1/admin/packs/publish", status_code=201)
    async def admin_publish_pack(body: PublishIn) -> dict[str, Any]:
        next_version = (_published_versions[-1] if _published_versions else 0) + 1
        _published_versions.append(next_version)
        return {
            "version": next_version,
            "schema_version": 5,
            "word_count": len(FIXTURE_PACK_PAYLOAD["words"]),
            "published_at": _now_iso(),
            "published_by": "parent",
            "notes": body.notes,
        }

    # ------------------------------------------------------------------
    # Admin: lesson drafts
    # ------------------------------------------------------------------

    @app.get("/api/v1/admin/lesson-drafts")
    async def admin_list_drafts(
        status: str | None = None,
        page: int = 0,
        size: int = 20,
    ) -> dict[str, Any]:
        filtered = list(_drafts.values())
        if status is not None:
            filtered = [d for d in filtered if d["status"] == status]
        start = max(0, page) * max(1, size)
        end = start + max(1, size)
        return {
            "items": filtered[start:end],
            "total": len(filtered),
            "page": page,
            "size": size,
        }

    @app.get("/api/v1/admin/lesson-drafts/{draft_id}")
    async def admin_get_draft(draft_id: str) -> dict[str, Any]:
        draft = _drafts.get(draft_id)
        if draft is None:
            raise HTTPException(status_code=404, detail={"code": "draft_not_found"})
        return draft

    @app.patch("/api/v1/admin/lesson-drafts/{draft_id}")
    async def admin_patch_draft(
        draft_id: str,
        body: dict[str, Any],
    ) -> dict[str, Any]:
        draft = _drafts.get(draft_id)
        if draft is None:
            raise HTTPException(status_code=404, detail={"code": "draft_not_found"})
        if draft["status"] != "pending":
            raise HTTPException(
                status_code=409,
                detail={"code": "draft_not_pending"},
            )
        edited = body.get("edited_extracted")
        if edited is None:
            raise HTTPException(
                status_code=422,
                detail={"code": "invalid_payload"},
            )
        draft["edited_extracted"] = edited
        return draft

    @app.post("/api/v1/admin/lesson-drafts/{draft_id}/approve")
    async def admin_approve_draft(draft_id: str) -> dict[str, Any]:
        draft = _drafts.get(draft_id)
        if draft is None:
            raise HTTPException(status_code=404, detail={"code": "draft_not_found"})
        if draft["status"] != "pending":
            raise HTTPException(
                status_code=409,
                detail={"code": "draft_not_pending"},
            )
        draft["status"] = "approved"
        draft["reviewed_at"] = _now_iso()
        draft["reviewer"] = "parent"
        kept_words = (
            (draft.get("edited_extracted") or draft["extracted"]).get("words") or []
        )
        return {
            "created_category": {
                "id": FIXTURE_DRAFT_CATEGORY_ID,
                "name_en": "Mock Lesson",
                "name_zh": "模拟课文",
                "created_at": _now_iso(),
                "deleted_at": None,
            },
            "created_words": [{"word": w["word"]} for w in kept_words],
            "skipped_words": [],
        }

    @app.post("/api/v1/admin/lesson-drafts/{draft_id}/reject")
    async def admin_reject_draft(draft_id: str) -> dict[str, Any]:
        draft = _drafts.get(draft_id)
        if draft is None:
            raise HTTPException(status_code=404, detail={"code": "draft_not_found"})
        if draft["status"] != "pending":
            raise HTTPException(
                status_code=409,
                detail={"code": "draft_not_pending"},
            )
        draft["status"] = "rejected"
        draft["reviewed_at"] = _now_iso()
        draft["reviewer"] = "parent"
        return draft

    # ------------------------------------------------------------------
    # Admin: lesson import (multipart)
    # ------------------------------------------------------------------

    @app.post("/api/v1/admin/lessons/import", status_code=201)
    async def admin_import_lesson(
        image: UploadFile = File(...),
    ) -> JSONResponse:
        # Drain the upload so the client side completes its multipart
        # write before we respond. We don't persist the bytes — the
        # purpose is just to keep the wire-protocol contract identical
        # to prod (multipart/form-data with field name "image").
        _ = await image.read()
        new_id = f"ui-mock-draft-{len(_drafts) + 1:03d}"
        draft = _fresh_draft(new_id)
        _drafts[new_id] = draft
        return JSONResponse(status_code=201, content=draft)

    # ------------------------------------------------------------------
    # Catch-all for unknown admin paths so failures are obvious in test
    # logs (instead of getting a default 404 that looks like a network
    # outage).
    # ------------------------------------------------------------------

    # ------------------------------------------------------------------
    # V0.6 device pairing + child binding
    # ------------------------------------------------------------------
    # Behaviour:
    #  - POST /api/v1/pair/redeem succeeds when ``device_id`` is non-empty
    #    AND (``token`` is non-empty OR ``short_code`` is exactly 6 digits).
    #    On success it adds the binding to ``_active_bindings`` and mints
    #    the deterministic device JWT defined above.
    #  - Specific short codes can simulate failures so the UI test can
    #    cover the error-banner path:
    #      "000000" → 410 TOKEN_EXPIRED
    #      "111111" → 409 TOKEN_REDEEMED
    #      "222222" → 422 TOKEN_INVALID
    #  - POST /api/v1/child/unbind clears the binding when the Bearer
    #    token matches; returns 404 BINDING_REVOKED when already cleared.

    def _err(status: int, code: str, message: str) -> HTTPException:
        return HTTPException(
            status_code=status,
            detail={"error": {"code": code, "message": message}},
        )

    @app.post("/api/v1/pair/redeem")
    async def pair_redeem(body: PairRedeemIn) -> dict[str, Any]:
        if not body.device_id:
            raise _err(422, "DEVICE_ID_REQUIRED", "device_id missing")
        token: str = (body.token or "").strip()
        short: str = (body.short_code or "").strip()
        if not token and not short:
            raise _err(422, "TOKEN_OR_SHORTCODE_REQUIRED", "token or short_code required")
        if short:
            if short == "000000":
                raise _err(410, "TOKEN_EXPIRED", "short code expired")
            if short == "111111":
                raise _err(409, "TOKEN_REDEEMED", "short code already redeemed")
            if short == "222222":
                raise _err(422, "TOKEN_INVALID", "short code malformed")
            if not (len(short) == 6 and short.isdigit()):
                raise _err(422, "TOKEN_INVALID", "short code must be 6 digits")
        _active_bindings.add(_PAIR_BINDING_ID)
        return {
            "binding_id": _PAIR_BINDING_ID,
            "family_id": _PAIR_FAMILY_ID,
            "child_profile_id": _PAIR_CHILD_PROFILE_ID,
            "nickname": _PAIR_NICKNAME,
            "avatar_emoji": _PAIR_AVATAR_EMOJI,
            "device_token": _PAIR_DEVICE_TOKEN,
        }

    @app.post("/api/v1/child/unbind")
    async def child_unbind(
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if authorization is None or not authorization.startswith("Bearer "):
            raise _err(401, "UNAUTHORIZED", "missing bearer token")
        token = authorization[len("Bearer "):]
        if token != _PAIR_DEVICE_TOKEN:
            raise _err(401, "UNAUTHORIZED", "invalid token")
        if _PAIR_BINDING_ID not in _active_bindings:
            raise _err(404, "BINDING_REVOKED", "binding already revoked")
        _active_bindings.discard(_PAIR_BINDING_ID)
        return {"ok": True}

    @app.get("/api/v1/child/me")
    async def child_me(
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        return {
            "binding_id": _PAIR_BINDING_ID,
            "family_id": _PAIR_FAMILY_ID,
            "child_profile_id": _PAIR_CHILD_PROFILE_ID,
            "nickname": _PAIR_NICKNAME,
            "avatar_emoji": _PAIR_AVATAR_EMOJI,
        }

    # ------------------------------------------------------------------
    # V0.6.3 family pack overlay (always empty so client falls through
    # to the global pack catalog and gameplay tests stay deterministic).
    # ------------------------------------------------------------------

    @app.get("/api/v1/child/family-packs/active.json")
    async def child_family_packs(
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        return {"family_id": _PAIR_FAMILY_ID, "packs": [], "etag": ""}

    # ------------------------------------------------------------------
    # V0.6.4 cloud sync (LWW). Always accepts pushes; pull returns no
    # server-side updates so client state is authoritative in tests.
    # ------------------------------------------------------------------

    @app.post("/api/v1/child/sync/word-stats")
    async def child_sync_word_stats(
        body: dict[str, Any],
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        # Echo back accept count for any words the client claimed to push.
        items = body.get("items") or []
        return {
            "accepted": len(items),
            "rejected": 0,
            "pulls": [],
            "server_now": _now_iso(),
        }

    @app.get("/api/v1/child/sync/word-stats")
    async def child_pull_word_stats(
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        return {"items": [], "server_now": _now_iso()}

    # ------------------------------------------------------------------
    # V0.6.6 cloud wishlist + redemption polling
    # ------------------------------------------------------------------

    @app.get("/api/v1/child/wishlist")
    async def child_wishlist(
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        return {"items": []}

    @app.post("/api/v1/child/wishlist/sync-custom")
    async def child_wishlist_sync_custom(
        body: dict[str, Any],
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        return {"accepted": len(body.get("items") or [])}

    @app.post("/api/v1/child/redemption-requests", status_code=201)
    async def child_create_redemption(
        body: dict[str, Any],
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        return {
            "request_id": "ui-mock-rdm-001",
            "wishlist_item_id": body.get("wishlist_item_id", ""),
            "cost_coins_at_request": body.get("cost_coins", 0),
            "status": "pending",
            "requested_at": _now_iso(),
        }

    @app.get("/api/v1/child/redemption-requests")
    async def child_list_redemptions(
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        return {"items": []}

    @app.get("/api/v1/child/redemption-requests/poll")
    async def child_poll_redemptions(
        authorization: str | None = Header(None, alias="Authorization"),
    ) -> dict[str, Any]:
        if not _is_authorized(authorization):
            raise _err(401, "UNAUTHORIZED", "missing or invalid token")
        return {"decisions": [], "server_now": _now_iso()}

    @app.get("/__mock_state__")
    async def mock_state() -> dict[str, Any]:
        """Internal: dump current state for debugging from the host shell.

        Not used by the client; here purely so a developer running the
        UI test loop can ``curl http://127.0.0.1:8123/__mock_state__``
        and inspect what the device has done.
        """
        return {
            "drafts": _drafts,
            "published_versions": _published_versions,
            "active_bindings": sorted(_active_bindings),
        }

    return app


# Module-level singleton for ``uvicorn server.mock_ui_server:app`` users.
app = create_app()


def main() -> None:
    parser = argparse.ArgumentParser(description="HappyWord mock UI server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8123)
    parser.add_argument(
        "--log-level",
        default="warning",
        help="uvicorn log level (default: warning to keep test logs clean)",
    )
    args = parser.parse_args()

    import uvicorn

    # Pass the app object directly (not as an import string) so this
    # script can be launched from any working directory without the
    # caller having to fix up PYTHONPATH for a "server" package.
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        log_level=args.log_level,
        reload=False,
    )


if __name__ == "__main__":
    main()
