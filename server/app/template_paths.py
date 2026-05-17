"""Shared Jinja2 template directory for server-rendered HTML.

Uses a path relative to this package so template resolution does not
depend on the process working directory (Vercel serverless may not cwd
into ``server/``). Keep legal/store pages under ``templates/legal/`` —
not ``templates/public/`` — because Vercel's bundler treats ``public``
path segments as static assets and can omit them from the function bundle.
"""

from __future__ import annotations

from pathlib import Path

from fastapi.templating import Jinja2Templates

TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

__all__ = ["TEMPLATES_DIR", "templates"]
