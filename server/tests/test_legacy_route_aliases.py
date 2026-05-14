"""Legacy route aliases were removed after the v0.6.5+ URL prefix cutover.

Keep a tiny import-time guard so we do not accidentally reintroduce the
duplicate-route attachment hook without updating this test suite.
"""

from __future__ import annotations

from fastapi import FastAPI


def test_app_main_has_no_legacy_alias_attachment() -> None:
    from app import main as app_main

    app = app_main.app
    assert isinstance(app, FastAPI)
    names = {getattr(r, "name", "") for r in app.routes}
    assert not any(str(n).startswith("alias_") for n in names)
