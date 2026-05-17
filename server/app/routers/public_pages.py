"""Public legal/support pages for store review.

These pages must stay reachable without a parent session because App Store
Connect and reviewers validate the URLs before logging into the product.

Templates live under ``templates/parent/store_*.html`` (not ``templates/legal/``
or ``templates/public/``) so they ship in the same Vercel serverless bundle
as ``parent/login.html`` and other parent-shell pages.
"""

from __future__ import annotations

import os
from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates

router = APIRouter(tags=["public-pages"])

# Same relative directory as parent_pages / pair landing (known-good on Vercel).
templates = Jinja2Templates(directory="app/templates")

_TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "templates"


def _render_legal(request: Request, template_name: str) -> HTMLResponse:
    try:
        return templates.TemplateResponse(
            request,
            template_name,
            {"user": None},
        )
    except Exception as exc:
        if os.environ.get("VERCEL"):
            return HTMLResponse(
                f"<pre>{type(exc).__name__}: {exc}</pre>",
                status_code=500,
            )
        raise


@router.get("/privacy", response_class=HTMLResponse)
async def get_privacy(request: Request) -> HTMLResponse:
    return _render_legal(request, "parent/store_privacy.html")


@router.get("/terms", response_class=HTMLResponse)
async def get_terms(request: Request) -> HTMLResponse:
    return _render_legal(request, "parent/store_terms.html")


@router.get("/support", response_class=HTMLResponse)
async def get_support(request: Request) -> HTMLResponse:
    return _render_legal(request, "parent/store_support.html")


@router.get("/_debug/template-fs", include_in_schema=False)
async def debug_template_fs() -> JSONResponse:
    """Preview-only filesystem probe for legal template bundling issues."""
    if os.environ.get("VERCEL_ENV") == "production":
        return JSONResponse({"detail": "not found"}, status_code=404)
    legal_dir = _TEMPLATES_DIR / "legal"
    return JSONResponse(
        {
            "cwd": os.getcwd(),
            "templates_dir": str(_TEMPLATES_DIR),
            "parent_login": (_TEMPLATES_DIR / "parent" / "login.html").is_file(),
            "store_privacy": (_TEMPLATES_DIR / "parent" / "store_privacy.html").is_file(),
            "store_terms": (_TEMPLATES_DIR / "parent" / "store_terms.html").is_file(),
            "legal_dir_exists": legal_dir.is_dir(),
            "legal_dir_files": (
                [p.name for p in legal_dir.glob("*.html")] if legal_dir.is_dir() else []
            ),
        }
    )


__all__ = ["router"]
