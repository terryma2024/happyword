"""V0.6.5 — Map existing legacy URLs onto the new prefix convention.

Per `.cursor/rules/api-route-pattern.mdc`, all new HTTP surfaces live
under `/api/v1/admin/**`, `/api/v1/public/**`, or
`/api/v1/family/{family_id}/**`. This module adds **path aliases**
pointing to the SAME handler functions already registered by the legacy
routers, so v0.6.5 clients can adopt the new URL shape immediately while
v0.6.4 clients keep working through the legacy paths.

Aliases are excluded from the OpenAPI schema (`include_in_schema=False`)
so /docs only shows the new shape going forward; legacy URLs remain
visible in /docs during the transition window.

Removal of legacy URLs is scheduled for v0.6.6+ once every shipped
HarmonyOS build has been seen migrating to the new URLs.

The `{family_id}` path parameter on the new family-prefix aliases is
**decorative in v0.6.5** — handlers continue to read `family_id` from
the existing parent session / Bearer device-token. v0.6.6 will land
"path-param-must-match-session" enforcement.

Implementation note: aliases must be cloned via FastAPI's `APIRoute`
class (not Starlette's bare `Route`) so dependency injection (`Depends`)
resolves correctly. We construct each alias as an `APIRoute` with the
same `endpoint`, `dependencies`, `dependency_overrides_provider`,
`response_model`, etc., as the legacy route.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

from fastapi.routing import APIRoute

if TYPE_CHECKING:
    from fastapi import FastAPI

# Exact-path rewrites (one-to-one).
_EXACT: dict[str, str] = {
    "/api/v1/health": "/api/v1/public/health",
    "/api/v1/packs/latest.json": "/api/v1/public/packs/latest.json",
    "/api/v1/auth/login": "/api/v1/admin/auth/login",
    "/api/v1/auth/me": "/api/v1/admin/auth/me",
}

# Prefix rewrites (apply to anything starting with `src`).
# Order matters — first match wins.
_PREFIX: list[tuple[str, str]] = [
    ("/api/v1/parent/", "/api/v1/family/{family_id}/"),
    ("/api/v1/child/", "/api/v1/family/{family_id}/"),
    ("/parent/", "/family/{family_id}/"),
]


def _alias_for(path: str) -> str | None:
    if path in _EXACT:
        return _EXACT[path]
    for src, tgt in _PREFIX:
        if path.startswith(src):
            return tgt + path[len(src) :]
    # Bare-prefix endpoints (e.g. `/parent` exactly) are also legacy;
    # treat them as if they had the trailing slash.
    for src, tgt in _PREFIX:
        bare = src.rstrip("/")
        if path == bare:
            return tgt.rstrip("/")
    return None


def _name_safe(s: str) -> str:
    """FastAPI route names must match `[a-zA-Z_][a-zA-Z0-9_]*`. Path-param
    braces and slashes need stripping."""
    return re.sub(r"[^a-zA-Z0-9_]+", "_", s).strip("_") or "alias"


def attach_legacy_aliases(app: FastAPI) -> int:
    """Register an alias APIRoute for every legacy path that has a
    new-shape counterpart in `_EXACT` / `_PREFIX`. Returns the count of
    aliases added (handy for log lines / smoke tests).

    MUST be called AFTER every `app.include_router(...)` so this function
    can see all legacy routes already registered on `app.routes`.
    """
    new_routes: list[APIRoute] = []
    seen: set[tuple[str, frozenset[str]]] = set()
    for route in list(app.routes):
        if not isinstance(route, APIRoute):
            continue
        new_path = _alias_for(route.path)
        if new_path is None:
            continue
        methods = frozenset(route.methods or set())
        key = (new_path, methods)
        if key in seen:
            continue
        seen.add(key)
        # Clone the route via FastAPI's APIRoute so that `Depends(...)`
        # and `response_model` continue to work. We pass the same
        # endpoint function and copy all routing-relevant attributes
        # the legacy route had.
        alias = APIRoute(
            path=new_path,
            endpoint=route.endpoint,
            response_model=route.response_model,
            status_code=route.status_code,
            tags=list(route.tags or []),
            dependencies=list(route.dependencies or []),
            summary=route.summary,
            description=route.description,
            response_description=route.response_description,
            responses=dict(route.responses or {}),
            deprecated=route.deprecated,
            methods=list(route.methods or []),
            operation_id=None,
            response_model_include=route.response_model_include,
            response_model_exclude=route.response_model_exclude,
            response_model_by_alias=route.response_model_by_alias,
            response_model_exclude_unset=route.response_model_exclude_unset,
            response_model_exclude_defaults=(
                route.response_model_exclude_defaults
            ),
            response_model_exclude_none=route.response_model_exclude_none,
            include_in_schema=False,
            response_class=route.response_class,
            name=f"alias_{_name_safe(new_path)}_{_name_safe('_'.join(sorted(methods)))}",
            callbacks=list(route.callbacks or []),
            openapi_extra=route.openapi_extra,
            generate_unique_id_function=route.generate_unique_id_function,
        )
        new_routes.append(alias)
    app.routes.extend(new_routes)
    return len(new_routes)
