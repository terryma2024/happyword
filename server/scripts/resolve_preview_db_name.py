"""Resolve the Mongo database name used by a Vercel preview deployment."""

from __future__ import annotations

import os

from app.config import _resolve_db_name

DEFAULT_PREVIEW_DB_TEMPLATE = "happyword_pr_{pr}_e2e"


def resolve_preview_db_name(*, template: str, pr: str, branch: str) -> str:
    """Mirror the application's preview Mongo DB template expansion."""
    return _resolve_db_name(template, pr=pr, branch=branch)


def main() -> None:
    template = os.environ.get("MONGO_DB_NAME", DEFAULT_PREVIEW_DB_TEMPLATE)
    pr = os.environ.get("VERCEL_GIT_PULL_REQUEST_ID", "")
    branch = (
        os.environ.get("VERCEL_GIT_COMMIT_REF")
        or os.environ.get("GITHUB_HEAD_REF")
        or os.environ.get("GITHUB_REF_NAME")
        or "local"
    )
    print(resolve_preview_db_name(template=template, pr=pr, branch=branch))


if __name__ == "__main__":
    main()
