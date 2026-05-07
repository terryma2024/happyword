"""Vercel python runtime entrypoint. Re-exports the FastAPI ASGI app.

Vercel's FastAPI Framework Preset auto-discovers an `app` instance at
`api/index.py`, `app/main.py`, and a few other conventional locations
(see https://vercel.com/docs/functions/runtimes/python#python-entrypoints).
Both `api/index.py` (this re-export) and `app/main.py` (the real definition)
match its search list — which one wins is undefined, and the loser's routes
silently disappear from the deployed function.

`pyproject.toml` therefore pins `tool.vercel.entrypoint = "api.index:app"`
so the preset always loads *this* file, which then re-exports `app.main:app`.
Do NOT remove this re-export, even though it looks pointless — it is the
disambiguator that makes the deployment routable.
"""

from app.main import app  # noqa: F401
