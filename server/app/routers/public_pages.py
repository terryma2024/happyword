"""Public legal/support pages for store review.

These pages must stay reachable without a parent session because App Store
Connect and reviewers validate the URLs before logging into the product.
"""

from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

router = APIRouter(tags=["public-pages"])
templates = Jinja2Templates(directory="app/templates")


@router.get("/privacy", response_class=HTMLResponse)
async def get_privacy(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "public/privacy.html",
        {"user": None},
    )


@router.get("/terms", response_class=HTMLResponse)
async def get_terms(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "public/terms.html",
        {"user": None},
    )


@router.get("/support", response_class=HTMLResponse)
async def get_support(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request,
        "public/support.html",
        {"user": None},
    )


__all__ = ["router"]
