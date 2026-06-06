"""Public legal/support pages for store review.

These pages must stay reachable without a parent session because App Store
Connect and reviewers validate the URLs before logging into the product.

Templates live under ``templates/parent/store_*.html`` (same Vercel bundle as
``parent/login.html``).
"""

from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

router = APIRouter(tags=["public-pages"])

# Same relative directory as parent_pages / pair landing (known-good on Vercel).
templates = Jinja2Templates(directory="app/templates")


@router.get("/privacy", response_class=HTMLResponse)
async def get_privacy(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "parent/store_privacy.html",
        {"user": None},
    )


@router.get("/terms", response_class=HTMLResponse)
async def get_terms(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "parent/store_terms.html",
        {"user": None},
    )


@router.get("/support", response_class=HTMLResponse)
async def get_support(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "parent/store_support.html",
        {"user": None},
    )


@router.get("/features", response_class=HTMLResponse)
async def get_features(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "features.html",
        {"user": None},
    )


@router.get("/report_and_appeal", response_class=HTMLResponse)
async def get_report_and_appeal(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "parent/report_and_appeal.html",
        {"user": None},
    )


__all__ = ["router"]
